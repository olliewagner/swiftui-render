import UIKit
import Foundation

// Hot-Reload Daemon for swiftui-render
// Stays running as a persistent Catalyst app. Watches for render requests
// via a trigger file protocol. Loads user views from compiled .dylib files
// via dlopen, renders to PNG.
//
// Protocol:
//   Config is read from /tmp/swiftui-render-daemon/request.json:
//     {"width": 390, "height": 844, "scale": 2, "dark": false,
//      "output": "/tmp/swiftui-render.png", "annotate": false, "deviceFrame": false}
//   1. Client compiles user_view.swift + bridge.swift -> /tmp/swiftui-render-daemon/preview.dylib
//   2. Client writes request.json
//   3. Client touches /tmp/swiftui-render-daemon/reload.trigger
//   4. Daemon detects trigger, reads config, dlopen's dylib, renders PNG
//   5. Daemon writes /tmp/swiftui-render-daemon/reload.done

struct RenderRequest: Codable {
    var width: CGFloat = 390
    var height: CGFloat = 844
    var scale: CGFloat = 2
    var dark: Bool = false
    var output: String = "/tmp/swiftui-render.png"
    var annotate: Bool = false
    var deviceFrame: Bool = false
    var tree: Bool = false
    var snapshot: Bool = false
}

class HotReloadManager {
    private var currentHandle: UnsafeMutableRawPointer?
    private var loadCount = 0
    private let basePath = "/tmp/swiftui-render-daemon"
    private var timer: Timer?
    private weak var window: UIWindow?

    var dylibPath: String { "\(basePath)/preview.dylib" }
    var triggerPath: String { "\(basePath)/reload.trigger" }
    var donePath: String { "\(basePath)/reload.done" }
    var requestPath: String { "\(basePath)/request.json" }
    var treePath: String { "\(basePath)/tree.txt" }

    func start(window: UIWindow) {
        self.window = window
        try? FileManager.default.createDirectory(atPath: basePath, withIntermediateDirectories: true)
        // Write PID file
        try? "\(ProcessInfo.processInfo.processIdentifier)".write(toFile: "\(basePath)/daemon.pid", atomically: true, encoding: .utf8)

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkTrigger()
        }
        print("Daemon ready (PID \(ProcessInfo.processInfo.processIdentifier))")
    }

    private func checkTrigger() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: triggerPath) else { return }
        try? fm.removeItem(atPath: triggerPath)
        try? fm.removeItem(atPath: donePath)
        reload()
    }

    func reload() {
        let start = CFAbsoluteTimeGetCurrent()

        // Read request config
        var req = RenderRequest()
        if let data = FileManager.default.contents(atPath: requestPath),
           let decoded = try? JSONDecoder().decode(RenderRequest.self, from: data) {
            req = decoded
        }

        // Close previous dylib
        if let handle = currentHandle {
            dlclose(handle)
            currentHandle = nil
        }

        // Copy to unique path (dyld caches by path)
        loadCount += 1
        let uniquePath = "\(basePath)/preview_\(loadCount).dylib"
        let fm = FileManager.default
        // Clean up old copies
        if loadCount > 2 {
            try? fm.removeItem(atPath: "\(basePath)/preview_\(loadCount - 2).dylib")
        }
        try? fm.removeItem(atPath: uniquePath)
        do {
            try fm.copyItem(atPath: dylibPath, toPath: uniquePath)
        } catch {
            writeError("copy dylib: \(error)")
            return
        }

        // dlopen
        guard let handle = dlopen(uniquePath, RTLD_NOW) else {
            writeError("dlopen: \(String(cString: dlerror()))")
            return
        }
        currentHandle = handle

        // dlsym
        guard let sym = dlsym(handle, "_createHostingController") else {
            writeError("dlsym: \(String(cString: dlerror()))")
            return
        }

        typealias CreateFn = @convention(c) () -> UnsafeMutableRawPointer
        let createFn = unsafeBitCast(sym, to: CreateFn.self)
        let ptr = createFn()
        let vc = Unmanaged<UIViewController>.fromOpaque(ptr).takeRetainedValue()

        let loadMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

        // Configure and render
        vc.view.frame = CGRect(x: 0, y: 0, width: req.width, height: req.height)
        vc.view.overrideUserInterfaceStyle = req.dark ? .dark : .unspecified
        vc.view.backgroundColor = .systemBackground
        vc.view.layoutIfNeeded()

        // Layout passes
        for _ in 0..<10 {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
            vc.view.setNeedsLayout()
            vc.view.layoutIfNeeded()
        }

        // Render
        let format = UIGraphicsImageRendererFormat()
        format.scale = req.scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: req.width, height: req.height), format: format)
        var image = renderer.image { _ in
            vc.view.drawHierarchy(in: CGRect(x: 0, y: 0, width: req.width, height: req.height), afterScreenUpdates: true)
        }

        // Tree dump
        if req.tree {
            if let tf = fopen(treePath, "w") {
                fputs("View tree:\n", tf)
                dumpTree(vc.view.layer, rootSize: CGSize(width: req.width, height: req.height), file: tf)
                fclose(tf)
            }
        }

        // Accessibility snapshot — combines layer frames with semantic labels
        if req.snapshot {
            let snapshotPath = "\(basePath)/snapshot.txt"
            if let sf = fopen(snapshotPath, "w") {
                // Get layer frames (for geometry)
                let layerInfos = collectLayers(vc.view.layer, rootSize: CGSize(width: req.width, height: req.height))

                // Get accessibility elements (for semantics)
                var accElements: [(label: String, traits: String, value: String?)] = []
                collectAccessLabels(vc.view, into: &accElements)

                // Get full accessibility elements with frames
                var fullAccElements: [(label: String, traits: String, value: String?, frame: CGRect)] = []
                collectFullAccessibility(vc.view, into: &fullAccElements)

                fputs("Snapshot (\(fullAccElements.count) elements)\n\n", sf)

                for (i, el) in fullAccElements.enumerated() {
                    var line = "  @e\(i) \"\(el.label)\" \(Int(el.frame.width))×\(Int(el.frame.height)) @ (\(Int(el.frame.origin.x)),\(Int(el.frame.origin.y)))"
                    if !el.traits.isEmpty { line += " [\(el.traits)]" }
                    if let v = el.value { line += " value=\"\(v)\"" }
                    fputs(line + "\n", sf)
                }

                fclose(sf)
            }
        }

        // Annotate
        if req.annotate {
            let layers = collectLayers(vc.view.layer, rootSize: CGSize(width: req.width, height: req.height))
            image = drawAnnotations(on: image, layers: layers, width: req.width, height: req.height, scale: req.scale)
        }

        // Device frame
        if req.deviceFrame {
            image = addDeviceFrame(on: image, width: req.width, height: req.height, scale: req.scale, isDark: req.dark)
        }

        // Save
        guard let png = image.pngData() else {
            writeError("PNG conversion failed")
            return
        }
        do {
            let url = URL(fileURLWithPath: req.output)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        } catch {
            writeError("write: \(error)")
            return
        }

        let totalMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let kb = png.count / 1024
        let result = "\(Int(req.width * req.scale))×\(Int(req.height * req.scale)) (\(kb)KB) → \(req.output) [load: \(String(format: "%.0f", loadMs))ms, total: \(String(format: "%.0f", totalMs))ms]"
        try? result.write(toFile: donePath, atomically: true, encoding: .utf8)
        print(result)
    }

    private func writeError(_ msg: String) {
        let err = "ERROR: \(msg)"
        try? err.write(toFile: donePath, atomically: true, encoding: .utf8)
        print(err)
    }

    // ---- Layer introspection ----

    struct LayerInfo { let frame: CGRect; let depth: Int }

    func collectLayers(_ layer: CALayer, depth: Int = 0, origin: CGPoint = .zero, rootSize: CGSize) -> [LayerInfo] {
        var results: [LayerInfo] = []
        let absFrame = CGRect(x: origin.x + layer.frame.origin.x, y: origin.y + layer.frame.origin.y,
                              width: layer.frame.width, height: layer.frame.height)
        guard absFrame.width > 4 && absFrame.height > 4 else { return results }
        let isFullSize = abs(absFrame.width - rootSize.width) < 2 && abs(absFrame.height - rootSize.height) < 2
        if depth > 0 && !isFullSize {
            results.append(LayerInfo(frame: absFrame, depth: depth))
        }
        for sub in layer.sublayers ?? [] {
            results += collectLayers(sub, depth: depth + 1, origin: absFrame.origin, rootSize: rootSize)
        }
        return results
    }

    func drawAnnotations(on image: UIImage, layers: [LayerInfo], width: CGFloat, height: CGFloat, scale: CGFloat) -> UIImage {
        let colors: [UIColor] = [.systemRed, .systemBlue, .systemGreen, .systemOrange, .systemPurple, .systemPink, .systemTeal, .systemIndigo]
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = scale
        let r = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: fmt)
        return r.image { uiCtx in
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            let ctx = uiCtx.cgContext
            for (i, info) in layers.enumerated() {
                let c = colors[i % colors.count]
                ctx.setStrokeColor(c.cgColor); ctx.setLineWidth(1); ctx.stroke(info.frame)
                let s = "\(Int(info.frame.width))×\(Int(info.frame.height))"
                let a: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8, weight: .bold), .foregroundColor: UIColor.white, .backgroundColor: c.withAlphaComponent(0.9)]
                let sz = (s as NSString).size(withAttributes: a)
                var lx = info.frame.minX, ly = info.frame.minY - sz.height - 1
                if ly < 0 { ly = info.frame.minY + 1 }
                if lx + sz.width > width { lx = width - sz.width }
                (s as NSString).draw(at: CGPoint(x: lx, y: ly), withAttributes: a)
            }
        }
    }

    func dumpTree(_ layer: CALayer, depth: Int = 0, origin: CGPoint = .zero, rootSize: CGSize, file: UnsafeMutablePointer<FILE>) {
        let indent = String(repeating: "  ", count: depth)
        let f = layer.frame
        guard f.width > 2 && f.height > 2 else { return }
        let typeName = String(describing: type(of: layer))
        let shortType: String
        switch typeName {
        case "CGDrawingLayer": shortType = "Text"
        case "ImageLayer": shortType = "Image"
        case "CALayer": shortType = f.width < rootSize.width ? "Container" : "Background"
        default: shortType = typeName
        }
        if depth > 0 {
            var line = "\(indent)\(shortType) \(Int(f.width))×\(Int(f.height))"
            if f.origin.x != 0 || f.origin.y != 0 { line += " @ (\(Int(f.origin.x)),\(Int(f.origin.y)))" }
            fputs(line + "\n", file)
        }
        for sub in layer.sublayers ?? [] {
            dumpTree(sub, depth: depth + 1, origin: CGPoint(x: origin.x + f.origin.x, y: origin.y + f.origin.y), rootSize: rootSize, file: file)
        }
    }

    // ---- Accessibility snapshot ----

    func scanAccessibility(_ element: Any, depth: Int, file: UnsafeMutablePointer<FILE>) {
        guard let nsObj = element as? NSObject else { return }

        if nsObj.isAccessibilityElement {
            let indent = String(repeating: "  ", count: depth)
            let label = nsObj.accessibilityLabel ?? ""
            let frame = nsObj.accessibilityFrame
            let traits = nsObj.accessibilityTraits
            let value = nsObj.accessibilityValue

            var traitNames: [String] = []
            if traits.contains(.button) { traitNames.append("button") }
            if traits.contains(.staticText) { traitNames.append("text") }
            if traits.contains(.image) { traitNames.append("image") }
            if traits.contains(.header) { traitNames.append("header") }
            if traits.contains(.selected) { traitNames.append("selected") }
            if traits.contains(.adjustable) { traitNames.append("adjustable") }
            if traits.contains(.link) { traitNames.append("link") }
            if traits.contains(.notEnabled) { traitNames.append("disabled") }

            let traitStr = traitNames.isEmpty ? "" : " [\(traitNames.joined(separator: ","))]"
            var line = "\(indent)\"\(label)\" \(Int(frame.width))×\(Int(frame.height)) @ (\(Int(frame.origin.x)),\(Int(frame.origin.y)))\(traitStr)"
            if let v = value, !v.isEmpty { line += " value=\"\(v)\"" }
            fputs(line + "\n", file)
        }

        if let view = element as? UIView {
            if let elements = view.accessibilityElements {
                for el in elements { scanAccessibility(el, depth: depth + 1, file: file) }
            } else {
                for sub in view.subviews { scanAccessibility(sub, depth: depth + 1, file: file) }
            }
            let count = view.accessibilityElementCount()
            if count > 0 && view.accessibilityElements == nil {
                for i in 0..<count {
                    if let el = view.accessibilityElement(at: i) { scanAccessibility(el, depth: depth + 1, file: file) }
                }
            }
        }
    }

    func collectFullAccessibility(_ element: Any, into results: inout [(label: String, traits: String, value: String?, frame: CGRect)]) {
        guard let nsObj = element as? NSObject else { return }
        if nsObj.isAccessibilityElement, let label = nsObj.accessibilityLabel, !label.isEmpty {
            let traits = nsObj.accessibilityTraits
            var names: [String] = []
            if traits.contains(.button) { names.append("button") }
            if traits.contains(.staticText) { names.append("text") }
            if traits.contains(.image) { names.append("image") }
            if traits.contains(.header) { names.append("header") }
            if traits.contains(.adjustable) { names.append("adjustable") }
            if traits.contains(.link) { names.append("link") }
            if traits.contains(.selected) { names.append("selected") }
            if traits.contains(.notEnabled) { names.append("disabled") }
            results.append((label: label, traits: names.joined(separator: ","), value: nsObj.accessibilityValue, frame: nsObj.accessibilityFrame))
        }
        if let view = element as? UIView {
            if let elements = view.accessibilityElements {
                for el in elements { collectFullAccessibility(el, into: &results) }
            } else {
                for sub in view.subviews { collectFullAccessibility(sub, into: &results) }
            }
            let count = view.accessibilityElementCount()
            if count > 0 && view.accessibilityElements == nil {
                for i in 0..<count {
                    if let el = view.accessibilityElement(at: i) { collectFullAccessibility(el, into: &results) }
                }
            }
        }
    }

    func collectAccessLabels(_ element: Any, into results: inout [(label: String, traits: String, value: String?)]) {
        guard let nsObj = element as? NSObject else { return }
        if nsObj.isAccessibilityElement, let label = nsObj.accessibilityLabel, !label.isEmpty {
            let traits = nsObj.accessibilityTraits
            var names: [String] = []
            if traits.contains(.button) { names.append("button") }
            if traits.contains(.staticText) { names.append("text") }
            if traits.contains(.image) { names.append("image") }
            if traits.contains(.header) { names.append("header") }
            if traits.contains(.adjustable) { names.append("adjustable") }
            if traits.contains(.link) { names.append("link") }
            if traits.contains(.selected) { names.append("selected") }
            if traits.contains(.notEnabled) { names.append("disabled") }
            results.append((label: label, traits: names.joined(separator: ","), value: nsObj.accessibilityValue))
        }
        if let view = element as? UIView {
            if let elements = view.accessibilityElements {
                for el in elements { collectAccessLabels(el, into: &results) }
            } else {
                for sub in view.subviews { collectAccessLabels(sub, into: &results) }
            }
            let count = view.accessibilityElementCount()
            if count > 0 && view.accessibilityElements == nil {
                for i in 0..<count {
                    if let el = view.accessibilityElement(at: i) { collectAccessLabels(el, into: &results) }
                }
            }
        }
    }

    func addDeviceFrame(on image: UIImage, width: CGFloat, height: CGFloat, scale: CGFloat, isDark: Bool) -> UIImage {
        let cr: CGFloat = 55
        let diW: CGFloat = 126, diH: CGFloat = 37.33, diY: CGFloat = 11
        let sbH: CGFloat = 59
        let hiY: CGFloat = height - 21, hiW: CGFloat = 139, hiH: CGFloat = 5.33
        let fg: UIColor = isDark ? .white : .black
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = scale
        let r = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: fmt)
        return r.image { uiCtx in
            let ctx = uiCtx.cgContext
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height), cornerRadius: cr).addClip()
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            ctx.setFillColor(UIColor.black.cgColor)
            UIBezierPath(roundedRect: CGRect(x: (width-diW)/2, y: diY, width: diW, height: diH), cornerRadius: diH/2).fill()
            let ta: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold), .foregroundColor: fg]
            let ts = ("9:41" as NSString).size(withAttributes: ta)
            ("9:41" as NSString).draw(at: CGPoint(x: 27, y: (sbH - ts.height)/2), withAttributes: ta)
            let ic = UIImage.SymbolConfiguration(pointSize: 12.5, weight: .semibold)
            let bc = UIImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            if let s = UIImage(systemName: "cellularbars", withConfiguration: ic) { s.withTintColor(fg, renderingMode: .alwaysOriginal).draw(at: CGPoint(x: width-92, y: sbH/2 - s.size.height/2)) }
            if let s = UIImage(systemName: "wifi", withConfiguration: ic) { s.withTintColor(fg, renderingMode: .alwaysOriginal).draw(at: CGPoint(x: width-70, y: sbH/2 - s.size.height/2)) }
            if let s = UIImage(systemName: "battery.100", withConfiguration: bc) { s.withTintColor(fg, renderingMode: .alwaysOriginal).draw(at: CGPoint(x: width-42, y: sbH/2 - s.size.height/2)) }
            ctx.setFillColor(fg.withAlphaComponent(0.25).cgColor)
            UIBezierPath(roundedRect: CGRect(x: (width-hiW)/2, y: hiY, width: hiW, height: hiH), cornerRadius: hiH/2).fill()
        }
    }
}

// MARK: - App Delegate

class DaemonAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    let hotReload = HotReloadManager()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = DaemonSceneDelegate.self
        return config
    }
}

class DaemonSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        self.window = window
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()

        let delegate = UIApplication.shared.delegate as! DaemonAppDelegate
        delegate.window = window
        delegate.hotReload.start(window: window)
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(DaemonAppDelegate.self))

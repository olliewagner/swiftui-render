import Foundation

/// Generates Swift source code for each rendering backend
enum TemplateGenerator {

    static func generate(config: RenderConfig) -> String {
        switch config.backend {
        case .imageRenderer:
            return imageRendererTemplate(config: config)
        case .apphost:
            return appHostTemplate(config: config)
        case .catalyst:
            return catalystTemplate(config: config)
        }
    }

    // MARK: - ImageRenderer (default, fast)

    private static func imageRendererTemplate(config: RenderConfig) -> String {
        let frame = frameModifier(config: config)
        let bg = config.dark ? "Color.black" : "Color.white"
        let colorScheme = config.dark ? ".dark" : ".light"
        let outputEscaped = config.outputPath.replacingOccurrences(of: "\"", with: "\\\"")

        return """
        import SwiftUI
        import AppKit

        struct __RenderHost: View {
            var body: some View {
                Preview()
                    \(frame)
                    .background(\(bg))
                    .environment(\\.colorScheme, \(colorScheme))
            }
        }

        @main struct __Main {
            @MainActor static func main() {
                let renderer = ImageRenderer(content: __RenderHost())
                renderer.scale = \(config.scale)

                guard let image = renderer.nsImage,
                      let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    fputs("ERROR: render failed\\n", stderr); exit(1)
                }

                let path = "\(outputEscaped)"
                do {
                    let url = URL(fileURLWithPath: path)
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try png.write(to: url)
                    let kb = png.count / 1024
                    print("\\(Int(image.size.width))×\\(Int(image.size.height)) @\\(Int(\(config.scale)))x (\\(kb)KB) → \\(path)")
                } catch {
                    fputs("ERROR: \\(error)\\n", stderr); exit(1)
                }
            }
        }
        """
    }

    // MARK: - AppHost (NSWindow + NSHostingView)

    private static func appHostTemplate(config: RenderConfig) -> String {
        let w = config.resolvedWidth
        let h = config.resolvedHeight
        let colorScheme = config.dark ? ".dark" : ".light"
        let outputEscaped = config.outputPath.replacingOccurrences(of: "\"", with: "\\\"")

        return """
        import SwiftUI
        import AppKit

        class __AppDelegate: NSObject, NSApplicationDelegate {
            func applicationDidFinishLaunching(_ notification: Notification) {
                let width: CGFloat = \(w)
                let height: CGFloat = \(h)
                let scale: CGFloat = \(config.scale)

                let hostingView = NSHostingView(rootView: Preview().environment(\\.colorScheme, \(colorScheme)))
                let window = NSWindow(contentRect: NSRect(x: -9999, y: -9999, width: width, height: height),
                    styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = hostingView
                window.backgroundColor = \(colorScheme) == .dark ? .black : .white
                window.isReleasedWhenClosed = false
                window.orderBack(nil)
                hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)

                for _ in 0..<10 {
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
                    hostingView.layoutSubtreeIfNeeded()
                }

                let pw = Int(width * scale), ph = Int(height * scale)
                guard let bitmapRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                    let ctx = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
                    fputs("ERROR: bitmap failed\\n", stderr); NSApp.terminate(nil); return
                }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = ctx
                ctx.cgContext.scaleBy(x: scale, y: scale)
                hostingView.displayIgnoringOpacity(hostingView.bounds, in: ctx)
                NSGraphicsContext.restoreGraphicsState()

                guard let png = bitmapRep.representation(using: .png, properties: [:]) else {
                    fputs("ERROR: PNG failed\\n", stderr); NSApp.terminate(nil); return
                }
                let path = "\(outputEscaped)"
                do {
                    let url = URL(fileURLWithPath: path)
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try png.write(to: url)
                    print("\\(pw)×\\(ph) (\\(png.count / 1024)KB) → \\(path)")
                } catch { fputs("ERROR: \\(error)\\n", stderr) }
                NSApp.terminate(nil)
            }
        }

        @main struct __Main {
            @MainActor static func main() {
                let app = NSApplication.shared
                app.setActivationPolicy(.accessory)
                let delegate = __AppDelegate()
                app.delegate = delegate
                app.run()
            }
        }
        """
    }

    // MARK: - Catalyst (full iOS rendering)

    private static func catalystTemplate(config: RenderConfig) -> String {
        let w = config.resolvedWidth
        let h = config.resolvedHeight
        let uikitStyle = config.dark ? ".dark" : ".unspecified"
        let isDark = config.dark ? "true" : "false"
        let outputEscaped = config.outputPath.replacingOccurrences(of: "\"", with: "\\\"")

        var treeCode = ""
        if config.tree {
            treeCode = """

                    // Tree dump
                    if let tf = fopen("/tmp/swiftui-render-tree.txt", "w") {
                        __dumpTree(hc.view.layer, rootSize: CGSize(width: width, height: height), file: tf)
                        fclose(tf)
                    }
            """
        }

        var annotateCode = ""
        if config.annotate {
            annotateCode = """

                    // Annotate
                    let __layers = __collectLayers(hc.view.layer, rootSize: CGSize(width: width, height: height))
                    image = __drawAnnotations(on: image, layers: __layers, width: width, height: height, scale: scale)
            """
        }

        var deviceFrameCode = ""
        if config.deviceFrame {
            deviceFrameCode = """

                    image = __addDeviceFrame(on: image, width: width, height: height, scale: scale, isDark: \(isDark))
            """
        }

        return """
        import SwiftUI
        import UIKit

        \(catalystHelpers)

        class __SceneDelegate: UIResponder, UIWindowSceneDelegate { var window: UIWindow? }

        class __AppDelegate: UIResponder, UIApplicationDelegate {
            func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.render() }
                return true
            }

            func application(_ application: UIApplication, configurationForConnecting cs: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
                let c = UISceneConfiguration(name: nil, sessionRole: cs.role)
                c.delegateClass = __SceneDelegate.self
                return c
            }

            func render() {
                let width: CGFloat = \(w)
                let height: CGFloat = \(h)
                let scale: CGFloat = \(config.scale)

                let hc = UIHostingController(rootView: Preview())
                hc.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
                hc.view.overrideUserInterfaceStyle = \(uikitStyle)
                hc.view.backgroundColor = .systemBackground
                hc.view.layoutIfNeeded()

                for _ in 0..<10 {
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
                    hc.view.setNeedsLayout()
                    hc.view.layoutIfNeeded()
                }

                let format = UIGraphicsImageRendererFormat(); format.scale = scale
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
                var image = renderer.image { _ in
                    hc.view.drawHierarchy(in: CGRect(x: 0, y: 0, width: width, height: height), afterScreenUpdates: true)
                }
        \(treeCode)\(annotateCode)\(deviceFrameCode)

                guard let png = image.pngData() else { fputs("ERROR: PNG failed\\n", stderr); exit(1) }
                let path = "\(outputEscaped)"
                do {
                    let url = URL(fileURLWithPath: path)
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try png.write(to: url)
                    print("\\(Int(width * scale))×\\(Int(height * scale)) (\\(png.count / 1024)KB) → \\(path)")
                } catch { fputs("ERROR: \\(error)\\n", stderr); exit(1) }
                exit(0)
            }
        }

        @main struct __CatalystMain {
            static func main() {
                UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(__AppDelegate.self))
            }
        }
        """
    }

    // MARK: - Helpers

    private static func frameModifier(config: RenderConfig) -> String {
        if let w = config.width, let h = config.height {
            return ".frame(width: \(w), height: \(h))"
        } else if let w = config.width {
            return ".frame(width: \(w))"
        } else if let h = config.height {
            return ".frame(height: \(h))"
        }
        return ""
    }

    /// Shared Swift helper functions for Catalyst templates
    private static let catalystHelpers = """
    struct __LayerInfo { let frame: CGRect; let depth: Int }

    func __collectLayers(_ layer: CALayer, depth: Int = 0, origin: CGPoint = .zero, rootSize: CGSize) -> [__LayerInfo] {
        var r: [__LayerInfo] = []
        let f = CGRect(x: origin.x + layer.frame.origin.x, y: origin.y + layer.frame.origin.y,
                       width: layer.frame.width, height: layer.frame.height)
        guard f.width > 4 && f.height > 4 else { return r }
        let full = abs(f.width - rootSize.width) < 2 && abs(f.height - rootSize.height) < 2
        if depth > 0 && !full { r.append(__LayerInfo(frame: f, depth: depth)) }
        for sub in layer.sublayers ?? [] { r += __collectLayers(sub, depth: depth + 1, origin: f.origin, rootSize: rootSize) }
        return r
    }

    func __drawAnnotations(on image: UIImage, layers: [__LayerInfo], width: CGFloat, height: CGFloat, scale: CGFloat) -> UIImage {
        let colors: [UIColor] = [.systemRed, .systemBlue, .systemGreen, .systemOrange, .systemPurple, .systemPink, .systemTeal, .systemIndigo]
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = scale
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: fmt).image { uiCtx in
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            let ctx = uiCtx.cgContext
            for (i, info) in layers.enumerated() {
                let c = colors[i % colors.count]; ctx.setStrokeColor(c.cgColor); ctx.setLineWidth(1); ctx.stroke(info.frame)
                let s = "\\(Int(info.frame.width))×\\(Int(info.frame.height))"
                let a: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8, weight: .bold), .foregroundColor: UIColor.white, .backgroundColor: c.withAlphaComponent(0.9)]
                let sz = (s as NSString).size(withAttributes: a)
                var lx = info.frame.minX, ly = info.frame.minY - sz.height - 1
                if ly < 0 { ly = info.frame.minY + 1 }; if lx + sz.width > width { lx = width - sz.width }
                (s as NSString).draw(at: CGPoint(x: lx, y: ly), withAttributes: a)
            }
        }
    }

    func __dumpTree(_ layer: CALayer, depth: Int = 0, origin: CGPoint = .zero, rootSize: CGSize, file: UnsafeMutablePointer<FILE>) {
        let f = layer.frame; guard f.width > 4 && f.height > 4 else { return }
        let typeName = String(describing: type(of: layer))
        let skip = ["CABackdropLayer", "CAChameleonLayer", "CAShapeLayer"]
        let full = abs(f.width - rootSize.width) < 2 && abs(f.height - rootSize.height) < 2
        if depth > 0 && !skip.contains(typeName) && !full {
            let t: String
            switch typeName {
            case "CGDrawingLayer": t = "Text"
            case "ImageLayer": t = "Image"
            case "GradientLayer": t = "Gradient"
            case "ColorShapeLayer": t = "Shape"
            default: t = "Box"
            }
            let indent = String(repeating: "  ", count: max(0, depth - 1))
            var line = "\\(indent)\\(t) \\(Int(f.width))×\\(Int(f.height))"
            if f.origin.x != 0 || f.origin.y != 0 { line += " @ (\\(Int(f.origin.x)),\\(Int(f.origin.y)))" }
            fputs(line + "\\n", file)
        }
        for sub in layer.sublayers ?? [] {
            __dumpTree(sub, depth: depth + 1, origin: CGPoint(x: origin.x + f.origin.x, y: origin.y + f.origin.y), rootSize: rootSize, file: file)
        }
    }

    func __addDeviceFrame(on image: UIImage, width: CGFloat, height: CGFloat, scale: CGFloat, isDark: Bool) -> UIImage {
        let cr: CGFloat = 55, diW: CGFloat = 126, diH: CGFloat = 37.33, diY: CGFloat = 11
        let sbH: CGFloat = 59, hiY = height - 21, hiW: CGFloat = 139, hiH: CGFloat = 5.33
        let fg: UIColor = isDark ? .white : .black
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = scale
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: fmt).image { uiCtx in
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
    """
}

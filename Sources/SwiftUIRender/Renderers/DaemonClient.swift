import Foundation

/// Client for communicating with the hot-reload daemon
enum DaemonClient {
    static let daemonDir = "/tmp/swiftui-render-daemon"
    static let pidPath = "\(daemonDir)/daemon.pid"
    static let triggerPath = "\(daemonDir)/reload.trigger"
    static let donePath = "\(daemonDir)/reload.done"
    static let requestPath = "\(daemonDir)/request.json"
    static let snapshotPath = "\(daemonDir)/snapshot.txt"
    static let treePath = "\(daemonDir)/tree.txt"

    /// Embedded bridge.swift content (avoids needing an external file)
    static let bridgeSource = """
        import SwiftUI
        import UIKit

        @_cdecl("_createHostingController")
        public func _createHostingController() -> UnsafeMutableRawPointer {
            let hc = UIHostingController(rootView: AnyView(Preview()))
            return Unmanaged.passRetained(hc).toOpaque()
        }
        """

    /// Path to the pre-built daemon app bundle
    static var daemonAppPath: String {
        let execDir = Bundle.main.executableURL?.deletingLastPathComponent().path ?? ""
        let candidates = [
            "\(execDir)/../share/swiftui-render/SwiftUIRenderDaemon.app",
            "\(NSHomeDirectory())/.local/share/swiftui-render/SwiftUIRenderDaemon.app",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
            ?? "\(NSHomeDirectory())/.local/share/swiftui-render/SwiftUIRenderDaemon.app"
    }

    /// Path to the bridge.swift file -- writes embedded version if missing
    static var bridgePath: String {
        let shareDir = "\(NSHomeDirectory())/.local/share/swiftui-render"
        let path = "\(shareDir)/bridge.swift"

        if !FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.createDirectory(
                atPath: shareDir, withIntermediateDirectories: true)
            try? bridgeSource.write(toFile: path, atomically: true, encoding: .utf8)
        }

        return path
    }

    static var isRunning: Bool {
        guard FileManager.default.fileExists(atPath: pidPath),
            let pidStr = try? String(contentsOfFile: pidPath, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            let pid = Int32(pidStr)
        else { return false }
        return kill(pid, 0) == 0
    }

    static func start() throws {
        if isRunning {
            let pid = try String(contentsOfFile: pidPath, encoding: .utf8).trimmingCharacters(
                in: .whitespacesAndNewlines)
            stderr("Daemon already running (PID \(pid))\n")
            return
        }

        try FileManager.default.createDirectory(
            atPath: daemonDir, withIntermediateDirectories: true)

        guard FileManager.default.fileExists(atPath: daemonAppPath) else {
            throw DaemonError.notBuilt
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-g", daemonAppPath]
        try task.run()
        task.waitUntilExit()

        // Wait for PID file
        for _ in 0..<20 {
            if FileManager.default.fileExists(atPath: pidPath) {
                let pid = try String(contentsOfFile: pidPath, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                stderr("Daemon started (PID \(pid))\n")
                return
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        throw DaemonError.startFailed
    }

    static func stop() throws {
        guard FileManager.default.fileExists(atPath: pidPath),
            let pidStr = try? String(contentsOfFile: pidPath, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            let pid = Int32(pidStr)
        else {
            stderr("Daemon not running\n")
            return
        }
        kill(pid, SIGTERM)
        try? FileManager.default.removeItem(atPath: pidPath)
        stderr("Daemon stopped (PID \(pid))\n")
    }

    static func render(config: RenderConfig) throws {
        // Auto-start daemon
        if !isRunning {
            try start()
        }

        // Ensure bridge.swift exists (writes from embedded source if needed)
        let bridge = bridgePath

        // Compile view into dylib
        try SwiftCompiler.compileDylib(
            input: config.inputPath,
            bridge: bridge,
            output: "\(daemonDir)/preview.dylib"
        )

        // Write request
        let request = """
            {"width":\(config.resolvedWidth),"height":\(config.resolvedHeight),"scale":\(config.scale),\
            "dark":\(config.dark),"output":"\(config.outputPath)",\
            "annotate":\(config.annotate),"deviceFrame":\(config.deviceFrame),\
            "tree":\(config.tree),"snapshot":\(config.snapshot)}
            """
        try request.write(toFile: requestPath, atomically: true, encoding: .utf8)

        // Trigger
        try? FileManager.default.removeItem(atPath: donePath)
        FileManager.default.createFile(atPath: triggerPath, contents: nil)

        // Wait for result (max 10s)
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: donePath) {
                let result = try String(contentsOfFile: donePath, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if result.hasPrefix("ERROR") {
                    throw DaemonError.renderFailed(result)
                }
                print(result)

                // Print tree/snapshot to stderr
                if FileManager.default.fileExists(atPath: treePath) {
                    let tree = try String(contentsOfFile: treePath, encoding: .utf8)
                    stderr(tree)
                    try? FileManager.default.removeItem(atPath: treePath)
                }
                if FileManager.default.fileExists(atPath: snapshotPath) {
                    let snap = try String(contentsOfFile: snapshotPath, encoding: .utf8)
                    stderr(snap)
                    try? FileManager.default.removeItem(atPath: snapshotPath)
                }
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw DaemonError.timeout
    }

    /// Build the daemon app from the embedded daemon source
    static func buildDaemon() throws {
        let shareDir = "\(NSHomeDirectory())/.local/share/swiftui-render"
        try FileManager.default.createDirectory(
            atPath: shareDir, withIntermediateDirectories: true)

        // Check if daemon.swift source exists
        let daemonSourcePath = "\(shareDir)/daemon.swift"
        guard FileManager.default.fileExists(atPath: daemonSourcePath) else {
            throw DaemonError.sourceNotFound(daemonSourcePath)
        }

        let appDir = "\(shareDir)/SwiftUIRenderDaemon.app/Contents"
        let macosDir = "\(appDir)/MacOS"
        try FileManager.default.createDirectory(
            atPath: macosDir, withIntermediateDirectories: true)

        // Write Info.plist
        let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
            <key>CFBundleIdentifier</key><string>com.swiftui-render.daemon</string>
            <key>CFBundleExecutable</key><string>daemon</string>
            <key>CFBundlePackageType</key><string>APPL</string>
            <key>LSUIElement</key><true/>
            </dict></plist>
            """
        try plist.write(toFile: "\(appDir)/Info.plist", atomically: true, encoding: .utf8)

        // Compile
        let binaryPath = "\(macosDir)/daemon"
        let sdkPath = SwiftCompiler.sdkPath
        let args = [
            "swiftc", "-swift-version", "5", "-suppress-warnings",
            "-parse-as-library",
            "-target", "arm64-apple-ios17.0-macabi",
            "-sdk", sdkPath,
            "-Fsystem",
            "\(sdkPath)/System/iOSSupport/System/Library/Frameworks",
            "-framework", "SwiftUI", "-framework", "UIKit",
            daemonSourcePath,
            "-o", binaryPath,
        ]

        let task = Process()
        let errPipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        task.arguments = args
        task.standardError = errPipe
        task.standardOutput = errPipe

        try task.run()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? "Unknown error"
            throw CompilationError.failed(errStr)
        }

        print("Daemon built: \(shareDir)/SwiftUIRenderDaemon.app")
    }
}

enum DaemonError: LocalizedError {
    case notBuilt
    case startFailed
    case timeout
    case renderFailed(String)
    case sourceNotFound(String)

    var errorDescription: String? {
        switch self {
        case .notBuilt:
            return
                "Daemon app not found. Run `swiftui-render daemon build` to build it, or ensure the daemon app is at ~/.local/share/swiftui-render/SwiftUIRenderDaemon.app"
        case .startFailed: return "Daemon failed to start within 5 seconds"
        case .timeout:
            return
                "Daemon render timed out after 10 seconds. Check daemon logs or restart with `swiftui-render daemon stop && swiftui-render daemon start`"
        case .renderFailed(let msg): return msg
        case .sourceNotFound(let path):
            return "Daemon source not found at \(path). Place daemon.swift there first."
        }
    }
}

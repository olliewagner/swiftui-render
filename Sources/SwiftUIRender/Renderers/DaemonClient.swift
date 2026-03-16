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

    /// Path to the pre-built daemon app bundle
    static var daemonAppPath: String {
        // Look in the same directory as the swiftui-render binary first,
        // then fall back to ~/.local/share
        let execDir = Bundle.main.executableURL?.deletingLastPathComponent().path ?? ""
        let candidates = [
            "\(execDir)/../share/swiftui-render/SwiftUIRenderDaemon.app",
            "\(NSHomeDirectory())/.local/share/swiftui-render/SwiftUIRenderDaemon.app",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? candidates.last!
    }

    /// Path to the bridge.swift file
    static var bridgePath: String {
        let execDir = Bundle.main.executableURL?.deletingLastPathComponent().path ?? ""
        let candidates = [
            "\(execDir)/../share/swiftui-render/bridge.swift",
            "\(NSHomeDirectory())/.local/share/swiftui-render/bridge.swift",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? candidates.last!
    }

    static var isRunning: Bool {
        guard FileManager.default.fileExists(atPath: pidPath),
              let pidStr = try? String(contentsOfFile: pidPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(pidStr) else { return false }
        return kill(pid, 0) == 0
    }

    static func start() throws {
        if isRunning {
            let pid = try String(contentsOfFile: pidPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            FileHandle.standardError.write("Daemon already running (PID \(pid))\n".data(using: .utf8)!)
            return
        }

        try FileManager.default.createDirectory(atPath: daemonDir, withIntermediateDirectories: true)

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
                let pid = try String(contentsOfFile: pidPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                FileHandle.standardError.write("Daemon started (PID \(pid))\n".data(using: .utf8)!)
                return
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        throw DaemonError.startFailed
    }

    static func stop() throws {
        guard FileManager.default.fileExists(atPath: pidPath),
              let pidStr = try? String(contentsOfFile: pidPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(pidStr) else {
            FileHandle.standardError.write("Daemon not running\n".data(using: .utf8)!)
            return
        }
        kill(pid, SIGTERM)
        try? FileManager.default.removeItem(atPath: pidPath)
        FileHandle.standardError.write("Daemon stopped (PID \(pid))\n".data(using: .utf8)!)
    }

    static func render(config: RenderConfig) throws {
        // Auto-start daemon
        if !isRunning {
            try start()
        }

        // Compile view into dylib
        try SwiftCompiler.compileDylib(
            input: config.inputPath,
            bridge: bridgePath,
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
                let result = try String(contentsOfFile: donePath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                if result.hasPrefix("ERROR") {
                    throw DaemonError.renderFailed(result)
                }
                print(result)

                // Print tree/snapshot if generated
                if FileManager.default.fileExists(atPath: treePath) {
                    let tree = try String(contentsOfFile: treePath, encoding: .utf8)
                    FileHandle.standardError.write(tree.data(using: .utf8)!)
                    try? FileManager.default.removeItem(atPath: treePath)
                }
                if FileManager.default.fileExists(atPath: snapshotPath) {
                    let snap = try String(contentsOfFile: snapshotPath, encoding: .utf8)
                    FileHandle.standardError.write(snap.data(using: .utf8)!)
                    try? FileManager.default.removeItem(atPath: snapshotPath)
                }
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw DaemonError.timeout
    }
}

enum DaemonError: LocalizedError {
    case notBuilt
    case startFailed
    case timeout
    case renderFailed(String)

    var errorDescription: String? {
        switch self {
        case .notBuilt: return "Daemon app not found. Build it first."
        case .startFailed: return "Daemon failed to start"
        case .timeout: return "Daemon render timed out"
        case .renderFailed(let msg): return msg
        }
    }
}

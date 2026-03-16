import Foundation

/// Orchestrates Swift compilation for different backends
enum SwiftCompiler {
    static let sdkPath: String = {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        task.arguments = ["--show-sdk-path"]
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }()

    /// Compile a SwiftUI view file + renderer template into an executable
    static func compile(
        input: String,
        renderer: String,
        output: String,
        backend: RenderBackend
    ) throws {
        var args: [String] = ["swiftc", "-swift-version", "5", "-suppress-warnings"]

        switch backend {
        case .imageRenderer, .apphost:
            args += ["-framework", "SwiftUI", "-framework", "AppKit"]

        case .catalyst:
            args += [
                "-parse-as-library",
                "-target", "arm64-apple-ios17.0-macabi",
                "-sdk", sdkPath,
                "-Fsystem", "\(sdkPath)/System/iOSSupport/System/Library/Frameworks",
                "-framework", "SwiftUI",
                "-framework", "UIKit",
            ]
        }

        args += [input, renderer, "-o", output]

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
            // Only show actual errors, not warnings
            let errors = errStr.components(separatedBy: "\n")
                .filter { $0.contains("error:") }
                .joined(separator: "\n")
            throw CompilationError.failed(errors.isEmpty ? errStr : errors)
        }
    }

    /// Compile a SwiftUI view + bridge into a dylib for the daemon
    static func compileDylib(input: String, bridge: String, output: String) throws {
        let args = [
            "swiftc", "-emit-library", "-swift-version", "5", "-suppress-warnings",
            "-target", "arm64-apple-ios17.0-macabi",
            "-sdk", sdkPath,
            "-Fsystem", "\(sdkPath)/System/iOSSupport/System/Library/Frameworks",
            "-framework", "SwiftUI", "-framework", "UIKit",
            input, bridge,
            "-o", output,
            "-module-name", "PreviewModule",
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
            let errors = errStr.components(separatedBy: "\n")
                .filter { $0.contains("error:") }
                .joined(separator: "\n")
            throw CompilationError.failed(errors.isEmpty ? errStr : errors)
        }
    }

    /// SHA-256 hash of a file's contents (first 16 chars)
    static func fileHash(_ path: String) throws -> String {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        return content.sha256Prefix(16)
    }
}

enum CompilationError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let msg): return msg
        }
    }
}

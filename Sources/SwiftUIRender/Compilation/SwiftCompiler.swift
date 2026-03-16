import CryptoKit
import Foundation

/// Orchestrates Swift compilation for different backends
enum SwiftCompiler {
    static let sdkPath: String = {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        task.arguments = ["--show-sdk-path"]
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
    }()

    /// Verify swiftc is available
    static func ensureToolchainAvailable() throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        task.arguments = ["--find", "swiftc"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            throw CompilationError.toolchainMissing
        }
    }

    /// Compile a SwiftUI view file + renderer template into an executable
    static func compile(
        input: String,
        renderer: String,
        output: String,
        backend: RenderBackend
    ) throws {
        var args: [String] = ["swiftc", "-swift-version", "5", "-suppress-warnings", "-Onone"]

        switch backend {
        case .imageRenderer, .apphost:
            args += ["-framework", "SwiftUI", "-framework", "AppKit"]

        case .catalyst:
            args += [
                "-parse-as-library",
                "-target", "arm64-apple-ios17.0-macabi",
                "-sdk", sdkPath,
                "-Fsystem",
                "\(sdkPath)/System/iOSSupport/System/Library/Frameworks",
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
            // Only show actual error lines, strip paths to just filenames for cleaner output
            let errors = errStr.components(separatedBy: "\n")
                .filter { $0.contains("error:") }
                .map { cleanErrorLine($0) }
                .joined(separator: "\n")
            throw CompilationError.failed(errors.isEmpty ? errStr : errors)
        }
    }

    /// Compile a SwiftUI view + bridge into a dylib for the daemon
    static func compileDylib(input: String, bridge: String, output: String) throws {
        let args = [
            "swiftc", "-emit-library", "-swift-version", "5", "-suppress-warnings", "-Onone",
            "-target", "arm64-apple-ios17.0-macabi",
            "-sdk", sdkPath,
            "-Fsystem",
            "\(sdkPath)/System/iOSSupport/System/Library/Frameworks",
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
                .map { cleanErrorLine($0) }
                .joined(separator: "\n")
            throw CompilationError.failed(errors.isEmpty ? errStr : errors)
        }
    }

    /// SHA-256 hash of a file's contents (first 16 chars) — in-process via CryptoKit
    static func fileHash(_ path: String) throws -> String {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        return content.sha256Prefix(16)
    }

    /// Strip verbose paths from error messages, keeping only filename + line info
    private static func cleanErrorLine(_ line: String) -> String {
        // Matches "/long/path/to/file.swift:10:5: error: ..." -> "file.swift:10:5: error: ..."
        guard let colonRange = line.range(of: ":\\d+:\\d+:", options: .regularExpression) else {
            return line
        }
        let pathEnd = colonRange.lowerBound
        let fullPath = String(line[line.startIndex..<pathEnd])
        let filename = (fullPath as NSString).lastPathComponent
        return filename + String(line[pathEnd...])
    }
}

enum CompilationError: LocalizedError {
    case failed(String)
    case toolchainMissing

    var errorDescription: String? {
        switch self {
        case .failed(let msg): return msg
        case .toolchainMissing:
            return
                "Swift toolchain not found. Install Xcode or Xcode Command Line Tools: xcode-select --install"
        }
    }
}

import Foundation

/// Orchestrates: generate template -> compile -> run -> output
enum CompileAndRender {

    private static let cacheDir: String = {
        let dir = NSHomeDirectory() + "/.cache/swiftui-render"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func run(config: RenderConfig) throws {
        let totalStart = CFAbsoluteTimeGetCurrent()

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftui-render-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let rendererPath = tmpDir.appendingPathComponent("renderer.swift").path
        let binaryPath: String

        let cacheKey = config.cacheKey
        let cachedPath: String

        // Catalyst stdout goes to the app process, not the CLI.
        // Use a temp file to capture the output from the renderer binary.
        let outputInfoPath = tmpDir.appendingPathComponent("output-info.txt").path

        switch config.backend {
        case .catalyst:
            cachedPath = "\(cacheDir)/\(cacheKey).app"
            let appBundle = tmpDir.appendingPathComponent("Renderer.app/Contents")
            try FileManager.default.createDirectory(
                at: appBundle.appendingPathComponent("MacOS"), withIntermediateDirectories: true)

            binaryPath = appBundle.appendingPathComponent("MacOS/renderer").path
            var compileMs: Double = 0

            if !config.noCache && FileManager.default.fileExists(atPath: cachedPath) {
                let cachedApp = tmpDir.appendingPathComponent("Renderer.app")
                try? FileManager.default.removeItem(at: cachedApp)
                try FileManager.default.copyItem(atPath: cachedPath, toPath: cachedApp.path)
            } else {
                // Write Info.plist
                let plist = """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                    <plist version="1.0"><dict>
                    <key>CFBundleIdentifier</key><string>com.swiftui-render.catalyst</string>
                    <key>CFBundleExecutable</key><string>renderer</string>
                    <key>CFBundlePackageType</key><string>APPL</string>
                    <key>LSUIElement</key><true/>
                    </dict></plist>
                    """
                try plist.write(
                    to: appBundle.appendingPathComponent("Info.plist"), atomically: true,
                    encoding: .utf8)

                let compileStart = CFAbsoluteTimeGetCurrent()
                let template = TemplateGenerator.generate(
                    config: config, outputInfoPath: outputInfoPath)
                try template.write(toFile: rendererPath, atomically: true, encoding: .utf8)
                try SwiftCompiler.compile(
                    input: config.inputPath, renderer: rendererPath, output: binaryPath,
                    backend: .catalyst)
                compileMs = (CFAbsoluteTimeGetCurrent() - compileStart) * 1000

                // Cache
                if !config.noCache {
                    try? FileManager.default.removeItem(atPath: cachedPath)
                    try? FileManager.default.copyItem(
                        atPath: tmpDir.appendingPathComponent("Renderer.app").path,
                        toPath: cachedPath
                    )
                }
            }

            // Run Catalyst app
            let runStart = CFAbsoluteTimeGetCurrent()
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-W", "-g", tmpDir.appendingPathComponent("Renderer.app").path]
            try task.run()
            task.waitUntilExit()
            _ = (CFAbsoluteTimeGetCurrent() - runStart) * 1000
            let totalMs = (CFAbsoluteTimeGetCurrent() - totalStart) * 1000

            // Read output from the info file (Catalyst stdout doesn't reach us)
            if FileManager.default.fileExists(atPath: outputInfoPath) {
                let info = try String(contentsOfFile: outputInfoPath, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if config.json {
                    // Parse the info and emit JSON
                    emitJSON(
                        infoLine: info, totalMs: totalMs, compileMs: compileMs, path: config.outputPath)
                } else {
                    print(info)
                }
            }

            // Print tree output if generated
            let treePath = "/tmp/swiftui-render-tree.txt"
            if FileManager.default.fileExists(atPath: treePath) {
                let tree = try String(contentsOfFile: treePath, encoding: .utf8)
                stderr("View tree:\n" + tree)
                try? FileManager.default.removeItem(atPath: treePath)
            }

        case .imageRenderer, .apphost:
            cachedPath = "\(cacheDir)/\(cacheKey)"
            binaryPath = tmpDir.appendingPathComponent("renderer").path
            var compileMs: Double = 0

            if !config.noCache && FileManager.default.fileExists(atPath: cachedPath) {
                try FileManager.default.copyItem(atPath: cachedPath, toPath: binaryPath)
            } else {
                let compileStart = CFAbsoluteTimeGetCurrent()
                let template = TemplateGenerator.generate(
                    config: config, outputInfoPath: nil)
                try template.write(toFile: rendererPath, atomically: true, encoding: .utf8)
                try SwiftCompiler.compile(
                    input: config.inputPath, renderer: rendererPath, output: binaryPath,
                    backend: config.backend)
                compileMs = (CFAbsoluteTimeGetCurrent() - compileStart) * 1000

                if !config.noCache {
                    try? FileManager.default.removeItem(atPath: cachedPath)
                    try? FileManager.default.copyItem(atPath: binaryPath, toPath: cachedPath)
                }
            }

            // Run binary
            let runStart = CFAbsoluteTimeGetCurrent()
            let task = Process()
            task.executableURL = URL(fileURLWithPath: binaryPath)
            let outPipe = Pipe()
            task.standardOutput = outPipe
            task.standardError = FileHandle.standardError
            try task.run()
            task.waitUntilExit()
            _ = (CFAbsoluteTimeGetCurrent() - runStart) * 1000
            let totalMs = (CFAbsoluteTimeGetCurrent() - totalStart) * 1000

            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            if let outStr = String(data: outData, encoding: .utf8)?.trimmingCharacters(
                in: .whitespacesAndNewlines), !outStr.isEmpty
            {
                if config.json {
                    emitJSON(
                        infoLine: outStr, totalMs: totalMs, compileMs: compileMs,
                        path: config.outputPath)
                } else {
                    print(outStr)
                }
            }

            if task.terminationStatus != 0 {
                throw CompilationError.failed(
                    "Render process exited with code \(task.terminationStatus)")
            }
        }
    }

    /// Parse a render info line and emit JSON
    private static func emitJSON(
        infoLine: String, totalMs: Double, compileMs: Double, path: String
    ) {
        // Parse "780x1688 @2x (195KB) -> /path" or "780x1688 (195KB) -> /path"
        var width = 0, height = 0, sizeKB = 0
        let parts = infoLine.components(separatedBy: " ")
        if let dims = parts.first {
            // Unicode multiplication sign or 'x'
            let dimParts = dims.replacingOccurrences(of: "\u{00d7}", with: "x")
                .components(separatedBy: "x")
            if dimParts.count == 2 {
                width = Int(dimParts[0]) ?? 0
                height = Int(dimParts[1]) ?? 0
            }
        }
        for part in parts {
            if part.hasPrefix("(") && part.hasSuffix("KB)") {
                let num = part.dropFirst().dropLast(3)
                sizeKB = Int(num) ?? 0
            }
        }

        let fileSize: Int
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
            let size = attrs[.size] as? Int
        {
            fileSize = size
        } else {
            fileSize = sizeKB * 1024
        }

        print(
            "{\"width\":\(width),\"height\":\(height),\"size\":\(fileSize),\"path\":\"\(path)\",\"time_ms\":\(Int(totalMs))}"
        )
    }

    /// Cache directory path (exposed for cache management)
    static var cacheDirPath: String { cacheDir }
}

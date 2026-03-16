import Foundation

/// Orchestrates: generate template → compile → run → output
enum CompileAndRender {

    private static let cacheDir: String = {
        let dir = NSHomeDirectory() + "/.cache/swiftui-render"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func run(config: RenderConfig) throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftui-render-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let rendererPath = tmpDir.appendingPathComponent("renderer.swift").path
        let binaryPath: String

        // Check cache
        let cacheKey = config.cacheKey
        let cachedPath: String

        switch config.backend {
        case .catalyst:
            cachedPath = "\(cacheDir)/\(cacheKey).app"
            let appBundle = tmpDir.appendingPathComponent("Renderer.app/Contents")
            try FileManager.default.createDirectory(at: appBundle.appendingPathComponent("MacOS"), withIntermediateDirectories: true)

            binaryPath = appBundle.appendingPathComponent("MacOS/renderer").path

            if !config.noCache && FileManager.default.fileExists(atPath: cachedPath) {
                // Cache hit
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
                try plist.write(to: appBundle.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

                // Generate and compile
                let template = TemplateGenerator.generate(config: config)
                try template.write(toFile: rendererPath, atomically: true, encoding: .utf8)
                try SwiftCompiler.compile(input: config.inputPath, renderer: rendererPath, output: binaryPath, backend: .catalyst)

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
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-W", "-g", tmpDir.appendingPathComponent("Renderer.app").path]
            try task.run()
            task.waitUntilExit()

            // Print tree output if generated
            let treePath = "/tmp/swiftui-render-tree.txt"
            if FileManager.default.fileExists(atPath: treePath) {
                let tree = try String(contentsOfFile: treePath, encoding: .utf8)
                FileHandle.standardError.write(("View tree:\n" + tree).data(using: .utf8)!)
                try? FileManager.default.removeItem(atPath: treePath)
            }

        case .imageRenderer, .apphost:
            cachedPath = "\(cacheDir)/\(cacheKey)"
            binaryPath = tmpDir.appendingPathComponent("renderer").path

            if !config.noCache && FileManager.default.fileExists(atPath: cachedPath) {
                try FileManager.default.copyItem(atPath: cachedPath, toPath: binaryPath)
            } else {
                let template = TemplateGenerator.generate(config: config)
                try template.write(toFile: rendererPath, atomically: true, encoding: .utf8)
                try SwiftCompiler.compile(input: config.inputPath, renderer: rendererPath, output: binaryPath, backend: config.backend)

                if !config.noCache {
                    try? FileManager.default.removeItem(atPath: cachedPath)
                    try? FileManager.default.copyItem(atPath: binaryPath, toPath: cachedPath)
                }
            }

            // Run binary
            let task = Process()
            task.executableURL = URL(fileURLWithPath: binaryPath)
            let outPipe = Pipe()
            task.standardOutput = outPipe
            task.standardError = FileHandle.standardError
            try task.run()
            task.waitUntilExit()

            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            if let outStr = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !outStr.isEmpty {
                print(outStr)
            }

            if task.terminationStatus != 0 {
                throw CompilationError.failed("Render process exited with code \(task.terminationStatus)")
            }
        }
    }
}

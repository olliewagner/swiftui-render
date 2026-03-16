import ArgumentParser
import Foundation

struct Preview: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Live preview -- watch file and re-render on changes via daemon"
    )

    @OptionGroup var options: RenderOptions

    mutating func run() throws {
        try options.validateInput()
        let inputPath = try options.inputPath
        let config = RenderConfig(
            inputPath: inputPath,
            outputPath: options.output,
            width: options.resolvedWidth,
            height: options.resolvedHeight,
            scale: options.scale,
            dark: options.dark,
            backend: .catalyst,
            annotate: false,
            tree: false,
            deviceFrame: options.deviceFrame,
            noCache: true,
            json: options.json
        )

        stderr(
            "Watching \(URL(fileURLWithPath: inputPath).lastPathComponent) -- Ctrl+C to stop\n")

        // Handle SIGINT gracefully
        signal(SIGINT) { _ in
            stderr("\nStopped\n")
            Darwin.exit(0)
        }

        var lastHash = ""
        while true {
            let currentHash = try SwiftCompiler.fileHash(inputPath)
            if currentHash != lastHash {
                lastHash = currentHash
                stderr("---\n")
                do {
                    try DaemonClient.render(config: config)
                } catch {
                    stderr("ERROR: \(error)\n")
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }
}

import ArgumentParser
import Foundation

struct Preview: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Live preview — watch file and re-render on changes via daemon"
    )

    @OptionGroup var options: RenderOptions

    mutating func run() throws {
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
            noCache: true
        )

        FileHandle.standardError.write("Watching \(URL(fileURLWithPath: inputPath).lastPathComponent) — Ctrl+C to stop\n".data(using: .utf8)!)

        var lastHash = ""
        while true {
            let currentHash = try SwiftCompiler.fileHash(inputPath)
            if currentHash != lastHash {
                lastHash = currentHash
                FileHandle.standardError.write("---\n".data(using: .utf8)!)
                do {
                    try DaemonClient.render(config: config)
                } catch {
                    FileHandle.standardError.write("ERROR: \(error)\n".data(using: .utf8)!)
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }
}

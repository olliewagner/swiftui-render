import ArgumentParser
import Foundation

struct Snapshot: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Output accessibility tree with @e refs (like agent-browser snapshot)"
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
            deviceFrame: false,
            noCache: options.noCache,
            snapshot: true
        )

        // Snapshot always uses daemon (needs real UIWindow for accessibility)
        try DaemonClient.render(config: config)
    }
}

import ArgumentParser
import Foundation

struct Snapshot: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Output accessibility tree with @e refs (like agent-browser snapshot)",
        discussion: """
            Requires the daemon (auto-started if not running). Outputs element
            references to stderr for use in automated UI inspection.

            Examples:
              swiftui-render snapshot MyView.swift --iphone
              swiftui-render snapshot MyView.swift --json
            """
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
            deviceFrame: false,
            noCache: options.noCache,
            snapshot: true,
            json: options.json
        )

        // Snapshot always uses daemon (needs real UIWindow for accessibility)
        try DaemonClient.render(config: config)
    }
}

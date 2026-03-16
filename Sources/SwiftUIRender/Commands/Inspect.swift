import ArgumentParser
import Foundation

struct Inspect: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Render with debug annotations and view tree dump"
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
            backend: .catalyst, // Annotate requires Catalyst
            annotate: true,
            tree: true,
            deviceFrame: options.deviceFrame,
            noCache: options.noCache
        )

        if options.daemon {
            try DaemonClient.render(config: config)
        } else {
            try CompileAndRender.run(config: config)
        }
    }
}

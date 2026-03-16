import ArgumentParser
import Foundation

struct Inspect: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Render with debug annotations and view tree dump"
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
            annotate: true,
            tree: true,
            deviceFrame: options.deviceFrame,
            noCache: options.noCache,
            json: options.json
        )

        if options.daemon {
            try DaemonClient.render(config: config)
        } else {
            try CompileAndRender.run(config: config)
        }
    }
}

import ArgumentParser
import Foundation

struct Render: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Render a SwiftUI view to PNG"
    )

    @OptionGroup var options: RenderOptions

    @Option(name: .long, help: "Rendering backend")
    var backend: RenderBackend = .imageRenderer

    mutating func run() throws {
        let inputPath = try options.inputPath
        let config = RenderConfig(
            inputPath: inputPath,
            outputPath: options.output,
            width: options.resolvedWidth,
            height: options.resolvedHeight,
            scale: options.scale,
            dark: options.dark,
            backend: backend,
            annotate: false,
            tree: false,
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

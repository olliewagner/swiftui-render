import ArgumentParser
import Foundation

struct Render: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Render a SwiftUI view to PNG",
        discussion: """
            Examples:
              swiftui-render render MyView.swift
              swiftui-render render MyView.swift --iphone --dark
              swiftui-render render MyView.swift -w 375 -h 667 -o screenshot.png
              swiftui-render render MyView.swift --json
              swiftui-render render MyView.swift --device-frame --iphone-pro-max
            """
    )

    @OptionGroup var options: RenderOptions

    @Option(name: .long, help: "Rendering backend (default, apphost, catalyst)")
    var backend: RenderBackend = .imageRenderer

    mutating func run() throws {
        try SwiftCompiler.ensureToolchainAvailable()
        try options.validateInput()
        options.warnAboutSystemContainers(backend: backend)
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

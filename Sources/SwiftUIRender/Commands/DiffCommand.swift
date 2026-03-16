import ArgumentParser
import Foundation

struct Diff: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Visual side-by-side diff of two SwiftUI views"
    )

    @Argument(help: "First Swift file (before)")
    var inputA: String

    @Argument(help: "Second Swift file (after)")
    var inputB: String

    @Option(name: .shortAndLong, help: "Output PNG path")
    var output: String = "/tmp/swiftui-render-diff.png"

    @Option(name: .shortAndLong, help: "Scale")
    var scale: Double = 2

    @Flag(help: "iPhone 15 (390×844)")
    var iphone: Bool = false

    @Flag(name: .long, help: "iPhone 15 Pro Max (430×932)")
    var iphoneProMax: Bool = false

    mutating func run() throws {
        let width = iphone ? 390.0 : iphoneProMax ? 430.0 : nil
        let height = iphone ? 844.0 : iphoneProMax ? 932.0 : nil

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftui-render-diff-\(ProcessInfo.processInfo.processIdentifier)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let pathA = tmpDir.appendingPathComponent("a.png").path
        let pathB = tmpDir.appendingPathComponent("b.png").path

        // Render A
        FileHandle.standardError.write("Rendering A: \(URL(fileURLWithPath: inputA).lastPathComponent)\n".data(using: .utf8)!)
        let configA = RenderConfig(
            inputPath: (inputA as NSString).standardizingPath,
            outputPath: pathA,
            width: width, height: height, scale: scale,
            dark: false, backend: .imageRenderer,
            annotate: false, tree: false, deviceFrame: false, noCache: true
        )
        try CompileAndRender.run(config: configA)

        // Render B
        FileHandle.standardError.write("Rendering B: \(URL(fileURLWithPath: inputB).lastPathComponent)\n".data(using: .utf8)!)
        let configB = RenderConfig(
            inputPath: (inputB as NSString).standardizingPath,
            outputPath: pathB,
            width: width, height: height, scale: scale,
            dark: false, backend: .imageRenderer,
            annotate: false, tree: false, deviceFrame: false, noCache: true
        )
        try CompileAndRender.run(config: configB)

        // Compose side-by-side
        try DiffComposer.compose(imageA: pathA, imageB: pathB, output: output, scale: scale)
    }
}

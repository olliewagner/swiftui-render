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

    @Flag(help: "iPhone 15 (390x844)")
    var iphone: Bool = false

    @Flag(name: .long, help: "iPhone 15 Pro Max (430x932)")
    var iphoneProMax: Bool = false

    mutating func run() throws {
        let width = iphone ? 390.0 : iphoneProMax ? 430.0 : nil
        let height = iphone ? 844.0 : iphoneProMax ? 932.0 : nil

        // Validate inputs exist
        let pathA = resolveAbsolutePath(inputA)
        let pathB = resolveAbsolutePath(inputB)
        guard FileManager.default.fileExists(atPath: pathA) else {
            throw ValidationError("File not found: \(inputA)")
        }
        guard FileManager.default.fileExists(atPath: pathB) else {
            throw ValidationError("File not found: \(inputB)")
        }

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "swiftui-render-diff-\(ProcessInfo.processInfo.processIdentifier)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let imgA = tmpDir.appendingPathComponent("a.png").path
        let imgB = tmpDir.appendingPathComponent("b.png").path

        // Render A
        stderr("Rendering A: \(URL(fileURLWithPath: inputA).lastPathComponent)\n")
        let configA = RenderConfig(
            inputPath: pathA,
            outputPath: imgA,
            width: width, height: height, scale: scale,
            dark: false, backend: .imageRenderer,
            annotate: false, tree: false, deviceFrame: false, noCache: true
        )
        try CompileAndRender.run(config: configA)

        // Render B
        stderr("Rendering B: \(URL(fileURLWithPath: inputB).lastPathComponent)\n")
        let configB = RenderConfig(
            inputPath: pathB,
            outputPath: imgB,
            width: width, height: height, scale: scale,
            dark: false, backend: .imageRenderer,
            annotate: false, tree: false, deviceFrame: false, noCache: true
        )
        try CompileAndRender.run(config: configB)

        // Compose side-by-side (in-process, no separate compilation)
        try DiffComposer.compose(imageA: imgA, imageB: imgB, output: output, scale: scale)
    }

    private func resolveAbsolutePath(_ path: String) -> String {
        let expanded = (path as NSString).standardizingPath
        return expanded.hasPrefix("/")
            ? expanded : FileManager.default.currentDirectoryPath + "/" + expanded
    }
}

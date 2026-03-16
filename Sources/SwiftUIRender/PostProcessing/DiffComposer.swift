import Foundation

/// Composes a side-by-side diff image from two rendered PNGs
enum DiffComposer {
    static func compose(imageA: String, imageB: String, output: String, scale: Double) throws {
        // Generate a small Swift program to compose the images
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftui-render-diff-compose-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let composerPath = tmpDir.appendingPathComponent("composer.swift").path
        let binaryPath = tmpDir.appendingPathComponent("composer").path

        let source = """
        import AppKit

        @main struct Composer {
            @MainActor static func main() {
                let args = CommandLine.arguments
                guard args.count >= 4,
                      let imgA = NSImage(contentsOfFile: args[1]),
                      let imgB = NSImage(contentsOfFile: args[2]) else {
                    fputs("ERROR: Could not load images\\n", stderr); exit(1)
                }

                let aSize = imgA.size, bSize = imgB.size
                let gap: CGFloat = 20, labelH: CGFloat = 30
                let totalW = aSize.width + gap + bSize.width
                let totalH = max(aSize.height, bSize.height) + labelH

                let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                    pixelsWide: Int(totalW * 2), pixelsHigh: Int(totalH * 2),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

                guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = ctx
                ctx.cgContext.scaleBy(x: 2, y: 2)

                NSColor.windowBackgroundColor.setFill()
                NSRect(x: 0, y: 0, width: totalW, height: totalH).fill()

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
                ("A: Before" as NSString).draw(at: NSPoint(x: aSize.width/2 - 30, y: totalH - labelH + 8), withAttributes: attrs)
                ("B: After" as NSString).draw(at: NSPoint(x: aSize.width + gap + bSize.width/2 - 25, y: totalH - labelH + 8), withAttributes: attrs)

                imgA.draw(in: NSRect(x: 0, y: 0, width: aSize.width, height: aSize.height))
                imgB.draw(in: NSRect(x: aSize.width + gap, y: 0, width: bSize.width, height: bSize.height))

                NSColor.separatorColor.setFill()
                NSRect(x: aSize.width + gap/2 - 1, y: 0, width: 2, height: totalH - labelH).fill()

                NSGraphicsContext.restoreGraphicsState()

                guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
                try! png.write(to: URL(fileURLWithPath: args[3]))
                print("\\(Int(totalW * 2))×\\(Int(totalH * 2)) (\\(png.count / 1024)KB) → \\(args[3])")
            }
        }
        """

        try source.write(toFile: composerPath, atomically: true, encoding: .utf8)

        // Compile
        let compileTask = Process()
        compileTask.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compileTask.arguments = ["swiftc", "-swift-version", "5", "-suppress-warnings", "-parse-as-library",
                                 "-framework", "AppKit", composerPath, "-o", binaryPath]
        try compileTask.run()
        compileTask.waitUntilExit()

        guard compileTask.terminationStatus == 0 else {
            throw CompilationError.failed("Diff composer compilation failed")
        }

        // Run
        let runTask = Process()
        runTask.executableURL = URL(fileURLWithPath: binaryPath)
        runTask.arguments = [imageA, imageB, output]
        let outPipe = Pipe()
        runTask.standardOutput = outPipe
        try runTask.run()
        runTask.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        if let str = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
            print(str)
        }
    }
}

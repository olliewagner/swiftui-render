import AppKit
import Foundation

/// Composes a side-by-side diff image from two rendered PNGs — in-process using AppKit
enum DiffComposer {
    static func compose(imageA: String, imageB: String, output: String, scale: Double, json: Bool = false) throws {
        guard let imgA = NSImage(contentsOfFile: imageA) else {
            throw DiffError.cannotLoad(imageA)
        }
        guard let imgB = NSImage(contentsOfFile: imageB) else {
            throw DiffError.cannotLoad(imageB)
        }

        let aSize = imgA.size
        let bSize = imgB.size
        let gap: CGFloat = 20
        let labelH: CGFloat = 30
        let totalW = aSize.width + gap + bSize.width
        let totalH = max(aSize.height, bSize.height) + labelH
        let pixelScale = CGFloat(scale)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(totalW * pixelScale),
            pixelsHigh: Int(totalH * pixelScale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw DiffError.bitmapFailed
        }

        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            throw DiffError.bitmapFailed
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.cgContext.scaleBy(x: pixelScale, y: pixelScale)

        // Background
        NSColor.windowBackgroundColor.setFill()
        NSRect(x: 0, y: 0, width: totalW, height: totalH).fill()

        // Labels
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        ("A: Before" as NSString).draw(
            at: NSPoint(x: aSize.width / 2 - 30, y: totalH - labelH + 8), withAttributes: attrs)
        ("B: After" as NSString).draw(
            at: NSPoint(x: aSize.width + gap + bSize.width / 2 - 25, y: totalH - labelH + 8),
            withAttributes: attrs)

        // Images
        imgA.draw(in: NSRect(x: 0, y: 0, width: aSize.width, height: aSize.height))
        imgB.draw(in: NSRect(x: aSize.width + gap, y: 0, width: bSize.width, height: bSize.height))

        // Separator
        NSColor.separatorColor.setFill()
        NSRect(x: aSize.width + gap / 2 - 1, y: 0, width: 2, height: totalH - labelH).fill()

        NSGraphicsContext.restoreGraphicsState()

        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw DiffError.pngFailed
        }

        let url = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)

        let pw = Int(totalW * pixelScale)
        let ph = Int(totalH * pixelScale)
        if json {
            let escaped = output.replacingOccurrences(of: "\"", with: "\\\"")
            print("{\"width\":\(pw),\"height\":\(ph),\"size\":\(png.count),\"path\":\"\(escaped)\"}")
        } else {
            print("\(pw)x\(ph) (\(png.count / 1024)KB) -> \(output)")
        }
    }
}

enum DiffError: LocalizedError {
    case cannotLoad(String)
    case bitmapFailed
    case pngFailed

    var errorDescription: String? {
        switch self {
        case .cannotLoad(let path): return "Could not load image: \(path)"
        case .bitmapFailed: return "Failed to create bitmap context"
        case .pngFailed: return "Failed to encode PNG"
        }
    }
}

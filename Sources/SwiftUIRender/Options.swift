import ArgumentParser
import Foundation

/// Shared options for all rendering commands
struct RenderOptions: ParsableArguments {
    @Argument(help: "Swift file defining `struct Preview: View`")
    var input: String

    @Option(name: .shortAndLong, help: "Output PNG path")
    var output: String = "/tmp/swiftui-render.png"

    @Option(name: .shortAndLong, help: "Width in points")
    var width: Double?

    @Option(name: .shortAndLong, help: "Height in points")
    var height: Double?

    @Option(name: .shortAndLong, help: "Render scale")
    var scale: Double = 2

    @Flag(help: "Dark mode")
    var dark: Bool = false

    @Flag(help: "Add iPhone device chrome (Dynamic Island, status bar, home indicator)")
    var deviceFrame: Bool = false

    @Flag(help: "Use hot-reload daemon for faster rendering")
    var daemon: Bool = false

    @Flag(help: "Skip binary cache")
    var noCache: Bool = false

    // Size presets
    @Flag(help: "iPhone 15 (390×844)")
    var iphone: Bool = false

    @Flag(help: "iPhone SE (375×667)")
    var iphoneSe: Bool = false

    @Flag(name: .long, help: "iPhone 15 Pro Max (430×932)")
    var iphoneProMax: Bool = false

    @Flag(help: "iPad Pro 12.9\" (1024×1366)")
    var ipad: Bool = false

    @Flag(name: .long, help: "Small widget (170×170)")
    var widgetSmall: Bool = false

    @Flag(name: .long, help: "Medium widget (364×170)")
    var widgetMedium: Bool = false

    @Flag(name: .long, help: "Large widget (364×382)")
    var widgetLarge: Bool = false

    /// Resolved width from flags/options
    var resolvedWidth: Double? {
        if let width { return width }
        if iphone { return 390 }
        if iphoneSe { return 375 }
        if iphoneProMax { return 430 }
        if ipad { return 1024 }
        if widgetSmall { return 170 }
        if widgetMedium { return 364 }
        if widgetLarge { return 364 }
        return nil
    }

    /// Resolved height from flags/options
    var resolvedHeight: Double? {
        if let height { return height }
        if iphone { return 844 }
        if iphoneSe { return 667 }
        if iphoneProMax { return 932 }
        if ipad { return 1366 }
        if widgetSmall { return 170 }
        if widgetMedium { return 170 }
        if widgetLarge { return 382 }
        return nil
    }

    /// Absolute path to input file
    var inputPath: String {
        get throws {
            let path = (input as NSString).standardizingPath
            let absolute = path.hasPrefix("/") ? path : FileManager.default.currentDirectoryPath + "/" + path
            guard FileManager.default.fileExists(atPath: absolute) else {
                throw ValidationError("File not found: \(input)")
            }
            return absolute
        }
    }
}

/// Rendering backend
enum RenderBackend: String, CaseIterable, ExpressibleByArgument {
    case imageRenderer = "default"
    case apphost
    case catalyst
}

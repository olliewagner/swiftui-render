import ArgumentParser
import Foundation

@main
struct SwiftUIRender: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftui-render",
        abstract: "Headless SwiftUI renderer -- render views to PNG without Xcode or Simulator",
        discussion: """
            Compile and render SwiftUI views from the command line. Input files must
            define `struct Preview: View` as the entry point.

            Quick start:
              swiftui-render MyView.swift                        # render to /tmp/swiftui-render.png
              swiftui-render MyView.swift --iphone --dark        # iPhone 15, dark mode
              swiftui-render MyView.swift -w 375 -h 667 -o out.png
              swiftui-render diff Before.swift After.swift       # side-by-side comparison
              swiftui-render inspect MyView.swift --iphone       # debug annotations + view tree
            """,
        version: "0.2.0",
        subcommands: [
            Render.self,
            Inspect.self,
            Snapshot.self,
            Preview.self,
            Diff.self,
            Daemon.self,
            Cache.self,
        ],
        defaultSubcommand: Render.self
    )
}

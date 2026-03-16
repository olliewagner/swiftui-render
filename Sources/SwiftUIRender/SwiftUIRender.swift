import ArgumentParser
import Foundation

@main
struct SwiftUIRender: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftui-render",
        abstract: "Headless SwiftUI renderer -- render views to PNG without Xcode or Simulator",
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

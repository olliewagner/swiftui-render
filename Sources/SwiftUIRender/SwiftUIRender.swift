import ArgumentParser
import Foundation

@main
struct SwiftUIRender: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftui-render",
        abstract: "Headless SwiftUI renderer — render views to PNG without Xcode",
        version: "0.1.0",
        subcommands: [
            Render.self,
            Inspect.self,
            Snapshot.self,
            Preview.self,
            Diff.self,
            Daemon.self,
        ],
        defaultSubcommand: Render.self
    )
}

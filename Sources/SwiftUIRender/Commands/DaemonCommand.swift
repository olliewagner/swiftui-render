import ArgumentParser
import Foundation

struct Daemon: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage the hot-reload daemon",
        subcommands: [Start.self, Stop.self, Status.self, Build.self],
        defaultSubcommand: Status.self
    )

    struct Start: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Start the daemon")

        mutating func run() throws {
            try DaemonClient.start()
        }
    }

    struct Stop: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Stop the daemon")

        mutating func run() throws {
            try DaemonClient.stop()
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Check daemon status")

        mutating func run() throws {
            if DaemonClient.isRunning {
                let pid = try String(contentsOfFile: DaemonClient.pidPath, encoding: .utf8)
                print(
                    "Daemon running (PID \(pid.trimmingCharacters(in: .whitespacesAndNewlines)))")
            } else {
                print("Daemon not running")
            }
        }
    }

    struct Build: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Build the daemon app from embedded source"
        )

        mutating func run() throws {
            try DaemonClient.buildDaemon()
        }
    }
}

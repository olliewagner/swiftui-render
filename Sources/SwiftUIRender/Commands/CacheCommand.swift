import ArgumentParser
import Foundation

struct Cache: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage the binary cache",
        subcommands: [Info.self, Clear.self],
        defaultSubcommand: Info.self
    )

    struct Info: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show cache size and entry count")

        mutating func run() throws {
            let dir = CompileAndRender.cacheDirPath
            let fm = FileManager.default

            guard fm.fileExists(atPath: dir) else {
                print("Cache directory: \(dir)")
                print("Entries: 0")
                print("Size: 0 KB")
                return
            }

            var totalSize: UInt64 = 0
            var entryCount = 0

            if let enumerator = fm.enumerator(atPath: dir) {
                while let file = enumerator.nextObject() as? String {
                    let fullPath = (dir as NSString).appendingPathComponent(file)
                    if let attrs = try? fm.attributesOfItem(atPath: fullPath),
                        let size = attrs[.size] as? UInt64
                    {
                        totalSize += size
                        // Only count top-level entries (not files inside .app bundles)
                        if !(file as NSString).pathComponents.dropFirst().contains(where: {
                            $0 != file
                        }) && !file.contains("/") {
                            entryCount += 1
                        }
                    }
                }
            }

            let sizeMB = Double(totalSize) / 1_048_576
            print("Cache directory: \(dir)")
            print("Entries: \(entryCount)")
            if sizeMB >= 1 {
                print("Size: \(String(format: "%.1f", sizeMB)) MB")
            } else {
                print("Size: \(totalSize / 1024) KB")
            }
        }
    }

    struct Clear: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Clear all cached binaries")

        mutating func run() throws {
            let dir = CompileAndRender.cacheDirPath
            let fm = FileManager.default

            guard fm.fileExists(atPath: dir) else {
                print("Cache already empty")
                return
            }

            var count = 0
            if let contents = try? fm.contentsOfDirectory(atPath: dir) {
                count = contents.count
                for item in contents {
                    try? fm.removeItem(atPath: (dir as NSString).appendingPathComponent(item))
                }
            }

            print("Cleared \(count) cached entries")
        }
    }
}

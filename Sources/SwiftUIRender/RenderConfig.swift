import Foundation

/// Complete configuration for a single render operation
struct RenderConfig {
    let inputPath: String
    let outputPath: String
    let width: Double?
    let height: Double?
    let scale: Double
    let dark: Bool
    let backend: RenderBackend
    let annotate: Bool
    let tree: Bool
    let deviceFrame: Bool
    let noCache: Bool
    var snapshot: Bool = false

    var resolvedWidth: Double { width ?? 390 }
    var resolvedHeight: Double { height ?? 844 }

    /// Cache key based on content + options (excludes output path for reusability)
    var cacheKey: String {
        let content = (try? String(contentsOfFile: inputPath, encoding: .utf8)) ?? ""
        let key = "\(content)|\(backend)|\(width ?? 0)|\(height ?? 0)|\(scale)|\(dark)|\(annotate)|\(deviceFrame)"
        return key.sha256Prefix(16)
    }
}

extension String {
    func sha256Prefix(_ length: Int) -> String {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        task.arguments = ["-a", "256"]
        task.standardInput = Pipe()
        task.standardOutput = pipe

        try? task.run()
        (task.standardInput as? Pipe)?.fileHandleForWriting.write(self.data(using: .utf8)!)
        (task.standardInput as? Pipe)?.fileHandleForWriting.closeFile()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let hash = String(data: data, encoding: .utf8) ?? ""
        return String(hash.prefix(length))
    }
}

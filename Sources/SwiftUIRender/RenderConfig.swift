import CryptoKit
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
    var json: Bool = false

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
        guard let data = self.data(using: .utf8) else { return "" }
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(length))
    }
}

extension FileHandle {
    /// Write a string to a file handle (stderr convenience)
    func write(_ string: String) {
        if let data = string.data(using: .utf8) {
            write(data)
        }
    }
}

/// Write a message to stderr
func stderr(_ message: String) {
    FileHandle.standardError.write(message)
}

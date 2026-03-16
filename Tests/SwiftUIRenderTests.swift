import XCTest

@testable import SwiftUIRender

// MARK: - RenderConfig Tests

final class RenderConfigTests: XCTestCase {

    func testCacheKeyIsStableForSameInput() throws {
        let testFile = "/tmp/swiftui-render-test-cachekey.swift"
        try "import SwiftUI\nstruct Preview: View { var body: some View { Text(\"Hello\") } }"
            .write(toFile: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: testFile) }

        let config1 = makeConfig(inputPath: testFile)
        let config2 = makeConfig(inputPath: testFile)

        XCTAssertEqual(config1.cacheKey, config2.cacheKey)
        XCTAssertEqual(config1.cacheKey.count, 16)
    }

    func testCacheKeyChangesWithContent() throws {
        let testFile = "/tmp/swiftui-render-test-cachekey2.swift"
        try "import SwiftUI\nstruct Preview: View { var body: some View { Text(\"A\") } }"
            .write(toFile: testFile, atomically: true, encoding: .utf8)
        let key1 = makeConfig(inputPath: testFile).cacheKey

        try "import SwiftUI\nstruct Preview: View { var body: some View { Text(\"B\") } }"
            .write(toFile: testFile, atomically: true, encoding: .utf8)
        let key2 = makeConfig(inputPath: testFile).cacheKey

        defer { try? FileManager.default.removeItem(atPath: testFile) }
        XCTAssertNotEqual(key1, key2)
    }

    func testCacheKeyChangesWithOptions() throws {
        let testFile = "/tmp/swiftui-render-test-cachekey3.swift"
        try "import SwiftUI\nstruct Preview: View { var body: some View { Text(\"X\") } }"
            .write(toFile: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: testFile) }

        let light = makeConfig(inputPath: testFile, dark: false)
        let dark = makeConfig(inputPath: testFile, dark: true)
        XCTAssertNotEqual(light.cacheKey, dark.cacheKey)

        let small = makeConfig(inputPath: testFile, width: 200, height: 200)
        let large = makeConfig(inputPath: testFile, width: 400, height: 800)
        XCTAssertNotEqual(small.cacheKey, large.cacheKey)
    }

    func testResolvedDimensionsDefaults() {
        let config = makeConfig(inputPath: "/tmp/dummy.swift")
        XCTAssertEqual(config.resolvedWidth, 390)
        XCTAssertEqual(config.resolvedHeight, 844)
    }

    func testResolvedDimensionsWithExplicit() {
        let config = makeConfig(inputPath: "/tmp/dummy.swift", width: 100, height: 200)
        XCTAssertEqual(config.resolvedWidth, 100)
        XCTAssertEqual(config.resolvedHeight, 200)
    }

    private func makeConfig(
        inputPath: String,
        width: Double? = nil,
        height: Double? = nil,
        dark: Bool = false
    ) -> RenderConfig {
        RenderConfig(
            inputPath: inputPath,
            outputPath: "/tmp/test-output.png",
            width: width,
            height: height,
            scale: 2,
            dark: dark,
            backend: .imageRenderer,
            annotate: false,
            tree: false,
            deviceFrame: false,
            noCache: false
        )
    }
}

// MARK: - SHA256 Tests

final class SHA256Tests: XCTestCase {

    func testSHA256PrefixConsistency() {
        let hash1 = "hello world".sha256Prefix(16)
        let hash2 = "hello world".sha256Prefix(16)
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash1.count, 16)
    }

    func testSHA256PrefixDifferentInputs() {
        let hash1 = "abc".sha256Prefix(16)
        let hash2 = "def".sha256Prefix(16)
        XCTAssertNotEqual(hash1, hash2)
    }

    func testSHA256PrefixIsHex() {
        let hash = "test".sha256Prefix(16)
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        for char in hash.unicodeScalars {
            XCTAssertTrue(hexChars.contains(char), "Non-hex character: \(char)")
        }
    }

    func testSHA256KnownValue() {
        // SHA-256 of empty string is e3b0c44298fc1c14...
        let hash = "".sha256Prefix(16)
        XCTAssertEqual(hash, "e3b0c44298fc1c14")
    }
}

// MARK: - TemplateGenerator Tests

final class TemplateGeneratorTests: XCTestCase {

    func testImageRendererTemplateContainsRequiredElements() {
        let config = RenderConfig(
            inputPath: "/tmp/test.swift",
            outputPath: "/tmp/out.png",
            width: 390, height: 844, scale: 2,
            dark: false, backend: .imageRenderer,
            annotate: false, tree: false, deviceFrame: false, noCache: false
        )
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains("import SwiftUI"))
        XCTAssertTrue(template.contains("import AppKit"))
        XCTAssertTrue(template.contains("ImageRenderer"))
        XCTAssertTrue(template.contains("Preview()"))
        XCTAssertTrue(template.contains("/tmp/out.png"))
        XCTAssertTrue(template.contains(".light"))
    }

    func testCatalystTemplateContainsRequiredElements() {
        let config = RenderConfig(
            inputPath: "/tmp/test.swift",
            outputPath: "/tmp/out.png",
            width: 390, height: 844, scale: 2,
            dark: true, backend: .catalyst,
            annotate: false, tree: false, deviceFrame: false, noCache: false
        )
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains("import UIKit"))
        XCTAssertTrue(template.contains("UIHostingController"))
        XCTAssertTrue(template.contains("Preview()"))
        XCTAssertTrue(template.contains(".dark"))
    }

    func testCatalystTemplateWithAnnotations() {
        let config = RenderConfig(
            inputPath: "/tmp/test.swift",
            outputPath: "/tmp/out.png",
            width: 390, height: 844, scale: 2,
            dark: false, backend: .catalyst,
            annotate: true, tree: true, deviceFrame: true, noCache: false
        )
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains("__collectLayers"))
        XCTAssertTrue(template.contains("__drawAnnotations"))
        XCTAssertTrue(template.contains("__dumpTree"))
        XCTAssertTrue(template.contains("__addDeviceFrame"))
    }

    func testDarkModeTemplateGeneration() {
        let config = RenderConfig(
            inputPath: "/tmp/test.swift",
            outputPath: "/tmp/out.png",
            width: nil, height: nil, scale: 2,
            dark: true, backend: .imageRenderer,
            annotate: false, tree: false, deviceFrame: false, noCache: false
        )
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains("Color.black"))
        XCTAssertTrue(template.contains(".dark"))
    }

    func testFrameModifierWithWidthAndHeight() {
        let config = RenderConfig(
            inputPath: "/tmp/test.swift",
            outputPath: "/tmp/out.png",
            width: 200, height: 300, scale: 2,
            dark: false, backend: .imageRenderer,
            annotate: false, tree: false, deviceFrame: false, noCache: false
        )
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains(".frame(width: 200.0, height: 300.0)"))
    }

    func testFrameModifierWithNoSize() {
        let config = RenderConfig(
            inputPath: "/tmp/test.swift",
            outputPath: "/tmp/out.png",
            width: nil, height: nil, scale: 2,
            dark: false, backend: .imageRenderer,
            annotate: false, tree: false, deviceFrame: false, noCache: false
        )
        let template = TemplateGenerator.generate(config: config)
        XCTAssertFalse(template.contains(".frame("))
    }

    func testCatalystOutputInfoFile() {
        let config = RenderConfig(
            inputPath: "/tmp/test.swift",
            outputPath: "/tmp/out.png",
            width: 390, height: 844, scale: 2,
            dark: false, backend: .catalyst,
            annotate: false, tree: false, deviceFrame: false, noCache: false
        )
        let template = TemplateGenerator.generate(
            config: config, outputInfoPath: "/tmp/output-info.txt")
        XCTAssertTrue(template.contains("output-info.txt"))
        XCTAssertTrue(template.contains("write(toFile:"))
    }
}

// MARK: - SwiftCompiler Tests

final class SwiftCompilerTests: XCTestCase {

    func testSDKPathIsNotEmpty() {
        XCTAssertFalse(SwiftCompiler.sdkPath.isEmpty)
    }

    func testFileHashConsistency() throws {
        let testFile = "/tmp/swiftui-render-test-hash.swift"
        try "test content".write(toFile: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: testFile) }

        let hash1 = try SwiftCompiler.fileHash(testFile)
        let hash2 = try SwiftCompiler.fileHash(testFile)
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash1.count, 16)
    }

    func testFileHashChangesWithContent() throws {
        let testFile = "/tmp/swiftui-render-test-hash2.swift"
        try "content A".write(toFile: testFile, atomically: true, encoding: .utf8)
        let hash1 = try SwiftCompiler.fileHash(testFile)

        try "content B".write(toFile: testFile, atomically: true, encoding: .utf8)
        let hash2 = try SwiftCompiler.fileHash(testFile)

        defer { try? FileManager.default.removeItem(atPath: testFile) }
        XCTAssertNotEqual(hash1, hash2)
    }
}

// MARK: - Integration Tests

final class IntegrationTests: XCTestCase {

    func testFullRenderPipeline() throws {
        let testFile = "/tmp/swiftui-render-integration-test.swift"
        let outputFile = "/tmp/swiftui-render-integration-output.png"
        try """
            import SwiftUI
            struct Preview: View {
                var body: some View {
                    Text("Integration Test")
                        .font(.title)
                        .padding()
                }
            }
            """.write(toFile: testFile, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(atPath: testFile)
            try? FileManager.default.removeItem(atPath: outputFile)
        }

        let config = RenderConfig(
            inputPath: testFile,
            outputPath: outputFile,
            width: nil, height: nil, scale: 2,
            dark: false, backend: .imageRenderer,
            annotate: false, tree: false, deviceFrame: false, noCache: true
        )
        try CompileAndRender.run(config: config)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputFile))
        let attrs = try FileManager.default.attributesOfItem(atPath: outputFile)
        let size = attrs[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 100, "Output PNG should not be empty")
    }

    func testRenderWithDimensions() throws {
        let testFile = "/tmp/swiftui-render-dims-test.swift"
        let outputFile = "/tmp/swiftui-render-dims-output.png"
        try """
            import SwiftUI
            struct Preview: View {
                var body: some View {
                    Color.blue
                }
            }
            """.write(toFile: testFile, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(atPath: testFile)
            try? FileManager.default.removeItem(atPath: outputFile)
        }

        let config = RenderConfig(
            inputPath: testFile,
            outputPath: outputFile,
            width: 200, height: 200, scale: 1,
            dark: false, backend: .imageRenderer,
            annotate: false, tree: false, deviceFrame: false, noCache: true
        )
        try CompileAndRender.run(config: config)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputFile))
    }

    func testRenderDarkMode() throws {
        let testFile = "/tmp/swiftui-render-dark-test.swift"
        let outputFile = "/tmp/swiftui-render-dark-output.png"
        try """
            import SwiftUI
            struct Preview: View {
                var body: some View {
                    Text("Dark Mode")
                        .foregroundColor(.primary)
                }
            }
            """.write(toFile: testFile, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(atPath: testFile)
            try? FileManager.default.removeItem(atPath: outputFile)
        }

        let config = RenderConfig(
            inputPath: testFile,
            outputPath: outputFile,
            width: nil, height: nil, scale: 2,
            dark: true, backend: .imageRenderer,
            annotate: false, tree: false, deviceFrame: false, noCache: true
        )
        try CompileAndRender.run(config: config)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputFile))
    }

    func testCompilationError() throws {
        let testFile = "/tmp/swiftui-render-error-test.swift"
        try "this is not valid swift {{{".write(
            toFile: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: testFile) }

        let config = RenderConfig(
            inputPath: testFile,
            outputPath: "/tmp/swiftui-render-error-output.png",
            width: nil, height: nil, scale: 2,
            dark: false, backend: .imageRenderer,
            annotate: false, tree: false, deviceFrame: false, noCache: true
        )

        XCTAssertThrowsError(try CompileAndRender.run(config: config))
    }
}

// MARK: - DaemonClient Tests

final class DaemonClientTests: XCTestCase {

    func testBridgeSourceIsValid() {
        let source = DaemonClient.bridgeSource
        XCTAssertTrue(source.contains("import SwiftUI"))
        XCTAssertTrue(source.contains("_createHostingController"))
        XCTAssertTrue(source.contains("Preview()"))
    }

    func testBridgePathCreatesMissingFile() {
        let path = DaemonClient.bridgePath
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }
}

// MARK: - RenderBackend Tests

final class RenderBackendTests: XCTestCase {

    func testAllCases() {
        XCTAssertEqual(RenderBackend.allCases.count, 3)
        XCTAssertEqual(RenderBackend.imageRenderer.rawValue, "default")
        XCTAssertEqual(RenderBackend.apphost.rawValue, "apphost")
        XCTAssertEqual(RenderBackend.catalyst.rawValue, "catalyst")
    }
}

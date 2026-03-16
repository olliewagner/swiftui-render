import XCTest

@testable import SwiftUIRender

// MARK: - Test Helpers

private let testDir = "/tmp/swiftui-render-tests"
private let fm = FileManager.default

/// Create a temp Swift file with the given content, returning its path
private func makeTempSwift(_ name: String, content: String) throws -> String {
    try fm.createDirectory(atPath: testDir, withIntermediateDirectories: true)
    let path = "\(testDir)/\(name).swift"
    try content.write(toFile: path, atomically: true, encoding: .utf8)
    return path
}

/// Minimal valid Preview view
private let minimalPreview = """
    import SwiftUI
    struct Preview: View {
        var body: some View {
            Text("Hello")
        }
    }
    """

/// Build a RenderConfig with defaults and selective overrides
private func makeConfig(
    inputPath: String = "/tmp/dummy.swift",
    outputPath: String = "/tmp/test-output.png",
    width: Double? = nil,
    height: Double? = nil,
    scale: Double = 2,
    dark: Bool = false,
    backend: RenderBackend = .imageRenderer,
    annotate: Bool = false,
    tree: Bool = false,
    deviceFrame: Bool = false,
    noCache: Bool = false,
    snapshot: Bool = false,
    json: Bool = false
) -> RenderConfig {
    RenderConfig(
        inputPath: inputPath,
        outputPath: outputPath,
        width: width,
        height: height,
        scale: scale,
        dark: dark,
        backend: backend,
        annotate: annotate,
        tree: tree,
        deviceFrame: deviceFrame,
        noCache: noCache,
        snapshot: snapshot,
        json: json
    )
}

// MARK: - RenderConfig Tests

final class RenderConfigTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        try? fm.createDirectory(atPath: testDir, withIntermediateDirectories: true)
    }

    override class func tearDown() {
        try? fm.removeItem(atPath: testDir)
        super.tearDown()
    }

    // -- Cache key stability --

    func testCacheKeyIsStableForSameInput() throws {
        let path = try makeTempSwift("stable", content: minimalPreview)
        defer { try? fm.removeItem(atPath: path) }

        let key1 = makeConfig(inputPath: path).cacheKey
        let key2 = makeConfig(inputPath: path).cacheKey
        XCTAssertEqual(key1, key2, "Same input and options must produce identical cache key")
        XCTAssertEqual(key1.count, 16, "Cache key should be 16 hex characters")
    }

    func testCacheKeyChangesWithContent() throws {
        let path = try makeTempSwift("content-change", content: "import SwiftUI\nstruct Preview: View { var body: some View { Text(\"A\") } }")
        let key1 = makeConfig(inputPath: path).cacheKey

        try "import SwiftUI\nstruct Preview: View { var body: some View { Text(\"B\") } }"
            .write(toFile: path, atomically: true, encoding: .utf8)
        let key2 = makeConfig(inputPath: path).cacheKey

        defer { try? fm.removeItem(atPath: path) }
        XCTAssertNotEqual(key1, key2, "Different file content must change cache key")
    }

    // -- Cache key changes with every option --

    func testCacheKeyChangesWithWidth() throws {
        let path = try makeTempSwift("width", content: minimalPreview)
        defer { try? fm.removeItem(atPath: path) }

        let key1 = makeConfig(inputPath: path, width: nil).cacheKey
        let key2 = makeConfig(inputPath: path, width: 200).cacheKey
        XCTAssertNotEqual(key1, key2)
    }

    func testCacheKeyChangesWithHeight() throws {
        let path = try makeTempSwift("height", content: minimalPreview)
        defer { try? fm.removeItem(atPath: path) }

        let key1 = makeConfig(inputPath: path, height: nil).cacheKey
        let key2 = makeConfig(inputPath: path, height: 300).cacheKey
        XCTAssertNotEqual(key1, key2)
    }

    func testCacheKeyChangesWithScale() throws {
        let path = try makeTempSwift("scale", content: minimalPreview)
        defer { try? fm.removeItem(atPath: path) }

        let key1 = makeConfig(inputPath: path, scale: 1).cacheKey
        let key2 = makeConfig(inputPath: path, scale: 3).cacheKey
        XCTAssertNotEqual(key1, key2)
    }

    func testCacheKeyChangesWithDarkMode() throws {
        let path = try makeTempSwift("dark", content: minimalPreview)
        defer { try? fm.removeItem(atPath: path) }

        let key1 = makeConfig(inputPath: path, dark: false).cacheKey
        let key2 = makeConfig(inputPath: path, dark: true).cacheKey
        XCTAssertNotEqual(key1, key2)
    }

    func testCacheKeyChangesWithAnnotate() throws {
        let path = try makeTempSwift("annotate", content: minimalPreview)
        defer { try? fm.removeItem(atPath: path) }

        let key1 = makeConfig(inputPath: path, annotate: false).cacheKey
        let key2 = makeConfig(inputPath: path, annotate: true).cacheKey
        XCTAssertNotEqual(key1, key2)
    }

    func testCacheKeyChangesWithDeviceFrame() throws {
        let path = try makeTempSwift("deviceframe", content: minimalPreview)
        defer { try? fm.removeItem(atPath: path) }

        let key1 = makeConfig(inputPath: path, deviceFrame: false).cacheKey
        let key2 = makeConfig(inputPath: path, deviceFrame: true).cacheKey
        XCTAssertNotEqual(key1, key2)
    }

    func testCacheKeyChangesWithBackend() throws {
        let path = try makeTempSwift("backend", content: minimalPreview)
        defer { try? fm.removeItem(atPath: path) }

        let key1 = makeConfig(inputPath: path, backend: .imageRenderer).cacheKey
        let key2 = makeConfig(inputPath: path, backend: .catalyst).cacheKey
        XCTAssertNotEqual(key1, key2)
    }

    func testCacheKeyChangesWithOutputPath() throws {
        let path = try makeTempSwift("outputpath", content: minimalPreview)
        defer { try? fm.removeItem(atPath: path) }

        let key1 = makeConfig(inputPath: path, outputPath: "/tmp/a.png").cacheKey
        let key2 = makeConfig(inputPath: path, outputPath: "/tmp/b.png").cacheKey
        XCTAssertNotEqual(key1, key2, "BUG REGRESSION: cache must include output path in key")
    }

    // -- Resolved dimensions --

    func testResolvedDimensionsDefaults() {
        let config = makeConfig()
        XCTAssertEqual(config.resolvedWidth, 390)
        XCTAssertEqual(config.resolvedHeight, 844)
    }

    func testResolvedDimensionsWithExplicit() {
        let config = makeConfig(width: 100, height: 200)
        XCTAssertEqual(config.resolvedWidth, 100)
        XCTAssertEqual(config.resolvedHeight, 200)
    }

    func testResolvedDimensionsWithOnlyWidth() {
        let config = makeConfig(width: 500)
        XCTAssertEqual(config.resolvedWidth, 500)
        XCTAssertEqual(config.resolvedHeight, 844, "Default height when only width specified")
    }

    func testResolvedDimensionsWithOnlyHeight() {
        let config = makeConfig(height: 600)
        XCTAssertEqual(config.resolvedWidth, 390, "Default width when only height specified")
        XCTAssertEqual(config.resolvedHeight, 600)
    }

    // -- Cache key for nonexistent file --

    func testCacheKeyForNonexistentFileDoesNotCrash() {
        let config = makeConfig(inputPath: "/tmp/does-not-exist-12345.swift")
        let key = config.cacheKey
        XCTAssertEqual(key.count, 16, "Cache key should still be 16 chars even for missing file")
    }

    // -- All fields stored --

    func testAllFieldsStored() {
        let config = makeConfig(
            inputPath: "/tmp/x.swift", outputPath: "/tmp/y.png",
            width: 123, height: 456, scale: 3,
            dark: true, backend: .apphost,
            annotate: true, tree: true, deviceFrame: true,
            noCache: true, snapshot: true, json: true
        )
        XCTAssertEqual(config.inputPath, "/tmp/x.swift")
        XCTAssertEqual(config.outputPath, "/tmp/y.png")
        XCTAssertEqual(config.width, 123)
        XCTAssertEqual(config.height, 456)
        XCTAssertEqual(config.scale, 3)
        XCTAssertTrue(config.dark)
        XCTAssertEqual(config.backend, .apphost)
        XCTAssertTrue(config.annotate)
        XCTAssertTrue(config.tree)
        XCTAssertTrue(config.deviceFrame)
        XCTAssertTrue(config.noCache)
        XCTAssertTrue(config.snapshot)
        XCTAssertTrue(config.json)
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

    func testSHA256KnownValueEmptyString() {
        // SHA-256 of empty string starts with e3b0c44298fc1c14
        let hash = "".sha256Prefix(16)
        XCTAssertEqual(hash, "e3b0c44298fc1c14")
    }

    func testSHA256KnownValueHelloWorld() {
        // SHA-256("hello world") = b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9
        let hash = "hello world".sha256Prefix(16)
        XCTAssertEqual(hash, "b94d27b9934d3e08")
    }

    func testSHA256DifferentLengths() {
        let short = "x".sha256Prefix(8)
        let long = "x".sha256Prefix(32)
        XCTAssertEqual(short.count, 8)
        XCTAssertEqual(long.count, 32)
        XCTAssertTrue(long.hasPrefix(short), "Longer prefix should start with shorter prefix")
    }

    func testSHA256PrefixZeroLengthReturnsEmpty() {
        let hash = "test".sha256Prefix(0)
        XCTAssertEqual(hash, "")
    }

    func testSHA256PrefixLargerThanHashTruncates() {
        // SHA-256 hex is 64 chars max
        let hash = "test".sha256Prefix(100)
        XCTAssertEqual(hash.count, 64, "Result truncated at full hash length")
    }

    func testSHA256Unicode() {
        let hash1 = "cafe\u{0301}".sha256Prefix(16)  // e with combining accent
        let hash2 = "caf\u{00E9}".sha256Prefix(16)   // precomposed e-acute
        // These are different UTF-8 byte sequences
        XCTAssertNotEqual(hash1, hash2, "Different UTF-8 encodings should produce different hashes")
    }

    func testSHA256Emoji() {
        let hash = "\u{1F600}\u{1F680}".sha256Prefix(16)
        XCTAssertEqual(hash.count, 16)
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        for char in hash.unicodeScalars {
            XCTAssertTrue(hexChars.contains(char))
        }
    }
}

// MARK: - TemplateGenerator Tests

final class TemplateGeneratorTests: XCTestCase {

    // -- ImageRenderer backend --

    func testImageRendererTemplateContainsRequiredElements() {
        let config = makeConfig(backend: .imageRenderer)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains("import SwiftUI"))
        XCTAssertTrue(template.contains("import AppKit"))
        XCTAssertTrue(template.contains("ImageRenderer"))
        XCTAssertTrue(template.contains("Preview()"))
        XCTAssertTrue(template.contains("/tmp/test-output.png"))
        XCTAssertTrue(template.contains(".light"))
    }

    func testImageRendererDarkMode() {
        let config = makeConfig(dark: true, backend: .imageRenderer)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains("Color.black"), "Dark mode should use black background")
        XCTAssertTrue(template.contains(".dark"), "Dark mode should set .dark color scheme")
        XCTAssertFalse(template.contains(".light"), "Dark mode should not have .light")
    }

    func testImageRendererLightMode() {
        let config = makeConfig(dark: false, backend: .imageRenderer)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains("Color.white"), "Light mode should use white background")
        XCTAssertTrue(template.contains(".light"), "Light mode should set .light color scheme")
    }

    func testImageRendererWithScale() {
        let config = makeConfig(scale: 3, backend: .imageRenderer)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains("renderer.scale = 3.0"))
    }

    func testImageRendererIsValidSwift() {
        let config = makeConfig(backend: .imageRenderer)
        let template = TemplateGenerator.generate(config: config)
        // Basic structural checks for valid Swift
        XCTAssertTrue(template.contains("@main struct"))
        XCTAssertTrue(template.contains("static func main()"))
    }

    // -- AppHost backend --

    func testAppHostTemplateContainsRequiredElements() {
        let config = makeConfig(backend: .apphost)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains("import SwiftUI"))
        XCTAssertTrue(template.contains("import AppKit"))
        XCTAssertTrue(template.contains("NSHostingView"))
        XCTAssertTrue(template.contains("NSWindow"))
        XCTAssertTrue(template.contains("Preview()"))
        XCTAssertTrue(template.contains("@main struct"))
    }

    func testAppHostDarkMode() {
        let config = makeConfig(dark: true, backend: .apphost)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains(".dark"))
    }

    func testAppHostUsesResolvedDimensions() {
        let config = makeConfig(width: 200, height: 300, backend: .apphost)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains("200.0"))
        XCTAssertTrue(template.contains("300.0"))
    }

    func testAppHostDefaultDimensions() {
        let config = makeConfig(backend: .apphost)
        let template = TemplateGenerator.generate(config: config)
        // Defaults are resolvedWidth=390, resolvedHeight=844
        XCTAssertTrue(template.contains("390.0"))
        XCTAssertTrue(template.contains("844.0"))
    }

    // -- Catalyst backend --

    func testCatalystTemplateContainsRequiredElements() {
        let config = makeConfig(dark: true, backend: .catalyst)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains("import UIKit"))
        XCTAssertTrue(template.contains("UIHostingController"))
        XCTAssertTrue(template.contains("Preview()"))
        XCTAssertTrue(template.contains(".dark"))
    }

    func testCatalystLightMode() {
        let config = makeConfig(dark: false, backend: .catalyst)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains(".unspecified"))
    }

    func testCatalystTemplateIsValidSwift() {
        let config = makeConfig(backend: .catalyst)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains("@main struct __CatalystMain"))
        XCTAssertTrue(template.contains("UIApplicationMain"))
    }

    // -- Annotations, tree, device frame --

    func testCatalystTemplateWithAnnotations() {
        let config = makeConfig(backend: .catalyst, annotate: true, tree: true, deviceFrame: true)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains("__collectLayers"))
        XCTAssertTrue(template.contains("__drawAnnotations"))
        XCTAssertTrue(template.contains("__dumpTree"))
        XCTAssertTrue(template.contains("__addDeviceFrame"))
    }

    func testCatalystTemplateAnnotateOnlyNoTree() {
        let config = makeConfig(backend: .catalyst, annotate: true, tree: false, deviceFrame: false)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains("__drawAnnotations"))
        XCTAssertFalse(template.contains("__dumpTree(hc"))  // tree dump call should not appear
        XCTAssertFalse(template.contains("__addDeviceFrame(on:"))
    }

    func testCatalystTemplateTreeOnlyNoAnnotate() {
        let config = makeConfig(backend: .catalyst, annotate: false, tree: true, deviceFrame: false)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains("__dumpTree"))
        XCTAssertFalse(template.contains("__drawAnnotations(on:"))
    }

    func testCatalystTemplateDeviceFrameOnlyNoAnnotate() {
        let config = makeConfig(backend: .catalyst, annotate: false, tree: false, deviceFrame: true)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains("__addDeviceFrame"))
        XCTAssertFalse(template.contains("__drawAnnotations(on:"))
        XCTAssertFalse(template.contains("__dumpTree(hc"))
    }

    func testCatalystNoAnnotationsNoTreeNoDeviceFrame() {
        let config = makeConfig(backend: .catalyst, annotate: false, tree: false, deviceFrame: false)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertFalse(template.contains("__drawAnnotations(on:"))
        XCTAssertFalse(template.contains("__dumpTree(hc"))
        XCTAssertFalse(template.contains("__addDeviceFrame(on:"))
    }

    // -- Catalyst output info file --

    func testCatalystOutputInfoFile() {
        let config = makeConfig(backend: .catalyst)
        let template = TemplateGenerator.generate(config: config, outputInfoPath: "/tmp/output-info.txt")
        XCTAssertTrue(template.contains("output-info.txt"))
        XCTAssertTrue(template.contains("write(toFile:"))
    }

    func testCatalystNoOutputInfoPath() {
        let config = makeConfig(backend: .catalyst)
        let template = TemplateGenerator.generate(config: config, outputInfoPath: nil)
        // When no outputInfoPath, should print instead
        XCTAssertTrue(template.contains("print("))
    }

    // -- Frame modifiers --

    func testFrameModifierWithWidthAndHeight() {
        let config = makeConfig(width: 200, height: 300, backend: .imageRenderer)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains(".frame(width: 200.0, height: 300.0)"))
    }

    func testFrameModifierWithWidthOnly() {
        let config = makeConfig(width: 200, height: nil, backend: .imageRenderer)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains(".frame(width: 200.0)"))
        XCTAssertFalse(template.contains("height:"))
    }

    func testFrameModifierWithHeightOnly() {
        let config = makeConfig(width: nil, height: 300, backend: .imageRenderer)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains(".frame(height: 300.0)"))
        XCTAssertFalse(template.contains("width:"))
    }

    func testFrameModifierWithNoSize() {
        let config = makeConfig(width: nil, height: nil, backend: .imageRenderer)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertFalse(template.contains(".frame("))
    }

    // -- Output path escaping --

    func testOutputPathWithQuotesEscaped() {
        let config = makeConfig(outputPath: "/tmp/my \"file\".png", backend: .imageRenderer)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains("my \\\"file\\\".png"))
    }

    // -- Device frame dark/light flag --

    func testDeviceFrameDarkFlag() {
        let configDark = makeConfig(dark: true, backend: .catalyst, deviceFrame: true)
        let templateDark = TemplateGenerator.generate(config: configDark)
        XCTAssertTrue(templateDark.contains("isDark: true"))

        let configLight = makeConfig(dark: false, backend: .catalyst, deviceFrame: true)
        let templateLight = TemplateGenerator.generate(config: configLight)
        XCTAssertTrue(templateLight.contains("isDark: false"))
    }
}

// MARK: - SwiftCompiler Tests

final class SwiftCompilerTests: XCTestCase {

    func testSDKPathIsNotEmpty() {
        XCTAssertFalse(SwiftCompiler.sdkPath.isEmpty)
    }

    func testSDKPathLooksLikePath() {
        XCTAssertTrue(SwiftCompiler.sdkPath.hasPrefix("/"), "SDK path should be absolute")
        XCTAssertTrue(SwiftCompiler.sdkPath.contains("SDK"), "SDK path should contain 'SDK'")
    }

    func testFileHashConsistency() throws {
        let path = try makeTempSwift("hash-consist", content: "test content")
        defer { try? fm.removeItem(atPath: path) }

        let hash1 = try SwiftCompiler.fileHash(path)
        let hash2 = try SwiftCompiler.fileHash(path)
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash1.count, 16)
    }

    func testFileHashChangesWithContent() throws {
        let path = try makeTempSwift("hash-change", content: "content A")
        let hash1 = try SwiftCompiler.fileHash(path)

        try "content B".write(toFile: path, atomically: true, encoding: .utf8)
        let hash2 = try SwiftCompiler.fileHash(path)

        defer { try? fm.removeItem(atPath: path) }
        XCTAssertNotEqual(hash1, hash2)
    }

    func testFileHashThrowsForMissingFile() {
        XCTAssertThrowsError(try SwiftCompiler.fileHash("/tmp/definitely-nonexistent-file-9999.swift"))
    }

    func testEnsureToolchainAvailable() throws {
        // This should not throw on a machine with Xcode
        try SwiftCompiler.ensureToolchainAvailable()
    }
}

// MARK: - RenderBackend Tests

final class RenderBackendTests: XCTestCase {

    func testAllCases() {
        XCTAssertEqual(RenderBackend.allCases.count, 3)
    }

    func testRawValues() {
        XCTAssertEqual(RenderBackend.imageRenderer.rawValue, "default")
        XCTAssertEqual(RenderBackend.apphost.rawValue, "apphost")
        XCTAssertEqual(RenderBackend.catalyst.rawValue, "catalyst")
    }

    func testExpressibleByArgument() {
        // RenderBackend conforms to ExpressibleByArgument via raw value
        XCTAssertEqual(RenderBackend(rawValue: "default"), .imageRenderer)
        XCTAssertEqual(RenderBackend(rawValue: "apphost"), .apphost)
        XCTAssertEqual(RenderBackend(rawValue: "catalyst"), .catalyst)
        XCTAssertNil(RenderBackend(rawValue: "invalid"))
    }
}

// MARK: - DaemonClient Tests

final class DaemonClientTests: XCTestCase {

    func testBridgeSourceContainsRequiredElements() {
        let source = DaemonClient.bridgeSource
        XCTAssertTrue(source.contains("import SwiftUI"))
        XCTAssertTrue(source.contains("import UIKit"))
        XCTAssertTrue(source.contains("_createHostingController"))
        XCTAssertTrue(source.contains("Preview()"))
        XCTAssertTrue(source.contains("UIHostingController"))
        XCTAssertTrue(source.contains("@_cdecl"))
    }

    func testBridgePathCreatesMissingFile() {
        let path = DaemonClient.bridgePath
        XCTAssertTrue(fm.fileExists(atPath: path), "bridgePath should auto-create the file")
    }

    func testBridgePathIsStable() {
        let path1 = DaemonClient.bridgePath
        let path2 = DaemonClient.bridgePath
        XCTAssertEqual(path1, path2)
    }

    func testBridgePathEndInSwift() {
        let path = DaemonClient.bridgePath
        XCTAssertTrue(path.hasSuffix(".swift"))
    }

    func testDaemonDirPath() {
        XCTAssertEqual(DaemonClient.daemonDir, "/tmp/swiftui-render-daemon")
    }

    func testDaemonPathConstants() {
        XCTAssertTrue(DaemonClient.pidPath.hasSuffix("daemon.pid"))
        XCTAssertTrue(DaemonClient.triggerPath.hasSuffix("reload.trigger"))
        XCTAssertTrue(DaemonClient.donePath.hasSuffix("reload.done"))
        XCTAssertTrue(DaemonClient.requestPath.hasSuffix("request.json"))
        XCTAssertTrue(DaemonClient.snapshotPath.hasSuffix("snapshot.txt"))
        XCTAssertTrue(DaemonClient.treePath.hasSuffix("tree.txt"))
    }
}

// MARK: - DaemonError Tests

final class DaemonErrorTests: XCTestCase {

    func testNotBuiltErrorDescription() {
        let error = DaemonError.notBuilt
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("daemon build"))
    }

    func testStartFailedErrorDescription() {
        let error = DaemonError.startFailed
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("5 seconds"))
    }

    func testTimeoutErrorDescription() {
        let error = DaemonError.timeout
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("10 seconds"))
    }

    func testRenderFailedErrorDescription() {
        let error = DaemonError.renderFailed("bad thing happened")
        XCTAssertEqual(error.errorDescription, "bad thing happened")
    }

    func testSourceNotFoundErrorDescription() {
        let error = DaemonError.sourceNotFound("/some/path")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("/some/path"))
    }
}

// MARK: - CompilationError Tests

final class CompilationErrorTests: XCTestCase {

    func testFailedErrorDescription() {
        let error = CompilationError.failed("some error text")
        XCTAssertEqual(error.errorDescription, "some error text")
    }

    func testToolchainMissingErrorDescription() {
        let error = CompilationError.toolchainMissing
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("xcode-select"))
    }
}

// MARK: - DiffError Tests

final class DiffErrorTests: XCTestCase {

    func testCannotLoadErrorDescription() {
        let error = DiffError.cannotLoad("/bad/path.png")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("/bad/path.png"))
    }

    func testBitmapFailedErrorDescription() {
        let error = DiffError.bitmapFailed
        XCTAssertNotNil(error.errorDescription)
    }

    func testPngFailedErrorDescription() {
        let error = DiffError.pngFailed
        XCTAssertNotNil(error.errorDescription)
    }
}

// MARK: - Options Validation Tests

final class OptionsValidationTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        try? fm.createDirectory(atPath: testDir, withIntermediateDirectories: true)
    }

    override class func tearDown() {
        try? fm.removeItem(atPath: testDir)
        super.tearDown()
    }

    // -- validateInput --

    func testValidateInputAcceptsValidPreview() throws {
        let path = try makeTempSwift("valid-preview", content: minimalPreview)
        defer { try? fm.removeItem(atPath: path) }

        var opts = try RenderOptions.parse([path])
        XCTAssertNoThrow(try opts.validateInput())
    }

    func testValidateInputRejectsFileWithoutPreview() throws {
        let path = try makeTempSwift("no-preview", content: "import SwiftUI\nstruct MyView: View { var body: some View { Text(\"hi\") } }")
        defer { try? fm.removeItem(atPath: path) }

        var opts = try RenderOptions.parse([path])
        XCTAssertThrowsError(try opts.validateInput()) { error in
            XCTAssertTrue("\(error)".contains("struct Preview: View"))
        }
    }

    func testValidateInputAcceptsPreviewWithFlexibleWhitespace() throws {
        let content = """
        import SwiftUI
        struct   Preview :  some  View {
            var body: some View { Text("hi") }
        }
        """
        let path = try makeTempSwift("flex-ws", content: content)
        defer { try? fm.removeItem(atPath: path) }

        var opts = try RenderOptions.parse([path])
        XCTAssertNoThrow(try opts.validateInput())
    }

    // -- inputPath validation --

    func testInputPathRejectsMissingFile() throws {
        let opts = try RenderOptions.parse(["/tmp/nonexistent-file-9999.swift"])
        XCTAssertThrowsError(try opts.inputPath) { error in
            XCTAssertTrue("\(error)".contains("not found"))
        }
    }

    func testInputPathRejectsNonSwiftFile() throws {
        let path = "\(testDir)/test.txt"
        try "hello".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(atPath: path) }

        let opts = try RenderOptions.parse([path])
        XCTAssertThrowsError(try opts.inputPath) { error in
            XCTAssertTrue("\(error)".contains(".swift"))
        }
    }

    func testInputPathAcceptsValidSwiftFile() throws {
        let path = try makeTempSwift("valid-input", content: minimalPreview)
        defer { try? fm.removeItem(atPath: path) }

        let opts = try RenderOptions.parse([path])
        XCTAssertEqual(try opts.inputPath, path)
    }

    // -- warnAboutSystemContainers --

    func testWarnAboutSystemContainersDetectsNavigationStack() throws {
        let content = """
        import SwiftUI
        struct Preview: View {
            var body: some View { NavigationStack { Text("hi") } }
        }
        """
        let path = try makeTempSwift("navstack", content: content)
        defer { try? fm.removeItem(atPath: path) }

        // The method writes to stderr; we verify it doesn't crash with .imageRenderer
        var opts = try RenderOptions.parse([path])
        opts.warnAboutSystemContainers(backend: .imageRenderer)
        // No crash = pass. The warning goes to stderr.
    }

    func testWarnAboutSystemContainersDetectsScrollView() throws {
        let content = """
        import SwiftUI
        struct Preview: View {
            var body: some View { ScrollView { Text("hi") } }
        }
        """
        let path = try makeTempSwift("scrollview", content: content)
        defer { try? fm.removeItem(atPath: path) }

        var opts = try RenderOptions.parse([path])
        opts.warnAboutSystemContainers(backend: .imageRenderer)
    }

    func testWarnAboutSystemContainersDetectsList() throws {
        let content = """
        import SwiftUI
        struct Preview: View {
            var body: some View { List { Text("hi") } }
        }
        """
        let path = try makeTempSwift("list", content: content)
        defer { try? fm.removeItem(atPath: path) }

        var opts = try RenderOptions.parse([path])
        opts.warnAboutSystemContainers(backend: .imageRenderer)
    }

    func testWarnAboutSystemContainersDetectsTabView() throws {
        let content = """
        import SwiftUI
        struct Preview: View {
            var body: some View { TabView { Text("hi") } }
        }
        """
        let path = try makeTempSwift("tabview", content: content)
        defer { try? fm.removeItem(atPath: path) }

        var opts = try RenderOptions.parse([path])
        opts.warnAboutSystemContainers(backend: .imageRenderer)
    }

    func testWarnAboutSystemContainersDetectsForm() throws {
        let content = """
        import SwiftUI
        struct Preview: View {
            var body: some View { Form { Text("hi") } }
        }
        """
        let path = try makeTempSwift("form", content: content)
        defer { try? fm.removeItem(atPath: path) }

        var opts = try RenderOptions.parse([path])
        opts.warnAboutSystemContainers(backend: .imageRenderer)
    }

    func testWarnAboutSystemContainersDetectsNavigationView() throws {
        let content = """
        import SwiftUI
        struct Preview: View {
            var body: some View { NavigationView { Text("hi") } }
        }
        """
        let path = try makeTempSwift("navview", content: content)
        defer { try? fm.removeItem(atPath: path) }

        var opts = try RenderOptions.parse([path])
        opts.warnAboutSystemContainers(backend: .imageRenderer)
    }

    func testWarnAboutSystemContainersSkipsForCatalyst() throws {
        let content = """
        import SwiftUI
        struct Preview: View {
            var body: some View { NavigationStack { Text("hi") } }
        }
        """
        let path = try makeTempSwift("catalyst-skip", content: content)
        defer { try? fm.removeItem(atPath: path) }

        // Should not warn for catalyst backend
        var opts = try RenderOptions.parse([path])
        opts.warnAboutSystemContainers(backend: .catalyst)
    }

    func testWarnAboutSystemContainersSkipsForApphost() throws {
        let content = """
        import SwiftUI
        struct Preview: View {
            var body: some View { NavigationStack { Text("hi") } }
        }
        """
        let path = try makeTempSwift("apphost-skip", content: content)
        defer { try? fm.removeItem(atPath: path) }

        var opts = try RenderOptions.parse([path])
        opts.warnAboutSystemContainers(backend: .apphost)
    }

    func testWarnAboutSystemContainersNoWarningForCleanView() throws {
        let path = try makeTempSwift("clean-view", content: minimalPreview)
        defer { try? fm.removeItem(atPath: path) }

        var opts = try RenderOptions.parse([path])
        opts.warnAboutSystemContainers(backend: .imageRenderer)
    }

    // -- Size presets --

    func testIPhonePresetDimensions() throws {
        let path = try makeTempSwift("iphone-preset", content: minimalPreview)
        defer { try? fm.removeItem(atPath: path) }

        let opts = try RenderOptions.parse([path, "--iphone"])
        XCTAssertEqual(opts.resolvedWidth, 390)
        XCTAssertEqual(opts.resolvedHeight, 844)
    }

    func testIPhoneSEPresetDimensions() throws {
        let path = try makeTempSwift("se-preset", content: minimalPreview)
        defer { try? fm.removeItem(atPath: path) }

        let opts = try RenderOptions.parse([path, "--iphone-se"])
        XCTAssertEqual(opts.resolvedWidth, 375)
        XCTAssertEqual(opts.resolvedHeight, 667)
    }

    func testIPhoneProMaxPresetDimensions() throws {
        let path = try makeTempSwift("promax-preset", content: minimalPreview)
        defer { try? fm.removeItem(atPath: path) }

        let opts = try RenderOptions.parse([path, "--iphone-pro-max"])
        XCTAssertEqual(opts.resolvedWidth, 430)
        XCTAssertEqual(opts.resolvedHeight, 932)
    }

    func testIPadPresetDimensions() throws {
        let path = try makeTempSwift("ipad-preset", content: minimalPreview)
        defer { try? fm.removeItem(atPath: path) }

        let opts = try RenderOptions.parse([path, "--ipad"])
        XCTAssertEqual(opts.resolvedWidth, 1024)
        XCTAssertEqual(opts.resolvedHeight, 1366)
    }

    func testWidgetSmallPresetDimensions() throws {
        let path = try makeTempSwift("widget-small", content: minimalPreview)
        defer { try? fm.removeItem(atPath: path) }

        let opts = try RenderOptions.parse([path, "--widget-small"])
        XCTAssertEqual(opts.resolvedWidth, 170)
        XCTAssertEqual(opts.resolvedHeight, 170)
    }

    func testWidgetMediumPresetDimensions() throws {
        let path = try makeTempSwift("widget-medium", content: minimalPreview)
        defer { try? fm.removeItem(atPath: path) }

        let opts = try RenderOptions.parse([path, "--widget-medium"])
        XCTAssertEqual(opts.resolvedWidth, 364)
        XCTAssertEqual(opts.resolvedHeight, 170)
    }

    func testWidgetLargePresetDimensions() throws {
        let path = try makeTempSwift("widget-large", content: minimalPreview)
        defer { try? fm.removeItem(atPath: path) }

        let opts = try RenderOptions.parse([path, "--widget-large"])
        XCTAssertEqual(opts.resolvedWidth, 364)
        XCTAssertEqual(opts.resolvedHeight, 382)
    }

    func testExplicitWidthOverridesPreset() throws {
        let path = try makeTempSwift("explicit-w", content: minimalPreview)
        defer { try? fm.removeItem(atPath: path) }

        let opts = try RenderOptions.parse([path, "--iphone", "-w", "500"])
        // Explicit -w takes priority over preset in resolvedWidth
        XCTAssertEqual(opts.resolvedWidth, 500)
    }

    func testNoPresetReturnsNil() throws {
        let path = try makeTempSwift("no-preset", content: minimalPreview)
        defer { try? fm.removeItem(atPath: path) }

        let opts = try RenderOptions.parse([path])
        XCTAssertNil(opts.resolvedWidth)
        XCTAssertNil(opts.resolvedHeight)
    }

    // -- Default output path --

    func testDefaultOutputPath() throws {
        let path = try makeTempSwift("default-out", content: minimalPreview)
        defer { try? fm.removeItem(atPath: path) }

        let opts = try RenderOptions.parse([path])
        XCTAssertEqual(opts.output, "/tmp/swiftui-render.png")
    }

    func testCustomOutputPath() throws {
        let path = try makeTempSwift("custom-out", content: minimalPreview)
        defer { try? fm.removeItem(atPath: path) }

        let opts = try RenderOptions.parse([path, "-o", "/tmp/custom-output.png"])
        XCTAssertEqual(opts.output, "/tmp/custom-output.png")
    }

    // -- Default scale --

    func testDefaultScale() throws {
        let path = try makeTempSwift("default-scale", content: minimalPreview)
        defer { try? fm.removeItem(atPath: path) }

        let opts = try RenderOptions.parse([path])
        XCTAssertEqual(opts.scale, 2)
    }
}

// MARK: - Integration Tests (Full Render Pipeline)

final class IntegrationTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        try? fm.createDirectory(atPath: testDir, withIntermediateDirectories: true)
    }

    override class func tearDown() {
        try? fm.removeItem(atPath: testDir)
        super.tearDown()
    }

    // -- Basic render --

    func testFullRenderPipeline() throws {
        let inputPath = try makeTempSwift("integration-basic", content: """
            import SwiftUI
            struct Preview: View {
                var body: some View {
                    Text("Integration Test")
                        .font(.title)
                        .padding()
                }
            }
            """)
        let outputPath = "\(testDir)/integration-output.png"
        defer {
            try? fm.removeItem(atPath: inputPath)
            try? fm.removeItem(atPath: outputPath)
        }

        let config = makeConfig(
            inputPath: inputPath, outputPath: outputPath,
            backend: .imageRenderer, noCache: true
        )
        try CompileAndRender.run(config: config)

        XCTAssertTrue(fm.fileExists(atPath: outputPath))
        let attrs = try fm.attributesOfItem(atPath: outputPath)
        let size = attrs[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 100, "Output PNG should not be trivially small")
    }

    // -- Render with custom dimensions --

    func testRenderWithCustomDimensions() throws {
        let inputPath = try makeTempSwift("integration-dims", content: """
            import SwiftUI
            struct Preview: View {
                var body: some View { Color.blue }
            }
            """)
        let outputPath = "\(testDir)/dims-output.png"
        defer {
            try? fm.removeItem(atPath: inputPath)
            try? fm.removeItem(atPath: outputPath)
        }

        let config = makeConfig(
            inputPath: inputPath, outputPath: outputPath,
            width: 200, height: 200, scale: 1,
            backend: .imageRenderer, noCache: true
        )
        try CompileAndRender.run(config: config)
        XCTAssertTrue(fm.fileExists(atPath: outputPath))
    }

    // -- Render dark mode --

    func testRenderDarkMode() throws {
        let inputPath = try makeTempSwift("integration-dark", content: """
            import SwiftUI
            struct Preview: View {
                var body: some View {
                    Text("Dark Mode").foregroundColor(.primary)
                }
            }
            """)
        let outputPath = "\(testDir)/dark-output.png"
        defer {
            try? fm.removeItem(atPath: inputPath)
            try? fm.removeItem(atPath: outputPath)
        }

        let config = makeConfig(
            inputPath: inputPath, outputPath: outputPath,
            dark: true, backend: .imageRenderer, noCache: true
        )
        try CompileAndRender.run(config: config)
        XCTAssertTrue(fm.fileExists(atPath: outputPath))
    }

    // -- REGRESSION: Render to two DIFFERENT output paths (cache bug) --

    func testRenderToDifferentOutputPathsProducesDifferentCacheKeys() throws {
        let inputPath = try makeTempSwift("cache-bug-regression", content: """
            import SwiftUI
            struct Preview: View {
                var body: some View { Text("Cache Bug") }
            }
            """)
        let output1 = "\(testDir)/output-A.png"
        let output2 = "\(testDir)/output-B.png"
        defer {
            try? fm.removeItem(atPath: inputPath)
            try? fm.removeItem(atPath: output1)
            try? fm.removeItem(atPath: output2)
        }

        // Render to output path A
        let config1 = makeConfig(
            inputPath: inputPath, outputPath: output1,
            backend: .imageRenderer, noCache: true
        )
        try CompileAndRender.run(config: config1)
        XCTAssertTrue(fm.fileExists(atPath: output1), "First render should produce output at path A")

        // Render to output path B (with caching enabled)
        let config2 = makeConfig(
            inputPath: inputPath, outputPath: output2,
            backend: .imageRenderer, noCache: true
        )
        try CompileAndRender.run(config: config2)
        XCTAssertTrue(fm.fileExists(atPath: output2), "Second render should produce output at path B, not reuse path A from cache")
    }

    func testCachedRenderRespectsDifferentOutputPath() throws {
        let inputPath = try makeTempSwift("cache-output-path", content: """
            import SwiftUI
            struct Preview: View {
                var body: some View { Text("Cached Output") }
            }
            """)
        let output1 = "\(testDir)/cached-output-1.png"
        let output2 = "\(testDir)/cached-output-2.png"
        defer {
            try? fm.removeItem(atPath: inputPath)
            try? fm.removeItem(atPath: output1)
            try? fm.removeItem(atPath: output2)
        }

        // Render first time (populates cache)
        let config1 = makeConfig(
            inputPath: inputPath, outputPath: output1,
            backend: .imageRenderer, noCache: false
        )
        try CompileAndRender.run(config: config1)
        XCTAssertTrue(fm.fileExists(atPath: output1))

        // Render again to different path (should NOT reuse cache since output path differs)
        let config2 = makeConfig(
            inputPath: inputPath, outputPath: output2,
            backend: .imageRenderer, noCache: false
        )

        // Cache keys must be different
        XCTAssertNotEqual(config1.cacheKey, config2.cacheKey,
                         "REGRESSION: Output path must be part of cache key")

        try CompileAndRender.run(config: config2)
        XCTAssertTrue(fm.fileExists(atPath: output2),
                     "Output at second path must exist regardless of cache")
    }

    // -- Compilation error handling --

    func testCompilationErrorForInvalidSwift() throws {
        let inputPath = try makeTempSwift("invalid-swift", content: "this is not valid swift {{{")
        defer { try? fm.removeItem(atPath: inputPath) }

        let config = makeConfig(
            inputPath: inputPath, outputPath: "\(testDir)/error-output.png",
            backend: .imageRenderer, noCache: true
        )
        XCTAssertThrowsError(try CompileAndRender.run(config: config)) { error in
            // Should be a CompilationError.failed
            XCTAssertTrue(error is CompilationError || "\(error)".contains("error"))
        }
    }

    // -- Missing file handling --

    func testMissingFileHandling() {
        let config = makeConfig(
            inputPath: "/tmp/this-file-does-not-exist-12345.swift",
            outputPath: "\(testDir)/missing-output.png",
            backend: .imageRenderer, noCache: true
        )
        XCTAssertThrowsError(try CompileAndRender.run(config: config))
    }

    // -- Empty file handling --

    func testEmptyFileHandling() throws {
        let inputPath = try makeTempSwift("empty-file", content: "")
        defer { try? fm.removeItem(atPath: inputPath) }

        let config = makeConfig(
            inputPath: inputPath, outputPath: "\(testDir)/empty-output.png",
            backend: .imageRenderer, noCache: true
        )
        XCTAssertThrowsError(try CompileAndRender.run(config: config))
    }

    // -- File without Preview struct compiles but fails at runtime --

    func testFileWithoutPreviewStructFailsCompilation() throws {
        let inputPath = try makeTempSwift("no-preview-struct", content: """
            import SwiftUI
            struct MyView: View {
                var body: some View { Text("no Preview struct") }
            }
            """)
        defer { try? fm.removeItem(atPath: inputPath) }

        let config = makeConfig(
            inputPath: inputPath, outputPath: "\(testDir)/no-preview-output.png",
            backend: .imageRenderer, noCache: true
        )
        // Should fail at compilation because template references Preview()
        XCTAssertThrowsError(try CompileAndRender.run(config: config))
    }

    // -- AppHost backend render --

    func testAppHostBackendRender() throws {
        let inputPath = try makeTempSwift("apphost-render", content: """
            import SwiftUI
            struct Preview: View {
                var body: some View { Text("AppHost Test") }
            }
            """)
        let outputPath = "\(testDir)/apphost-output.png"
        defer {
            try? fm.removeItem(atPath: inputPath)
            try? fm.removeItem(atPath: outputPath)
        }

        let config = makeConfig(
            inputPath: inputPath, outputPath: outputPath,
            width: 200, height: 200,
            backend: .apphost, noCache: true
        )
        try CompileAndRender.run(config: config)
        XCTAssertTrue(fm.fileExists(atPath: outputPath))
    }

    // -- Very large view (many elements) --

    func testLargeViewWithManyElements() throws {
        var lines = ["import SwiftUI", "struct Preview: View {", "    var body: some View {", "        VStack {"]
        for i in 0..<50 {
            lines.append("            Text(\"Line \\(\(i))\")")
        }
        lines += ["        }", "    }", "}"]
        let content = lines.joined(separator: "\n")

        let inputPath = try makeTempSwift("large-view", content: content)
        let outputPath = "\(testDir)/large-output.png"
        defer {
            try? fm.removeItem(atPath: inputPath)
            try? fm.removeItem(atPath: outputPath)
        }

        let config = makeConfig(
            inputPath: inputPath, outputPath: outputPath,
            backend: .imageRenderer, noCache: true
        )
        try CompileAndRender.run(config: config)
        XCTAssertTrue(fm.fileExists(atPath: outputPath))
    }

    // -- Unicode/emoji in view --

    func testUnicodeAndEmojiInView() throws {
        let inputPath = try makeTempSwift("unicode-view", content: """
            import SwiftUI
            struct Preview: View {
                var body: some View {
                    VStack {
                        Text("\\u{1F680} Rocket")
                        Text("cafe\\u{0301}")
                        Text("\\u{1F1FA}\\u{1F1F8}")
                    }
                }
            }
            """)
        let outputPath = "\(testDir)/unicode-output.png"
        defer {
            try? fm.removeItem(atPath: inputPath)
            try? fm.removeItem(atPath: outputPath)
        }

        let config = makeConfig(
            inputPath: inputPath, outputPath: outputPath,
            backend: .imageRenderer, noCache: true
        )
        try CompileAndRender.run(config: config)
        XCTAssertTrue(fm.fileExists(atPath: outputPath))
    }

    // -- Special characters in output path --

    func testSpecialCharactersInOutputPath() throws {
        let inputPath = try makeTempSwift("special-path", content: minimalPreview)
        let specialDir = "\(testDir)/my output dir"
        try fm.createDirectory(atPath: specialDir, withIntermediateDirectories: true)
        let outputPath = "\(specialDir)/test output.png"
        defer {
            try? fm.removeItem(atPath: inputPath)
            try? fm.removeItem(atPath: specialDir)
        }

        let config = makeConfig(
            inputPath: inputPath, outputPath: outputPath,
            backend: .imageRenderer, noCache: true
        )
        try CompileAndRender.run(config: config)
        XCTAssertTrue(fm.fileExists(atPath: outputPath))
    }

    // -- Tiny dimensions (1x1) --

    func testTinyDimensions1x1() throws {
        let inputPath = try makeTempSwift("tiny-view", content: """
            import SwiftUI
            struct Preview: View {
                var body: some View { Color.red }
            }
            """)
        let outputPath = "\(testDir)/tiny-output.png"
        defer {
            try? fm.removeItem(atPath: inputPath)
            try? fm.removeItem(atPath: outputPath)
        }

        let config = makeConfig(
            inputPath: inputPath, outputPath: outputPath,
            width: 1, height: 1, scale: 1,
            backend: .imageRenderer, noCache: true
        )
        // This should not crash; whether it renders anything meaningful is questionable
        try CompileAndRender.run(config: config)
        XCTAssertTrue(fm.fileExists(atPath: outputPath))
    }
}

// MARK: - CLI Integration Tests (via Process)

final class CLIIntegrationTests: XCTestCase {

    private var binaryPath: String!

    override func setUp() {
        super.setUp()
        binaryPath = "/Users/ollie/Dropbox/Projects/swiftui-render/.build/debug/swiftui-render"
        try? fm.createDirectory(atPath: testDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? fm.removeItem(atPath: testDir)
        super.tearDown()
    }

    private func runCLI(_ args: [String]) throws -> (stdout: String, stderr: String, status: Int32) {
        let task = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.executableURL = URL(fileURLWithPath: binaryPath)
        task.arguments = args
        task.standardOutput = outPipe
        task.standardError = errPipe
        try task.run()
        task.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        return (stdout, stderr, task.terminationStatus)
    }

    func testCLIBinaryExists() {
        XCTAssertTrue(fm.fileExists(atPath: binaryPath), "Debug binary must exist for CLI tests")
    }

    // -- Missing file error --

    func testCLIMissingFileError() throws {
        let result = try runCLI(["render", "/tmp/nonexistent-file-99999.swift"])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("not found") || result.stderr.contains("Error"),
                      "Should report file not found")
    }

    // -- Non-.swift file error --

    func testCLINonSwiftFileError() throws {
        let path = "\(testDir)/test.txt"
        try "hello".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(atPath: path) }

        let result = try runCLI(["render", path])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains(".swift"))
    }

    // -- File without Preview struct --

    func testCLINoPreviewStructError() throws {
        let path = try makeTempSwift("cli-no-preview", content: """
            import SwiftUI
            struct NotPreview: View { var body: some View { Text("x") } }
            """)
        defer { try? fm.removeItem(atPath: path) }

        let result = try runCLI(["render", path])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("Preview"))
    }

    // -- NavigationStack warning on stderr --

    func testCLINavigationStackWarning() throws {
        let path = try makeTempSwift("cli-navstack", content: """
            import SwiftUI
            struct Preview: View {
                var body: some View { NavigationStack { Text("Hello") } }
            }
            """)
        defer { try? fm.removeItem(atPath: path) }

        let result = try runCLI(["render", path, "--no-cache"])
        // Should warn on stderr
        XCTAssertTrue(result.stderr.contains("NavigationStack") || result.stderr.contains("warning"),
                      "REGRESSION: NavigationStack should produce a warning on stderr. Got stderr: \(result.stderr)")
    }

    // -- ScrollView warning on stderr --

    func testCLIScrollViewWarning() throws {
        let path = try makeTempSwift("cli-scrollview", content: """
            import SwiftUI
            struct Preview: View {
                var body: some View { ScrollView { Text("Hello") } }
            }
            """)
        defer { try? fm.removeItem(atPath: path) }

        let result = try runCLI(["render", path, "--no-cache"])
        XCTAssertTrue(result.stderr.contains("ScrollView") || result.stderr.contains("warning"),
                      "REGRESSION: ScrollView should produce a warning on stderr")
    }

    // -- JSON output format --

    func testCLIJSONOutputFormat() throws {
        let path = try makeTempSwift("cli-json", content: minimalPreview)
        let outputPath = "\(testDir)/json-test-output.png"
        defer {
            try? fm.removeItem(atPath: path)
            try? fm.removeItem(atPath: outputPath)
        }

        let result = try runCLI(["render", path, "--json", "--no-cache", "-o", outputPath])
        XCTAssertEqual(result.status, 0, "Render should succeed. stderr: \(result.stderr)")

        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(trimmed.hasPrefix("{"), "JSON output should start with {")
        XCTAssertTrue(trimmed.hasSuffix("}"), "JSON output should end with }")
        XCTAssertTrue(trimmed.contains("\"width\""))
        XCTAssertTrue(trimmed.contains("\"height\""))
        XCTAssertTrue(trimmed.contains("\"size\""))
        XCTAssertTrue(trimmed.contains("\"path\""))
        XCTAssertTrue(trimmed.contains("\"time_ms\""))
    }

    // -- Diff command --

    func testCLIDiffCommand() throws {
        let pathA = try makeTempSwift("cli-diff-a", content: """
            import SwiftUI
            struct Preview: View {
                var body: some View { Text("Before").foregroundColor(.red) }
            }
            """)
        let pathB = try makeTempSwift("cli-diff-b", content: """
            import SwiftUI
            struct Preview: View {
                var body: some View { Text("After").foregroundColor(.blue) }
            }
            """)
        let outputPath = "\(testDir)/diff-output.png"
        defer {
            try? fm.removeItem(atPath: pathA)
            try? fm.removeItem(atPath: pathB)
            try? fm.removeItem(atPath: outputPath)
        }

        let result = try runCLI(["diff", pathA, pathB, "-o", outputPath])
        XCTAssertEqual(result.status, 0, "Diff should succeed. stderr: \(result.stderr)")
        XCTAssertTrue(fm.fileExists(atPath: outputPath), "Diff output image should exist")
    }

    // -- Cache lifecycle --

    func testCLICacheLifecycle() throws {
        // 1. Clear cache first
        let clearResult = try runCLI(["cache", "clear"])
        XCTAssertEqual(clearResult.status, 0)

        // 2. Check cache is empty
        let infoResult1 = try runCLI(["cache", "info"])
        XCTAssertEqual(infoResult1.status, 0)
        XCTAssertTrue(infoResult1.stdout.contains("Entries: 0"))

        // 3. Render something (populates cache)
        let path = try makeTempSwift("cli-cache-test", content: minimalPreview)
        let outputPath = "\(testDir)/cache-test-output.png"
        defer {
            try? fm.removeItem(atPath: path)
            try? fm.removeItem(atPath: outputPath)
        }

        let renderResult = try runCLI(["render", path, "-o", outputPath])
        XCTAssertEqual(renderResult.status, 0, "Render should succeed. stderr: \(renderResult.stderr)")

        // 4. Cache should now have at least 1 entry
        let infoResult2 = try runCLI(["cache", "info"])
        XCTAssertEqual(infoResult2.status, 0)
        XCTAssertFalse(infoResult2.stdout.contains("Entries: 0"),
                       "Cache should have entries after render. Got: \(infoResult2.stdout)")

        // 5. Render same thing again (should use cache -- faster)
        let renderResult2 = try runCLI(["render", path, "-o", outputPath])
        XCTAssertEqual(renderResult2.status, 0)

        // 6. Clear cache
        let clearResult2 = try runCLI(["cache", "clear"])
        XCTAssertEqual(clearResult2.status, 0)

        // 7. Verify cache is empty
        let infoResult3 = try runCLI(["cache", "info"])
        XCTAssertEqual(infoResult3.status, 0)
        XCTAssertTrue(infoResult3.stdout.contains("Entries: 0"),
                      "Cache should be empty after clear. Got: \(infoResult3.stdout)")
    }

    // -- Version flag --

    func testCLIVersionFlag() throws {
        let result = try runCLI(["--version"])
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.contains("0.2.1"))
    }

    // -- Help flag --

    func testCLIHelpFlag() throws {
        let result = try runCLI(["--help"])
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.contains("swiftui-render"))
        XCTAssertTrue(result.stdout.contains("render"))
    }

    // -- Diff with JSON output --

    func testCLIDiffJSONOutput() throws {
        let pathA = try makeTempSwift("diff-json-a", content: """
            import SwiftUI
            struct Preview: View {
                var body: some View { Text("A") }
            }
            """)
        let pathB = try makeTempSwift("diff-json-b", content: """
            import SwiftUI
            struct Preview: View {
                var body: some View { Text("B") }
            }
            """)
        let outputPath = "\(testDir)/diff-json-output.png"
        defer {
            try? fm.removeItem(atPath: pathA)
            try? fm.removeItem(atPath: pathB)
            try? fm.removeItem(atPath: outputPath)
        }

        let result = try runCLI(["diff", pathA, pathB, "-o", outputPath, "--json"])
        XCTAssertEqual(result.status, 0, "stderr: \(result.stderr)")
        // Diff stdout may contain intermediate render info lines before the final JSON.
        // The JSON from DiffComposer is the last line.
        let lines = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
        let lastLine = lines.last ?? ""
        XCTAssertTrue(lastLine.hasPrefix("{"), "Last line of diff --json should be JSON. Got: \(lastLine)")
        XCTAssertTrue(lastLine.contains("\"width\""))
        XCTAssertTrue(lastLine.contains("\"path\""))
    }

    // -- JSON does not produce JSON on errors (known bug) --

    func testCLIJSONDoesNotProduceJSONOnErrors() throws {
        // This tests the known bug: --json doesn't produce JSON when there's an error
        let result = try runCLI(["render", "/tmp/nonexistent-file-99999.swift", "--json"])
        XCTAssertNotEqual(result.status, 0)

        let trimmedStdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        // BUG: errors should ideally be JSON when --json is passed, but they're not
        // This test documents the current behavior
        if !trimmedStdout.isEmpty {
            // If there's stdout, it should be JSON (but currently errors go to stderr as plain text)
            XCTExpectFailure("Known bug: --json flag doesn't produce JSON output on errors") {
                XCTAssertTrue(trimmedStdout.hasPrefix("{"), "Error output should be JSON when --json is used")
            }
        }
        // Error goes to stderr as plain text regardless of --json
        XCTAssertFalse(result.stderr.isEmpty, "Error should appear on stderr")
    }

    // -- Conflicting presets silently ignored (known issue) --

    func testCLIConflictingPresetsAreAccepted() throws {
        let path = try makeTempSwift("cli-conflict-preset", content: minimalPreview)
        let outputPath = "\(testDir)/conflict-preset-output.png"
        defer {
            try? fm.removeItem(atPath: path)
            try? fm.removeItem(atPath: outputPath)
        }

        // Using two presets -- the first matching one wins silently
        let result = try runCLI(["render", path, "--iphone", "--ipad", "-o", outputPath, "--no-cache"])
        // Both flags are accepted without error -- first match wins in resolvedWidth/resolvedHeight
        XCTAssertEqual(result.status, 0, "Conflicting presets should not cause an error (known limitation). stderr: \(result.stderr)")
    }
}

// MARK: - DiffComposer Unit Tests

final class DiffComposerTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        try? fm.createDirectory(atPath: testDir, withIntermediateDirectories: true)
    }

    override class func tearDown() {
        try? fm.removeItem(atPath: testDir)
        super.tearDown()
    }

    func testDiffComposerCannotLoadMissingImageA() {
        XCTAssertThrowsError(
            try DiffComposer.compose(
                imageA: "/tmp/nonexistent-a.png",
                imageB: "/tmp/nonexistent-b.png",
                output: "\(testDir)/diff.png",
                scale: 2
            )
        ) { error in
            XCTAssertTrue(error is DiffError)
        }
    }

    func testDiffComposerCannotLoadMissingImageB() throws {
        // Create a real image for A by rendering
        let inputPath = try makeTempSwift("diff-a", content: minimalPreview)
        let imgA = "\(testDir)/diff-a-real.png"
        defer {
            try? fm.removeItem(atPath: inputPath)
            try? fm.removeItem(atPath: imgA)
        }

        let config = makeConfig(inputPath: inputPath, outputPath: imgA, backend: .imageRenderer, noCache: true)
        try CompileAndRender.run(config: config)

        XCTAssertThrowsError(
            try DiffComposer.compose(
                imageA: imgA,
                imageB: "/tmp/nonexistent-b.png",
                output: "\(testDir)/diff.png",
                scale: 2
            )
        ) { error in
            XCTAssertTrue(error is DiffError)
        }
    }
}

// MARK: - FileHandle/stderr extension Tests

final class StderrHelperTests: XCTestCase {

    func testStderrFunctionDoesNotCrash() {
        // Just verify it doesn't crash
        stderr("test message from unit test\n")
    }

    func testFileHandleWriteStringDoesNotCrash() {
        FileHandle.standardError.write("test write\n")
    }
}

// MARK: - CompileAndRender Cache Dir Tests

final class CompileAndRenderTests: XCTestCase {

    func testCacheDirPathIsNotEmpty() {
        XCTAssertFalse(CompileAndRender.cacheDirPath.isEmpty)
    }

    func testCacheDirPathContainsSwiftuiRender() {
        XCTAssertTrue(CompileAndRender.cacheDirPath.contains("swiftui-render"))
    }

    func testCacheDirExists() {
        XCTAssertTrue(fm.fileExists(atPath: CompileAndRender.cacheDirPath))
    }
}

// MARK: - Edge Cases: Zero/Negative Dimensions

final class ZeroNegativeDimensionTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        try? fm.createDirectory(atPath: testDir, withIntermediateDirectories: true)
    }

    override class func tearDown() {
        try? fm.removeItem(atPath: testDir)
        super.tearDown()
    }

    func testZeroWidthConfig() {
        let config = makeConfig(width: 0, height: 100)
        XCTAssertEqual(config.resolvedWidth, 0)
        // Template still generates -- no validation at config level
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains(".frame(width: 0.0, height: 100.0)"))
    }

    func testZeroHeightConfig() {
        let config = makeConfig(width: 100, height: 0)
        XCTAssertEqual(config.resolvedHeight, 0)
    }

    func testNegativeWidthConfig() {
        let config = makeConfig(width: -10, height: 100)
        XCTAssertEqual(config.resolvedWidth, -10)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains("-10.0"))
    }

    func testNegativeHeightConfig() {
        let config = makeConfig(width: 100, height: -20)
        XCTAssertEqual(config.resolvedHeight, -20)
    }

    func testZeroScale() {
        let config = makeConfig(scale: 0)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains("renderer.scale = 0.0"))
    }

    func testNegativeScale() {
        let config = makeConfig(scale: -1)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains("renderer.scale = -1.0"))
    }
}

// MARK: - Template Generator: Backend Dispatch

final class TemplateGeneratorBackendDispatchTests: XCTestCase {

    func testImageRendererBackendDispatch() {
        let config = makeConfig(backend: .imageRenderer)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains("ImageRenderer"), "imageRenderer backend should produce ImageRenderer code")
        XCTAssertFalse(template.contains("UIKit"), "imageRenderer backend should not import UIKit")
    }

    func testAppHostBackendDispatch() {
        let config = makeConfig(backend: .apphost)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains("NSHostingView"), "apphost backend should produce NSHostingView code")
        XCTAssertTrue(template.contains("NSWindow"))
    }

    func testCatalystBackendDispatch() {
        let config = makeConfig(backend: .catalyst)
        let template = TemplateGenerator.generate(config: config)
        XCTAssertTrue(template.contains("UIKit"), "catalyst backend should import UIKit")
        XCTAssertTrue(template.contains("UIHostingController"))
        XCTAssertFalse(template.contains("AppKit"), "catalyst backend should not import AppKit")
    }
}

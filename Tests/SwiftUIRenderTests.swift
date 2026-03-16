import XCTest

final class SwiftUIRenderTests: XCTestCase {
    func testRenderConfigCacheKey() {
        let config = RenderConfig(
            inputPath: "/tmp/test.swift",
            outputPath: "/tmp/test.png",
            width: 390,
            height: 844,
            scale: 2,
            dark: false,
            backend: .imageRenderer,
            annotate: false,
            tree: false,
            deviceFrame: false,
            noCache: false
        )
        XCTAssertFalse(config.cacheKey.isEmpty)
    }
}

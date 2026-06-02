import XCTest
@testable import Glimmer

final class MarkdownConfigurationBuilderTests: XCTestCase {
    func testBuilderCanConfigureRenderCacheControls() {
        let config = MarkdownConfiguration.builder()
            .setRenderCaching(false)
            .setMaxRenderCacheEntries(42)
            .build()

        XCTAssertFalse(config.enableRenderCaching)
        XCTAssertEqual(config.maxRenderCacheEntries, 42)
    }

    func testBuilderCanConfigureOnImageTapHandler() {
        let config = MarkdownConfiguration.builder()
            .setOnImageTap { _, _ in
            }
            .build()

        XCTAssertNotNil(config.onImageTap)
    }
}

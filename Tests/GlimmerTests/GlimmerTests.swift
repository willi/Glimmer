import XCTest
@testable import Glimmer

final class GlimmerTests: XCTestCase {
    
    func testGlimmerParsing() {
        let markdown = "Hello **world**!"
        let attributedString = Glimmer.parseToAttributedString(markdown)
        
        XCTAssertFalse(attributedString.characters.isEmpty, "Should produce attributed string")
    }
    
    func testCacheClearing() {
        // Test that cache clearing doesn't crash
        Glimmer.clearCache()
        
        let markdown = "# Test"
        let blocks = Glimmer.parse(markdown)
        XCTAssertFalse(blocks.isEmpty, "Should still work after cache clear")
    }

    func testRenderCacheAPIsAreUsable() {
        Glimmer.clearRenderCache()
        _ = Glimmer.parseToAttributedString("# Render Cache")
        let stats = Glimmer.getRenderCacheStatistics()

        XCTAssertGreaterThanOrEqual(stats.hits, 0)
        XCTAssertGreaterThanOrEqual(stats.misses, 0)
    }
}

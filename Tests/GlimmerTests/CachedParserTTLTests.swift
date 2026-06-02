import XCTest
@testable import Glimmer

final class CachedParserTTLTests: XCTestCase {
    func testCacheTTLExpiryEvicts() {
        var config = MarkdownConfiguration()
        config.cacheTimeToLiveSeconds = 0
        config.enableCaching = true

        let parser = CachedMarkdownParser()
        _ = parser.parse("# A", configuration: config)
        _ = parser.parse("# A", configuration: config)

        let stats = parser.getCacheStatistics()
        XCTAssertGreaterThanOrEqual(stats.evictions, 1, "Expected eviction due to TTL=0")
    }
}


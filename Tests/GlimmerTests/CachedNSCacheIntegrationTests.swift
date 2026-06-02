import XCTest
@testable import Glimmer

final class CachedNSCacheIntegrationTests: XCTestCase {
    func testNSCacheHitAndMiss() {
        var config = MarkdownConfiguration()
        config.enableCaching = true
        config.cacheTimeToLiveSeconds = 300
        let parser = CachedMarkdownParser(useNSCache: true)

        parser.clearCache()
        _ = parser.parse("# Title", configuration: config) // miss
        _ = parser.parse("# Title", configuration: config) // hit
        let stats = parser.getCacheStatistics()
        XCTAssertGreaterThanOrEqual(stats.misses, 1)
        XCTAssertGreaterThanOrEqual(stats.hits, 1)
        let nsInfo = parser.getNSCacheInfo()
        XCTAssertTrue(nsInfo.enabled)
        XCTAssertGreaterThanOrEqual(nsInfo.totalCostLimit, 0)
    }

    func testNSCacheTTLExpiryEvictsOnAccess() {
        var config = MarkdownConfiguration()
        config.enableCaching = true
        config.cacheTimeToLiveSeconds = 0
        let parser = CachedMarkdownParser(useNSCache: true)

        parser.clearCache()
        _ = parser.parse("# A", configuration: config)
        _ = parser.parse("# A", configuration: config)
        let stats = parser.getCacheStatistics()
        XCTAssertGreaterThanOrEqual(stats.evictions, 1, "Expected eviction in NSCache mode when TTL=0")
    }

    func testLargeContentHashPathWithNSCache() {
        var config = MarkdownConfiguration()
        config.enableCaching = true
        let parser = CachedMarkdownParser(useNSCache: true)

        // Build >50k chars markdown without worst-case inline scanning behavior
        let md = String(repeating: "# Title\n\n", count: 7000)
        XCTAssertGreaterThan(md.count, 50_000)
        parser.clearCache()
        _ = parser.parse(md, configuration: config) // miss
        let stats1 = parser.getCacheStatistics()
        _ = parser.parse(md, configuration: config) // hit
        let stats2 = parser.getCacheStatistics()
        XCTAssertGreaterThan(stats2.hits, stats1.hits)
    }
}

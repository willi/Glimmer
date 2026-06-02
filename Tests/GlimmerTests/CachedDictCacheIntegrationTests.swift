import XCTest
@testable import Glimmer

final class CachedDictCacheIntegrationTests: XCTestCase {
    func testDictCacheHitAndMiss() {
        var config = MarkdownConfiguration()
        config.enableCaching = true
        let parser = CachedMarkdownParser(useNSCache: false)

        parser.clearCache()
        _ = parser.parse("# Title", configuration: config) // miss
        _ = parser.parse("# Title", configuration: config) // hit
        let stats = parser.getCacheStatistics()
        XCTAssertGreaterThanOrEqual(stats.misses, 1)
        XCTAssertGreaterThanOrEqual(stats.hits, 1)
    }

    func testLargeContentHashPathDict() {
        var config = MarkdownConfiguration()
        config.enableCaching = true
        let parser = CachedMarkdownParser(useNSCache: false)

        let md = String(repeating: "# Title\n\n", count: 7000) // > 50k chars, avoids pathological inline scanning
        XCTAssertGreaterThan(md.count, 50_000)
        parser.clearCache()
        _ = parser.parse(md, configuration: config) // miss
        let stats1 = parser.getCacheStatistics()
        _ = parser.parse(md, configuration: config) // hit
        let stats2 = parser.getCacheStatistics()
        XCTAssertGreaterThan(stats2.hits, stats1.hits)
    }
}

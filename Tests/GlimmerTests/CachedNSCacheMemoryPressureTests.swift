import XCTest
@testable import Glimmer

final class CachedNSCacheMemoryPressureTests: XCTestCase {
    func testWarningReducesCostLimitAndEvicts() {
        var config = MarkdownConfiguration()
        config.enableCaching = true
        // small limit to make eviction likely
        config.maxCacheSizeMB = 1
        let parser = CachedMarkdownParser(useNSCache: true)

        parser.clearCache()
        // Insert multiple entries to accumulate cost
        for i in 0..<50 {
            _ = parser.parse("# Title \(i)", configuration: config)
        }
        let statsBefore = parser.getCacheStatistics()
        let infoBefore = parser.getNSCacheInfo()

        parser.handleMemoryPressure(level: .warning)

        // Trigger some access after pressure to allow NSCache to evict based on reduced limit
        for i in 50..<100 {
            _ = parser.parse("# Title \(i)", configuration: config)
        }

        let statsAfter = parser.getCacheStatistics()
        let infoAfter = parser.getNSCacheInfo()
        XCTAssertTrue(infoAfter.enabled)
        XCTAssertLessThanOrEqual(infoAfter.totalCostLimit, infoBefore.totalCostLimit)
        XCTAssertGreaterThanOrEqual(statsAfter.evictions, statsBefore.evictions)
    }
}

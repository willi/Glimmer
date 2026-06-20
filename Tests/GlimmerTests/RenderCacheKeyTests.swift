import XCTest
@testable import Glimmer

final class RenderCacheKeyTests: XCTestCase {
    func testRenderCacheDistinguishesEmphasisAndStrong() {
        Glimmer.clearRenderCache()

        var config = MarkdownConfiguration()
        config.enableRenderCaching = true

        let italic = Glimmer.parseToAttributedString("*cache-key*", configuration: config)
        let bold = Glimmer.parseToAttributedString("**cache-key**", configuration: config)

        XCTAssertNotEqual(italic, bold, "Render cache should not alias emphasis and strong text")
    }

    func testRenderCacheDistinguishesLinkDestinations() {
        Glimmer.clearRenderCache()

        var config = MarkdownConfiguration()
        config.enableRenderCaching = true

        let first = Glimmer.parseToAttributedString("[x](https://a.example)", configuration: config)
        let second = Glimmer.parseToAttributedString("[x](https://b.example)", configuration: config)

        let firstLink = first.runs.compactMap(\.link).first
        let secondLink = second.runs.compactMap(\.link).first

        XCTAssertEqual(firstLink?.host, "a.example")
        XCTAssertEqual(secondLink?.host, "b.example")
    }

    func testCompositeRenderCacheRecordsListHit() {
        MarkdownRenderer.clearRenderCache()

        var config = MarkdownConfiguration()
        config.enableRenderCaching = true

        let blocks = MarkdownParser.parse("- **one**\n- two", configuration: config)
        var renderer = MarkdownRenderer()
        _ = renderer.render(blocks: blocks, configuration: config)
        _ = renderer.render(blocks: blocks, configuration: config)

        let stats = MarkdownRenderer.getRenderCacheStats()
        XCTAssertGreaterThanOrEqual(stats.misses, 1)
        XCTAssertGreaterThanOrEqual(stats.hits, 1)
    }

    func testCompositeRenderCacheDistinguishesNestedLinkDestinations() {
        MarkdownRenderer.clearRenderCache()

        var config = MarkdownConfiguration()
        config.enableRenderCaching = true

        let first = Glimmer.parseToAttributedString("- [x](https://a.example)", configuration: config)
        let second = Glimmer.parseToAttributedString("- [x](https://b.example)", configuration: config)

        let firstLink = first.runs.compactMap(\.link).first
        let secondLink = second.runs.compactMap(\.link).first

        XCTAssertEqual(firstLink?.host, "a.example")
        XCTAssertEqual(secondLink?.host, "b.example")
    }

    func testLargeDocumentRenderCacheDistinguishesLinkDestinations() {
        MarkdownRenderer.clearRenderCache()

        var config = MarkdownConfiguration()
        config.enableRenderCaching = true

        let first = Glimmer.parseToAttributedString(
            makeLargeDocument(link: "https://a.example"),
            configuration: config
        )
        let second = Glimmer.parseToAttributedString(
            makeLargeDocument(link: "https://b.example"),
            configuration: config
        )

        XCTAssertEqual(first.runs.compactMap(\.link).first?.host, "a.example")
        XCTAssertEqual(second.runs.compactMap(\.link).first?.host, "b.example")
    }

    func testLargeDocumentRenderCacheDoesNotPopulateNestedBlockCacheOnColdFill() {
        MarkdownRenderer.clearRenderCache()

        var config = MarkdownConfiguration()
        config.enableRenderCaching = true

        let blocks = MarkdownParser.parse(makeLargeDocument(link: "https://example.com"), configuration: config)
        XCTAssertGreaterThanOrEqual(blocks.count, 32)

        var renderer = MarkdownRenderer()
        _ = renderer.render(blocks: blocks, configuration: config)
        var stats = MarkdownRenderer.getRenderCacheStats()
        XCTAssertEqual(stats.misses, 1)
        XCTAssertEqual(stats.hits, 0)

        _ = renderer.render(blocks: blocks, configuration: config)
        stats = MarkdownRenderer.getRenderCacheStats()
        XCTAssertEqual(stats.misses, 1)
        XCTAssertEqual(stats.hits, 1)
    }

    private func makeLargeDocument(link: String) -> String {
        (0..<40).map { index in
            index == 20 ? "Paragraph \(index) with [link](\(link))." : "Paragraph \(index)."
        }.joined(separator: "\n\n")
    }
}

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
}

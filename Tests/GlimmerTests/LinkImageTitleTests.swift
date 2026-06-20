import XCTest
@testable import Glimmer

final class LinkImageTitleTests: XCTestCase {
    func testSimpleLinkResourceParsesWithoutTitle() {
        let md = "[site](https://example.com/docs/123?ref=glimmer)"
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        guard case .link(let url, let title, let inner) = children.first else { return XCTFail("Expected link") }
        XCTAssertEqual(url.absoluteString, "https://example.com/docs/123?ref=glimmer")
        XCTAssertNil(title)
        XCTAssertEqual(inner, [.text("site")])
    }

    func testSimpleImageResourceParsesWithoutTitle() {
        let md = "![diagram](https://example.com/assets/diagram.png)"
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        guard case .image(let url, let alt, let title) = children.first else { return XCTFail("Expected image") }
        XCTAssertEqual(url.absoluteString, "https://example.com/assets/diagram.png")
        XCTAssertEqual(alt, "diagram")
        XCTAssertNil(title)
    }

    func testLinkWithDoubleQuotedTitle() {
        let md = "[site](http://example.com \"Example\")"
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        guard case .link(let url, let title, let inner) = children.first else { return XCTFail("Expected link") }
        XCTAssertEqual(url.absoluteString, "http://example.com")
        XCTAssertEqual(title, "Example")
        XCTAssertEqual(inner, [.text("site")])
    }

    func testImageWithSingleQuotedTitle() {
        let md = "![alt](http://img.test 'Pic')"
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        guard case .image(let url, let alt, let title) = children.first else { return XCTFail("Expected image") }
        XCTAssertEqual(url.absoluteString, "http://img.test")
        XCTAssertEqual(alt, "alt")
        XCTAssertEqual(title, "Pic")
    }

    func testLinkWithParenDelimitedTitle() {
        let md = "[t](http://a (Paren Title))"
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        guard case .link(let url, let title, let inner) = children.first else { return XCTFail("Expected link") }
        XCTAssertEqual(url.absoluteString, "http://a")
        XCTAssertEqual(title, "Paren Title")
        XCTAssertEqual(inner, [.text("t")])
    }

    func testImageWithParenDelimitedTitle() {
        let md = "![a](http://img (Paren Title))"
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        guard case .image(let url, let alt, let title) = children.first else { return XCTFail("Expected image") }
        XCTAssertEqual(url.absoluteString, "http://img")
        XCTAssertEqual(alt, "a")
        XCTAssertEqual(title, "Paren Title")
    }

    func testLinkTitleWithEscapedQuotes() {
        let md = "[t](http://a \"A \\\"quote\\\" title\")"
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        guard case .link(let url, let title, _) = children.first else { return XCTFail("Expected link") }
        XCTAssertEqual(url.absoluteString, "http://a")
        XCTAssertEqual(title, "A \"quote\" title")
    }

    func testLinkQuotedTitleWithBalancedParentheses() {
        let md = "[t](http://a \"A (parenthetical) title\")"
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        guard case .link(let url, let title, let inner) = children.first else { return XCTFail("Expected link") }
        XCTAssertEqual(url.absoluteString, "http://a")
        XCTAssertEqual(title, "A (parenthetical) title")
        XCTAssertEqual(inner, [.text("t")])
    }

    func testLinkParenTitleWithEscapedClosingParen() {
        let md = "[t](http://a (A \\) title))"
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        guard case .link(let url, let title, let inner) = children.first else { return XCTFail("Expected link") }
        XCTAssertEqual(url.absoluteString, "http://a")
        XCTAssertEqual(title, "A ) title")
        XCTAssertEqual(inner, [.text("t")])
    }

    func testLinkUnicodeDestinationBeforeTitle() {
        let md = "[cafe](https://example.com/café \"Cafe title\")"
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        guard case .link(let url, let title, let inner) = children.first else { return XCTFail("Expected link") }
        XCTAssertEqual(url.absoluteString, "https://example.com/caf%C3%A9")
        XCTAssertEqual(title, "Cafe title")
        XCTAssertEqual(inner, [.text("cafe")])
    }

    func testLinkTitleCanBeSeparatedByTab() {
        let md = "[t](https://example.com/a\t\"Tabbed title\")"
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        guard case .link(let url, let title, let inner) = children.first else { return XCTFail("Expected link") }
        XCTAssertEqual(url.absoluteString, "https://example.com/a")
        XCTAssertEqual(title, "Tabbed title")
        XCTAssertEqual(inner, [.text("t")])
    }

    func testLinkDestinationUnescapesBackslashEscapes() {
        let md = "[t](https://example.com/a\\_b)"
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        guard case .link(let url, _, let inner) = children.first else { return XCTFail("Expected link") }
        XCTAssertEqual(url.absoluteString, "https://example.com/a_b")
        XCTAssertEqual(inner, [.text("t")])
    }

    func testLinkDestinationPreservesBalancedParentheses() {
        let md = "[t](https://example.com/a(b)c)"
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        guard case .link(let url, _, let inner) = children.first else { return XCTFail("Expected link") }
        XCTAssertEqual(url.absoluteString, "https://example.com/a(b)c")
        XCTAssertEqual(inner, [.text("t")])
    }

    func testLinkDestinationUnescapesClosingParenthesis() {
        let md = "[t](https://example.com/a\\)b)"
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        guard case .link(let url, _, let inner) = children.first else { return XCTFail("Expected link") }
        XCTAssertEqual(url.absoluteString, "https://example.com/a)b")
        XCTAssertEqual(inner, [.text("t")])
    }

    func testImageDestinationUnescapesBackslashEscapes() {
        let md = "![alt](https://example.com/i\\_1.png)"
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        guard case .image(let url, let alt, _) = children.first else { return XCTFail("Expected image") }
        XCTAssertEqual(url.absoluteString, "https://example.com/i_1.png")
        XCTAssertEqual(alt, "alt")
    }

    func testLinkTextWithEscapedBrackets() {
        let md = "[a \\[b\\]](http://example.com)"
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        guard case .link(let url, _, let inner) = children.first else { return XCTFail("Expected link") }
        XCTAssertEqual(url.absoluteString, "http://example.com")
        XCTAssertEqual(inner, [.text("a [b]")])
    }

    func testLinkTextWithNestedBrackets() {
        let md = "[outer [inner]](http://example.com)"
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        guard case .link(let url, _, let inner) = children.first else { return XCTFail("Expected link") }
        XCTAssertEqual(url.absoluteString, "http://example.com")
        XCTAssertEqual(inner, [.text("outer [inner]")])
    }

    func testImageAltTextWithEscapedBrackets() {
        let md = "![a \\[b\\]](http://img.test)"
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        guard case .image(let url, let alt, _) = children.first else { return XCTFail("Expected image") }
        XCTAssertEqual(url.absoluteString, "http://img.test")
        XCTAssertEqual(alt, "a [b]")
    }
}

import XCTest
@testable import Glimmer

final class LinkImageTitleTests: XCTestCase {
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
}

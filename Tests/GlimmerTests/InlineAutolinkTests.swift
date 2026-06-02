import XCTest
@testable import Glimmer

final class InlineAutolinkTests: XCTestCase {
    func testAngleBracketURL() {
        let md = "<https://example.com>"
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        guard case .autolink(let url, let type, let original) = children.first else { return XCTFail("Expected autolink") }
        XCTAssertEqual(url.absoluteString, "https://example.com")
        XCTAssertEqual(type, .url)
        XCTAssertEqual(original, "https://example.com")
    }

    func testAngleBracketEmail() {
        let md = "<user@example.com>"
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        guard case .autolink(let url, let type, let original) = children.first else { return XCTFail("Expected autolink") }
        XCTAssertEqual(url.absoluteString, "mailto:user@example.com")
        XCTAssertEqual(type, .email)
        XCTAssertEqual(original, "user@example.com")
    }

    func testWWWAutolink() {
        let md = "Go www.example.com!"
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        // Match any autolink in children
        guard let node = children.first(where: { if case .autolink = $0 { return true } else { return false } }) else {
            return XCTFail("No autolink found")
        }
        if case let .autolink(url, type, original) = node {
            XCTAssertEqual(url.absoluteString, "http://www.example.com")
            XCTAssertEqual(type, .www)
            XCTAssertEqual(original, "www.example.com")
        }
    }

    func testTrimTrailingPunctuation() {
        let md = "See http://example.com, now."
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        // Should contain an autolink to the domain without comma
        XCTAssertTrue(children.contains { node in
            if case let .autolink(url, _, _) = node { return url.absoluteString == "http://example.com" }
            return false
        })
    }

    func testTrimUnbalancedClosingParen() {
        let md = "Visit http://a.com)."
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        XCTAssertTrue(children.contains { node in
            if case let .autolink(url, _, _) = node { return url.absoluteString == "http://a.com" }
            return false
        })
    }

    func testBalancedParensPreserved() {
        let md = "See http://example.com/path(foo)."
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        XCTAssertTrue(children.contains { node in
            if case let .autolink(url, _, _) = node { return url.absoluteString == "http://example.com/path(foo)" }
            return false
        })
    }

    func testAngleBracketWithTrailingPunctuation() {
        let md = "<https://example.com>."
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        guard case .autolink(let url, let type, let original) = children.first else { return XCTFail("Expected autolink") }
        XCTAssertEqual(url.absoluteString, "https://example.com")
        XCTAssertEqual(type, .url)
        XCTAssertEqual(original, "https://example.com")
    }

    func testWWWAutolinkTrimComma() {
        let md = "Check www.site.com, please"
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        XCTAssertTrue(children.contains { node in
            if case let .autolink(url, _, original) = node {
                return url.absoluteString == "http://www.site.com" && original == "www.site.com"
            }
            return false
        })
    }
}

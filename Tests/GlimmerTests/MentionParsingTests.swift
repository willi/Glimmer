import XCTest
@testable import Glimmer

final class MentionParsingTests: XCTestCase {
    func testEmailNotMention() {
        let md = "Contact user@example.com please"
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        XCTAssertFalse(children.contains { if case .mention = $0 { return true } else { return false } })
    }

    func testMentionInParens() {
        let md = "Hello (@alice)"
        let blocks = MarkdownParser.parse(md)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        XCTAssertTrue(children.contains { if case .mention(let u) = $0 { return u == "alice" } else { return false } })
    }
}


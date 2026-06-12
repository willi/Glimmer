import XCTest
import SwiftUI
@testable import Glimmer

final class RevealModelTests: XCTestCase {

    // MARK: - Renderer session

    func testStandaloneInlineCodeStyledAfterBeginSession() {
        let config = MarkdownConfiguration.default
        var renderer = MarkdownRenderer()
        renderer.beginSession(configuration: config)
        let attributed = renderer.renderInlines(
            [.code("let x = 1")], configuration: config
        )
        XCTAssertEqual(attributed.runs.first?.font, config.codeFont,
                       "code inline must get codeFont without a full render(blocks:) pass")
    }

    func testStandaloneMentionColoredAfterBeginSession() {
        let config = MarkdownConfiguration.default
        var renderer = MarkdownRenderer()
        renderer.beginSession(configuration: config)
        let attributed = renderer.renderInlines(
            [.mention(username: "octocat")], configuration: config
        )
        XCTAssertEqual(attributed.runs.first?.foregroundColor, config.mentionColor)
    }

    // MARK: - Tokenization

    func testRevealTokensSplitsWordsAndSpaces() {
        let tokens = AttributedString("Hello brave world").revealTokens()
        XCTAssertEqual(tokens.count, 5)
        XCTAssertEqual(String(tokens[0].slice.characters), "Hello")
        XCTAssertTrue(tokens[1].isWhitespace)
        XCTAssertEqual(String(tokens[2].slice.characters), "brave")
        XCTAssertEqual(String(tokens[4].slice.characters), "world")
        XCTAssertFalse(tokens[4].isWhitespace)
    }

    func testRevealTokensCollapsedWhitespaceRuns() {
        let tokens = AttributedString("a  b").revealTokens()
        XCTAssertEqual(tokens.count, 3)
        XCTAssertEqual(String(tokens[1].slice.characters), "  ")
        XCTAssertTrue(tokens[1].isWhitespace)
    }

    func testRevealTokensEmptyString() {
        XCTAssertTrue(AttributedString("").revealTokens().isEmpty)
    }

    func testRevealTokensPreserveRunAttributes() {
        var s = AttributedString("tap here now")
        if let range = s.range(of: "here") {
            s[range].link = URL(string: "https://example.com")
        }
        let tokens = s.revealTokens()
        XCTAssertEqual(tokens[2].slice.runs.first?.link?.absoluteString, "https://example.com")
        XCTAssertNil(tokens[0].slice.runs.first?.link)
    }

    func testRevealCharactersSplitsPreservingAttributes() {
        var s = AttributedString("ab")
        s.font = .body.bold()
        let chars = s.revealCharacters()
        XCTAssertEqual(chars.count, 2)
        XCTAssertEqual(String(chars[0].characters), "a")
        XCTAssertEqual(chars[1].runs.first?.font, Font.body.bold())
    }
}

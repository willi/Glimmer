import UIKit
import XCTest
@testable import Glimmer

/// `:emoji:` shortcodes (opt-in): GitHub's set, restored from 1.x. Standard ones become their emoji; GitHub's custom
/// ones (`:octocat:`) inline images.
@MainActor
final class GlimmerEmojiShortcodesTests: XCTestCase {
    private func composed(_ markdown: String) -> NSAttributedString {
        GlimmerComposer(theme: .default, extensions: [GlimmerEmojiShortcodes()]).compose(GlimmerParser.parse(markdown))
    }

    func testAShortcodeBecomesItsEmoji() {
        XCTAssertEqual(composed("Ship it :rocket: now").string, "Ship it 🚀 now")
        XCTAssertEqual(composed(":+1: and :-1:").string, "👍 and 👎")
    }

    func testACustomShortcodeIsAnInlineImage() throws {
        let text = composed("Hi :octocat:!")
        let attachment = try XCTUnwrap(text.attribute(.attachment, at: 3, effectiveRange: nil) as? GlimmerInlineImageAttachment)
        XCTAssertEqual(attachment.source.host(), "github.githubassets.com")
        XCTAssertEqual(attachment.alt, ":octocat:")
    }

    func testUnknownShortcodesStayText() {
        XCTAssertEqual(composed("A :notanemoji: here").string, "A :notanemoji: here")
    }

    func testTimesAndRatiosAreNotShortcodes() {
        for markdown in ["Meet at 10:30 today", "Ratio a:b:c holds", "Scores 3:1:2"] {
            XCTAssertEqual(composed(markdown).string, markdown)
        }
    }

    func testAnEscapedColonIsNotAShortcode() {
        XCTAssertEqual(composed("Type \\:rocket: for :rocket:").string, "Type :rocket: for 🚀")
    }

    func testShortcodesSkipCode() throws {
        XCTAssertEqual(composed("Type `:rocket:` for 🚀").string, "Type :rocket: for 🚀")
        let text = composed("```\n:rocket:\n```")
        let attachment = try XCTUnwrap(blockAttachments(in: text).first)
        guard case .codeBlock(_, let code, _) = attachment.embed else { return XCTFail("expected fenced code") }
        XCTAssertEqual(code, ":rocket:")
        XCTAssertEqual(GlimmerMarkdownSerializer.plainText(from: text, range: NSRange(location: 0, length: text.length)), ":rocket:")
    }

    func testAnUnclosedShortcodeIsHeldBackUntilItCloses() async {
        let shortcodes = GlimmerEmojiShortcodes()
        XCTAssertEqual(shortcodes.streamingHoldBack(in: "go :rock"), 5)
        XCTAssertEqual(shortcodes.streamingHoldBack(in: "go :rocket:"), 0)
        XCTAssertEqual(shortcodes.streamingHoldBack(in: "go :rock and"), 0, "released after a space")
        XCTAssertEqual(shortcodes.streamingHoldBack(in: "at 10:3"), 0, "a time")
        XCTAssertEqual(shortcodes.streamingHoldBack(in: "Note:"), 0)

        let view = GlimmerView(configuration: GlimmerConfiguration(extensions: [shortcodes], imageLoader: nil, reveal: .none))
        for (source, shown) in [("go :rock", "go"), ("go :rocket:", "go 🚀"), ("go :rock and", "go :rock and"), ("at 10:3", "at 10:3")] {
            view.update(markdown: source, isStreaming: true)
            await view.pendingDocument?.value
            XCTAssertEqual(view.plainText(), shown, "visible content for \(source)")
        }

    }

    func testShortcodesCopyAsSourceAndEmoji() {
        let text = composed("Ship it :rocket:!")
        let all = NSRange(location: 0, length: text.length)
        XCTAssertEqual(GlimmerMarkdownSerializer.markdown(from: text, range: all), "Ship it :rocket:!")
        XCTAssertEqual(GlimmerMarkdownSerializer.plainText(from: text, range: all), "Ship it 🚀!")
    }

    /// A missing or broken table says why, instead of leaving every shortcode as text without a word.
    func testAMissingTableSaysWhy() throws {
        XCTAssertThrowsError(try GlimmerEmojiShortcodes.loadTable(from: nil)) { error in
            XCTAssertEqual(error as? GlimmerEmojiShortcodes.TableError, .missingResource)
        }
        let broken = FileManager.default.temporaryDirectory.appendingPathComponent("broken-emoji.json")
        try Data("[1, 2]".utf8).write(to: broken)
        XCTAssertThrowsError(try GlimmerEmojiShortcodes.loadTable(from: broken)) { error in
            XCTAssertEqual(error as? GlimmerEmojiShortcodes.TableError, .notAnObject)
        }
    }

    func testTheTableHasTheGitHubSet() {
        XCTAssertGreaterThanOrEqual(GlimmerEmojiShortcodes.table.count, 1_900)
        guard case .image = GlimmerEmojiShortcodes.table["octocat"] else { return XCTFail("octocat is a custom image") }
        guard case .unicode("🚀") = GlimmerEmojiShortcodes.table["rocket"] else { return XCTFail("rocket is 🚀") }
    }

    func testShortcodesStreamWithoutMovingShownText() {
        assertStreamingKeepsShownTextInPlace(
            "Ship it :rocket: then :tada: and :octocat: at 10:30.\n\nThe next paragraph keeps growing.",
            configuration: GlimmerConfiguration(extensions: [GlimmerEmojiShortcodes()], imageLoader: nil, reveal: .none),
            every: 1, expectedPlainText: "Ship it 🚀 then 🎉 and :octocat: at 10:30.\nThe next paragraph keeps growing."
        )
    }

    func testStyledAndRepeatedShortcodesCopyAsWritten() {
        for markdown in ["**:rocket: Launch**", "[:rocket: docs](https://x.y)", ":tada::tada:", "a :+1::+1: b", "*:octocat: here*"] {
            let text = composed(markdown)
            XCTAssertEqual(GlimmerMarkdownSerializer.markdown(from: text, range: NSRange(location: 0, length: text.length)), markdown)
        }
    }
}

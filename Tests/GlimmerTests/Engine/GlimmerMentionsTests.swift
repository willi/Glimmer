import UIKit
import XCTest
@testable import Glimmer

/// `@username` mentions (opt-in): GitHub's rules, text in the mention colour, reported through `onTokenTap`.
@MainActor
final class GlimmerMentionsTests: XCTestCase {
    private let theme = GlimmerTheme.default

    private func composed(_ markdown: String, extensions: [any GlimmerExtension] = [GlimmerMentions()]) -> NSAttributedString {
        GlimmerComposer(theme: theme, extensions: extensions).compose(GlimmerParser.parse(markdown))
    }

    private func mentions(in text: NSAttributedString) -> [String] {
        var found: [String] = []
        text.enumerateAttribute(.glimmerToken, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if value is GlimmerTokenBox { found.append((text.string as NSString).substring(with: range)) }
        }
        return found
    }

    func testAMentionIsTappableTextInTheMentionColor() throws {
        let text = composed("Thanks @ada for this.")
        XCTAssertEqual(text.string, "Thanks @ada for this.", "the mention stays text")
        XCTAssertEqual(mentions(in: text), ["@ada"])
        let location = (text.string as NSString).range(of: "@ada").location
        XCTAssertEqual(text.attribute(.foregroundColor, at: location, effectiveRange: nil) as? UIColor, theme.mentionColor)
        XCTAssertNotNil(text.attribute(.textItemTag, at: location, effectiveRange: nil), "UIKit reports taps on it")
        let box = try XCTUnwrap(text.attribute(.glimmerToken, at: location, effectiveRange: nil) as? GlimmerTokenBox)
        XCTAssertEqual(box.token.kind, "mention")
        XCTAssertEqual(box.token.payload["username"], "ada")
    }

    func testTappingAMentionCallsOnTokenTap() throws {
        let view = GlimmerView(configuration: GlimmerConfiguration(extensions: [GlimmerMentions()], imageLoader: nil))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: "Thanks @grace-hopper!")
        settle(view)
        let location = (view.textView.textStorage.string as NSString).range(of: "@grace").location
        XCTAssertNil(view.tokenAction(atCharacter: location), "no action without a handler")
        var tapped: GlimmerInlineToken?
        view.onTokenTap = { tapped = $0 }
        XCTAssertNotNil(view.tokenAction(atCharacter: location))
        view.tapToken(atCharacter: location)
        XCTAssertEqual(tapped?.payload["username"], "grace-hopper")
        _ = window
    }

    func testEmailsAndLoneAtSignsAreNotMentions() {
        for markdown in ["Write ada@example.com today.", "A lone @ sign.", "Not @-x either.", "Visit @example.com now.", "Too @a--b."] {
            XCTAssertEqual(mentions(in: composed(markdown)), [], markdown)
        }
        XCTAssertEqual(mentions(in: composed("Ask @ada.")), ["@ada"], "a sentence-ending period is not a domain")
    }

    func testMentionsSkipLinksAndCode() {
        XCTAssertEqual(mentions(in: composed("See [@ada](https://example.com) and `@grace`.")), [])
    }

    func testMentionsCopyAsTheirSource() {
        let text = composed("Thanks @ada!")
        let all = NSRange(location: 0, length: text.length)
        XCTAssertEqual(GlimmerMarkdownSerializer.markdown(from: text, range: all), "Thanks @ada!")
        XCTAssertEqual(GlimmerMarkdownSerializer.plainText(from: text, range: all), "Thanks @ada!")
    }

    func testWithoutTheExtensionAMentionIsPlainText() {
        let text = composed("Thanks @ada!", extensions: [])
        XCTAssertEqual(mentions(in: text), [])
        XCTAssertEqual(text.attribute(.foregroundColor, at: 7, effectiveRange: nil) as? UIColor, theme.textColor)
    }

    func testAPartialMentionIsHeldBackWhileStreaming() {
        let mentions = GlimmerMentions()
        XCTAssertEqual(mentions.streamingHoldBack(in: "Thanks @gra"), 4)
        XCTAssertEqual(mentions.streamingHoldBack(in: "Thanks @grace."), 7)
        XCTAssertEqual(mentions.streamingHoldBack(in: "Thanks @grace "), 0)
        XCTAssertEqual(mentions.streamingHoldBack(in: "ada@exa"), 0, "part of an email")
    }

    func testMentionsStreamWithoutMovingShownText() {
        assertStreamingKeepsShownTextInPlace(
            "Thanks @ada and @grace-hopper for this. Reach ada@example.com or @example.com.",
            configuration: GlimmerConfiguration(extensions: [GlimmerMentions()], imageLoader: nil, reveal: .none),
            every: 1
        )
    }
}

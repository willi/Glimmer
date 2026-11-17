import UIKit
import XCTest
@testable import Glimmer

/// Turns `[3]` into a citation chip.
private struct CitationExtension: GlimmerExtension {
    func scan(_ text: String) -> [GlimmerInlineToken] {
        text.ranges(of: #/\[\d+\]/#).map { range in
            let label = String(text[range])
            return GlimmerInlineToken(
                range: range, kind: "citation", payload: ["index": String(label.dropFirst().dropLast())],
                displayText: label, source: label
            )
        }
    }

    @MainActor func makeInlineView(for token: GlimmerInlineToken, theme: GlimmerTheme) -> UIView? {
        let label = UILabel()
        label.text = token.payload["index"]
        label.font = theme.captionFont
        label.accessibilityIdentifier = "citation"
        return label
    }
}

/// A citation chip that reports taps.
private struct TappableCitations: GlimmerExtension {
    private let base = CitationExtension()

    func scan(_ text: String) -> [GlimmerInlineToken] {
        base.scan(text).map { token in
            var tappable = token
            tappable.isTappable = true
            return tappable
        }
    }

    @MainActor func makeInlineView(for token: GlimmerInlineToken, theme: GlimmerTheme) -> UIView? {
        base.makeInlineView(for: token, theme: theme)
    }
}

@MainActor
final class GlimmerExtensionTests: XCTestCase {
    private let theme = GlimmerTheme.default

    private func compose(_ markdown: String, extensions: [any GlimmerExtension]) -> NSAttributedString {
        GlimmerComposer(theme: theme, extensions: extensions).compose(GlimmerParser.parse(markdown))
    }

    func testCitationBecomesInlineAttachmentWithSource() {
        let text = compose("See [3] now", extensions: [CitationExtension()])
        XCTAssertEqual(text.string, "See \u{FFFC} now")
        XCTAssertTrue(text.attribute(.attachment, at: 4, effectiveRange: nil) is GlimmerInlineAttachment)
        XCTAssertEqual(text.attribute(.glimmerSource, at: 4, effectiveRange: nil) as? String, "[3]")
    }

    func testWithoutExtensionsTextIsUntouched() {
        XCTAssertEqual(compose("See [3] now", extensions: []).string, "See [3] now")
    }

    func testChipsInsideBoldKeepBoldFont() {
        let text = compose("**See [3]**", extensions: [CitationExtension()])
        let font = text.attribute(.font, at: 4, effectiveRange: nil) as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
    }

    func testTwoTokensInOneRun() {
        XCTAssertEqual(compose("a [1] b [2] c", extensions: [CitationExtension()]).string, "a \u{FFFC} b \u{FFFC} c")
    }

    func testInlineChipIsHostedAtLineHeight() throws {
        let textView = GlimmerTextView()
        textView.attributedText = compose("See [3] now", extensions: [CitationExtension()])
        let height = textView.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height
        let window = hostInWindow(textView, width: 390, height: height)
        let chip = try XCTUnwrap(textView.allSubviews.compactMap { $0 as? UILabel }.first { $0.accessibilityIdentifier == "citation" })
        XCTAssertEqual(chip.frame.height, ceil(theme.bodyFont.lineHeight), accuracy: 1)
        _ = window
    }

    func testChipAfterEmojiKeepsItsRange() {
        let text = compose("👋🏽 [3] after", extensions: [CitationExtension()])
        let chip = (text.string as NSString).range(of: "\u{FFFC}").location
        XCTAssertEqual(text.string, "👋🏽 \u{FFFC} after")
        XCTAssertTrue(text.attribute(.attachment, at: chip, effectiveRange: nil) is GlimmerInlineAttachment)
        XCTAssertEqual(text.attribute(.glimmerSource, at: chip, effectiveRange: nil) as? String, "[3]")
        XCTAssertNil(text.attribute(.attachment, at: chip + 2, effectiveRange: nil))
    }

    // MARK: - Tappable chips

    private func tappableView(reveal: GlimmerReveal = .none) -> GlimmerView {
        GlimmerView(configuration: GlimmerConfiguration(extensions: [TappableCitations()], imageLoader: nil, reveal: reveal))
    }

    func testTappingATappableChipCallsOnTokenTap() {
        let view = tappableView()
        view.update(markdown: "See [1].")
        let window = hostInWindow(view, width: 320, height: 200)
        var tapped: GlimmerInlineToken?
        view.onTokenTap = { tapped = $0 }
        let host = findSubview(GlimmerChipTapView.self, in: view)
        XCTAssertNotNil(host)
        host?.handleTap()
        XCTAssertEqual(tapped?.displayText, "[1]")
        _ = window
    }

    func testATappableChipIsAVoiceOverLink() throws {
        let text = compose("See [1].", extensions: [TappableCitations()])
        var linkRange: NSRange?
        text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let url = value as? URL, GlimmerTokenBox.isTokenLink(url) { linkRange = range }
        }
        let range = try XCTUnwrap(linkRange)
        // The link covers the chip's glyph and its spoken text, so its frame is the chip's rect.
        XCTAssertEqual((text.string as NSString).substring(with: range), "\u{FFFC}[1]")
        XCTAssertNil(text.attribute(.glimmerSpokenOnly, at: range.location, effectiveRange: nil))
        XCTAssertNotNil(text.attribute(.glimmerSpokenOnly, at: range.location + 1, effectiveRange: nil))
        XCTAssertNotNil(text.attribute(.glimmerToken, at: range.location, effectiveRange: nil))
        XCTAssertNotNil(text.attribute(.glimmerToken, at: range.location + 1, effectiveRange: nil))
    }

    func testAnUntappableChipHasNoLinkAndNoTapHost() {
        let text = compose("See [1].", extensions: [CitationExtension()])
        XCTAssertEqual(text.string, "See \u{FFFC}.")
        text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, _, _ in XCTAssertNil(value) }
        text.enumerateAttribute(.glimmerToken, in: NSRange(location: 0, length: text.length)) { value, _, _ in XCTAssertNil(value) }
        let view = GlimmerView(configuration: GlimmerConfiguration(extensions: [CitationExtension()], imageLoader: nil, reveal: .none))
        view.update(markdown: "See [1].")
        let window = hostInWindow(view, width: 320, height: 200)
        XCTAssertNil(findSubview(GlimmerChipTapView.self, in: view))
        _ = window
    }

    func testCopyingATappableChipWritesItsSourceOnce() {
        let view = tappableView()
        view.update(markdown: "See [1].")
        let window = hostInWindow(view, width: 320, height: 200)
        XCTAssertEqual(view.markdownSource(for: nil), "See [1].")
        XCTAssertEqual(view.plainText(for: nil), "See [1].")
        _ = window
    }

    func testATappableChipCannotBeTappedBeforeItIsRevealed() async throws {
        let view = tappableView(reveal: .smooth(GlimmerRevealOptions()))
        let clock = ManualRevealClock()
        view.clock = clock
        let window = hostInWindow(view, width: 320, height: 200)
        view.onTokenTap = { _ in }
        let markdown = "A fairly long opening sentence so the reveal takes a while to reach the end. See [1]."
        view.update(markdown: markdown, isStreaming: true)
        await view.pendingDocument?.value
        settle(view)
        let host = try XCTUnwrap(findSubview(GlimmerChipTapView.self, in: view))
        XCTAssertFalse(host.acceptsTaps)
        view.update(markdown: markdown, isStreaming: false)
        await view.pendingDocument?.value
        clock.advance(to: 60)
        XCTAssertTrue(host.acceptsTaps)
        _ = window
    }

    /// The text under a hidden chip or mention carries a token link too: a tap through the text view must not reach the
    /// host before the token is revealed.
    func testTokenTapsThroughTheTextViewWaitForTheReveal() async throws {
        for extensions: [any GlimmerExtension] in [[TappableCitations()], [GlimmerMentions()]] {
            let view = GlimmerView(configuration: GlimmerConfiguration(extensions: extensions, imageLoader: nil, reveal: .smooth(GlimmerRevealOptions())))
            let clock = ManualRevealClock()
            view.clock = clock
            let window = hostInWindow(view, width: 320, height: 200)
            view.onTokenTap = { _ in }
            let token = extensions.first is GlimmerMentions ? "@grace" : "[1]"
            let markdown = "A fairly long opening sentence so the reveal takes a while to reach the end. See \(token) now."
            view.update(markdown: markdown, isStreaming: true)
            await view.pendingDocument?.value
            settle(view)
            let index = (view.textView.textStorage.string as NSString).range(of: token == "[1]" ? "\u{FFFC}" : token).location
            XCTAssertNotEqual(index, NSNotFound)
            XCTAssertNil(view.tokenAction(atCharacter: index), "hidden \(token) can't be tapped")
            var taps = 0
            view.onTokenTap = { _ in taps += 1 }
            view.tapToken(atCharacter: index)
            XCTAssertEqual(taps, 0)
            view.update(markdown: markdown, isStreaming: false)
            await view.pendingDocument?.value
            clock.advance(to: 60)
            XCTAssertNotNil(view.tokenAction(atCharacter: index), "revealed \(token) can be tapped")
            view.tapToken(atCharacter: index)
            XCTAssertEqual(taps, 1)
            _ = window
        }
    }
}

private extension UIView {
    var allSubviews: [UIView] { subviews + subviews.flatMap(\.allSubviews) }
}

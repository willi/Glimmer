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
}

private extension UIView {
    var allSubviews: [UIView] { subviews + subviews.flatMap(\.allSubviews) }
}

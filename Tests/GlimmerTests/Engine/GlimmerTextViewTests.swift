import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerTextViewTests: XCTestCase {
    private let theme = GlimmerTheme.default

    private func attachment(_ embed: GlimmerEmbed) -> NSAttributedString {
        NSAttributedString(attachment: GlimmerBlockAttachment(
            embed: embed, theme: theme, highlighter: GlimmerBasicHighlighter(), imageLoader: nil
        ))
    }

    private func document(_ parts: [NSAttributedString]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, part) in parts.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n")) }
            result.append(part)
        }
        result.addAttribute(.font, value: theme.bodyFont, range: NSRange(location: 0, length: result.length))
        return result
    }

    func testStaysOnTextKit2() {
        let textView = GlimmerTextView()
        textView.attributedText = NSAttributedString(string: "Hello")
        XCTAssertNotNil(textView.textLayoutManager)
        XCTAssertFalse(textView.isScrollEnabled)
        XCTAssertFalse(textView.isEditable)
        XCTAssertTrue(textView.isSelectable)
    }

    func testEmptyTextAndZeroWidthMeasureZero() {
        let textView = GlimmerTextView()
        XCTAssertEqual(textView.sizeThatFits(CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)).height, 0)
        textView.attributedText = NSAttributedString(string: "Hello")
        XCTAssertEqual(textView.sizeThatFits(CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)).height, 0)
    }

    func testCodeBlockAttachmentHostsAFullWidthView() throws {
        let code = GlimmerEmbed.codeBlock(language: "swift", code: "let x = 1\nlet y = 2")
        let textView = GlimmerTextView()
        textView.attributedText = document([NSAttributedString(string: "Before"), attachment(code), NSAttributedString(string: "After")])
        let height = textView.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height
        let window = hostInWindow(textView, width: 390, height: height)

        let view = try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: textView))
        XCTAssertEqual(view.frame.width, 390, accuracy: 0.5)
        XCTAssertEqual(view.frame.height, view.embedHeight(forWidth: 390), accuracy: 0.5)
        XCTAssertGreaterThan(height, view.frame.height)
        _ = window
    }

    func testFactoryBuildsEveryEmbedKind() {
        let url = URL(string: "https://example.com/a.png")!  // test-only literal
        let embeds: [GlimmerEmbed] = [
            .codeBlock(language: nil, code: "x"),
            .table(header: [NSAttributedString(string: "h")], rows: [], alignments: [.none]),
            .image(source: url, alt: "a"),
            .thematicBreak,
        ]
        let kinds = embeds.map { embed in
            let attachment = GlimmerBlockAttachment(embed: embed, theme: theme, highlighter: GlimmerBasicHighlighter(), imageLoader: nil)
            return String(describing: type(of: GlimmerEmbedViewFactory.makeView(for: attachment)))
        }
        XCTAssertEqual(kinds, ["GlimmerCodeBlockView", "GlimmerTableView", "GlimmerImageEmbedView", "GlimmerRuleView"])
    }

    func testEmbedsResizeWhenWidthChanges() throws {
        let words = String(repeating: "wrap these words ", count: 30)
        let textView = GlimmerTextView()
        textView.attributedText = document([NSAttributedString(string: words), attachment(.thematicBreak)])
        let wide = textView.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height
        let window = hostInWindow(textView, width: 390, height: wide)
        let rule = try XCTUnwrap(findSubview(GlimmerRuleView.self, in: textView))
        XCTAssertEqual(rule.frame.width, 390, accuracy: 0.5)

        let narrow = textView.sizeThatFits(CGSize(width: 250, height: CGFloat.greatestFiniteMagnitude)).height
        XCTAssertGreaterThan(narrow, wide)
        textView.frame = CGRect(x: 0, y: 0, width: 250, height: narrow)
        settle(textView)
        let resized = try XCTUnwrap(findSubview(GlimmerRuleView.self, in: textView))
        XCTAssertEqual(resized.frame.width, 250, accuracy: 0.5)
        _ = window
    }

    func testThemeSetsLinkAttributes() {
        var themed = theme
        themed.underlinesLinks = true
        let textView = GlimmerTextView()
        textView.apply(theme: themed)
        XCTAssertEqual(textView.linkTextAttributes[.foregroundColor] as? UIColor, themed.linkColor)
        XCTAssertEqual(textView.linkTextAttributes[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)
    }
}

import SwiftUI
import UIKit
import XCTest
@testable import Glimmer

private struct LinkedChip: GlimmerExtension {
    func scan(_ text: String) -> [GlimmerInlineToken] {
        text.ranges(of: #/\[\d+\]/#).map { range in
            let label = String(text[range])
            var token = GlimmerInlineToken(range: range, kind: "chip", displayText: label, source: label)
            token.url = URL(string: "https://a.example/cite")
            return token
        }
    }

    @MainActor func makeInlineView(for token: GlimmerInlineToken, theme: GlimmerTheme) -> UIView? { UILabel() }
}

private struct RefuseAll: GlimmerLinkPolicy {
    func decision(for link: GlimmerLinkCandidate) -> GlimmerLinkDecision { .text }
}

/// Heading and code line height, loose-list spacing and the colour of a linked chip.
@MainActor
final class GlimmerThemeRolesTests: XCTestCase {
    private func theme(heading: CGFloat? = nil, code: CGFloat? = nil, loose: CGFloat? = nil) -> GlimmerTheme {
        var theme = GlimmerTheme.default
        theme.lineHeightMultiple = 1.4
        theme.headingLineHeightMultiple = heading
        theme.codeLineHeightMultiple = code
        theme.looseListSpacing = loose
        return theme
    }

    private func multiple(of text: String, in composed: NSAttributedString) -> CGFloat? {
        let location = (composed.string as NSString).range(of: text).location
        let style = composed.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        return style?.lineHeightMultiple
    }

    private func spacing(of text: String, in composed: NSAttributedString) -> CGFloat? {
        let location = (composed.string as NSString).range(of: text).location
        let style = composed.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        return style?.paragraphSpacing
    }

    private func compose(_ markdown: String, _ theme: GlimmerTheme) -> NSAttributedString {
        GlimmerComposer(theme: theme).compose(GlimmerParser.parse(markdown))
    }

    func testHeadingUsesItsOwnMultipleWhenSet() {
        let composed = compose("# Title\n\nBody", theme(heading: 1.1))
        XCTAssertEqual(multiple(of: "Title", in: composed), 1.1)
        XCTAssertEqual(multiple(of: "Body", in: composed), 1.4)
    }

    func testHeadingUsesTheBodyMultipleWhenNil() {
        XCTAssertEqual(multiple(of: "Title", in: compose("# Title", theme())), 1.4)
    }

    func testCodeUsesItsOwnMultipleWhenSet() {
        let styled = GlimmerCodeHighlighting.highlightedCode(
            "let x = 1", language: nil, theme: theme(code: 1.0), highlighter: GlimmerBasicHighlighter()
        )
        let style = styled.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.lineHeightMultiple, 1.0)
        let body = GlimmerCodeHighlighting.highlightedCode(
            "let x = 1", language: nil, theme: theme(), highlighter: GlimmerBasicHighlighter()
        )
        let bodyStyle = body.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(bodyStyle?.lineHeightMultiple, 1.4)
    }

    func testLooseListUsesLooseSpacingAndTightListKeepsItsOwn() {
        let theme = theme(loose: 10)
        let loose = compose("- one\n\n- two\n\nAfter", theme)
        XCTAssertEqual(spacing(of: "one", in: loose), 10)
        XCTAssertEqual(spacing(of: "After", in: loose), theme.paragraphSpacing)
        let tight = compose("- one\n- two\n\nAfter", theme)
        XCTAssertEqual(spacing(of: "one", in: tight), theme.tightListSpacing)
    }

    func testLooseListUsesParagraphSpacingWhenNil() {
        let theme = theme()
        XCTAssertEqual(spacing(of: "one", in: compose("- one\n\n- two", theme)), theme.paragraphSpacing)
    }

    func testNilFieldsComposeLikeTheDefaults() {
        let markdown = "# H\n\n- a\n\n- b\n\n```\ncode\n```"
        var plain = GlimmerTheme.default
        plain.lineHeightMultiple = 1.4
        assertEquivalent(compose(markdown, theme()), compose(markdown, plain), "nil fields")
    }

    func testLooseListSpacingScalesWithDynamicTypeButMultiplesDoNot() {
        let large = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraLarge)
        let scaled = theme(heading: 1.1, code: 1.0, loose: 10).scaled(for: large)
        XCTAssertGreaterThan(scaled.looseListSpacing ?? 0, 10)
        XCTAssertEqual(scaled.headingLineHeightMultiple, 1.1)
        XCTAssertEqual(scaled.codeLineHeightMultiple, 1.0)
        XCTAssertNil(theme().scaled(for: large).looseListSpacing)
    }

    func testStaticListSpacingMatches() throws {
        let theme = theme(loose: 10)
        var configuration = GlimmerConfiguration.default
        configuration.theme = theme
        let document = GlimmerStaticDocument(markdown: "- a\n\n- b", configuration: configuration, dynamicTypeSize: .large)
        let scaled = theme.scaled(for: UITraitCollection(preferredContentSizeCategory: .large))
        guard case .list(let list) = try XCTUnwrap(document.blocks.first).content else { return XCTFail("not a list") }
        XCTAssertEqual(list.items.map(\.spacingAbove), [0, scaled.looseListSpacing])
    }

    func testALinkedChipTakesTheLinkColour() throws {
        var configuration = GlimmerConfiguration()
        configuration.extensions = [LinkedChip()]
        configuration.theme.linkColor = .systemRed
        let text = GlimmerView.attributedString(for: "see [3] now", configuration: configuration, traitCollection: .init())
        let chip = try XCTUnwrap(text.range(of: "[3]"))
        XCTAssertEqual(text[chip].uiKit.foregroundColor, .systemRed)
        let prose = try XCTUnwrap(text.range(of: "see"))
        XCTAssertNotEqual(text[prose].uiKit.foregroundColor, .systemRed)
    }

    func testARefusedLinkInATableCellComposesWithoutALink() {
        let markdown = "| a |\n|---|\n| [x](https://a.example) |"
        var configuration = GlimmerConfiguration()
        configuration.linkPolicy = RefuseAll()
        let text = GlimmerView.attributedString(for: markdown, configuration: configuration)
        XCTAssertTrue(text.runs.allSatisfy { $0.link == nil })
        XCTAssertTrue(String(text.characters).contains("x"))
    }
}

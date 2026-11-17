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

/// `[n]` as tappable text (no chip), with a URL.
private struct TextToken: GlimmerExtension {
    func scan(_ text: String) -> [GlimmerInlineToken] {
        text.ranges(of: #/\[\d+\]/#).map { range in
            let label = String(text[range])
            var token = GlimmerInlineToken(
                range: range, kind: "text", displayText: label, source: label, presentation: .text(tappable: true)
            )
            token.url = URL(string: "https://a.example/cite")
            return token
        }
    }

    @MainActor func makeInlineView(for token: GlimmerInlineToken, theme: GlimmerTheme) -> UIView? { nil }
}

/// `[n]` as a chip without a URL.
private struct BareChip: GlimmerExtension {
    func scan(_ text: String) -> [GlimmerInlineToken] {
        text.ranges(of: #/\[\d+\]/#).map { range in
            let label = String(text[range])
            return GlimmerInlineToken(range: range, kind: "bare", displayText: label, source: label)
        }
    }

    @MainActor func makeInlineView(for token: GlimmerInlineToken, theme: GlimmerTheme) -> UIView? { UILabel() }
}

private struct RefuseAll: GlimmerLinkPolicy {
    func decision(for link: GlimmerLinkCandidate) -> GlimmerLinkDecision { .text }
}

/// Per-role line spacing, loose-list spacing and the colour of a linked chip.
@MainActor
final class GlimmerThemeRolesTests: XCTestCase {
    private func theme(
        body: CGFloat? = nil, heading: CGFloat? = nil, code: CGFloat? = nil, loose: CGFloat? = nil
    ) -> GlimmerTheme {
        var theme = GlimmerTheme.default
        theme.lineHeightMultiple = 1.4
        theme.lineSpacing = body
        theme.headingLineSpacing = heading
        theme.codeLineSpacing = code
        theme.looseListSpacing = loose
        return theme
    }

    private func style(of text: String, in composed: NSAttributedString) -> NSParagraphStyle? {
        let location = (composed.string as NSString).range(of: text).location
        return composed.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
    }

    private func multiple(of text: String, in composed: NSAttributedString) -> CGFloat? {
        style(of: text, in: composed)?.lineHeightMultiple
    }

    private func spacing(of text: String, in composed: NSAttributedString) -> CGFloat? {
        style(of: text, in: composed)?.paragraphSpacing
    }

    private func compose(_ markdown: String, _ theme: GlimmerTheme) -> NSAttributedString {
        GlimmerComposer(theme: theme).compose(GlimmerParser.parse(markdown))
    }

    private func codeStyle(_ theme: GlimmerTheme) -> NSParagraphStyle? {
        let styled = GlimmerCodeHighlighting.highlightedCode(
            "let x = 1\nlet y = 2", language: nil, theme: theme, highlighter: GlimmerBasicHighlighter()
        )
        return styled.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    }

    /// A set role spacing: no multiple, the spacing between lines, and the same amount off the space above.
    private func assertSpaced(
        _ style: NSParagraphStyle?, _ spacing: CGFloat, before: CGFloat = 0, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(style?.lineHeightMultiple, 1, file: file, line: line)
        XCTAssertEqual(style?.lineSpacing, spacing, file: file, line: line)
        XCTAssertEqual(style?.paragraphSpacingBefore, before - spacing, file: file, line: line)
    }

    func testHeadingUsesItsOwnSpacingWhenSet() {
        let composed = compose("Intro\n\n# Title\n\nBody", theme(heading: 2))
        let theme = theme(heading: 2)
        assertSpaced(style(of: "Title", in: composed), 2, before: theme.blockSpacing - theme.paragraphSpacing)
        XCTAssertEqual(spacing(of: "Title", in: composed), theme.paragraphSpacing)
        XCTAssertEqual(multiple(of: "Body", in: composed), 1.4)
        XCTAssertEqual(style(of: "Body", in: composed)?.lineSpacing, 0)
    }

    func testHeadingUsesTheBodyMultipleWhenNil() {
        let composed = compose("# Title", theme(body: 3))
        XCTAssertEqual(multiple(of: "Title", in: composed), 1.4)
        XCTAssertEqual(style(of: "Title", in: composed)?.lineSpacing, 0)
    }

    func testBodyListAndQuoteTextUseTheBodySpacing() {
        let composed = compose("Para\n\n- item\n\n> quoted\n\n# Head", theme(body: 3))
        for text in ["Para", "item", "quoted"] {
            assertSpaced(style(of: text, in: composed), 3)
        }
        XCTAssertEqual(spacing(of: "Para", in: composed), GlimmerTheme.default.paragraphSpacing)
        XCTAssertEqual(multiple(of: "Head", in: composed), 1.4)
    }

    func testCodeUsesItsOwnSpacingWhenSet() {
        let style = codeStyle(theme(body: 3, code: 2))
        XCTAssertEqual(style?.lineHeightMultiple, 1)
        XCTAssertEqual(style?.lineSpacing, 2)
        // Code lines are paragraphs of their own, so the spacing is not taken off above them.
        XCTAssertEqual(style?.paragraphSpacingBefore, 0)
        XCTAssertEqual(codeStyle(theme(body: 3))?.lineHeightMultiple, 1.4)
        XCTAssertEqual(codeStyle(theme(body: 3))?.lineSpacing, 0)
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

    func testNilFieldsKeepTheBodyBehaviour() throws {
        let theme = theme()
        let composed = compose("Intro\n\n# H\n\n- a\n\n- b\n\n> q\n\n```\ncode\n```", theme)
        // 2.3.0: every text paragraph has the theme's multiple and no line spacing; a heading after a paragraph has the
        // collapsed 16 − 12 pt above it.
        for text in ["Intro", "H", "a", "b", "q"] {
            XCTAssertEqual(multiple(of: text, in: composed), 1.4, text)
            XCTAssertEqual(style(of: text, in: composed)?.lineSpacing, 0, text)
        }
        XCTAssertEqual(style(of: "Intro", in: composed)?.paragraphSpacingBefore, 0)
        XCTAssertEqual(style(of: "H", in: composed)?.paragraphSpacingBefore, 4)
        XCTAssertEqual(spacing(of: "Intro", in: composed), 12)
        XCTAssertEqual(spacing(of: "a", in: composed), 12)
        XCTAssertEqual(spacing(of: "b", in: composed), 12)
        XCTAssertEqual(codeStyle(theme)?.lineHeightMultiple, 1.4)
        XCTAssertEqual(codeStyle(theme)?.lineSpacing, 0)
        let document = GlimmerStaticDocument(
            markdown: "- a\n\n- b", configuration: configuration(theme), dynamicTypeSize: .large
        )
        guard case .list(let list) = try XCTUnwrap(document.blocks.first).content else { return XCTFail("not a list") }
        XCTAssertEqual(list.items.map(\.spacingAbove), [0, 12])
    }

    private func configuration(_ theme: GlimmerTheme) -> GlimmerConfiguration {
        var configuration = GlimmerConfiguration.default
        configuration.theme = theme
        return configuration
    }

    func testHeadingInsideAListItemAndAQuoteUsesTheHeadingSpacing() {
        let theme = theme(body: 3, heading: 2)
        assertSpaced(style(of: "Item", in: compose("- # Item", theme)), 2)
        assertSpaced(style(of: "Quoted", in: compose("> # Quoted", theme)), 2)
    }

    func testTheLastLooseItemAndNestedLooseListGetTheExpectedSpacing() throws {
        let theme = theme(loose: 10)
        let composed = compose("- tight\n  - one\n\n  - two\n\nAfter", theme)
        XCTAssertEqual(spacing(of: "one", in: composed), 10)
        // The tight outer list ends, so its last paragraph takes the paragraph spacing.
        XCTAssertEqual(spacing(of: "two", in: composed), theme.paragraphSpacing)
        XCTAssertEqual(spacing(of: "tight", in: composed), theme.tightListSpacing)
        let loose = compose("- a\n\n- b\n\nAfter", theme)
        XCTAssertEqual(spacing(of: "b", in: loose), theme.paragraphSpacing)

        let scaled = theme.scaled(for: UITraitCollection(preferredContentSizeCategory: .large))
        let document = GlimmerStaticDocument(
            markdown: "- a\n\n- b\n\nAfter", configuration: configuration(theme), dynamicTypeSize: .large
        )
        XCTAssertEqual(document.blocks.map(\.spacingAbove), [0, scaled.paragraphSpacing])
        let nested = GlimmerStaticDocument(
            markdown: "- tight\n  - one\n\n  - two\n\nAfter", configuration: configuration(theme), dynamicTypeSize: .large
        )
        XCTAssertEqual(nested.blocks.map(\.spacingAbove), [0, scaled.paragraphSpacing])
        guard case .list(let outer) = try XCTUnwrap(nested.blocks.first).content,
              case .list(let inner) = try XCTUnwrap(outer.items.first?.blocks.last).content else {
            return XCTFail("not nested lists")
        }
        XCTAssertEqual(inner.items.map(\.spacingAbove), [0, scaled.looseListSpacing])
    }

    func testSpacingFieldsScaleWithDynamicType() {
        let large = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraLarge)
        let scaled = theme(body: 3, heading: 2, code: 2, loose: 10).scaled(for: large)
        XCTAssertGreaterThan(scaled.looseListSpacing ?? 0, 10)
        XCTAssertGreaterThan(scaled.lineSpacing ?? 0, 3)
        XCTAssertGreaterThan(scaled.headingLineSpacing ?? 0, 2)
        XCTAssertGreaterThan(scaled.codeLineSpacing ?? 0, 2)
        let unscaled = theme().scaled(for: large)
        XCTAssertNil(unscaled.looseListSpacing)
        XCTAssertNil(unscaled.lineSpacing)
        XCTAssertNil(unscaled.headingLineSpacing)
        XCTAssertNil(unscaled.codeLineSpacing)
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

    private func chipColors(_ glimmerExtension: any GlimmerExtension) throws -> (chip: UIColor?, prose: UIColor?, theme: GlimmerTheme) {
        var configuration = GlimmerConfiguration()
        configuration.extensions = [glimmerExtension]
        configuration.theme.linkColor = .systemRed
        configuration.theme.mentionColor = .systemGreen
        configuration.theme.textColor = .systemBlue
        let text = GlimmerView.attributedString(for: "see [3] now", configuration: configuration, traitCollection: .init())
        let chip = try XCTUnwrap(text.range(of: "[3]"))
        let prose = try XCTUnwrap(text.range(of: "see"))
        return (text[chip].uiKit.foregroundColor, text[prose].uiKit.foregroundColor, configuration.theme)
    }

    func testALinkedChipTakesTheLinkColour() throws {
        let colors = try chipColors(LinkedChip())
        XCTAssertEqual(colors.chip, .systemRed)
        XCTAssertEqual(colors.prose, .systemBlue)
    }

    func testTappableTextKeepsTheMentionColour() throws {
        XCTAssertEqual(try chipColors(TextToken()).chip, .systemGreen)
    }

    func testAChipWithoutAURLKeepsTheProseColour() throws {
        XCTAssertEqual(try chipColors(BareChip()).chip, .systemBlue)
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

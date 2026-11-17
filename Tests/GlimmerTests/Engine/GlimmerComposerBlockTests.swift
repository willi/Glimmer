import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerComposerBlockTests: XCTestCase {
    private let theme = GlimmerTheme.default

    func testParseWithLinesReportsStartLines() {
        let parsed = GlimmerParser.parseWithLines("# A\n\npara\n\n- x\n- y\n\n```\ncode\n```")
        XCTAssertEqual(parsed.map(\.startLine), [1, 3, 5, 8])
        XCTAssertEqual(parsed.map(\.block), GlimmerParser.parse("# A\n\npara\n\n- x\n- y\n\n```\ncode\n```"))
    }

    func testComposeIsBlocksJoinedWithoutTheFinalNewline() {
        let markdown = "# Title\n\nSome **bold** text.\n\n- one\n- two\n\n> quoted\n\n```swift\nlet x = 1\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |"
        let blocks = GlimmerParser.parse(markdown)
        let composer = GlimmerComposer(theme: theme)
        let joined = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            let fragment = composer.composeBlock(block, isFirst: index == 0)
            XCTAssertTrue(fragment.string.hasSuffix("\n"), "block \(index) must end in a newline")
            joined.append(fragment)
        }
        joined.deleteCharacters(in: NSRange(location: joined.length - 1, length: 1))
        assertEquivalent(composer.compose(blocks), joined, "compose vs joined blocks")
    }

    func testHeadingOpeningTheDocumentHasNoSpaceAbove() {
        let text = GlimmerComposer(theme: theme).compose(GlimmerParser.parse("# Title"))
        let style = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.paragraphSpacingBefore, 0)
    }

    /// The space between a block's last paragraph and a heading's first: the paragraph's space after plus the heading's
    /// space before, which TextKit adds together.
    private func gapAboveHeading(_ markdown: String, theme: GlimmerTheme) -> CGFloat? {
        let text = GlimmerComposer(theme: theme).compose(GlimmerParser.parse(markdown))
        let heading = (text.string as NSString).range(of: "Head")
        guard heading.location != NSNotFound, heading.location > 1 else { return nil }
        func style(at index: Int) -> NSParagraphStyle? { text.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle }
        guard let before = style(at: heading.location), let above = style(at: heading.location - 1) else { return nil }
        return above.paragraphSpacing + before.paragraphSpacingBefore
    }

    private func spacedTheme(paragraph: CGFloat, block: CGFloat) -> GlimmerTheme {
        var spaced = theme
        spaced.paragraphSpacing = paragraph
        spaced.blockSpacing = block
        return spaced
    }

    func testTheGapAboveAHeadingIsTheLargerSpacingNotTheSum() {
        XCTAssertEqual(gapAboveHeading("Para\n\n## Head", theme: spacedTheme(paragraph: 16, block: 16)), 16)
        XCTAssertEqual(gapAboveHeading("Para\n\n## Head", theme: spacedTheme(paragraph: 8, block: 16)), 16)
        XCTAssertEqual(gapAboveHeading("Para\n\n## Head", theme: spacedTheme(paragraph: 24, block: 16)), 24)
    }

    func testTheGapAboveAHeadingAfterEachKindOfBlockIsCollapsed() {
        let spaced = spacedTheme(paragraph: 8, block: 16)
        let blocks = ["```\ncode\n```", "---", "> quote", "- a\n- b", "1. a\n2. b", "## Other", "| a | b |\n|---|---|\n| 1 | 2 |"]
        for block in blocks {
            XCTAssertEqual(gapAboveHeading("\(block)\n\n## Head", theme: spaced), 16, block)
        }
    }

    func testAHeadingFirstHasNoSpaceAbove() {
        let text = GlimmerComposer(theme: theme).compose(GlimmerParser.parse("## Head\n\nPara"))
        let style = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.paragraphSpacingBefore, 0)
    }

    func testTheGapBelowAHeadingIsUnchanged() {
        let text = GlimmerComposer(theme: theme).compose(GlimmerParser.parse("## Head\n\nPara"))
        let style = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        // 2.2.0: the heading's space after is the default theme's paragraph spacing (12, captured before the change), and the paragraph below adds no space before.
        XCTAssertEqual(style?.paragraphSpacing, 12)
        let below = (text.string as NSString).range(of: "Para").location
        let belowStyle = text.attribute(.paragraphStyle, at: below, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(belowStyle?.paragraphSpacingBefore, 0)
    }

    func testNestedHeadingLaterInTheDocumentCollapsesIntoTheSpaceAbove() {
        XCTAssertEqual(gapAboveHeading("para\n\n> # Head", theme: spacedTheme(paragraph: 8, block: 16)), 16)
        XCTAssertEqual(gapAboveHeading("para\n\n> # Head", theme: spacedTheme(paragraph: 16, block: 16)), 16)
    }

    func testStreamingFragmentsGiveTheSameGapAsComposingTheWholeDocument() {
        let spaced = spacedTheme(paragraph: 8, block: 16)
        let document = GlimmerStreamingDocument(composer: GlimmerComposer(theme: spaced))
        _ = document.update(markdown: "Para", isStreaming: true)
        _ = document.update(markdown: "Para\n\n## Head", isStreaming: true)
        let whole = GlimmerComposer(theme: spaced).compose(GlimmerParser.parse("Para\n\n## Head"))
        assertEquivalent(document.text, whole, "streamed vs composed")
    }

    func testNumberedListKeepsItsIndentWhenItReachesTwoDigits() {
        let composer = GlimmerComposer(theme: theme)
        func headIndent(items: Int) -> CGFloat {
            let markdown = (1...items).map { "\($0). item" }.joined(separator: "\n")
            let style = composer.compose(GlimmerParser.parse(markdown)).attribute(.paragraphStyle, at: 0, effectiveRange: nil)
            return (style as? NSParagraphStyle)?.headIndent ?? -1
        }
        // Items 1–9 already streamed must not shift right when item 10 arrives.
        XCTAssertEqual(headIndent(items: 3), headIndent(items: 10))
        XCTAssertEqual(headIndent(items: 10), headIndent(items: 99))
    }

    func testNumbersEndTheSameGapBeforeTheText() throws {
        let text = GlimmerComposer(theme: theme).compose(GlimmerParser.parse((1...10).map { "\($0). item" }.joined(separator: "\n")))
        let string = text.string as NSString
        // Like a browser's list: "1." sits a small gap before its text, and "10." grows to the left, not into the gap.
        func markerEnd(_ number: Int) throws -> CGFloat {
            let location = string.range(of: "\(number).\t").location
            let style = try XCTUnwrap(text.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)
            let width = text.attributedSubstring(from: NSRange(location: location, length: "\(number).".count)).size().width
            return style.firstLineHeadIndent + width
        }
        let style = try XCTUnwrap(text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(try markerEnd(1), try markerEnd(10), accuracy: 0.5)
        XCTAssertEqual(style.headIndent - (try markerEnd(1)), ceil(theme.bodyFont.pointSize * 0.4), accuracy: 0.5)
    }
}

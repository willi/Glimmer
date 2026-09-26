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

    func testNestedHeadingLaterInTheDocumentGetsBlockSpace() {
        let text = GlimmerComposer(theme: theme).compose(GlimmerParser.parse("para\n\n> # Quoted heading"))
        let location = (text.string as NSString).range(of: "Quoted").location
        let style = text.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.paragraphSpacingBefore, theme.blockSpacing)
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
}

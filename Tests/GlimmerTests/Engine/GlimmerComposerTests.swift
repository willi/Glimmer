import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerComposerTests: XCTestCase {
    private let theme = GlimmerTheme.default

    private func compose(_ markdown: String) -> NSAttributedString {
        GlimmerComposer(theme: theme).compose(GlimmerParser.parse(markdown))
    }

    private func attributes(of substring: String, in text: NSAttributedString, file: StaticString = #filePath, line: UInt = #line) -> [NSAttributedString.Key: Any] {
        let range = (text.string as NSString).range(of: substring)
        guard range.location != NSNotFound else {
            XCTFail("missing \(substring.debugDescription) in \(text.string.debugDescription)", file: file, line: line)
            return [:]
        }
        return text.attributes(at: range.location, effectiveRange: nil)
    }

    private func style(of substring: String, in text: NSAttributedString) -> NSParagraphStyle? {
        attributes(of: substring, in: text)[.paragraphStyle] as? NSParagraphStyle
    }

    private func blockAttachment(in text: NSAttributedString) -> GlimmerBlockAttachment? {
        var found: GlimmerBlockAttachment?
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, stop in
            if let attachment = value as? GlimmerBlockAttachment { found = attachment; stop.pointee = true }
        }
        return found
    }

    func testParagraphTextAndBoldTrait() {
        let text = compose("Hello **bold** world")
        XCTAssertEqual(text.string, "Hello bold world")
        XCTAssertEqual(attributes(of: "Hello", in: text)[.font] as? UIFont, theme.bodyFont)
        let bold = attributes(of: "bold", in: text)[.font] as? UIFont
        XCTAssertTrue(bold?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
    }

    func testHeadingUsesHeadingFontAndLevel() {
        let text = compose("# Title\n\nBody")
        XCTAssertEqual(text.string, "Title\nBody")
        XCTAssertEqual(attributes(of: "Title", in: text)[.font] as? UIFont, theme.headingFont(level: 1))
        XCTAssertEqual(attributes(of: "Title", in: text)[.accessibilityTextHeadingLevel] as? Int, 1)
    }

    func testInlineCodeIsTaggedAndMonospaced() {
        let code = attributes(of: "let", in: compose("Use `let` here"))
        XCTAssertEqual(code[.glimmerInlineCode] as? Bool, true)
        let font = code[.font] as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) ?? false)
    }

    func testLinkCarriesURL() {
        let link = attributes(of: "site", in: compose("[site](https://example.com)"))
        XCTAssertEqual(link[.link] as? URL, URL(string: "https://example.com"))
    }

    func testBulletListMarkersAndHangingIndent() {
        let text = compose("- one\n- two")
        XCTAssertEqual(text.string, "•\tone\n•\ttwo")
        XCTAssertEqual(attributes(of: "•", in: text)[.glimmerListMarker] as? String, "- ")
        let first = style(of: "one", in: text)
        XCTAssertEqual(first?.headIndent, theme.listIndent)
        XCTAssertEqual(first?.firstLineHeadIndent, 0)
        XCTAssertEqual(first?.tabStops.first?.location, theme.listIndent)
        XCTAssertEqual(first?.paragraphSpacing, theme.tightListSpacing)
        XCTAssertEqual(style(of: "two", in: text)?.paragraphSpacing, theme.paragraphSpacing, "the last item of a tight list restores normal spacing")
    }

    func testOrderedListStartsAtGivenNumber() {
        let text = compose("3. three\n4. four")
        XCTAssertEqual(text.string, "3.\tthree\n4.\tfour")
        XCTAssertEqual(attributes(of: "3.", in: text)[.glimmerListMarker] as? String, "3. ")
    }

    func testNestedListIndentsTwice() {
        let text = compose("- outer\n  - inner")
        XCTAssertEqual(text.string, "•\touter\n◦\tinner")
        XCTAssertEqual(style(of: "inner", in: text)?.headIndent, theme.listIndent * 2)
    }

    func testWideListMarkerKeepsAGapBeforeTheText() {
        let text = compose("1000. item")
        let markerWidth = NSAttributedString(string: "1000.", attributes: [.font: theme.bodyFont]).size().width
        let paragraph = style(of: "item", in: text)
        XCTAssertGreaterThanOrEqual(paragraph?.headIndent ?? 0, markerWidth + 4, "the text never touches its marker")
        XCTAssertGreaterThanOrEqual(paragraph?.firstLineHeadIndent ?? -1, 0, "the marker stays inside the column")
        XCTAssertLessThanOrEqual((paragraph?.firstLineHeadIndent ?? 0) + markerWidth + 4, paragraph?.headIndent ?? 0, "and ends before the text")
        XCTAssertEqual(paragraph?.tabStops.first?.location, paragraph?.headIndent)
    }

    func testListAtAccessibilitySizeKeepsAGap() {
        let scaled = theme.scaled(for: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge))
        let text = GlimmerComposer(theme: scaled).compose(GlimmerParser.parse("1. item"))
        let markerWidth = NSAttributedString(string: "1.", attributes: [.font: scaled.bodyFont]).size().width
        let paragraph = style(of: "item", in: text)
        XCTAssertGreaterThanOrEqual(paragraph?.headIndent ?? 0, markerWidth + 4)
    }

    func testTaskListUsesCheckboxAndMarkdownSource() {
        let text = compose("- [x] done")
        XCTAssertNotNil(text.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
        XCTAssertEqual(text.attribute(.glimmerListMarker, at: 0, effectiveRange: nil) as? String, "- [x] ")
        XCTAssertTrue(text.string.hasSuffix("\tdone"))
    }

    func testBlockQuoteIndentsTagsDepthAndDims() {
        let text = compose("> quoted")
        let quoted = attributes(of: "quoted", in: text)
        XCTAssertEqual(quoted[.glimmerQuoteDepth] as? Int, 1)
        XCTAssertEqual(quoted[.foregroundColor] as? UIColor, theme.secondaryTextColor)
        XCTAssertEqual(style(of: "quoted", in: text)?.headIndent, theme.quoteIndent)
    }

    func testQuoteEndIsMarkedAndSpacedLikeABlock() {
        let text = compose("> one\n>\n> two\n\nafter")
        XCTAssertNil(attributes(of: "one", in: text)[.glimmerQuoteContinues], "a middle paragraph keeps its bar running")
        XCTAssertEqual(attributes(of: "two", in: text)[.glimmerQuoteContinues] as? Int, 0, "no quote level continues")
        XCTAssertEqual(style(of: "two", in: text)?.paragraphSpacing, theme.blockSpacing)
        XCTAssertEqual(style(of: "one", in: text)?.paragraphSpacing, theme.paragraphSpacing)
    }

    func testNestedQuoteEndKeepsOuterLevelRunning() {
        let text = compose("> > inner\n>\n> outer")
        XCTAssertEqual(attributes(of: "inner", in: text)[.glimmerQuoteContinues] as? Int, 1, "the outer quote continues past the inner one")
        XCTAssertEqual(style(of: "inner", in: text)?.paragraphSpacing, theme.paragraphSpacing)
        XCTAssertEqual(attributes(of: "outer", in: text)[.glimmerQuoteContinues] as? Int, 0)
    }

    func testQuotesEndingTogetherContinueNothing() {
        let text = compose("> > both end here\n\nafter")
        XCTAssertEqual(attributes(of: "both", in: text)[.glimmerQuoteContinues] as? Int, 0)
    }

    func testCodeBlockBecomesAttachmentWithSource() throws {
        let text = compose("```swift\nlet x = 1\n```")
        XCTAssertEqual(text.string, "\u{FFFC}")
        let attachment = try XCTUnwrap(blockAttachment(in: text))
        guard case .codeBlock(let language, let code) = attachment.embed else { return XCTFail("expected code") }
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(code, "let x = 1")
        XCTAssertEqual(text.attribute(.glimmerSource, at: 0, effectiveRange: nil) as? String, "```swift\nlet x = 1\n```")
        let paragraph = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(paragraph?.lineHeightMultiple, 1)
    }

    func testCodeShowingAFenceGetsALongerFence() {
        let text = compose("````\n```\nx\n```\n````")
        XCTAssertEqual(text.attribute(.glimmerSource, at: 0, effectiveRange: nil) as? String, "````\n```\nx\n```\n````")
    }

    func testTableBecomesAttachmentWithComposedCells() throws {
        let text = compose("| a | **b** |\n|---|---|\n| 1 | 2 |")
        let attachment = try XCTUnwrap(blockAttachment(in: text))
        guard case .table(let header, let rows, _) = attachment.embed else { return XCTFail("expected table") }
        XCTAssertEqual(header.map(\.string), ["a", "b"])
        XCTAssertEqual(rows.map { $0.map(\.string) }, [["1", "2"]])
        let boldHeader = header[1].attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertTrue(boldHeader?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
        XCTAssertEqual(text.attribute(.glimmerSource, at: 0, effectiveRange: nil) as? String, "| a | **b** |\n| --- | --- |\n| 1 | 2 |",
                       "cells copy with their styles")
    }

    func testStandaloneImageIsEmbedInlineImageIsAltText() throws {
        let standalone = compose("![Chart](https://example.com/c.png)")
        let attachment = try XCTUnwrap(blockAttachment(in: standalone))
        guard case .image(let source, let alt) = attachment.embed else { return XCTFail("expected image") }
        XCTAssertEqual(source, URL(string: "https://example.com/c.png"))
        XCTAssertEqual(alt, "Chart")

        let inline = compose("See ![icon](https://example.com/i.png) here")
        XCTAssertEqual(inline.string, "See icon here")
        XCTAssertEqual(attributes(of: "icon", in: inline)[.foregroundColor] as? UIColor, theme.secondaryTextColor)
    }

    func testThematicBreakIsEmbed() throws {
        let text = compose("above\n\n---\n\nbelow")
        XCTAssertEqual(text.string, "above\n\u{FFFC}\nbelow")
        let attachment = try XCTUnwrap(blockAttachment(in: text))
        guard case .thematicBreak = attachment.embed else { return XCTFail("expected rule") }
    }

    func testEmptyMarkdownComposesToEmptyString() {
        XCTAssertEqual(compose("").length, 0)
        XCTAssertEqual(compose("  \n\n ").length, 0)
    }

    func testEmojiAndRTLKeepAttributeRanges() {
        let text = compose("👋🏽 مرحبا **bold** ✓")
        XCTAssertEqual(text.string, "👋🏽 مرحبا bold ✓")
        let bold = attributes(of: "bold", in: text)[.font] as? UIFont
        XCTAssertTrue(bold?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
        let wave = attributes(of: "✓", in: text)[.font] as? UIFont
        XCTAssertFalse(wave?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? true)
    }

    func testQuoteListCodeNestingIndents() throws {
        let text = compose("> 1. step\n>    ```swift\n>    let x = 1\n>    ```")
        XCTAssertEqual(text.string, "1.\tstep\n\u{FFFC}")
        let embedStyle = text.attribute(.paragraphStyle, at: text.length - 1, effectiveRange: nil) as? NSParagraphStyle
        let itemStyle = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(embedStyle?.headIndent, itemStyle?.headIndent, "the code sits in the item's content column")
        XCTAssertGreaterThanOrEqual(itemStyle?.headIndent ?? 0, theme.quoteIndent + theme.listIndent)
        XCTAssertEqual(text.attribute(.glimmerQuoteDepth, at: text.length - 1, effectiveRange: nil) as? Int, 1)
    }

    func testSoftAndHardBreaks() {
        XCTAssertEqual(compose("a\nb").string, "a b")
        XCTAssertEqual(compose("a  \nb").string, "a\u{2028}b")
    }

    private func prefix(of substring: String, in text: NSAttributedString) -> String? {
        attributes(of: substring, in: text)[.glimmerMarkdownPrefix] as? String
    }

    func testParagraphsRecordTheirMarkdownPrefix() {
        let text = compose("> - outer\n>   - inner\n>\n>   more of outer")
        XCTAssertEqual(prefix(of: "outer", in: text), "> ", "a marker line inside a quote")
        XCTAssertEqual(prefix(of: "inner", in: text), ">   ", "nested under a two-character marker")
        XCTAssertEqual(prefix(of: "more of outer", in: text), ">   ", "a continuation paragraph of the outer item")
        XCTAssertEqual(prefix(of: "Plain", in: compose("Plain")), "")
    }

    func testOrderedMarkersIndentTheirContentByTheirWidth() {
        let text = compose("10. ten\n\n    ```\n    code\n    ```")
        let code = (text.string as NSString).range(of: "\u{FFFC}").location
        XCTAssertEqual(text.attribute(.glimmerMarkdownPrefix, at: code, effectiveRange: nil) as? String, "    ")
    }

    func testQuoteOpeningAListItemPutsItsMarkerAfterTheBullet() {
        let text = compose("- > quoted")
        XCTAssertEqual(prefix(of: "quoted", in: text), "")
        XCTAssertEqual(attributes(of: "•", in: text)[.glimmerListMarker] as? String, "- > ")
    }

    func testTightListParagraphsAreMarked() {
        XCTAssertEqual(attributes(of: "b", in: compose("- a\n- b"))[.glimmerTightList] as? Bool, true)
        XCTAssertNil(attributes(of: "b", in: compose("- a\n\n- b"))[.glimmerTightList])
        XCTAssertNil(attributes(of: "p", in: compose("p"))[.glimmerTightList])
    }

    func testStrongAndEmphasisAreMarkedButHeadingsAreNot() {
        let text = compose("# Head\n\n**b** and *i*")
        XCTAssertEqual(attributes(of: "b", in: text)[.glimmerStrong] as? Bool, true)
        XCTAssertEqual(attributes(of: "i", in: text)[.glimmerEmphasis] as? Bool, true)
        XCTAssertNil(attributes(of: "Head", in: text)[.glimmerStrong], "a heading's bold font is not strong text")
    }

    func testInlineImageKeepsItsMarkdown() {
        let text = compose("see ![alt](https://example.com/a.png) here")
        XCTAssertEqual(attributes(of: "alt", in: text)[.glimmerSource] as? String, "![alt](https://example.com/a.png)")
    }
}

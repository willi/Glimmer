import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerTextViewEditTests: XCTestCase {
    private let composer = GlimmerComposer(theme: .default)

    func testAppendingKeepsEarlierLayoutFragments() throws {
        let document = GlimmerStreamingDocument(composer: composer)
        let textView = GlimmerTextView()
        if let edit = document.update(markdown: "First paragraph.\n\nSecond", isStreaming: true) { textView.apply(edit) }
        let window = hostInWindow(textView, width: 390, height: 400)
        let before = layoutFragments(textView).map(ObjectIdentifier.init)
        let edit = try XCTUnwrap(document.update(markdown: "First paragraph.\n\nSecond paragraph grows.", isStreaming: true))
        textView.apply(edit)
        let after = layoutFragments(textView).map(ObjectIdentifier.init)
        XCTAssertEqual(textView.textStorage.string, document.text.string)
        XCTAssertEqual(before.first, after.first, "the untouched first paragraph keeps its layout fragment")
        _ = window
    }

    func testSegmentRectsCoverEveryLineOfAWrappedRange() {
        let textView = GlimmerTextView()
        textView.attributedText = composer.compose(GlimmerParser.parse(String(repeating: "wrapping words ", count: 20)))
        let window = hostInWindow(textView, width: 200, height: 600)
        let rects = textView.segmentRects(for: NSRange(location: 0, length: textView.textStorage.length))
        XCTAssertGreaterThan(rects.count, 1)
        XCTAssertEqual(rects.first?.minY ?? -1, 0, accuracy: 0.5)
        // Trailing spaces may hang a little past the edge; an unwrapped line would be hundreds of points wide.
        XCTAssertLessThanOrEqual(rects.map(\.maxX).max() ?? 0, 210)
        _ = window
    }

    func testLineRectCoversAWholeLineHeight() throws {
        let theme = GlimmerTheme.default
        let textView = GlimmerTextView()
        textView.attributedText = composer.compose(GlimmerParser.parse("Hello there"))
        let window = hostInWindow(textView, width: 390, height: 200)
        let rect = try XCTUnwrap(textView.lineRect(atCharacter: 0))
        XCTAssertGreaterThanOrEqual(rect.height, theme.bodyFont.lineHeight - 0.5)
        XCTAssertNil(textView.lineRect(atCharacter: textView.textStorage.length))
        _ = window
    }

    func testBlockAttachmentSegmentMatchesTheEmbed() throws {
        let textView = GlimmerTextView()
        textView.attributedText = composer.compose(GlimmerParser.parse("```\nx\ny\n```"))
        let height = textView.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height
        let window = hostInWindow(textView, width: 390, height: height)
        let code = try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: textView))
        let rect = try XCTUnwrap(textView.segmentRects(for: NSRange(location: 0, length: 1)).first)
        // The segment is the attachment's whole line box, which must contain the embed (the mask covers it).
        let embedFrame = code.convert(code.bounds, to: textView)
        XCTAssertLessThanOrEqual(rect.minY, embedFrame.minY + 0.5)
        XCTAssertGreaterThanOrEqual(rect.maxY, embedFrame.maxY - 0.5)
        _ = window
    }
}

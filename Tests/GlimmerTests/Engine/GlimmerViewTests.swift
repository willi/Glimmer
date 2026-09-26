import UIKit
import XCTest
@testable import Glimmer

private struct ShoutExtension: GlimmerExtension {
    func preprocess(_ markdown: String) -> String { markdown.replacingOccurrences(of: "!!", with: "**") }
}

@MainActor
final class GlimmerViewTests: XCTestCase {
    func testRendersMarkdownIntoTheTextView() {
        let view = GlimmerView()
        view.update(markdown: "# Hi\n\nThere")
        XCTAssertEqual(view.textView.attributedText.string, "Hi\nThere")
    }

    func testEmptyMarkdownHasZeroHeight() {
        let view = GlimmerView()
        view.update(markdown: "")
        XCTAssertEqual(view.sizeThatFits(CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)).height, 0)
        view.update(markdown: "   \n ")
        XCTAssertEqual(view.sizeThatFits(CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)).height, 0)
    }

    func testPreprocessRunsBeforeParsing() {
        let view = GlimmerView(configuration: GlimmerConfiguration(extensions: [ShoutExtension()]))
        view.update(markdown: "!!loud!!")
        let font = view.textView.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
        XCTAssertEqual(view.textView.attributedText.string, "loud")
    }

    func testLongURLStaysWithinWidth() throws {
        let view = GlimmerView()
        view.update(markdown: "https://example.com/" + String(repeating: "a", count: 300))
        let height = view.sizeThatFits(CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)).height
        XCTAssertGreaterThan(height, 0)
        let window = hostInWindow(view, width: 320, height: height)
        let manager = try XCTUnwrap(view.textView.textLayoutManager)
        manager.ensureLayout(for: manager.documentRange)
        XCTAssertLessThanOrEqual(manager.usageBoundsForTextContainer.width, 320.5)
        _ = window
    }

    func testDynamicTypeScalesFonts() {
        let view = GlimmerView()
        view.update(markdown: "Body")
        let window = hostInWindow(view, width: 320, height: 200)
        let before = (view.textView.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.pointSize ?? 0
        view.traitOverrides.preferredContentSizeCategory = .accessibilityExtraLarge
        settle(view)
        let after = (view.textView.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.pointSize ?? 0
        XCTAssertGreaterThan(after, before)
        _ = window
    }

    func testIntrinsicHeightTracksWidth() {
        let view = GlimmerView()
        view.update(markdown: String(repeating: "Some words that wrap. ", count: 20))
        let window = hostInWindow(view, width: 390, height: 100)
        let wide = view.intrinsicContentSize.height
        view.frame.size.width = 250
        settle(view)
        XCTAssertGreaterThan(view.intrinsicContentSize.height, wide)
        _ = window
    }

    func testLinkActionRequiresAHandler() throws {
        let view = GlimmerView()
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        XCTAssertNil(view.linkAction(for: url))
        view.onLinkTap = { _ in }
        XCTAssertNotNil(view.linkAction(for: url))
    }
}

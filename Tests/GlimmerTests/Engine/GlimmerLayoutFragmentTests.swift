import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerLayoutFragmentTests: XCTestCase {
    private let theme = GlimmerTheme.default

    private func hostedTextView(_ markdown: String) -> (GlimmerTextView, UIWindow) {
        let textView = GlimmerTextView()
        textView.apply(theme: theme)
        textView.attributedText = GlimmerComposer(theme: theme).compose(GlimmerParser.parse(markdown))
        let height = textView.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height
        return (textView, hostInWindow(textView, width: 390, height: height))
    }

    func testEveryFragmentIsAGlimmerFragment() {
        let (textView, window) = hostedTextView("One\n\nTwo\n\n> Three")
        let fragments = layoutFragments(textView)
        XCTAssertFalse(fragments.isEmpty)
        XCTAssertTrue(fragments.allSatisfy { $0 is GlimmerLayoutFragment })
        _ = window
    }

    func testInlineCodeProducesOnePillAfterLeadingText() throws {
        let (textView, window) = hostedTextView("Use `let` here")
        let fragment = try XCTUnwrap(layoutFragments(textView).first as? GlimmerLayoutFragment)
        let pills = fragment.inlineCodePillRects()
        XCTAssertEqual(pills.count, 1)
        let pill = try XCTUnwrap(pills.first)
        XCTAssertGreaterThan(pill.minX, 10, "the pill starts after \"Use \"")
        XCTAssertGreaterThan(pill.width, 10)
        XCTAssertLessThan(pill.maxX, 390)
        _ = window
    }

    func testNestedQuoteDrawsOneBarPerLevel() throws {
        let (textView, window) = hostedTextView("> > deep")
        let fragment = try XCTUnwrap(layoutFragments(textView).first as? GlimmerLayoutFragment)
        let bars = fragment.quoteBarRects()
        XCTAssertEqual(bars.count, 2)
        // An indented paragraph's fragment frame starts at its indent, so bars sit at negative fragment x.
        let containerX = bars.map { $0.minX + fragment.layoutFragmentFrame.minX }
        XCTAssertEqual(containerX[0], 0, accuracy: 0.5, "the outer bar sits at the container's leading edge")
        XCTAssertEqual(containerX[1], theme.quoteIndent, accuracy: 0.5)
        XCTAssertLessThan(bars[1].maxX, 0, "bars stay left of the quoted text")
        XCTAssertTrue(fragment.renderingSurfaceBounds.contains(bars[0]), "the surface must cover the bars or they are clipped")
        XCTAssertEqual(bars[0].height, fragment.layoutFragmentFrame.height, accuracy: 0.5)
        _ = window
    }

    func testPlainParagraphHasNoDecorations() throws {
        let (textView, window) = hostedTextView("Nothing special")
        let fragment = try XCTUnwrap(layoutFragments(textView).first as? GlimmerLayoutFragment)
        XCTAssertEqual(fragment.inlineCodePillRects(), [])
        XCTAssertEqual(fragment.quoteBarRects(), [])
        _ = window
    }
}

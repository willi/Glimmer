import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerVisibleBandTests: XCTestCase {
    private let long = Array(repeating: StreamingFixtures.all.map(\.markdown).joined(separator: "\n\n"), count: 29)
        .joined(separator: "\n\n")

    /// A long settled answer in a scroll view 800 pt tall, scrolled to the top.
    private func scrolled(in outer: UIScrollView? = nil) -> (GlimmerView, UIScrollView, UIWindow) {
        let scrollView = UIScrollView()
        let window: UIWindow
        if let outer {
            window = hostInWindow(outer, width: 390, height: 800)
            scrollView.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
            outer.addSubview(scrollView)
        } else {
            window = hostInWindow(scrollView, width: 390, height: 800)
        }
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        view.update(markdown: long)
        let height = view.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height
        view.frame = CGRect(x: 0, y: 0, width: 390, height: height)
        scrollView.addSubview(view)
        scrollView.contentSize = view.frame.size
        settle(scrollView)
        return (view, scrollView, window)
    }

    private func character(atY y: CGFloat, in textView: UITextView) -> Int {
        guard let manager = textView.textLayoutManager, let content = manager.textContentManager,
              let fragment = manager.textLayoutFragment(for: CGPoint(x: 10, y: y)) else { return -1 }
        return content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
    }

    func testRendersOnlyTheTextNearTheScreen() throws {
        let (view, _, window) = scrolled()
        XCTAssertLessThan(renderedViewCount(view.textView), 300, "a 5,000-word answer rendered every paragraph")
        let range = try XCTUnwrap(viewportRange(view.textView))
        XCTAssertLessThan(NSMaxRange(range), view.textView.textStorage.length / 4)
        XCTAssertTrue(inked(view.textView, in: CGRect(x: 0, y: 100, width: 390, height: 500)))
        _ = window
    }

    func testScrollingMovesTheRenderedBand() throws {
        let (view, scrollView, window) = scrolled()
        let middle = (view.bounds.height / 2).rounded()
        scrollView.contentOffset = CGPoint(x: 0, y: middle)
        settle(scrollView)
        let range = try XCTUnwrap(viewportRange(view.textView))
        XCTAssertTrue(NSLocationInRange(character(atY: middle + 400, in: view.textView), range))
        XCTAssertTrue(inked(view.textView, in: CGRect(x: 0, y: middle + 100, width: 390, height: 600)))
        _ = window
    }

    func testScrollingAnOuterScrollViewMovesTheBand() throws {
        let outer = UIScrollView()
        let (view, inner, window) = scrolled(in: outer)
        // The inner scroll view is as tall as the answer; only the outer one scrolls.
        inner.frame.size.height = view.bounds.height
        outer.contentSize = inner.frame.size
        let middle = (view.bounds.height / 2).rounded()
        outer.contentOffset = CGPoint(x: 0, y: middle)
        settle(outer)
        let range = try XCTUnwrap(viewportRange(view.textView))
        XCTAssertTrue(NSLocationInRange(character(atY: middle + 400, in: view.textView), range))
        _ = window
    }

    func testLayoutPassRefreshesTheBandAfterTheHostMovesTheView() throws {
        let container = UIView()
        let window = hostInWindow(container, width: 390, height: 800)
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        view.update(markdown: long)
        let height = view.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height
        view.frame = CGRect(x: 0, y: 0, width: 390, height: height)
        container.addSubview(view)
        settle(container)
        // Content inserted above pushes the answer up by half its height, with no scroll view involved.
        let middle = (height / 2).rounded()
        view.frame.origin.y = -middle
        view.setNeedsLayout()
        settle(container)
        let range = try XCTUnwrap(viewportRange(view.textView))
        XCTAssertTrue(NSLocationInRange(character(atY: middle + 400, in: view.textView), range))
        _ = window
    }

    func testSelectionStillSpansTheWholeAnswer() throws {
        let (view, _, window) = scrolled()
        let textView = view.textView
        textView.selectedRange = NSRange(location: 10, length: textView.textStorage.length - 20)
        let rects = textView.selectionRects(for: try XCTUnwrap(textView.selectedTextRange))
        XCTAssertGreaterThan(rects.last?.rect.maxY ?? 0, view.bounds.height - 200)
        _ = window
    }
}

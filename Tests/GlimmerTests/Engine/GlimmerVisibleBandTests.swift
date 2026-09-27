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

    /// A code block taller than the screen: its own text view renders the lines on screen, at first and after a scroll.
    func testATallCodeBlockRendersTheLinesOnScreen() throws {
        let code = (1...200).map { "let line\($0) = \($0)" }.joined(separator: "\n")
        let scrollView = UIScrollView()
        let window = hostInWindow(scrollView, width: 390, height: 800)
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil, reveal: .none))
        view.update(markdown: "Intro.\n\n```swift\n\(code)\n```\n\nOutro.")
        let height = view.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height
        view.frame = CGRect(x: 0, y: 0, width: 390, height: height)
        scrollView.addSubview(view)
        scrollView.contentSize = view.frame.size
        settle(scrollView)
        let block = try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: view))
        func assertLinesOnScreenRendered(_ moment: String) throws {
            let textView = block.textView
            let onScreen = textView.convert(window.bounds, from: window).intersection(textView.bounds)
            let viewport = try XCTUnwrap(textView.textLayoutManager?.textViewportLayoutController.viewportBounds)
            XCTAssertLessThanOrEqual(viewport.minY, onScreen.minY + 1, "\(moment): viewport \(viewport), screen \(onScreen)")
            XCTAssertGreaterThanOrEqual(viewport.maxY, onScreen.maxY - 1, "\(moment): viewport \(viewport), screen \(onScreen)")
        }
        try assertLinesOnScreenRendered("at the top")
        scrollView.contentOffset.y = 2_000
        settle(scrollView)
        try assertLinesOnScreenRendered("scrolled 2,000 pt")
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

    func testMovingTheViewRefreshesTheBandWithoutALayoutPass() throws {
        let container = UIView()
        let window = hostInWindow(container, width: 390, height: 800)
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        view.update(markdown: long)
        let height = view.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height
        view.frame = CGRect(x: 0, y: 0, width: 390, height: height)
        container.addSubview(view)
        settle(container)
        // Only the origin moves, so UIKit gives the view no layout pass.
        let middle = (height / 2).rounded()
        view.frame.origin.y = -middle
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
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

    func testMovingTheViewInsideAnAnimationDoesNotAnimateTheText() throws {
        let container = UIView()
        let window = hostInWindow(container, width: 390, height: 800)
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        view.update(markdown: long)
        let height = view.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height
        view.frame = CGRect(x: 0, y: 0, width: 390, height: height)
        container.addSubview(view)
        settle(container)
        UIView.animate(withDuration: 1) { view.frame.origin.y = -(height / 2).rounded() }
        func animated(_ root: UIView) -> Bool {
            (root.layer.animationKeys()?.isEmpty == false) || root.subviews.contains(where: animated)
        }
        XCTAssertFalse(view.textView.subviews.contains(where: animated), "fragment views appear in place")
        _ = window
    }

    func testABandMoveRunsOnePass() throws {
        let (view, scrollView, window) = scrolled()
        CATransaction.flush()
        let before = view.textView.viewportPasses
        let band = try XCTUnwrap(view.textView.renderedBand)
        scrollView.contentOffset = CGPoint(x: 0, y: 800 * 0.3)
        view.textView.refreshVisibleBandIfNeeded()
        view.layoutIfNeeded()
        view.textView.layoutIfNeeded()
        CATransaction.flush()
        XCTAssertEqual(view.textView.viewportPasses - before, 1, "one viewport pass per band move")
        XCTAssertNotEqual(view.textView.renderedBand, band)
        _ = window
    }

    func testIdleFramesPreloadAheadOfTheBand() throws {
        let (view, _, window) = scrolled()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let band = try XCTUnwrap(view.textView.renderedBand)
        let preloaded = try XCTUnwrap(view.textView.preloadedRange, "idle frames laid out ahead")
        XCTAssertGreaterThanOrEqual(preloaded.upperBound, min(band.maxY + 800 * 1.5, view.textView.contentHeight) - 1)
        XCTAssertLessThanOrEqual(preloaded.lowerBound, band.minY)
        _ = window
    }

    func testAPreloadStepStaysWithinItsBudget() {
        let (view, _, window) = scrolled()
        view.textView.layoutIfNeeded()
        let start = threadCPUTime()
        view.textView.preloadStep()
        XCTAssertLessThan(threadCPUTime() - start, .milliseconds(4), "one idle frame's preload")
        _ = window
    }

    func testAFlingPastThePreloadStillRendersTheScreen() throws {
        let (view, scrollView, window) = scrolled()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        scrollView.contentOffset = CGPoint(x: 0, y: 800 * 6)
        view.textView.refreshVisibleBandIfNeeded()
        view.textView.layoutIfNeeded()
        let band = try XCTUnwrap(view.textView.renderedBand)
        XCTAssertTrue(band.contains(CGRect(x: 0, y: 800 * 6, width: 390, height: 800).intersection(view.textView.bounds)))
        _ = window
    }

    func testTheBandRefreshesAfterAQuarterScreen() throws {
        let (view, scrollView, window) = scrolled()
        let before = try XCTUnwrap(view.textView.renderedBand)
        scrollView.contentOffset = CGPoint(x: 0, y: 800 * 0.3)
        view.textView.refreshVisibleBandIfNeeded()
        // The pass runs in the next layout: the frame's commit.
        view.textView.layoutIfNeeded()
        let after = try XCTUnwrap(view.textView.renderedBand)
        XCTAssertNotEqual(after, before, "0.3 screens of travel re-renders")
        _ = window
    }

    func testAConfigureRendersTheScreenFirstAndTheBandNextFrame() throws {
        let scrollView = UIScrollView()
        let window = hostInWindow(scrollView, width: 390, height: 800)
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 100_000)
        scrollView.addSubview(view)
        scrollView.contentSize = view.frame.size
        view.update(markdown: long)
        view.layoutIfNeeded()
        view.textView.layoutIfNeeded()
        let first = try XCTUnwrap(view.textView.renderedBand)
        XCTAssertLessThanOrEqual(first.height, 801, "the first frame renders the screen")
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let full = try XCTUnwrap(view.textView.renderedBand)
        XCTAssertGreaterThan(full.height, 1_500, "the band follows")
        _ = window
    }

    func testConfiguringAViewStillSizedToALongAnswerCostsNoMoreThanAScreenTallOne() {
        // A reused cell or a SwiftUI update: the view is still as tall as the answer it showed before. Its cached
        // configure must lay out the screen, not everything inside its old height.
        let earlier = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        earlier.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        earlier.update(markdown: long)
        func configure(inHeight height: CGFloat) -> Duration {
            let scrollView = UIScrollView()
            let window = hostInWindow(scrollView, width: 390, height: 800)
            let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
            view.frame = CGRect(x: 0, y: 0, width: 390, height: height)
            scrollView.addSubview(view)
            scrollView.contentSize = view.frame.size
            view.layoutIfNeeded()
            let start = threadCPUTime()
            view.update(markdown: long)
            view.layoutIfNeeded()
            view.textView.layoutIfNeeded()
            let cost = threadCPUTime() - start
            _ = window
            return cost
        }
        var tall: [Duration] = []
        var screen: [Duration] = []
        for _ in 0..<5 {
            tall.append(configure(inHeight: 100_000))
            screen.append(configure(inHeight: 800))
        }
        let tallMedian = tall.sorted()[2]
        let screenMedian = screen.sorted()[2]
        print("PERF cached configure: view 100,000 pt tall \(tallMedian), 800 pt \(screenMedian)")
        XCTAssertLessThan(tallMedian, screenMedian * 1.5)
    }

    func testScrollingBeforeTheBandWidensStillRendersTheScreen() throws {
        let scrollView = UIScrollView()
        let window = hostInWindow(scrollView, width: 390, height: 800)
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 100_000)
        scrollView.addSubview(view)
        scrollView.contentSize = view.frame.size
        view.update(markdown: long)
        view.layoutIfNeeded()
        view.textView.layoutIfNeeded()
        // The reader flings before the band has widened.
        scrollView.contentOffset = CGPoint(x: 0, y: 600)
        view.textView.refreshVisibleBandIfNeeded()
        view.textView.layoutIfNeeded()
        let band = try XCTUnwrap(view.textView.renderedBand)
        XCTAssertTrue(band.contains(CGRect(x: 0, y: 600, width: 390, height: 800).intersection(view.textView.bounds)))
        _ = window
    }
}

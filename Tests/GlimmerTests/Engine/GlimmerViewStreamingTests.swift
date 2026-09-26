import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerViewStreamingTests: XCTestCase {
    private let answer = "First sentence of the answer arrives now. Then a second sentence follows it closely, and a third one wraps onto more lines of the view."

    private func streamingView(width: CGFloat = 320) -> (GlimmerView, ManualRevealClock, UIWindow) {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let clock = ManualRevealClock()
        view.clock = clock
        let window = hostInWindow(view, width: width, height: 800)
        return (view, clock, window)
    }

    private func fullHeight(_ view: GlimmerView) -> CGFloat {
        view.textView.sizeThatFits(CGSize(width: view.bounds.width, height: CGFloat.greatestFiniteMagnitude)).height
    }

    func testStreamingStartsMaskedAndRevealsFromTheFirstPhrase() throws {
        let (view, _, window) = streamingView()
        view.update(markdown: answer, isStreaming: true)
        XCTAssertNotNil(view.textView.layer.mask)
        let engine = try XCTUnwrap(view.engine)
        XCTAssertGreaterThan(engine.revealedLength, 0)
        XCTAssertLessThan(engine.revealedLength, view.textView.textStorage.length)
        XCTAssertLessThan(view.intrinsicContentSize.height, fullHeight(view), "height ends at the last revealed line")
        _ = window
    }

    func testStaticUpdateShowsEverythingWithoutAMask() {
        let (view, _, window) = streamingView()
        view.update(markdown: answer)
        XCTAssertNil(view.textView.layer.mask)
        XCTAssertNil(view.engine)
        XCTAssertEqual(view.intrinsicContentSize.height, fullHeight(view), accuracy: 0.5)
        _ = window
    }

    func testRevealCompletesAndRemovesTheMask() {
        let (view, clock, window) = streamingView()
        view.update(markdown: answer, isStreaming: true)
        view.update(markdown: answer, isStreaming: false)
        clock.advance(to: 10)
        XCTAssertNil(view.engine)
        XCTAssertNil(view.textView.layer.mask)
        XCTAssertEqual(view.intrinsicContentSize.height, fullHeight(view), accuracy: 0.5)
        _ = window
    }

    func testHeightGrowsWithRevealedLinesAndNeverShrinks() {
        let (view, clock, window) = streamingView(width: 240)
        var reported: [CGFloat] = []
        view.onHeightChange = { reported.append(view.intrinsicContentSize.height) }
        view.update(markdown: answer, isStreaming: true)
        var time = 0.0
        while view.engine != nil, time < 10 {
            time += 0.05
            if time > 1 { view.update(markdown: answer, isStreaming: false) }
            clock.advance(to: time)
        }
        XCTAssertGreaterThan(reported.count, 2, "the height grows line by line")
        XCTAssertEqual(reported, reported.sorted(), "the height never shrinks while revealing")
        _ = window
    }

    func testNoRevealShowsTextImmediately() {
        var configuration = GlimmerConfiguration(imageLoader: nil)
        configuration.reveal = .none
        let view = GlimmerView(configuration: configuration)
        let window = hostInWindow(view, width: 320, height: 800)
        view.update(markdown: answer, isStreaming: true)
        XCTAssertNil(view.textView.layer.mask)
        XCTAssertNil(view.engine)
        _ = window
    }

    func testRevealIDResumesWithoutReplaying() throws {
        let store = GlimmerRevealStore.shared
        store.clear("resume-test")
        let (first, clock, window) = streamingView()
        first.update(markdown: answer, isStreaming: true, revealID: "resume-test")
        first.update(markdown: answer, isStreaming: false, revealID: "resume-test")
        clock.advance(to: 10)
        XCTAssertEqual(store.revealedLength(for: "resume-test"), first.textView.textStorage.length)

        let (second, _, secondWindow) = streamingView()
        second.update(markdown: answer, isStreaming: true, revealID: "resume-test")
        let engine = try XCTUnwrap(second.engine)
        XCTAssertEqual(engine.revealedLength, second.textView.textStorage.length)
        XCTAssertEqual(second.revealMask.phraseLayerCount, 0, "nothing fades in again")
        _ = window
        _ = secondWindow
    }

    func testReplacedStreamKeepsRevealing() throws {
        let (view, clock, window) = streamingView()
        view.update(markdown: answer, isStreaming: true)
        clock.advance(to: 0.5)
        view.update(markdown: "A completely different regenerated answer with new words in it.", isStreaming: true)
        let engine = try XCTUnwrap(view.engine)
        XCTAssertLessThanOrEqual(engine.revealedLength, view.textView.textStorage.length)
        view.update(markdown: "A completely different regenerated answer with new words in it.", isStreaming: false)
        clock.advance(to: 10)
        XCTAssertNil(view.engine)
        _ = window
    }

    func testEmptyStreamingUpdateStaysEmpty() {
        let (view, clock, window) = streamingView()
        view.update(markdown: "", isStreaming: true)
        view.update(markdown: "   ", isStreaming: true)
        clock.advance(to: 1)
        XCTAssertEqual(view.intrinsicContentSize.height, 0)
        XCTAssertEqual(view.engine?.phrases.count ?? 0, 0)
        _ = window
    }

    func testStoreIsMonotonicAndBounded() {
        let store = GlimmerRevealStore(capacity: 2)
        store.record(10, for: "a")
        store.record(5, for: "a")
        XCTAssertEqual(store.revealedLength(for: "a"), 10)
        store.record(1, for: "b")
        store.record(1, for: "c")
        XCTAssertNil(store.revealedLength(for: "a"), "least recently used is evicted")
    }
}

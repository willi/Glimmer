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

    func testStreamingStartsMaskedAndRevealsFromTheFirstPhrase() async throws {
        let (view, _, window) = streamingView()
        view.update(markdown: answer, isStreaming: true)
        await view.pendingDocument?.value
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

    func testRevealCompletesAndRemovesTheMask() async {
        let (view, clock, window) = streamingView()
        view.update(markdown: answer, isStreaming: true)
        await view.pendingDocument?.value
        view.update(markdown: answer, isStreaming: false)
        await view.pendingDocument?.value
        clock.advance(to: 10)
        XCTAssertNil(view.engine)
        XCTAssertNil(view.textView.layer.mask)
        XCTAssertEqual(view.intrinsicContentSize.height, fullHeight(view), accuracy: 0.5)
        _ = window
    }

    func testHeightGrowsWithRevealedLinesAndNeverShrinks() async {
        let (view, clock, window) = streamingView(width: 240)
        var reported: [CGFloat] = []
        view.onHeightChange = { reported.append(view.intrinsicContentSize.height) }
        view.update(markdown: answer, isStreaming: true)
        await view.pendingDocument?.value
        var time = 0.0
        while view.engine != nil, time < 10 {
            time += 0.05
            if time > 1 {
                view.update(markdown: answer, isStreaming: false)
                await view.pendingDocument?.value
            }
            clock.advance(to: time)
        }
        XCTAssertGreaterThan(reported.count, 2, "the height grows line by line")
        XCTAssertEqual(reported, reported.sorted(), "the height never shrinks while revealing")
        _ = window
    }

    func testNoRevealShowsTextImmediately() async {
        var configuration = GlimmerConfiguration(imageLoader: nil)
        configuration.reveal = .none
        let view = GlimmerView(configuration: configuration)
        let window = hostInWindow(view, width: 320, height: 800)
        view.update(markdown: answer, isStreaming: true)
        await view.pendingDocument?.value
        XCTAssertNil(view.textView.layer.mask)
        XCTAssertNil(view.engine)
        _ = window
    }

    func testRevealIDResumesWithoutReplaying() async throws {
        let store = GlimmerRevealStore.shared
        store.clear("resume-test")
        let (first, clock, window) = streamingView()
        first.update(markdown: answer, isStreaming: true, revealID: "resume-test")
        await first.pendingDocument?.value
        first.update(markdown: answer, isStreaming: false, revealID: "resume-test")
        await first.pendingDocument?.value
        clock.advance(to: 10)
        XCTAssertEqual(store.revealedLength(for: "resume-test", text: first.textView.textStorage.string as NSString), first.textView.textStorage.length)

        let (second, _, secondWindow) = streamingView()
        second.update(markdown: answer, isStreaming: true, revealID: "resume-test")
        await second.pendingDocument?.value
        let engine = try XCTUnwrap(second.engine)
        XCTAssertEqual(engine.revealedLength, second.textView.textStorage.length)
        XCTAssertEqual(second.revealMask.phraseLayerCount, 0, "nothing fades in again")
        _ = window
        _ = secondWindow
    }

    func testReplacedStreamKeepsRevealing() async throws {
        let (view, clock, window) = streamingView()
        view.update(markdown: answer, isStreaming: true)
        await view.pendingDocument?.value
        clock.advance(to: 0.5)
        view.update(markdown: "A completely different regenerated answer with new words in it.", isStreaming: true)
        await view.pendingDocument?.value
        let engine = try XCTUnwrap(view.engine)
        XCTAssertLessThanOrEqual(engine.revealedLength, view.textView.textStorage.length)
        view.update(markdown: "A completely different regenerated answer with new words in it.", isStreaming: false)
        await view.pendingDocument?.value
        clock.advance(to: 10)
        XCTAssertNil(view.engine)
        _ = window
    }

    func testEmptyStreamingUpdateStaysEmpty() async {
        let (view, clock, window) = streamingView()
        view.update(markdown: "", isStreaming: true)
        await view.pendingDocument?.value
        view.update(markdown: "   ", isStreaming: true)
        await view.pendingDocument?.value
        clock.advance(to: 1)
        XCTAssertEqual(view.intrinsicContentSize.height, 0)
        XCTAssertEqual(view.engine?.phrases.count ?? 0, 0)
        _ = window
    }

    func testWidthQueriedDuringARevealEndsWithTheNewWidthsHeight() async {
        let (view, clock, window) = streamingView(width: 390)
        let prose = String(repeating: "Prose that wraps across several lines of the view. ", count: 12)
        view.update(markdown: prose, isStreaming: true)
        await view.pendingDocument?.value
        clock.advance(to: 0.3)
        XCTAssertNotNil(view.engine, "a reveal is under way")
        // A host sizes its cell at a new width (rotation) before the frame follows.
        _ = view.sizeThatFits(CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude))
        view.frame.size.width = 320
        settle(view)
        view.update(markdown: prose, isStreaming: false)
        await view.pendingDocument?.value
        clock.advance(to: 30)
        XCTAssertNil(view.engine)
        let settled = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let settledWindow = hostInWindow(settled, width: 320, height: 800)
        settled.update(markdown: prose)
        XCTAssertEqual(view.intrinsicContentSize.height, settled.intrinsicContentSize.height, accuracy: 0.5)
        _ = (window, settledWindow)
    }

    func testReflowingRevealedTextMovesItsFadingPhrases() async throws {
        let (view, clock, window) = streamingView()
        let tight = "- alpha beta gamma\n- delta epsilon zeta"
        view.update(markdown: tight, isStreaming: true)
        await view.pendingDocument?.value
        let delta = (view.textView.textStorage.string as NSString).range(of: "delta").location
        var time = 0.0
        while let engine = view.engine, !engine.phrases.contains(where: { NSMaxRange($0.range) > delta }), time < 5 {
            time += 0.02
            clock.advance(to: time)
        }
        // A third item after a blank line makes the list loose: the revealed second item moves down.
        view.update(markdown: tight + "\n\n- eta", isStreaming: true)
        await view.pendingDocument?.value
        let engine = try XCTUnwrap(view.engine)
        let moved = try XCTUnwrap(engine.phrases.last { NSMaxRange($0.range) > delta })
        let covered = try XCTUnwrap(view.revealMask.phraseLayer(startingAt: moved.range.location)?.path?.boundingBox)
        for rect in view.textView.segmentRects(for: moved.range) {
            XCTAssertTrue(covered.insetBy(dx: -0.5, dy: -0.5).contains(rect), "the fading phrase follows its glyphs: \(covered) vs \(rect)")
        }
        _ = window
    }

    func testReleasedSystemClockNeverFires() async {
        var fired = false
        var clock: GlimmerSystemRevealClock? = GlimmerSystemRevealClock()
        clock?.wake(at: CACurrentMediaTime() + 0.05) { fired = true }
        clock = nil
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(fired)
    }
}

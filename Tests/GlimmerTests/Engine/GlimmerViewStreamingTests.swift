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

    func testTheHeightHoldsMidRevealWhenRevealedTextShrinks() async {
        let (view, clock, window) = streamingView(width: 240)
        view.update(markdown: answer, isStreaming: true)
        await view.pendingDocument?.value
        var time = 0.0
        while view.intrinsicContentSize.height < 60, time < 10 {
            time += 0.05
            clock.advance(to: time)
        }
        let revealed = view.intrinsicContentSize.height
        XCTAssertGreaterThanOrEqual(revealed, 60, "a few lines are revealed")
        view.update(markdown: "Short.", isStreaming: true)
        await view.pendingDocument?.value
        XCTAssertTrue(view.isRevealing)
        XCTAssertGreaterThanOrEqual(view.intrinsicContentSize.height, revealed, "the height holds while the reveal runs")
        XCTAssertGreaterThanOrEqual(view.sizeThatFits(CGSize(width: 240, height: 1000)).height, revealed)
        view.update(markdown: "Short.", isStreaming: false)
        await view.pendingDocument?.value
        while view.isRevealing, time < 20 {
            time += 0.05
            clock.advance(to: time)
        }
        XCTAssertFalse(view.isRevealing)
        XCTAssertEqual(view.intrinsicContentSize.height, fullHeight(view), accuracy: 0.5, "the true height once it ends")
        XCTAssertLessThan(view.intrinsicContentSize.height, revealed)
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
        XCTAssertEqual(view.plainText(), answer)
        XCTAssertGreaterThan(view.intrinsicContentSize.height, 0)
        XCTAssertEqual(view.intrinsicContentSize.height, fullHeight(view), accuracy: 0.5)
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

    func testRestylingMidRevealKeepsRevealing() async throws {
        let (view, clock, window) = streamingView()
        view.update(markdown: answer, isStreaming: true)
        await view.pendingDocument?.value
        clock.advance(to: 0.5)
        let revealed = try XCTUnwrap(view.engine).revealedLength
        XCTAssertGreaterThan(revealed, 0)
        // A configuration change (like a Dynamic Type change) composes the whole answer again.
        var configuration = view.configuration
        configuration.theme.paragraphSpacing += 2
        view.configuration = configuration
        let engine = try XCTUnwrap(view.engine, "still revealing")
        XCTAssertGreaterThanOrEqual(engine.revealedLength, revealed, "no replay from the start")
        XCTAssertEqual(view.textView.textStorage.string, GlimmerComposer(theme: configuration.theme)
            .compose(GlimmerParser.parse(answer)).string)
        _ = window
    }

    func testHiddenLookaheadChunksKeepRevealedHeightAndSuppressHostRelayout() async throws {
        final class CountingHost: UIView {
            var passes = 0
            override func layoutSubviews() {
                passes += 1
                super.layoutSubviews()
            }
        }
        let host = CountingHost(frame: CGRect(x: 0, y: 0, width: 240, height: 800))
        let window = hostInWindow(host, width: 240, height: 800)
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let clock = ManualRevealClock()
        view.clock = clock
        view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            view.topAnchor.constraint(equalTo: host.topAnchor),
        ])
        var heightChanges = 0
        view.onHeightChange = { heightChanges += 1 }

        let opening = "First phrase here. Second phrase"
        view.update(markdown: opening, isStreaming: true)
        await view.pendingDocument?.value
        host.layoutIfNeeded()
        let initialRevealed = try XCTUnwrap(view.engine).revealedLength
        let initialHeight = view.intrinsicContentSize.height
        XCTAssertGreaterThan(initialRevealed, 0)
        XCTAssertGreaterThan(initialHeight, 0)
        XCTAssertEqual(heightChanges, 2, "the first height, then the settle report")

        heightChanges = 0
        host.passes = 0

        // Appending lookahead text to the same paragraph and following paragraphs while the reveal has not advanced
        // must keep the cached revealed height and never report a height change or trigger host Auto Layout passes.
        let chunk2 = opening + " continues with many more unrevealed words that wrap across a second and third line of the paragraph."
        view.update(markdown: chunk2, isStreaming: true)
        await view.pendingDocument?.value
        host.layoutIfNeeded()
        XCTAssertNotNil(view.revealedHeight, "unrevealed lookahead inside the same paragraph keeps the cached revealed height")
        XCTAssertEqual(view.engine?.revealedLength, initialRevealed)
        XCTAssertEqual(view.intrinsicContentSize.height, initialHeight)
        XCTAssertGreaterThan(view.textView.contentHeight, initialHeight * 2)
        XCTAssertEqual(heightChanges, 1, "hidden lookahead reports only that the update settled")
        XCTAssertEqual(host.passes, 0, "hidden lookahead must not invalidate intrinsic content size")

        let chunk3 = chunk2 + "\n\nAnother hidden paragraph arrives in the same frame.\n\nAnd a third hidden paragraph below that."
        view.update(markdown: chunk3, isStreaming: true)
        await view.pendingDocument?.value
        host.layoutIfNeeded()
        XCTAssertNotNil(view.revealedHeight)
        XCTAssertEqual(view.intrinsicContentSize.height, initialHeight)
        XCTAssertEqual(heightChanges, 2)
        XCTAssertEqual(host.passes, 0)

        // Advancing the reveal clock onto the next lines now reports the new height and lays out the host.
        var time = 0.0
        while view.intrinsicContentSize.height <= initialHeight, time < 5 {
            time += 0.05
            clock.advance(to: time)
        }
        host.layoutIfNeeded()
        XCTAssertGreaterThan(view.intrinsicContentSize.height, initialHeight)
        XCTAssertGreaterThanOrEqual(heightChanges, 1)
        XCTAssertGreaterThanOrEqual(host.passes, 1)
        XCTAssertEqual(view.frame.height, view.intrinsicContentSize.height, accuracy: 0.5)
        _ = window
    }

    func testAStreamedTableNeverShrinksTheHeightMidRevealAndFitsOnceTheRevealEnds() async throws {
        let (view, clock, window) = streamingView(width: 320)
        var heights: [CGFloat] = []
        var reportedAfterReveal: CGFloat?
        func record() {
            guard view.isRevealing else { return }
            heights.append(view.intrinsicContentSize.height)
            heights.append(view.sizeThatFits(CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)).height)
        }
        view.onHeightChange = {
            if view.isRevealing { record() } else { reportedAfterReveal = view.intrinsicContentSize.height }
        }
        let note = "a longer note that wraps when its column is narrow and fits on one line when it is wide"
        let rows = (1...6).map { "| row \($0) | item | \(note) |" }.joined(separator: "\n")
        let markdown = "Here is the comparison.\n\n| Name | Kind | Note |\n|---|---|---|\n" + rows
            + "\n\nThat covers every row. " + String(repeating: "A closing sentence follows the table here. ", count: 12)
        let words = markdown.split(separator: " ", omittingEmptySubsequences: false)
        var time = 0.0
        var shown = ""
        for (index, word) in words.enumerated() {
            shown += (index == 0 ? "" : " ") + word
            view.update(markdown: shown, isStreaming: true)
            await view.pendingDocument?.value
            time += 0.02
            clock.advance(to: time)
            record()
        }
        XCTAssertTrue(view.isRevealing, "the reveal is still running when the answer settles")
        let table = try XCTUnwrap(blockAttachments(in: view.textView.textStorage).first?.existingView as? GlimmerTableView)
        XCTAssertGreaterThan(view.engine?.revealedLength ?? 0, view.textView.textStorage.string.count / 3,
                             "the reveal has passed into the table")
        view.update(markdown: markdown, isStreaming: false)
        await view.pendingDocument?.value
        record()
        XCTAssertTrue(view.isRevealing, "the settled result landed mid-reveal")
        XCTAssertTrue(table.isStreaming, "the table keeps its streaming layout until the reveal ends")
        while view.isRevealing, time < 30 {
            time += 0.05
            clock.advance(to: time)
            record()
        }
        XCTAssertFalse(view.isRevealing)
        XCTAssertGreaterThan(heights.count, 10)
        for (index, height) in heights.enumerated().dropFirst() {
            XCTAssertGreaterThanOrEqual(height, heights[index - 1] - 0.01, "the height shrank mid-reveal at report \(index)")
        }

        view.layoutIfNeeded()
        XCTAssertFalse(table.isStreaming, "the table fits once the reveal ends")
        XCTAssertTrue(blockAttachments(in: view.textView.textStorage).first?.existingView === table, "the table keeps its view")
        let layout = try XCTUnwrap(table.cachedLayout)
        XCTAssertEqual(layout.layout.contentWidth, layout.width, accuracy: 0.001, "the fitted table fills its box")
        let fresh = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let freshWindow = hostInWindow(fresh, width: 320, height: 800)
        fresh.update(markdown: markdown)
        fresh.layoutIfNeeded()
        let freshTable = try XCTUnwrap(blockAttachments(in: fresh.textView.textStorage).first?.existingView as? GlimmerTableView)
        XCTAssertEqual(table.cachedLayout?.layout, freshTable.cachedLayout?.layout, "the table fits as a fresh one does")
        XCTAssertEqual(view.intrinsicContentSize.height, fresh.intrinsicContentSize.height, accuracy: 0.5)
        let reported = try XCTUnwrap(reportedAfterReveal, "the host hears the height once the reveal ends")
        XCTAssertEqual(reported, fresh.intrinsicContentSize.height, accuracy: 0.5, "the reported height is the fitted one")
        _ = (window, freshWindow)
    }

    func testANotRevealedStreamingTableFitsWhenTheAnswerSettles() async throws {
        var configuration = GlimmerConfiguration(imageLoader: nil)
        configuration.reveal = .none
        let view = GlimmerView(configuration: configuration)
        let window = hostInWindow(view, width: 320, height: 800)
        let markdown = "| A | B |\n|---|---|\n| one | two |"
        view.update(markdown: markdown, isStreaming: true)
        await view.pendingDocument?.value
        view.layoutIfNeeded()
        let table = try XCTUnwrap(blockAttachments(in: view.textView.textStorage).first?.existingView as? GlimmerTableView)
        XCTAssertTrue(table.isStreaming)
        XCTAssertLessThan(try XCTUnwrap(table.cachedLayout).layout.contentWidth, 320, "natural widths while streaming")
        view.update(markdown: markdown, isStreaming: false)
        await view.pendingDocument?.value
        view.layoutIfNeeded()
        let settled = try XCTUnwrap(blockAttachments(in: view.textView.textStorage).first?.existingView as? GlimmerTableView)
        XCTAssertFalse(settled.isStreaming, "with no reveal, the table fits when the settled result applies")
        let layout = try XCTUnwrap(settled.cachedLayout)
        XCTAssertEqual(layout.layout.contentWidth, layout.width, accuracy: 0.001)
        _ = window
    }

    func testASettledUpdateIsSettledAtOnce() {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil, reveal: .none))
        view.update(markdown: "Hello")
        XCTAssertTrue(view.isLayoutSettled)
    }

    func testAStreamedUpdateSettlesWhenComposedAndReportsIt() async {
        let (view, _, window) = streamingView(width: 320)
        var reports = 0
        view.onHeightChange = { reports += 1 }
        view.update(markdown: "Hello", isStreaming: true, revealID: nil)
        XCTAssertFalse(view.isLayoutSettled)
        await view.pendingDocument?.value
        XCTAssertTrue(view.isLayoutSettled)
        XCTAssertGreaterThan(reports, 0)
        _ = window
    }

    func testSettlingReportsEvenWhenTheHeightIsUnchanged() async {
        let (view, clock, window) = streamingView(width: 320)
        view.update(markdown: "First phrase here. Second phrase", isStreaming: true, revealID: nil)
        await view.pendingDocument?.value
        var time = 0.0
        while view.intrinsicContentSize.height <= 0, time < 5 {
            time += 0.05
            clock.advance(to: time)
        }
        XCTAssertGreaterThan(view.intrinsicContentSize.height, 0)
        let before = view.intrinsicContentSize.height
        var reports = 0
        view.onHeightChange = { reports += 1 }
        view.update(markdown: "First phrase here. Second phrase", isStreaming: false, revealID: nil)
        XCTAssertFalse(view.isLayoutSettled)
        await view.pendingDocument?.value
        XCTAssertTrue(view.isLayoutSettled)
        XCTAssertEqual(reports, 1)
        XCTAssertEqual(view.intrinsicContentSize.height, before, accuracy: 0.5)
        _ = window
    }

    // MARK: - Reveal control after a stream ends

    /// Forty words of plain prose, long enough that a reveal takes several phrases.
    private let longAnswer = "The first sentence of this answer arrives right now. A second sentence follows it closely and keeps going. "
        + "Then a third sentence wraps onto more lines of the view. A fourth one closes the paragraph with a few more words "
        + "to read."

    func testFinishRevealShowsEverythingAtOnceAndRecordsIt() async throws {
        let id = "finish-reveal-test"
        GlimmerRevealStore.shared.clear(id)
        let (view, clock, window) = streamingView()
        view.update(markdown: longAnswer, isStreaming: true, revealID: id)
        await view.pendingDocument?.value
        clock.advance(to: 0.3)
        XCTAssertLessThan(try XCTUnwrap(view.engine).revealedLength, view.textView.textStorage.length)
        var reports = 0
        view.onHeightChange = { reports += 1 }
        view.finishReveal()
        XCTAssertNil(view.engine)
        XCTAssertNil(view.textView.layer.mask)
        XCTAssertEqual(view.intrinsicContentSize.height, fullHeight(view), accuracy: 0.5)
        XCTAssertGreaterThan(reports, 0, "the host hears about the full height")

        let (second, _, secondWindow) = streamingView()
        second.update(markdown: longAnswer, isStreaming: true, revealID: id)
        await second.pendingDocument?.value
        XCTAssertEqual(try XCTUnwrap(second.engine).revealedLength, second.textView.textStorage.length, "resumes complete")
        _ = window
        _ = secondWindow
    }

    func testALateWorkerResultDoesNotRestartAFinishedReveal() async {
        let id = "late-worker-test"
        GlimmerRevealStore.shared.clear(id)
        let (view, clock, window) = streamingView()
        view.update(markdown: longAnswer, isStreaming: true, revealID: id)
        await view.pendingDocument?.value
        clock.advance(to: 0.3)
        view.update(markdown: longAnswer, isStreaming: false, revealID: id)
        XCTAssertNotNil(view.pendingDocument, "goes to the worker")
        view.finishReveal()
        await view.pendingDocument?.value
        XCTAssertNil(view.engine)
        XCTAssertNil(view.textView.layer.mask)
        _ = window
    }

    func testAStreamedResultInFlightDoesNotRestartAFinishedRevealUntilTheNextStreamedUpdate() async {
        let id = "late-streamed-worker-test"
        GlimmerRevealStore.shared.clear(id)
        let (view, clock, window) = streamingView()
        view.update(markdown: "The first sentence of this answer arrives right now.", isStreaming: true, revealID: id)
        await view.pendingDocument?.value
        clock.advance(to: 0.3)
        view.update(markdown: longAnswer, isStreaming: true, revealID: id)
        view.finishReveal()
        await view.pendingDocument?.value
        XCTAssertNil(view.engine, "a result requested before finishReveal starts no reveal")
        XCTAssertEqual(view.plainText(), longAnswer)
        XCTAssertEqual(
            GlimmerRevealStore.shared.revealedLength(for: id, text: view.textView.textStorage.string as NSString),
            view.textView.textStorage.length, "the text that landed counts as revealed"
        )

        view.update(markdown: longAnswer + " More text arrives after that.", isStreaming: true, revealID: id)
        await view.pendingDocument?.value
        XCTAssertNotNil(view.engine, "the next streamed update reveals again")
        _ = window
    }

    func testFinishedTextRevealsWhenAsked() throws {
        let id = "finished-text-test"
        GlimmerRevealStore.shared.clear(id)
        let (view, clock, window) = streamingView()
        view.update(markdown: longAnswer, isStreaming: false, revealID: id, revealsFinishedText: true)
        XCTAssertTrue(view.isLayoutSettled, "composed synchronously")
        XCTAssertEqual(view.plainText(), longAnswer)
        let engine = try XCTUnwrap(view.engine)
        XCTAssertLessThan(engine.revealedLength, view.textView.textStorage.length)
        XCTAssertNotNil(view.textView.layer.mask)
        XCTAssertLessThan(view.intrinsicContentSize.height, fullHeight(view))
        let options = GlimmerRevealOptions()
        clock.advance(to: options.drainDuration + options.fadeDuration + 0.1)
        XCTAssertNil(view.engine, "drains within drainDuration")
        XCTAssertNil(view.textView.layer.mask)

        let (second, _, secondWindow) = streamingView()
        second.update(markdown: longAnswer, isStreaming: false, revealID: id, revealsFinishedText: true)
        XCTAssertNil(second.engine, "stored progress covers the whole text: nothing reveals")
        _ = window
        _ = secondWindow
    }

    func testFinishedTextResumesStoredProgress() async throws {
        let id = "finished-text-resume-test"
        GlimmerRevealStore.shared.clear(id)
        let (first, firstClock, firstWindow) = streamingView()
        first.update(markdown: longAnswer, isStreaming: true, revealID: id)
        await first.pendingDocument?.value
        firstClock.advance(to: 0.3)
        let stored = try XCTUnwrap(
            GlimmerRevealStore.shared.revealedLength(for: id, text: first.textView.textStorage.string as NSString)
        )
        XCTAssertGreaterThan(stored, 0)
        XCTAssertLessThan(stored, first.textView.textStorage.length)

        let (second, _, secondWindow) = streamingView()
        second.update(markdown: longAnswer, isStreaming: false, revealID: id, revealsFinishedText: true)
        let engine = try XCTUnwrap(second.engine)
        // The next phrase starts at once, where the stored progress ended.
        XCTAssertEqual(engine.settledLength, stored, "what was revealed shows without fading in again")
        XCTAssertEqual(engine.phrases.first?.range.location, stored)
        _ = firstWindow
        _ = secondWindow
    }

    func testFinishedTextWithoutTheFlagShowsAtOnce() {
        let id = "finished-text-no-flag-test"
        GlimmerRevealStore.shared.clear(id)
        let (view, _, window) = streamingView()
        view.update(markdown: longAnswer, isStreaming: false, revealID: id, revealsFinishedText: false)
        XCTAssertNil(view.engine)
        view.update(markdown: answer, isStreaming: false, revealID: id)
        XCTAssertNil(view.engine)
        _ = window
    }

    func testFinishedTextWithoutARevealIDShowsAtOnce() {
        let (view, _, window) = streamingView()
        view.update(markdown: longAnswer, isStreaming: false, revealID: nil, revealsFinishedText: true)
        XCTAssertNil(view.engine)
        _ = window
    }

    func testFinishedTextDoesNotRevealWithRevealNone() {
        let id = "finished-text-none-test"
        GlimmerRevealStore.shared.clear(id)
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil, reveal: .none))
        let window = hostInWindow(view, width: 320, height: 800)
        view.update(markdown: longAnswer, isStreaming: false, revealID: id, revealsFinishedText: true)
        XCTAssertNil(view.engine)
        XCTAssertNil(view.textView.layer.mask)
        _ = window
    }

    func testIsRevealingFollowsTheEngine() async {
        let id = "is-revealing-test"
        GlimmerRevealStore.shared.clear(id)
        let (view, _, window) = streamingView()
        XCTAssertFalse(view.isRevealing)
        view.update(markdown: longAnswer, isStreaming: true, revealID: id)
        await view.pendingDocument?.value
        XCTAssertTrue(view.isRevealing)
        view.finishReveal()
        XCTAssertFalse(view.isRevealing)
        _ = window
    }
}

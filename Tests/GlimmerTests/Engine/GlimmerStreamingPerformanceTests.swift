import UIKit
import XCTest
@testable import Glimmer

/// Main-thread cost of one streamed `update` near the end of a long answer, followed by its scroll view the way a chat
/// follows a streaming reply. Two numbers per update:
/// - the apply (`lastApplyDuration`): the spec's §3 metric, ≤ 2 ms p95 in Release on an iPhone 16 Pro Max. Parse and
///   compose run on the worker, so this is the edit, measuring and the reveal's bookkeeping.
/// - the rest of the main thread's CPU for that update: layout and drawing (Core Animation runs them while the test
///   awaits the worker) and the reveal's wake-ups. It is mostly TextKit drawing the changed and newly scrolled-in
///   lines. Gated as a regression bound: rendering every paragraph (no visible band) costs well over 30 ms here.
/// These run in Debug on the simulator, so the gates are looser than the spec's.
@MainActor
final class GlimmerStreamingPerformanceTests: XCTestCase {
    // The apply is Glimmer's own code: Debug is slower, so its gate is looser; Release gates at the spec's 2 ms.
    #if DEBUG
    private let budget: Duration = .milliseconds(8)
    private let embedStreamingBudget: Duration = .milliseconds(8)
    #else
    private let budget: Duration = .milliseconds(2)
    /// Over the spec's 2 ms for now: a streaming code block is highlighted again on main (~1.3 ms; §4.2 wants it on
    /// the worker) and a streaming table rebuilds its labels per row. Both are Plan 5 work.
    private let embedStreamingBudget: Duration = .milliseconds(4)
    #endif
    /// TextKit re-lays out the ~60 fragments of the rendered band after every change: 3–4 ms p95 here, 4–6 ms with a
    /// reveal's mask (it was 30 ms before the band). Plan 5's on-device harness checks the Release cost against hitches.
    /// The rest of the main thread is TextKit's layout and drawing — framework code, as fast in Debug as in Release — so
    /// these bounds hold for both. Measured before moving compose off-main (main-thread CPU, p95): mixed 12 ms,
    /// revealing 18 ms, long list 20 ms; after: 13, 19 and 6 ms (Release: 8, 21 and 6 under load).
    private let mainThreadBudget: Duration = .milliseconds(18)
    /// A regression bound, not the spec's 4 ms: TextKit's first layout of the screen dominates a cached configure.
    private let configureBudget: Duration = .milliseconds(24)
    private let revealingMainThreadBudget: Duration = .milliseconds(26)

    /// About 5,000 words of headings, prose, lists, quotes, code and tables.
    private let longMixedAnswer = Array(repeating: StreamingFixtures.all.map(\.markdown).joined(separator: "\n\n"), count: 29)
        .joined(separator: "\n\n")

    /// The typical long-code answer: an intro and a 150-line code block, streamed a line at a time at its end.
    private let longCodeAnswer = "Here is the file:\n\n```swift\n"
        + (1...150).map { "let value\($0) = compute(\($0), scale: 2.5) // line \($0)" }.joined(separator: "\n")

    /// A 40-row table streamed a row at a time at its end.
    private let longTableAnswer = "Here are the numbers:\n\n| Name | Value | Notes |\n|---|---|---|\n"
        + (1...40).map { "| row \($0) | \($0 * 3) | a note about row \($0) |" }.joined(separator: "\n")

    /// About 5,000 words in one tight list: no blank line anywhere.
    private let longList = (1...500).map { "- Item \($0) keeps the list going with a few more words" }.joined(separator: "\n")

    func testUpdatesNearTheEndOfALongAnswerStayWithinBudget() async {
        let p95 = await measured({ $0.update < budget && $0.layout < mainThreadBudget }) {
            await streamTail(of: longMixedAnswer, reveal: .none)
        }
        XCTAssertLessThan(p95.update, budget, "update p95")
        XCTAssertLessThan(p95.layout, mainThreadBudget, "main-thread work p95")
    }

    /// The tail holds a code block and a table, which reveal a line or row at a time: each unit start grows the box,
    /// and TextKit re-lays it out and redraws it with the text after it. Hence a looser main-thread gate.
    func testRevealingUpdatesNearTheEndOfALongAnswerStayWithinBudget() async {
        let p95 = await measured({ $0.update < budget && $0.layout < revealingMainThreadBudget }) {
            await streamTail(of: longMixedAnswer, reveal: .smooth(GlimmerRevealOptions()))
        }
        XCTAssertLessThan(p95.update, budget, "update p95")
        XCTAssertLessThan(p95.layout, revealingMainThreadBudget, "main-thread work p95")
    }

    /// A list is one block, so every update re-composes all of it — on the worker. On the main thread it cost 14 ms
    /// before compose moved off it, and 35 ms before edits were trimmed.
    func testUpdatesNearTheEndOfALongListStayWithinBudget() async {
        let p95 = await measured({ $0.update < budget && $0.layout < mainThreadBudget }) {
            await streamTail(of: longList, reveal: .none)
        }
        XCTAssertLessThan(p95.update, budget, "update p95")
        XCTAssertLessThan(p95.layout, mainThreadBudget, "main-thread work p95")
    }

    /// A streaming code block updates in place; its cost per chunk must not grow with the lines already shown.
    func testStreamingALongCodeBlockStaysWithinBudget() async {
        let p95 = await measured({ $0.update < embedStreamingBudget && $0.layout < revealingMainThreadBudget }) {
            await streamTail(of: longCodeAnswer, reveal: .none)
        }
        XCTAssertLessThan(p95.update, embedStreamingBudget, "update p95")
        // Each chunk grows the code box, so TextKit re-lays out and redraws it: the growing-embed bound, as for a
        // revealing embed. It was 49 ms here when every chunk re-set the whole code.
        XCTAssertLessThan(p95.layout, revealingMainThreadBudget, "main-thread work p95")
    }

    /// A streaming table updates in place; its cost per row must not grow with the rows already shown.
    func testStreamingALongTableStaysWithinBudget() async {
        let p95 = await measured({ $0.update < embedStreamingBudget && $0.layout < mainThreadBudget }) {
            await streamTail(of: longTableAnswer, reveal: .none)
        }
        XCTAssertLessThan(p95.update, embedStreamingBudget, "update p95")
        XCTAssertLessThan(p95.layout, mainThreadBudget, "main-thread work p95")
    }

    /// Spec §3: starting a phrase ≤ 0.2 ms, and its segment lookup is most of that. TextKit's time, so the budget holds
    /// in Debug too.
    func testFindingLateTextStaysCheap() {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: longMixedAnswer)
        view.layoutIfNeeded()
        let late = NSRange(location: view.textView.textStorage.length - 2, length: 1)
        let timer = ContinuousClock()
        var samples: [Duration] = []
        for _ in 0..<21 { samples.append(timer.measure { _ = view.textView.segmentRects(for: late) }) }
        print("PERF late segment lookup at 5,000 words: median \(samples.sorted()[10])")
        XCTAssertLessThan(samples.sorted()[10], .microseconds(200), "median segment lookup at the end of 5,000 words")
        _ = window
    }

    /// Measuring after a change lays out from the change, not the whole answer: every update and every embed unit
    /// pays for it.
    func testMeasuringAfterAnAppendStaysCheap() throws {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: longMixedAnswer)
        view.layoutIfNeeded()
        let textView = view.textView
        let full = textView.laidOutHeight(from: 0)
        let content = try XCTUnwrap(textView.textLayoutManager?.textContentManager as? NSTextContentStorage)
        let timer = ContinuousClock()
        var samples: [Duration] = []
        for _ in 0..<11 {
            let end = textView.textStorage.length
            content.performEditingTransaction {
                textView.textStorage.append(NSAttributedString(string: " more", attributes: [.font: GlimmerTheme.default.bodyFont]))
            }
            samples.append(timer.measure { _ = textView.laidOutHeight(from: end) })
        }
        XCTAssertEqual(textView.laidOutHeight(from: textView.textStorage.length - 1), textView.laidOutHeight(from: 0))
        XCTAssertGreaterThanOrEqual(textView.laidOutHeight(from: 0), full)
        XCTAssertLessThan(samples.sorted()[5], .microseconds(300), "median measure after an append at 5,000 words")
        _ = window
    }

    /// Spec §3: configuring a settled answer on cell reuse ≤ 4 ms, with the document and height cached. What the cache
    /// owns is parsing, composing and measuring; TextKit still lays out and draws the first screen, and builds its
    /// embeds' views, on every configure. So this gates the cache's share against an uncached configure measured the
    /// same way, and prints the absolute numbers for Plan 5's device run.
    func testConfiguringACachedSettledAnswerStaysWithinBudget() {
        let answer = Array(repeating: StreamingFixtures.all.map(\.markdown).joined(separator: "\n\n"), count: 7).joined(separator: "\n\n")
        func configure() -> Duration {
            let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
            let window = hostInWindow(view, width: 390, height: 800)
            defer { _ = window }
            return ContinuousClock().measure {
                view.update(markdown: answer)
                view.layoutIfNeeded()
            }
        }
        func medians() -> (cached: Duration, uncached: Duration) {
            var uncached: [Duration] = []
            for _ in 0..<9 {
                GlimmerDocumentCache.shared.removeAll()
                uncached.append(configure())
            }
            _ = configure()
            var cached: [Duration] = []
            for _ in 0..<9 { cached.append(configure()) }
            return (cached.sorted()[4], uncached.sorted()[4])
        }
        var result = medians()
        if !(result.cached < result.uncached * 0.7 && result.cached < configureBudget) { result = medians() }
        let (cachedMedian, uncachedMedian) = result
        print("PERF configure ~1,200 words: cached median \(cachedMedian), uncached median \(uncachedMedian)")
        XCTAssertLessThan(cachedMedian, uncachedMedian * 0.7, "the cache saves parsing, composing and measuring")
        XCTAssertLessThan(cachedMedian, configureBudget)
    }

    /// Load on a shared machine (another simulator, a compile) can push one run's p95 over a gate; a real regression
    /// fails both runs. So each gated measurement gets one retry.
    private func measured(
        _ passes: ((update: Duration, layout: Duration)) -> Bool,
        _ measure: () async -> (update: Duration, layout: Duration)
    ) async -> (update: Duration, layout: Duration) {
        let first = await measure()
        return passes(first) ? first : await measure()
    }

    /// Streams all but the last 1,200 characters at once, then the rest in 30-character chunks, following the view's
    /// bottom in a scroll view. Returns the p95 of each update's main-thread apply (parse and compose run on the
    /// worker) and of the rest of the main thread's work for that update: layout and drawing (wherever Core Animation
    /// ran them, including while the test awaited the worker) plus the reveal's wake-ups — main-thread CPU time for
    /// the whole update, less the apply.
    private func streamTail(of markdown: String, reveal: GlimmerReveal) async -> (update: Duration, layout: Duration) {
        var configuration = GlimmerConfiguration(imageLoader: nil)
        configuration.reveal = reveal
        let view = GlimmerView(configuration: configuration)
        let clock = ManualRevealClock()
        view.clock = clock
        let scrollView = UIScrollView()
        let window = hostInWindow(scrollView, width: 390, height: 800)
        scrollView.addSubview(view)
        /// Sizes the view to its height and scrolls to its bottom, as a chat follows a streaming answer.
        func follow() {
            let height = view.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height
            view.frame = CGRect(x: 0, y: 0, width: 390, height: height)
            scrollView.contentSize = view.frame.size
            scrollView.contentOffset = CGPoint(x: 0, y: max(0, height - 800))
        }
        let characters = Array(markdown)
        var end = characters.count - 1_200
        view.update(markdown: String(characters[..<end]), isStreaming: true)
        await view.pendingDocument?.value
        follow()
        view.layoutIfNeeded()
        var time = 1.0
        clock.advance(to: time)
        var samples: [Duration] = []
        var updates: [Duration] = []
        var layouts: [Duration] = []
        while end < characters.count {
            end = min(end + 30, characters.count)
            let prefix = String(characters[..<end])
            time += 0.05
            let cpuStart = threadCPUTime()
            view.update(markdown: prefix, isStreaming: true)
            await view.pendingDocument?.value
            follow()
            view.layoutIfNeeded()
            clock.advance(to: time)
            let update = view.lastApplyDuration
            let layout = max(.zero, threadCPUTime() - cpuStart - update)
            updates.append(update)
            layouts.append(layout)
            samples.append(update + layout)
        }
        func p(_ values: [Duration], _ percent: Int) -> Duration { values.sorted()[values.count * percent / 100] }
        print("PERF \(name): update p50 \(p(updates, 50)) p95 \(p(updates, 95)); rest of main thread p95 \(p(layouts, 95)); total p95 \(p(samples, 95)) over \(samples.count) updates, \(markdown.count) characters")
        _ = window
        return (p(updates, 95), p(layouts, 95))
    }
}

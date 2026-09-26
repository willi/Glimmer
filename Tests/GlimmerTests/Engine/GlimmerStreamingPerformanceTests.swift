import UIKit
import XCTest
@testable import Glimmer

/// Main-thread cost of one streamed `update`, and of the layout pass after it, near the end of a long answer followed
/// by its scroll view the way a chat follows a streaming reply. The spec's budget (§3) is ≤ 2 ms p95 in a Release
/// build on an iPhone 16 Pro Max; these run in Debug on the simulator, so they gate at a looser bound — one that still
/// fails for any cost that grows with the whole answer (re-measuring it, re-scanning it, re-laying it out, rendering
/// all of it).
@MainActor
final class GlimmerStreamingPerformanceTests: XCTestCase {
    private let budget: Duration = .milliseconds(8)
    /// TextKit re-lays out the ~60 fragments of the rendered band after every change: 3–4 ms p95 here, 4–6 ms with a
    /// reveal's mask (it was 30 ms before the band). Plan 5's on-device harness checks the Release cost against hitches.
    private let layoutBudget: Duration = .milliseconds(6)

    /// About 5,000 words of headings, prose, lists, quotes, code and tables.
    private let longMixedAnswer = Array(repeating: StreamingFixtures.all.map(\.markdown).joined(separator: "\n\n"), count: 29)
        .joined(separator: "\n\n")

    /// About 5,000 words in one tight list: no blank line anywhere.
    private let longList = (1...500).map { "- Item \($0) keeps the list going with a few more words" }.joined(separator: "\n")

    func testUpdatesNearTheEndOfALongAnswerStayWithinBudget() {
        let p95 = streamTail(of: longMixedAnswer, reveal: .none)
        XCTAssertLessThan(p95.update, budget, "update p95")
        XCTAssertLessThan(p95.layout, layoutBudget, "layout pass p95")
    }

    func testRevealingUpdatesNearTheEndOfALongAnswerStayWithinBudget() {
        let p95 = streamTail(of: longMixedAnswer, reveal: .smooth(GlimmerRevealOptions()))
        XCTAssertLessThan(p95.update, budget, "update p95")
        XCTAssertLessThan(p95.layout, layoutBudget, "layout pass p95")
    }

    /// A list is one block, so every update still re-composes all of it; what this bounds is the rest — TextKit
    /// re-laying out every item took 35 ms here before edits were trimmed.
    func testUpdatesNearTheEndOfALongListStayWithinBudget() {
        let p95 = streamTail(of: longList, reveal: .none)
        XCTAssertLessThan(p95.update, .milliseconds(25), "update p95")
        XCTAssertLessThan(p95.layout, layoutBudget, "layout pass p95")
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
        XCTAssertLessThan(samples.sorted()[10], .microseconds(200), "median segment lookup at the end of 5,000 words")
        _ = window
    }

    /// Streams all but the last 1,200 characters at once, then the rest in 30-character chunks, following the view's
    /// bottom in a scroll view. Returns the p95 of the updates and of the layout passes after them.
    private func streamTail(of markdown: String, reveal: GlimmerReveal) -> (update: Duration, layout: Duration) {
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
        follow()
        view.layoutIfNeeded()
        var time = 1.0
        clock.advance(to: time)
        var samples: [Duration] = []
        var updates: [Duration] = []
        var layouts: [Duration] = []
        let timer = ContinuousClock()
        while end < characters.count {
            end = min(end + 30, characters.count)
            let prefix = String(characters[..<end])
            time += 0.05
            let update = timer.measure { view.update(markdown: prefix, isStreaming: true) }
            let layout = timer.measure {
                follow()
                view.layoutIfNeeded()
                clock.advance(to: time)
            }
            updates.append(update)
            layouts.append(layout)
            samples.append(update + layout)
        }
        func p(_ values: [Duration], _ percent: Int) -> Duration { values.sorted()[values.count * percent / 100] }
        print("PERF \(name): update p50 \(p(updates, 50)) p95 \(p(updates, 95)); layout pass p95 \(p(layouts, 95)); total p95 \(p(samples, 95)) over \(samples.count) updates, \(markdown.count) characters")
        _ = window
        return (p(updates, 95), p(layouts, 95))
    }
}

import UIKit
import XCTest
@testable import Glimmer

/// Main-thread cost of one streamed `update` near the end of a long answer. The spec's budget (§3) is ≤ 2 ms p95 in a
/// Release build on an iPhone 16 Pro Max; these run in Debug on the simulator, so they gate at a looser bound — one
/// that still fails for any cost that grows with the whole answer (re-measuring it, re-scanning it, re-laying it out).
///
/// The layout pass that follows each update is printed, not gated: with the text view as tall as the document,
/// TextKit's viewport covers every paragraph, and that pass grows with the answer until Plan 3 bounds the viewport.
@MainActor
final class GlimmerStreamingPerformanceTests: XCTestCase {
    private let budget: Duration = .milliseconds(8)

    /// About 5,000 words of headings, prose, lists, quotes, code and tables.
    private let longMixedAnswer = Array(repeating: StreamingFixtures.all.map(\.markdown).joined(separator: "\n\n"), count: 29)
        .joined(separator: "\n\n")

    /// About 5,000 words in one tight list: no blank line anywhere.
    private let longList = (1...500).map { "- Item \($0) keeps the list going with a few more words" }.joined(separator: "\n")

    func testUpdatesNearTheEndOfALongAnswerStayWithinBudget() {
        XCTAssertLessThan(streamTail(of: longMixedAnswer, reveal: .none), budget, "p95 per update")
    }

    func testRevealingUpdatesNearTheEndOfALongAnswerStayWithinBudget() {
        XCTAssertLessThan(streamTail(of: longMixedAnswer, reveal: .smooth(GlimmerRevealOptions())), budget, "p95 per update")
    }

    /// A list is one block, so every update still re-composes all of it (per-item composition is Plan 3's); what this
    /// bounds is the rest — TextKit re-laying out every item took 35 ms here before edits were trimmed.
    func testUpdatesNearTheEndOfALongListStayWithinBudget() {
        XCTAssertLessThan(streamTail(of: longList, reveal: .none), .milliseconds(25), "p95 per update")
    }

    /// Streams all but the last 1,200 characters at once, then the rest in 30-character chunks, and returns the p95
    /// time of those chunk updates (without the layout pass after each).
    private func streamTail(of markdown: String, reveal: GlimmerReveal, file: StaticString = #filePath) -> Duration {
        var configuration = GlimmerConfiguration(imageLoader: nil)
        configuration.reveal = reveal
        let view = GlimmerView(configuration: configuration)
        let clock = ManualRevealClock()
        view.clock = clock
        let window = hostInWindow(view, width: 390, height: 800)
        let characters = Array(markdown)
        var end = characters.count - 1_200
        view.update(markdown: String(characters[..<end]), isStreaming: true)
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
        return p(updates, 95)
    }
}

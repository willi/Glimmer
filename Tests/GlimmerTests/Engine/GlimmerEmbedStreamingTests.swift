import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerEmbedStreamingTests: XCTestCase {
    private func noRevealView() -> (GlimmerView, UIWindow) {
        var configuration = GlimmerConfiguration(imageLoader: nil)
        configuration.reveal = .none
        let view = GlimmerView(configuration: configuration)
        return (view, hostInWindow(view, width: 390, height: 800))
    }

    func testStreamingCodeBlockKeepsItsView() async throws {
        let (view, window) = noRevealView()
        view.update(markdown: "```swift\nlet a = 1", isStreaming: true)
        await view.pendingDocument?.value
        settle(view)
        let first = try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: view))
        let firstHeight = first.bounds.height
        view.update(markdown: "```swift\nlet a = 1\nlet b = 2\nlet c = 3", isStreaming: true)
        await view.pendingDocument?.value
        settle(view)
        let second = try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: view))
        XCTAssertTrue(first === second, "the view updates in place")
        XCTAssertEqual(second.code, "let a = 1\nlet b = 2\nlet c = 3")
        XCTAssertGreaterThan(second.bounds.height, firstHeight)
        _ = window
    }

    func testStreamingTableKeepsItsView() async throws {
        let (view, window) = noRevealView()
        view.update(markdown: "| a | b |\n|---|---|\n| 1 | 2 |", isStreaming: true)
        await view.pendingDocument?.value
        settle(view)
        let first = try XCTUnwrap(findSubview(GlimmerTableView.self, in: view))
        view.update(markdown: "| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |", isStreaming: true)
        await view.pendingDocument?.value
        settle(view)
        let second = try XCTUnwrap(findSubview(GlimmerTableView.self, in: view))
        XCTAssertTrue(first === second)
        XCTAssertEqual(second.cellLabels.count, 3, "header plus two rows")
        _ = window
    }

    private func revealingView(width: CGFloat = 390) -> (GlimmerView, ManualRevealClock, UIWindow) {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let clock = ManualRevealClock()
        view.clock = clock
        return (view, clock, hostInWindow(view, width: width, height: 800))
    }

    func testCodeBlockRevealsLineByLine() async throws {
        let (view, clock, window) = revealingView()
        let markdown = "```swift\nlet a = 1\nlet b = 2\nlet c = 3\n```"
        view.update(markdown: markdown, isStreaming: true)
        await view.pendingDocument?.value
        settle(view)
        let code = try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: view))
        XCTAssertEqual(code.visibleUnitCount, 1, "the first line starts alone")
        XCTAssertGreaterThan(view.intrinsicContentSize.height, 0, "an answer that opens with code shows its first line")
        let oneLine = code.bounds.height
        clock.advance(to: 0.4)
        settle(view)
        XCTAssertGreaterThan(code.visibleUnitCount ?? 0, 1)
        XCTAssertGreaterThan(code.bounds.height, oneLine, "the box grows with the revealed lines")
        // Unit rects come from TextKit's attachment frame; once laid out, they match the view on screen.
        let rects = try XCTUnwrap(view.textView.embedUnitRects(atCharacter: 0))
        let onScreen = code.convert(code.bounds, to: view.textView)
        XCTAssertEqual(rects[0].minY, onScreen.minY, accuracy: 1)
        XCTAssertEqual(rects[(code.visibleUnitCount ?? 1) - 1].maxY, onScreen.maxY, accuracy: 1)
        view.update(markdown: markdown, isStreaming: false)
        await view.pendingDocument?.value
        clock.advance(to: 10)
        settle(view)
        XCTAssertNil(code.visibleUnitCount, "a settled code block shows every line")
        XCTAssertEqual(code.bounds.height, code.embedHeight(forWidth: code.bounds.width), accuracy: 0.5)
        _ = window
    }

    func testUnitPhraseFadesOverItsLine() async throws {
        let (view, clock, window) = revealingView()
        view.update(markdown: "```\nfirst line\nsecond line\nthird line\n```", isStreaming: true)
        await view.pendingDocument?.value
        var time = 0.0
        while (view.engine?.unitsRevealed.values.max() ?? 0) < 2, time < 0.5 {
            time += 0.02
            clock.advance(to: time)
        }
        settle(view)
        let engine = try XCTUnwrap(view.engine)
        let first = try XCTUnwrap(engine.phrases.first { $0.unit == 0 }, "the first line is still fading")
        let rects = try XCTUnwrap(view.textView.embedUnitRects(atCharacter: first.range.location))
        let covered = try XCTUnwrap(view.revealMask.phraseLayer(forUnit: 0, at: first.range.location)?.path?.boundingBox)
        XCTAssertTrue(covered.insetBy(dx: -1.5, dy: -2.5).contains(rects[0]), "\(covered) covers \(rects[0])")
        XCTAssertLessThanOrEqual(covered.maxY, rects[0].maxY + 3, "the first line's fade stops at the first line")
        _ = window
    }

    func testWidthChangeDuringAnEmbedRevealEndsIdenticalToSettled() async throws {
        let markdown = "Intro.\n\n```\none\ntwo\nthree\nfour\n```\n\nOutro."
        let (view, clock, window) = revealingView(width: 390)
        view.update(markdown: markdown, isStreaming: true)
        await view.pendingDocument?.value
        clock.advance(to: 0.3)
        window.frame.size.width = 320
        view.frame.size.width = 320
        settle(view)
        view.update(markdown: markdown, isStreaming: false)
        await view.pendingDocument?.value
        clock.advance(to: 20)
        settle(view)
        let settled = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let settledWindow = hostInWindow(settled, width: 320, height: 800)
        settled.update(markdown: markdown)
        settle(settled)
        XCTAssertEqual(view.intrinsicContentSize.height, settled.intrinsicContentSize.height, accuracy: 0.5)
        XCTAssertNil(findSubview(GlimmerCodeBlockView.self, in: view)?.visibleUnitCount)
        _ = (window, settledWindow)
    }
}

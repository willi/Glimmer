import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerStreamParityTests: XCTestCase {
    private let width: CGFloat = 320
    private let configuration = GlimmerConfiguration(imageLoader: nil)

    func testDocumentMatchesAFreshComposeAtEveryPrefix() {
        let composer = GlimmerComposer(theme: .default)
        for fixture in StreamingFixtures.all {
            let document = GlimmerStreamingDocument(composer: composer)
            let characters = Array(fixture.markdown)
            for end in stride(from: 1, through: characters.count, by: 3) {
                let prefix = String(characters[..<end])
                _ = document.update(markdown: prefix, isStreaming: true)
                assertEquivalent(document.text, composer.compose(GlimmerParser.parse(GlimmerTailHealer.heal(prefix))),
                                 "\(fixture.name) prefix \(end)")
            }
            _ = document.update(markdown: fixture.markdown, isStreaming: false)
            assertEquivalent(document.text, composer.compose(GlimmerParser.parse(fixture.markdown)), "\(fixture.name) final")
        }
    }

    func testCommittedBlocksNeverChangeWhileStreaming() {
        let composer = GlimmerComposer(theme: .default)
        for fixture in StreamingFixtures.all {
            let document = GlimmerStreamingDocument(composer: composer)
            let characters = Array(fixture.markdown)
            var lastBlockStart = 0
            for end in stride(from: 1, through: characters.count, by: 2) {
                if let edit = document.update(markdown: String(characters[..<end]), isStreaming: true) {
                    XCTAssertGreaterThanOrEqual(edit.range.location, max(0, lastBlockStart - 1),
                                                "\(fixture.name): a committed block changed at prefix \(end)")
                }
                // The last two blocks are open (Task 3 ruling); everything before them is committed.
                lastBlockStart = document.blockOffsets.dropLast().last ?? 0
            }
        }
    }

    func testStreamedViewEndsIdenticalToASettledView() throws {
        for fixture in StreamingFixtures.all {
            let streamed = GlimmerView(configuration: configuration)
            let clock = ManualRevealClock()
            streamed.clock = clock
            let streamedWindow = hostInWindow(streamed, width: width, height: 1400)
            var heights: [CGFloat] = []
            let characters = Array(fixture.markdown)
            var time = 0.0
            for end in stride(from: 1, through: characters.count, by: 25) {
                streamed.update(markdown: String(characters[..<end]), isStreaming: true, revealID: "parity-\(fixture.name)")
                time += 0.05
                clock.advance(to: time)
                heights.append(streamed.intrinsicContentSize.height)
            }
            streamed.update(markdown: fixture.markdown, isStreaming: false, revealID: "parity-\(fixture.name)")
            clock.advance(to: time + 10)
            GlimmerRevealStore.shared.clear("parity-\(fixture.name)")

            XCTAssertEqual(heights, heights.sorted(), "\(fixture.name): the height shrank while streaming")
            XCTAssertNil(streamed.engine, "\(fixture.name): the reveal did not finish")
            XCTAssertNil(streamed.textView.layer.mask)

            let settled = GlimmerView(configuration: configuration)
            let settledWindow = hostInWindow(settled, width: width, height: 1400)
            settled.update(markdown: fixture.markdown)
            assertEquivalent(streamed.textView.textStorage, settled.textView.textStorage, fixture.name)
            let size = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            XCTAssertEqual(streamed.sizeThatFits(size).height, settled.sizeThatFits(size).height, accuracy: 0.5)

            let height = settled.sizeThatFits(size).height
            streamed.frame.size.height = height
            settled.frame.size.height = height
            settle(streamed)
            settle(settled)
            XCTAssertEqual(snapshot(streamed), snapshot(settled), "\(fixture.name): pixels differ after the reveal")
            _ = streamedWindow
            _ = settledWindow
        }
    }

    private func snapshot(_ view: UIView) -> Data {
        UIGraphicsImageRenderer(bounds: view.bounds).pngData { view.layer.render(in: $0.cgContext) }
    }
}

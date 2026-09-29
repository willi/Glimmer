import UIKit
import XCTest
@testable import Glimmer

/// Streaming never moves or restyles text already shown (the spec's stability requirement).
@MainActor
final class GlimmerStreamStabilityTests: XCTestCase {
    func testTheCheckRejectsAStreamWithNoStableParagraph() {
        let options = XCTExpectedFailure.Options()
        options.issueMatcher = { $0.compactDescription.contains("the fixture never compared a nonempty stable paragraph") }
        XCTExpectFailure("A stability check must compare some committed text", options: options) {
            assertStreamingKeepsShownTextInPlace("Only one paragraph.")
        }
    }

    func testTheCheckCatchesMovedAndChangedText() {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil, reveal: .none))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: "First paragraph.\n\nSecond")
        view.layoutIfNeeded()
        let before = ShownText(view.textView)
        view.update(markdown: "# First paragraph.\n\nSecond")
        view.layoutIfNeeded()
        XCTAssertNotNil(ShownText(view.textView).movedText(since: before), "a restyled paragraph moves its glyphs")
        view.update(markdown: "Changed paragraph.\n\nSecond")
        view.layoutIfNeeded()
        XCTAssertNotNil(ShownText(view.textView).movedText(since: before), "changed text is caught")
        view.update(markdown: "First paragraph.\n\nSecond and more")
        view.layoutIfNeeded()
        XCTAssertNil(ShownText(view.textView).movedText(since: before), "the last paragraph may grow")
        _ = window
    }

    /// A restyle that keeps the characters and their places (a link turning into plain text) is caught too.
    func testTheCheckCatchesAColourOnlyRestyle() {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil, reveal: .none))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: "First [paragraph](https://example.com).\n\nSecond")
        view.layoutIfNeeded()
        let before = ShownText(view.textView)
        view.update(markdown: "First paragraph.\n\nSecond")
        view.layoutIfNeeded()
        let plain = ShownText(view.textView)
        XCTAssertNotNil(plain.movedText(since: before), "a shown word changed colour")
        view.update(markdown: "First [paragraph](https://example.com).\n\nSecond")
        view.layoutIfNeeded()
        XCTAssertNotNil(ShownText(view.textView).movedText(since: plain), "a new style inside an old uniform run is caught")
        _ = window
    }

    func testStreamingFixturesKeepShownTextInPlace() {
        for fixture in StreamingFixtures.all {
            assertStreamingKeepsShownTextInPlace(fixture.markdown)
        }
    }
}

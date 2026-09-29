import UIKit
import XCTest
@_spi(Diagnostics) @testable import Glimmer

/// Counters the demo's benchmark shows, behind SPI: not part of the API.
@MainActor
final class GlimmerDiagnosticsTests: XCTestCase {
    func testViewportPassesCountEveryTextViewsPasses() throws {
        guard #available(iOS 27.0, *) else {
            throw XCTSkip("Viewport-pass diagnostics use the iOS 27 TextKit callback")
        }
        let before = GlimmerDiagnostics.viewportPasses
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil, reveal: .none))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: "An answer.\n\nWith two paragraphs.")
        settle(view)
        XCTAssertGreaterThan(view.textView.viewportPasses, 0)
        XCTAssertGreaterThanOrEqual(GlimmerDiagnostics.viewportPasses - before, view.textView.viewportPasses)
        _ = window
    }
}

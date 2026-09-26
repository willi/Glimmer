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

    func testStreamingCodeBlockKeepsItsView() throws {
        let (view, window) = noRevealView()
        view.update(markdown: "```swift\nlet a = 1", isStreaming: true)
        settle(view)
        let first = try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: view))
        let firstHeight = first.bounds.height
        view.update(markdown: "```swift\nlet a = 1\nlet b = 2\nlet c = 3", isStreaming: true)
        settle(view)
        let second = try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: view))
        XCTAssertTrue(first === second, "the view updates in place")
        XCTAssertEqual(second.code, "let a = 1\nlet b = 2\nlet c = 3")
        XCTAssertGreaterThan(second.bounds.height, firstHeight)
        _ = window
    }

    func testStreamingTableKeepsItsView() throws {
        let (view, window) = noRevealView()
        view.update(markdown: "| a | b |\n|---|---|\n| 1 | 2 |", isStreaming: true)
        settle(view)
        let first = try XCTUnwrap(findSubview(GlimmerTableView.self, in: view))
        view.update(markdown: "| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |", isStreaming: true)
        settle(view)
        let second = try XCTUnwrap(findSubview(GlimmerTableView.self, in: view))
        XCTAssertTrue(first === second)
        XCTAssertEqual(second.cellLabels.count, 3, "header plus two rows")
        _ = window
    }
}

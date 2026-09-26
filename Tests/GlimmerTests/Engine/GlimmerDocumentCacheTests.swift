import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerDocumentCacheTests: XCTestCase {
    private let answer = "# Title\n\nSome **text**.\n\n```swift\nlet x = 1\n```"

    override func setUp() async throws {
        GlimmerDocumentCache.shared.removeAll()
    }

    func testSecondConfigureOfTheSameAnswerComesFromTheCache() {
        let first = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let firstWindow = hostInWindow(first, width: 390, height: 800)
        first.update(markdown: answer)
        let hits = GlimmerDocumentCache.shared.hits
        let second = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let secondWindow = hostInWindow(second, width: 390, height: 800)
        second.update(markdown: answer)
        XCTAssertEqual(GlimmerDocumentCache.shared.hits, hits + 1)
        XCTAssertEqual(second.textView.textStorage.string, first.textView.textStorage.string)
        _ = (firstWindow, secondWindow)
    }

    func testTwoViewsOfOneAnswerNeverShareAnEmbedView() throws {
        let first = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let second = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let firstWindow = hostInWindow(first, width: 390, height: 800)
        let secondWindow = hostInWindow(second, width: 390, height: 800)
        first.update(markdown: answer)
        second.update(markdown: answer)
        settle(first)
        settle(second)
        let a = try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: first))
        let b = try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: second))
        XCTAssertFalse(a === b)
        XCTAssertTrue(a.isDescendant(of: first))
        _ = (firstWindow, secondWindow)
    }

    func testMemoryWarningEmptiesTheCache() {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: answer)
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        let key = GlimmerDocumentCache.Key(source: answer, theme: view.configuration.theme.scaled(for: view.traitCollection), extensions: [])
        XCTAssertNil(GlimmerDocumentCache.shared.text(for: key))
        _ = window
    }

    func testCachedHeightMatchesAMeasuredOne() {
        let first = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let firstWindow = hostInWindow(first, width: 390, height: 800)
        first.update(markdown: answer)
        let measured = first.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height
        let second = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let secondWindow = hostInWindow(second, width: 390, height: 800)
        second.update(markdown: answer)
        XCTAssertEqual(second.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height, measured, accuracy: 0.5)
        _ = (firstWindow, secondWindow)
    }
}

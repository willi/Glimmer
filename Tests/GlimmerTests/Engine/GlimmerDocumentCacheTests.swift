import UIKit
import XCTest
@testable import Glimmer

/// Records the images it was asked for.
private final class RecordingImageLoader: GlimmerImageLoader, @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    var requested: [URL] { lock.withLock { urls } }
    func loadImage(from url: URL) async throws -> UIImage {
        lock.withLock { urls.append(url) }
        return UIImage()
    }
}

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
        let key = GlimmerDocumentCache.Key(source: answer, theme: view.configuration.theme.scaled(for: view.traitCollection),
                                           extensions: [], highlighter: String(reflecting: GlimmerBasicHighlighter.self), imageLoader: nil)
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

    func testStreamingOnNeverChangesWhatTheCacheHandsOut() async throws {
        let first = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let firstWindow = hostInWindow(first, width: 390, height: 800)
        first.update(markdown: "```swift\nlet a = 1")
        settle(first)
        // The same view streams on: its worker reuses the code block's attachment and grows it.
        first.update(markdown: "```swift\nlet a = 1\nlet b = 2", isStreaming: true)
        await first.pendingDocument?.value
        let second = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let secondWindow = hostInWindow(second, width: 390, height: 800)
        second.update(markdown: "```swift\nlet a = 1")
        settle(second)
        XCTAssertEqual(try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: second)).code, "let a = 1")
        _ = (firstWindow, secondWindow)
    }

    func testTheCacheKeepsNoEmbedViewAlive() {
        weak var codeView: GlimmerCodeBlockView?
        autoreleasepool {
            let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
            let window = hostInWindow(view, width: 390, height: 800)
            view.update(markdown: answer)
            settle(view)
            codeView = findSubview(GlimmerCodeBlockView.self, in: view)
            XCTAssertNotNil(codeView)
            window.isHidden = true
            view.removeFromSuperview()
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertNil(codeView, "the cached text must not hold the view that composed it")
    }

    func testAViewWithAnotherImageLoaderUsesItsOwn() async {
        let answer = "![Chart](https://example.com/chart.png)"
        let preview = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let previewWindow = hostInWindow(preview, width: 390, height: 800)
        preview.update(markdown: answer)
        settle(preview)
        let loader = RecordingImageLoader()
        let full = GlimmerView(configuration: GlimmerConfiguration(imageLoader: loader))
        let fullWindow = hostInWindow(full, width: 390, height: 800)
        full.update(markdown: answer)
        settle(full)
        let loaded = await waitUntil { !loader.requested.isEmpty }
        XCTAssertTrue(loaded, "the view's own loader fetches the image, not the cached text's")
        _ = (previewWindow, fullWindow)
    }
}

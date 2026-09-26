import UIKit
import XCTest
@testable import Glimmer

/// Records which thread each preprocess ran on.
private final class ThreadRecorder: GlimmerExtension, @unchecked Sendable {
    private let lock = NSLock()
    private var mainThreadFlags: [Bool] = []
    var ranOnMain: [Bool] { lock.withLock { mainThreadFlags } }
    func preprocess(_ markdown: String) -> String {
        lock.withLock { mainThreadFlags.append(Thread.isMainThread) }
        return markdown
    }
}

@MainActor
final class GlimmerDocumentWorkerTests: XCTestCase {
    func testStreamingUpdatesComposeOffTheMainThread() async {
        let recorder = ThreadRecorder()
        let view = GlimmerView(configuration: GlimmerConfiguration(extensions: [recorder], imageLoader: nil))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: "Streaming **text** arrives", isStreaming: true)
        await view.pendingDocument?.value
        XCTAssertEqual(recorder.ranOnMain.last, false)
        XCTAssertEqual(view.textView.textStorage.string, "Streaming text arrives")
        _ = window
    }

    func testSettledConfigureIsSynchronous() {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: "A settled **answer**.")
        XCTAssertNil(view.pendingDocument)
        XCTAssertEqual(view.textView.textStorage.string, "A settled answer.")
        XCTAssertGreaterThan(view.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height, 0)
        _ = window
    }

    func testLatestUpdateWinsWhenUpdatesArriveFasterThanTheWorker() async {
        let recorder = ThreadRecorder()
        var configuration = GlimmerConfiguration(extensions: [recorder], imageLoader: nil)
        configuration.reveal = .none
        let view = GlimmerView(configuration: configuration)
        let window = hostInWindow(view, width: 390, height: 800)
        let before = recorder.ranOnMain.count
        var markdown = ""
        for word in ["one", "two", "three", "four", "five", "six"] {
            markdown += word + " "
            view.update(markdown: markdown, isStreaming: true)
        }
        await view.pendingDocument?.value
        // CommonMark drops a paragraph's trailing space.
        XCTAssertEqual(view.textView.textStorage.string, "one two three four five six")
        XCTAssertLessThan(recorder.ranOnMain.count - before, 6, "updates queued behind a busy worker coalesce to the latest")
        _ = window
    }

    func testRebuildWhileComposingNeverAppliesStaleText() async throws {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: "Before the theme change, streaming", isStreaming: true)
        var configuration = view.configuration
        configuration.theme.bodyFont = UIFont.systemFont(ofSize: 23)
        view.configuration = configuration
        await view.pendingDocument?.value
        let font = try XCTUnwrap(view.textView.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        XCTAssertEqual(font.pointSize, configuration.theme.scaled(for: view.traitCollection).bodyFont.pointSize, accuracy: 0.5)
        XCTAssertEqual(view.textView.textStorage.string, "Before the theme change, streaming")
        _ = window
    }
}

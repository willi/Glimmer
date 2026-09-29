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

/// Holds the first nonempty worker request while the main actor changes the view.
private final class HeldWorkerExtension: GlimmerExtension, @unchecked Sendable {
    private let lock = NSLock()
    private let release = DispatchSemaphore(value: 0)
    private var requests: [String] = []
    private var timedOut = false

    var workerRequests: [String] { lock.withLock { requests } }
    var didTimeOut: Bool { lock.withLock { timedOut } }

    func preprocess(_ markdown: String) -> String {
        // Initial configuration and the rebuild are synchronous: never block the main actor.
        guard !markdown.isEmpty, !Thread.isMainThread else { return markdown }
        let shouldHold = lock.withLock {
            requests.append(markdown)
            return requests.count == 1
        }
        if shouldHold, release.wait(timeout: .now() + 5) == .timedOut {
            lock.withLock { timedOut = true }
        }
        return markdown
    }

    func resume() { release.signal() }
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
        let held = HeldWorkerExtension()
        defer { held.resume() }
        var configuration = GlimmerConfiguration(extensions: [held], imageLoader: nil)
        configuration.reveal = .none
        let view = GlimmerView(configuration: configuration)
        let window = hostInWindow(view, width: 390, height: 800)
        var markdown = "one "
        view.update(markdown: markdown, isStreaming: true)
        let started = await waitUntil { !held.workerRequests.isEmpty }
        guard started else { return XCTFail("the first request never entered the worker") }
        for word in ["two", "three", "four", "five", "six"] {
            markdown += word + " "
            view.update(markdown: markdown, isStreaming: true)
        }
        held.resume()
        await view.pendingDocument?.value
        // CommonMark drops a paragraph's trailing space.
        XCTAssertEqual(view.textView.textStorage.string, "one two three four five six")
        XCTAssertEqual(held.workerRequests, ["one ", markdown], "only the latest request queued behind the held worker is composed")
        XCTAssertFalse(held.didTimeOut, "the test releases the worker, not its safety timeout")
        _ = window
    }

    func testRebuildWhileComposingNeverAppliesStaleText() async throws {
        let held = HeldWorkerExtension()
        defer { held.resume() }
        let view = GlimmerView(configuration: GlimmerConfiguration(extensions: [held], imageLoader: nil))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: "Before the theme change, streaming", isStreaming: true)
        let started = await waitUntil { !held.workerRequests.isEmpty }
        guard started else { return XCTFail("the old request never entered the worker") }
        var configuration = view.configuration
        configuration.theme.bodyFont = UIFont.systemFont(ofSize: 23)
        view.configuration = configuration
        held.resume()
        await view.pendingDocument?.value
        XCTAssertFalse(held.didTimeOut, "the test releases the worker, not its safety timeout")
        let font = try XCTUnwrap(view.textView.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        XCTAssertEqual(font.pointSize, configuration.theme.scaled(for: view.traitCollection).bodyFont.pointSize, accuracy: 0.5)
        XCTAssertEqual(view.textView.textStorage.string, "Before the theme change, streaming")
        _ = window
    }
}

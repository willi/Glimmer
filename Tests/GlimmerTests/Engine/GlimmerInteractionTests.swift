import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerInteractionTests: XCTestCase {
    private let pasteboard = UIPasteboard(name: UIPasteboard.Name("glimmer.test.copy"), create: true)!

    private func string(_ type: String) -> String? {
        let value = pasteboard.items.first?[type]
        if let string = value as? String { return string }
        if let data = value as? Data { return String(data: data, encoding: .utf8) }
        return nil
    }

    private func settledView(_ markdown: String) -> (GlimmerView, UIWindow) {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: markdown)
        view.textView.pasteboard = pasteboard
        return (view, window)
    }

    func testCopyWritesPlainTextAndMarkdown() {
        let (view, window) = settledView("Some **bold** text.\n\n- item")
        view.textView.selectedRange = NSRange(location: 0, length: view.textView.textStorage.length)
        view.textView.copy(nil)
        XCTAssertEqual(string(UTType.utf8PlainText.identifier), "Some bold text.\n- item")
        XCTAssertEqual(string("net.daringfireball.markdown"), "Some **bold** text.\n\n- item")
        _ = window
    }

    func testSelectionNeverReachesUnrevealedText() async throws {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let clock = ManualRevealClock()
        view.clock = clock
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: String(repeating: "Streaming words arrive one phrase at a time. ", count: 8), isStreaming: true)
        await view.pendingDocument?.value
        clock.advance(to: 0.2)
        let revealed = try XCTUnwrap(view.engine).revealedLength
        XCTAssertLessThan(revealed, view.textView.textStorage.length)
        view.textView.selectedRange = NSRange(location: 0, length: view.textView.textStorage.length)
        view.textViewDidChangeSelection(view.textView)
        XCTAssertLessThanOrEqual(NSMaxRange(view.textView.selectedRange), revealed)
        _ = window
    }

    func testCopyWhileStreamingCopiesOnlyRevealedText() async throws {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let clock = ManualRevealClock()
        view.clock = clock
        let window = hostInWindow(view, width: 390, height: 800)
        view.textView.pasteboard = pasteboard
        let answer = String(repeating: "Streaming words arrive one phrase at a time. ", count: 8)
        view.update(markdown: answer, isStreaming: true)
        await view.pendingDocument?.value
        clock.advance(to: 0.2)
        view.textView.selectedRange = NSRange(location: 0, length: view.textView.textStorage.length)
        view.textViewDidChangeSelection(view.textView)
        view.textView.copy(nil)
        let copied = try XCTUnwrap(string(UTType.utf8PlainText.identifier))
        XCTAssertLessThan(copied.count, answer.count)
        XCTAssertTrue(answer.hasPrefix(copied))
        _ = window
    }

    func testEditMenuAddsHostActions() throws {
        let (view, window) = settledView("Ask about this sentence.")
        var received: GlimmerSelection?
        view.editMenuActions = { selection in
            received = selection
            return [UIAction(title: "Ask SuperMe") { _ in }]
        }
        let range = (view.textView.textStorage.string as NSString).range(of: "this sentence")
        let menu = try XCTUnwrap(view.textView(view.textView, editMenuForTextIn: range, suggestedActions: []))
        XCTAssertTrue(menu.children.contains { ($0 as? UIAction)?.title == "Ask SuperMe" })
        XCTAssertEqual(received?.plainText, "this sentence")
        XCTAssertEqual(received?.markdown, "this sentence")
        _ = window
    }

    func testLinkMenuKeepsTheDefaultAndAddsHostItems() {
        let (view, window) = settledView("[docs](https://example.com)")
        view.linkMenuActions = { url in [UIAction(title: "Open in App \(url.host() ?? "")") { _ in }] }
        let menu = view.linkMenu(for: URL(string: "https://example.com")!,
                                 defaultMenu: UIMenu(children: [UIAction(title: "Copy Link") { _ in }]))
        XCTAssertEqual(menu.children.compactMap { ($0 as? UIAction)?.title }, ["Copy Link", "Open in App example.com"])
        _ = window
    }

    func testCopyInsideACodeBlockCopiesTheCodeAsIs() {
        let code = GlimmerCodeBlockView(code: "let snake_case = 1", language: "swift", theme: .default,
                                        highlighter: GlimmerBasicHighlighter())
        code.textView.pasteboard = pasteboard
        code.textView.selectedRange = NSRange(location: 0, length: code.textView.textStorage.length)
        code.textView.copy(nil)
        XCTAssertEqual(pasteboard.string, "let snake_case = 1")
        XCTAssertNil(string("net.daringfireball.markdown"), "code copies as code, not as escaped markdown")
    }

    func testDataDetectorsAndFindFollowTheConfiguration() {
        var configuration = GlimmerConfiguration(imageLoader: nil)
        XCTAssertEqual(GlimmerView(configuration: configuration).textView.dataDetectorTypes, [])
        configuration.dataDetectors = [.phoneNumber, .link]
        configuration.allowsFind = true
        let view = GlimmerView(configuration: configuration)
        XCTAssertEqual(view.textView.dataDetectorTypes, [.phoneNumber, .link])
        XCTAssertTrue(view.textView.isFindInteractionEnabled)
    }

    func testFindCanBePresentedByTheHost() {
        var configuration = GlimmerConfiguration(imageLoader: nil)
        XCTAssertNil(GlimmerView(configuration: configuration).findInteraction)
        configuration.allowsFind = true
        XCTAssertNotNil(GlimmerView(configuration: configuration).findInteraction)
    }
}

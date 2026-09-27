import UIKit
import XCTest
@testable import Glimmer

/// The basic highlighter, counting the calls made on the main thread.
final class ThreadRecordingHighlighter: GlimmerHighlighter, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private let base = GlimmerBasicHighlighter()

    var mainThreadCalls: Int { lock.withLock { calls } }

    func highlight(_ code: String, language: String?) -> [GlimmerHighlightSpan] {
        if Thread.isMainThread { lock.withLock { calls += 1 } }
        return base.highlight(code, language: language)
    }
}

@MainActor
final class GlimmerCodeHighlightingTests: XCTestCase {
    private let theme = GlimmerTheme.default

    private func streamingView(highlighter: any GlimmerHighlighter) -> (GlimmerView, UIWindow) {
        var configuration = GlimmerConfiguration(imageLoader: nil, highlighter: highlighter)
        configuration.reveal = .none
        let view = GlimmerView(configuration: configuration)
        return (view, hostInWindow(view, width: 390, height: 800))
    }

    func testStreamingCodeIsNeverHighlightedOnMain() async throws {
        let highlighter = ThreadRecordingHighlighter()
        let (view, window) = streamingView(highlighter: highlighter)
        var markdown = "Here:\n\n```swift\n"
        for line in 1...20 {
            markdown += "let value\(line) = \(line) // line \(line)\n"
            view.update(markdown: markdown, isStreaming: true)
            await view.pendingDocument?.value
            settle(view)
        }
        XCTAssertNotNil(findSubview(GlimmerCodeBlockView.self, in: view), "the code view was made on main")
        XCTAssertEqual(highlighter.mainThreadCalls, 0)
        _ = window
    }

    func testAClosingCommentRecolorsEarlierLines() async throws {
        let (view, window) = streamingView(highlighter: GlimmerBasicHighlighter())
        view.update(markdown: "```c\n/* a\nb\n", isStreaming: true)
        await view.pendingDocument?.value
        settle(view)
        view.update(markdown: "```c\n/* a\nb\n*/\nint c;\n", isStreaming: true)
        await view.pendingDocument?.value
        settle(view)
        let code = try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: view)).textView.textStorage
        let string = code.string as NSString
        let color = { (word: String) in code.attribute(.foregroundColor, at: string.range(of: word).location, effectiveRange: nil) as? UIColor }
        XCTAssertEqual(color("b"), theme.syntaxCommentColor, "inside the now-closed comment")
        XCTAssertEqual(color("int"), theme.syntaxKeywordColor, "after it")
        _ = window
    }

    func testTheComposerHighlightsTheEmbed() throws {
        let text = GlimmerComposer(theme: theme).compose(GlimmerParser.parse("```swift\nlet x = 1\n```"))
        let attachment = try XCTUnwrap(blockAttachments(in: text).first)
        guard case .codeBlock(_, _, let highlighted) = attachment.embed else { return XCTFail("expected code") }
        let keyword = try XCTUnwrap(highlighted).attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        XCTAssertEqual(keyword, theme.syntaxKeywordColor)
    }
}

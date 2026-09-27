import UIKit
import XCTest
@testable import Glimmer

/// A code block's first frame costs about three times a warmed view's: its first layout sets up the text view. While a
/// view streams, the pool keeps one code block view built and laid out, ready for the next fence.
@MainActor
final class GlimmerEmbedViewPoolTests: XCTestCase {
    override func setUp() async throws {
        GlimmerEmbedViewPool.shared.removeAll()
    }

    func testAStreamingViewPreparesACodeBlockView() async {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: "An answer begins", isStreaming: true, revealID: "pool")
        let prepared = await waitUntil { GlimmerEmbedViewPool.shared.hasCodeBlockView(for: GlimmerTheme.default.scaled(for: view.traitCollection)) }
        XCTAssertTrue(prepared)
        _ = window
    }

    func testAStreamedCodeBlockTakesThePreparedView() async throws {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let window = hostInWindow(view, width: 390, height: 800)
        let theme = GlimmerTheme.default.scaled(for: view.traitCollection)
        view.update(markdown: "An answer begins", isStreaming: true, revealID: "pool")
        let prepared = await waitUntil { GlimmerEmbedViewPool.shared.hasCodeBlockView(for: theme) }
        XCTAssertTrue(prepared)
        let pooled = try XCTUnwrap(GlimmerEmbedViewPool.shared.peekCodeBlockView(for: theme))
        view.update(markdown: "An answer begins\n\n```swift\nlet x = 1\n```", isStreaming: true, revealID: "pool")
        let shown = await waitUntil {
            let string = view.textView.textStorage.string as NSString
            return (0..<string.length).contains { view.textView.blockAttachment(atCharacter: $0)?.existingView != nil }
        }
        XCTAssertTrue(shown)
        let string = view.textView.textStorage.string as NSString
        let index = try XCTUnwrap((0..<string.length).first { view.textView.blockAttachment(atCharacter: $0) != nil })
        let codeView = try XCTUnwrap(view.textView.blockAttachment(atCharacter: index)?.existingView as? GlimmerCodeBlockView)
        XCTAssertTrue(codeView === pooled, "the fence took the prepared view")
        XCTAssertEqual(codeView.textView.textStorage.string, "let x = 1")
        _ = window
    }

    func testAPooledViewTakesTheBlocksLanguage() {
        let theme = GlimmerTheme.default
        let view = GlimmerCodeBlockView(code: "", language: nil, theme: theme, highlighter: GlimmerBasicHighlighter())
        view.update(to: .codeBlock(language: "swift", code: "let x = 1", highlighted: nil))
        XCTAssertEqual(view.languageLabel.text, "swift")
        XCTAssertEqual(view.textView.accessibilityLabel, GlimmerStrings.code(language: "swift"))
    }
}

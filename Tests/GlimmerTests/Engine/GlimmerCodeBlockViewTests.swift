import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerCodeBlockViewTests: XCTestCase {
    private let theme = GlimmerTheme.default

    func testRuleViewHeightIsPaddingAroundAHairline() {
        let rule = GlimmerRuleView(theme: theme)
        XCTAssertEqual(rule.embedHeight(forWidth: 300), theme.blockSpacing + 1)
        XCTAssertEqual(rule.embedHeight(forWidth: 900), theme.blockSpacing + 1)
    }

    func testBasicHighlighterFindsSwiftTokens() {
        // "let" is 0..<3, "\"hi\"" is 8..<12, "// note 42" is 13..<23.
        let code = #"let x = "hi" // note 42"#
        let spans = GlimmerBasicHighlighter().highlight(code, language: "swift")
        XCTAssertTrue(spans.contains(GlimmerHighlightSpan(range: NSRange(location: 0, length: 3), kind: .keyword)))
        XCTAssertTrue(spans.contains(GlimmerHighlightSpan(range: NSRange(location: 8, length: 4), kind: .string)))
        XCTAssertTrue(spans.contains(GlimmerHighlightSpan(range: NSRange(location: 13, length: 10), kind: .comment)))
        // The comment is applied last so it wins over the number inside it.
        XCTAssertEqual(spans.last?.kind, .comment)
    }

    func testCommentMarkersInsideStringsStayString() {
        // The string is 8..<23; the real comment "// c" is 24..<28.
        let spans = GlimmerBasicHighlighter().highlight(#"let u = "https://x.y/z" // c"#, language: "swift")
        XCTAssertTrue(spans.contains(GlimmerHighlightSpan(range: NSRange(location: 8, length: 15), kind: .string)))
        XCTAssertEqual(spans.filter { $0.kind == .comment }.map(\.range), [NSRange(location: 24, length: 4)])
    }

    func testQuotesInsideCommentsStayComment() {
        let spans = GlimmerBasicHighlighter().highlight(#"// say "hi" to 42 people"#, language: "swift")
        XCTAssertEqual(spans.map(\.kind), [.comment])
    }

    func testUnknownLanguageHasNoSpans() {
        XCTAssertEqual(GlimmerBasicHighlighter().highlight("let x = 1", language: "klingon"), [])
        XCTAssertEqual(GlimmerBasicHighlighter().highlight("let x = 1", language: nil), [])
    }

    func testHighlightedCodeColorsKeywords() {
        let text = GlimmerCodeBlockView.highlightedCode("let x = 1", language: "swift", theme: theme, highlighter: GlimmerBasicHighlighter())
        let color = text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        XCTAssertEqual(color, theme.syntaxKeywordColor)
        XCTAssertEqual(text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont, theme.codeFont)
    }

    func testCodeBlockHeightIgnoresWidthAndLongLinesScroll() {
        let longLine = "let value = \"" + String(repeating: "x", count: 400) + "\""
        let view = GlimmerCodeBlockView(code: longLine, language: "swift", theme: theme, highlighter: GlimmerBasicHighlighter())
        let height = view.embedHeight(forWidth: 300)
        XCTAssertEqual(height, view.embedHeight(forWidth: 600))
        XCTAssertGreaterThan(height, GlimmerCodeBlockView.headerHeight + theme.embedPadding * 2)

        let window = hostInWindow(view, width: 300, height: height)
        XCTAssertGreaterThan(view.scrollView.contentSize.width, 300, "long lines scroll instead of wrapping")
        XCTAssertLessThan(view.scrollView.contentSize.width, 10_000)
        XCTAssertGreaterThanOrEqual(view.textView.frame.width, view.textSize.width, "the code is laid out unwrapped")
        _ = window
    }

    func testCopyButtonCopiesTheCode() throws {
        let view = GlimmerCodeBlockView(code: "print(1)", language: "python", theme: theme, highlighter: GlimmerBasicHighlighter())
        // Reading the general pasteboard is not authorized in the test runner, so copy into a private one.
        let pasteboard = try XCTUnwrap(UIPasteboard(name: UIPasteboard.Name("glimmer.tests.copy"), create: true))
        pasteboard.string = ""
        view.pasteboard = pasteboard
        view.copyButton.sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(pasteboard.string, "print(1)")
        XCTAssertEqual(view.copyButton.accessibilityLabel, "Copy code")
    }

    func testHeaderShowsLanguage() {
        let view = GlimmerCodeBlockView(code: "x", language: "Swift", theme: theme, highlighter: GlimmerBasicHighlighter())
        XCTAssertEqual(view.languageLabel.text, "swift")
        let plain = GlimmerCodeBlockView(code: "x", language: nil, theme: theme, highlighter: GlimmerBasicHighlighter())
        XCTAssertEqual(plain.languageLabel.text, "code")
    }

    func testRevealingCodeBlockHidesLinesNotYetShown() throws {
        let view = GlimmerCodeBlockView(code: "one\ntwo\nthree", language: nil, theme: theme, highlighter: GlimmerBasicHighlighter())
        view.visibleUnitCount = 1
        let height = view.embedHeight(forWidth: 300)
        view.frame = CGRect(x: 0, y: 0, width: 300, height: height)
        view.layoutIfNeeded()
        let firstLineBottom = try XCTUnwrap(view.revealUnitRects(in: view.bounds).first).maxY
        // Glyphs are clipped at the shown line, so the next line never peeks into the bottom padding.
        XCTAssertLessThanOrEqual(view.scrollView.frame.maxY, height - theme.embedPadding + 0.5)
        XCTAssertLessThanOrEqual(view.scrollView.frame.maxY, firstLineBottom)
        view.visibleUnitCount = nil
        view.frame.size.height = view.embedHeight(forWidth: 300)
        view.layoutIfNeeded()
        XCTAssertEqual(view.scrollView.frame.maxY, view.bounds.height, accuracy: 0.5, "a settled code block scrolls over its full height")
    }
}

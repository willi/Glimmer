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

    func testEachNewLanguageHighlightsItsTokens() {
        let highlighter = GlimmerBasicHighlighter()
        func kinds(_ code: String, _ language: String) -> [String: GlimmerHighlightSpan.Kind] {
            let string = code as NSString
            return Dictionary(highlighter.highlight(code, language: language).map { (string.substring(with: $0.range), $0.kind) },
                              uniquingKeysWith: { first, _ in first })
        }
        let samples: [(language: String, code: String, keyword: String, string: String?, comment: String?)] = [
            ("json", #"{"name": "Ada", "ok": true}"#, #""name""#, #""Ada""#, nil),
            ("sql", "select name from users -- all\nWHERE id = 'x'", "select", "'x'", "-- all"),
            ("yaml", "name: \"Ada\" # who\nok: true", "name", "\"Ada\"", "# who"),
            ("html", #"<a href="/x">Go</a> <!-- note -->"#, "<a", #""/x""#, "<!-- note -->"),
            ("css", "@media screen { .a { color: red; /* c */ } }", "@media", nil, "/* c */"),
            ("csharp", "public class A { string s = \"x\"; } // c", "public", "\"x\"", "// c"),
            ("php", "<?php function f() { echo 'x'; } # c", "function", "'x'", "# c"),
        ]
        for sample in samples {
            let found = kinds(sample.code, sample.language)
            XCTAssertEqual(found[sample.keyword], .keyword, "\(sample.language) keyword \(sample.keyword): \(found)")
            if let string = sample.string { XCTAssertEqual(found[string], .string, "\(sample.language) string") }
            if let comment = sample.comment { XCTAssertEqual(found[comment], .comment, "\(sample.language) comment") }
        }
    }

    func testTheRegexIsBuiltOncePerFamily() throws {
        let swift = try XCTUnwrap(GlimmerBasicHighlighter.expression(for: "swift"))
        XCTAssertTrue(swift === GlimmerBasicHighlighter.expression(for: "Swift"))
        XCTAssertTrue(GlimmerBasicHighlighter.expression(for: "yml") === GlimmerBasicHighlighter.expression(for: "yaml"))
        XCTAssertNil(GlimmerBasicHighlighter.expression(for: "brainfuck"))
    }

    func testUnknownLanguageHasNoSpans() {
        XCTAssertEqual(GlimmerBasicHighlighter().highlight("let x = 1", language: "klingon"), [])
        XCTAssertEqual(GlimmerBasicHighlighter().highlight("let x = 1", language: nil), [])
    }

    func testHighlightedCodeColorsKeywords() {
        let text = GlimmerCodeHighlighting.highlightedCode("let x = 1", language: "swift", theme: theme, highlighter: GlimmerBasicHighlighter())
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

    func testStreamedCodeMatchesAFreshCodeBlock() {
        let highlighter = GlimmerBasicHighlighter()
        let final = "let a = 1\n/* a comment\nthat spans lines */\nlet b = \"two\"\nlet widerLine = compute(value: 42, scale: 2.5)"
        let streamed = GlimmerCodeBlockView(code: "let a = 1\n/* a comment", language: "swift", theme: theme, highlighter: highlighter)
        // Grows line by line; the closing */ recolors a line that was already shown.
        for end in ["let a = 1\n/* a comment\nthat spans", "let a = 1\n/* a comment\nthat spans lines */", final] {
            streamed.update(to: .codeBlock(language: "swift", code: end))
        }
        let fresh = GlimmerCodeBlockView(code: final, language: "swift", theme: theme, highlighter: highlighter)
        XCTAssertTrue(streamed.textView.textStorage.isEqual(to: fresh.textView.textStorage), "same text and colors")
        XCTAssertEqual(streamed.textSize, fresh.textSize)
        XCTAssertEqual(streamed.embedHeight(forWidth: 300), fresh.embedHeight(forWidth: 300))
    }

    func testStreamedCodeMatchesAFreshHighlightAtEveryStep() {
        let theme = GlimmerTheme.default
        let highlighter = GlimmerBasicHighlighter()
        let code = """
        /* A header comment
           that spans lines */
        let greeting = "Hello, world" // trailing
        func count(to limit: Int) -> Int {
            var total = 0 /* inline */ + 42
            return total
        }
        """
        // Swift recolours as it streams; plain code is one colour run the whole way.
        for language in ["swift", nil] as [String?] {
            let view = GlimmerCodeBlockView(code: "", language: language, theme: theme, highlighter: highlighter)
            var end = code.startIndex
            while end < code.endIndex {
                end = code.index(end, offsetBy: 3, limitedBy: code.endIndex) ?? code.endIndex
                let prefix = String(code[..<end])
                let fresh = GlimmerCodeHighlighting.highlightedCode(prefix, language: language, theme: theme, highlighter: highlighter)
                view.update(to: .codeBlock(language: language, code: prefix, highlighted: fresh))
                XCTAssertTrue(view.textView.textStorage.isEqual(to: fresh), "\(language ?? "plain") after \(prefix.count) characters")
            }
        }
    }

    func testColorRunsDescribeTheHighlight() {
        let theme = GlimmerTheme.default
        let text = GlimmerCodeHighlighting.highlightedCode("let x = 1 // c", language: "swift", theme: theme, highlighter: GlimmerBasicHighlighter())
        let runs = GlimmerCodeBlockView.colorRuns(of: text)
        XCTAssertEqual(runs.first?.range.location, 0)
        XCTAssertEqual(runs.map(\.range.length).reduce(0, +), text.length)
        XCTAssertTrue(runs.contains { $0.color == theme.syntaxCommentColor })
    }

    /// The colour-run diff also handles code that shrinks (a healed fence dropped) and a language that changes (the info
    /// string completing): the text and colours match a fresh block at each step.
    func testStreamedCodeThatShrinksOrChangesLanguageMatchesAFreshHighlight() {
        let theme = GlimmerTheme.default
        let highlighter = GlimmerBasicHighlighter()
        let view = GlimmerCodeBlockView(code: "", language: "sw", theme: theme, highlighter: highlighter)
        let steps: [(String?, String)] = [
            ("sw", "let a = 1\nlet b = \"two\" // three"),
            ("swift", "let a = 1\nlet b = \"two\" // three"),
            ("swift", "let a = 1"),
            ("python", "let a = 1\ndef b(): return 2"),
            (nil, "plain"),
        ]
        for (language, code) in steps {
            let fresh = GlimmerCodeHighlighting.highlightedCode(code, language: language, theme: theme, highlighter: highlighter)
            view.update(to: .codeBlock(language: language, code: code, highlighted: fresh))
            XCTAssertTrue(view.textView.textStorage.isEqual(to: fresh), "\(language ?? "plain"): \(code)")
            XCTAssertEqual(view.languageLabel.text, language ?? "code", "the header follows the language")
        }
    }
}

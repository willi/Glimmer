import XCTest
@testable import Glimmer

final class GlimmerTailHealerTests: XCTestCase {
    private let cases: [(input: String, healed: String)] = [
        ("Hello **wor", "Hello **wor**"),
        ("Hello __wor", "Hello __wor__"),
        ("a _b", "a _b_"),
        ("snake_case_name", "snake_case_name"),
        ("Title\n-", "Title\n"),
        // Footnotes: a marker still being typed waits; a complete one shows; a line that may start a definition waits.
        ("see [^1", "see "),
        ("see [^", "see "),
        ("see [^1]", "see [^1]"),
        ("text\n\n[^1]", "text\n\n"),
        ("text\n\n[^1]:", "text\n\n"),
        ("text\n\n[^1]\n[^2]", "text\n\n[^1]\n"),
        // A body row that is only its opening pipe would parse as a paragraph "|" below the table.
        ("| A |\n|---|\n| ", "| A |\n|---|\n"),
        ("| A |\n|---|\n| x |\n|", "| A |\n|---|\n| x |\n"),
        ("Title\n---", "Title\n"),
        ("text\n\n---", "text\n\n---"),
        ("Hello **wor ", "Hello **wor** "),
        ("Hello **", "Hello "),
        ("**b *", "**b** "),
        ("a *b **c", "a *b **c***"),
        ("use `co", "use `co`"),
        ("**a `b", "**a `b`**"),
        ("~~old", "~~old~~"),
        ("* item **b", "* item **b**"),
        ("```swift\nlet x", "```swift\nlet x\n```"),
        ("~~~\ncode\n", "~~~\ncode\n~~~"),
        ("1. Install:\n\n   ```bash\n   npm i", "1. Install:\n\n   ```bash\n   npm i\n   ```"),
        ("1. ```sh\n   ls", "1. ```sh\n   ls\n   ```"),
        ("> ```swift\n> let x", "> ```swift\n> let x\n> ```"),
        ("para\n\n| a | b |\n|--", "para\n\n"),
        ("| a | b |\n|---|", ""),
        ("| a | b |\n|---|-", "| a | b |\n|---|-"),
        ("see [docs](https://ex", "see [docs](https://ex)"),
        ("see [do", "see do"),
        ("[a](b) c [d", "[a](b) c d"),
        ("see ![alt](http", "see "),
        ("see ![al", "see "),
        ("see [3]", "see "),
        ("para\n\n| a | b |", "para\n\n"),
        ("| a | b |\n|---|---|\n| 1 |", "| a | b |\n|---|---|\n| 1 |"),
        ("text\n\n**Bold", "text\n\n**Bold**"),
        ("**x\n\ny", "**x\n\ny"),
        ("done.", "done."),
        ("`a` and **b**", "`a` and **b**"),
        ("", ""),
    ]

    func testHealsEveryCase() {
        for (input, healed) in cases {
            XCTAssertEqual(GlimmerTailHealer.heal(input), healed, "healing \(input.debugDescription)")
        }
    }

    func testOpenFenceDetection() {
        XCTAssertEqual(GlimmerTailHealer.openFence(in: "````js\nx"), "````")
        XCTAssertNil(GlimmerTailHealer.openFence(in: "```\nx\n```"))
        XCTAssertNil(GlimmerTailHealer.openFence(in: "inline ``` not a fence"))
    }

    func testFenceInsideAListStaysInTheList() {
        let blocks = GlimmerParser.parse(GlimmerTailHealer.heal("1. Install:\n\n   ```bash\n   npm i"))
        XCTAssertEqual(blocks.count, 1, "no phantom top-level code block")
        guard case .list = blocks.first else { return XCTFail("expected a list, got \(blocks)") }
    }

    func testHealedMarkdownRendersWithoutRawMarkers() {
        let text = GlimmerComposerTestHelper.plainText(GlimmerTailHealer.heal("Some **bold and `code"))
        XCTAssertFalse(text.contains("*"))
        XCTAssertFalse(text.contains("`"))
    }

    /// A trailing backslash may escape the next character: shown now, it would vanish when that arrives.
    func testATrailingBackslashIsHeldBack() {
        XCTAssertEqual(GlimmerTailHealer.heal("Not \\"), "Not ")
        XCTAssertEqual(GlimmerTailHealer.heal("Not \\@ada"), "Not \\@ada")
        XCTAssertEqual(GlimmerTailHealer.heal("A path C:\\\\"), "A path C:\\\\", "an escaped backslash stays")
        XCTAssertEqual(GlimmerTailHealer.heal("Run `C:\\"), "Run `C:\\`", "inside code a backslash is text")
    }

    /// A break tag still arriving would show as text, then turn into a line break.
    func testAPartialBreakTagIsHeldBack() {
        for partial in ["One<", "One<b", "One<br", "One<BR", "One<br ", "One<br /"] {
            XCTAssertEqual(GlimmerTailHealer.heal(partial), "One", partial)
        }
        XCTAssertEqual(GlimmerTailHealer.heal("One<br>"), "One<br>")
        XCTAssertEqual(GlimmerTailHealer.heal("a < b"), "a < b", "a comparison")
        XCTAssertEqual(GlimmerTailHealer.heal("One<bold"), "One<bold", "not a break tag")
        XCTAssertEqual(GlimmerTailHealer.heal("Use `a <b"), "Use `a <b`", "inside code a tag is text")
    }

    func testLinkAndFootnoteSyntaxInsideCodeStaysLiteralWhileStreaming() {
        for code in ["array[0", "array[0]", "[label](url", "![alt", "[^note", "[^note]"] {
            for delimiter in ["`", "``", "```"] {
                let source = "Use " + delimiter + code
                let healed = GlimmerTailHealer.heal(source)
                XCTAssertEqual(GlimmerComposerTestHelper.plainText(healed), "Use " + code, source)
            }
        }
    }

    func testCodeSpansMatchTheWholeBacktickRun() {
        XCTAssertEqual(GlimmerTailHealer.heal("Use ``a`[0]"), "Use ``a`[0]``")
        XCTAssertEqual(GlimmerTailHealer.heal("Use ``a`[0]`` then [docs](url"), "Use ``a`[0]`` then [docs](url)")
        XCTAssertEqual(GlimmerTailHealer.heal("Use `array[0` then [docs](url"), "Use `array[0` then [docs](url)")
        XCTAssertEqual(GlimmerTailHealer.heal("Use ``a <b"), "Use ``a <b``")
        XCTAssertEqual(GlimmerTailHealer.heal(#"An escaped \` then [docs](url"#), #"An escaped \` then [docs](url)"#)
    }
}

/// Plain rendered text of markdown, for assertions that care only about visible characters.
enum GlimmerComposerTestHelper {
    static func plainText(_ markdown: String) -> String {
        GlimmerParser.parse(markdown).map { block -> String in
            if case .paragraph(let inlines) = block { return GlimmerInline.plainText(inlines) }
            return ""
        }.joined(separator: "\n")
    }
}

import XCTest
@testable import Glimmer

final class GlimmerParserTests: XCTestCase {
    func testParagraphWithInlineStyles() {
        XCTAssertEqual(
            GlimmerParser.parse("Hello **bold** *em* `code` ~~gone~~"),
            [.paragraph([
                .text("Hello "), .strong([.text("bold")]), .text(" "),
                .emphasis([.text("em")]), .text(" "), .code("code"), .text(" "),
                .strikethrough([.text("gone")]),
            ])]
        )
    }

    func testHeadingLevels() {
        XCTAssertEqual(
            GlimmerParser.parse("# One\n###### Six"),
            [.heading(level: 1, [.text("One")]), .heading(level: 6, [.text("Six")])]
        )
    }

    func testStrongInsideLinkParsesAsNestedStrong() {
        // Glimmer 1.x leaked the raw `**` here.
        XCTAssertEqual(
            GlimmerParser.parse("[**Ada**](https://superme.ai/u/1)"),
            [.paragraph([.link(destination: "https://superme.ai/u/1", title: nil, [.strong([.text("Ada")])])])]
        )
    }

    func testLooseOrderedListKeepsNumbering() {
        // Glimmer 1.x numbered every loose item "1.".
        guard case .list(let list)? = GlimmerParser.parse("1. one\n\n2. two\n\n3. three").first else {
            return XCTFail("expected a list")
        }
        XCTAssertEqual(list.kind, .ordered(start: 1))
        XCTAssertFalse(list.isTight)
        XCTAssertEqual(list.items.count, 3)
    }

    func testTaskListCheckboxes() {
        guard case .list(let list)? = GlimmerParser.parse("- [x] done\n- [ ] todo\n- plain").first else {
            return XCTFail("expected a list")
        }
        XCTAssertEqual(list.items.map(\.checkbox), [true, false, nil])
        XCTAssertEqual(list.items[0].blocks, [.paragraph([.text("done")])])
    }

    func testFencedCodeKeepsLanguageAndDropsTrailingNewline() {
        XCTAssertEqual(
            GlimmerParser.parse("```swift title=x\nlet x = 1\n```"),
            [.codeBlock(language: "swift", code: "let x = 1")]
        )
        XCTAssertEqual(GlimmerParser.parse("    indented"), [.codeBlock(language: nil, code: "indented")])
    }

    func testTableWithAlignments() {
        XCTAssertEqual(
            GlimmerParser.parse("| a | b |\n|:--|--:|\n| 1 | 2 |"),
            [.table(GlimmerTable(
                alignments: [.left, .right],
                header: [[.text("a")], [.text("b")]],
                rows: [[[.text("1")], [.text("2")]]]
            ))]
        )
    }

    func testBareURLAutolinks() {
        XCTAssertEqual(
            GlimmerParser.parse("Visit https://example.com today"),
            [.paragraph([
                .text("Visit "),
                .link(destination: "https://example.com", title: nil, [.text("https://example.com")]),
                .text(" today"),
            ])]
        )
    }

    func testImageAltTitleAndBreaks() {
        XCTAssertEqual(
            GlimmerParser.parse("![Alt *text*](https://x.y/a.png \"T\")"),
            [.paragraph([.image(source: "https://x.y/a.png", title: "T", alt: "Alt text")])]
        )
        XCTAssertEqual(GlimmerParser.parse("a  \nb"), [.paragraph([.text("a"), .lineBreak, .text("b")])])
        XCTAssertEqual(GlimmerParser.parse("a\nb"), [.paragraph([.text("a"), .softBreak, .text("b")])])
    }

    func testRawHTMLIsKept() {
        XCTAssertEqual(
            GlimmerParser.parse("a <b>x</b>"),
            [.paragraph([.text("a "), .html("<b>"), .text("x"), .html("</b>")])]
        )
    }

    func testBracketedTextStaysOneTextRun() {
        // Extensions scan whole text runs, so cmark's split text nodes must be merged.
        XCTAssertEqual(GlimmerParser.parse("See [3] now"), [.paragraph([.text("See [3] now")])])
    }

    func testEmptyInputHasNoBlocks() {
        XCTAssertEqual(GlimmerParser.parse(""), [])
        XCTAssertEqual(GlimmerParser.parse("   \n\n  "), [])
    }

    func testQuoteContainingListContainingCode() {
        let blocks = GlimmerParser.parse("> 1. step\n>    ```swift\n>    let x = 1\n>    ```")
        guard case .blockQuote(let quoted)? = blocks.first,
              case .list(let list)? = quoted.first else {
            return XCTFail("expected quote > list, got \(blocks)")
        }
        XCTAssertEqual(list.kind, .ordered(start: 1))
        XCTAssertEqual(list.items.first?.blocks, [
            .paragraph([.text("step")]),
            .codeBlock(language: "swift", code: "let x = 1"),
        ])
    }

    func testPlainTextFlattensMarkup() {
        let inlines: [GlimmerInline] = [.text("a "), .strong([.text("b")]), .softBreak, .code("c"), .image(source: "u", title: nil, alt: "d")]
        XCTAssertEqual(GlimmerInline.plainText(inlines), "a b cd")
    }

    func testFenceLanguageStopsAtAnyWhitespace() {
        guard case .codeBlock(let language, _) = GlimmerParser.parse("```swift\tlinenos\nlet x = 1\n```").first else {
            return XCTFail("expected a code block")
        }
        XCTAssertEqual(language, "swift")
    }

    private func checkboxes(_ markdown: String) -> [Bool?] {
        func items(in blocks: [GlimmerBlock]) -> [Bool?] {
            blocks.flatMap { block -> [Bool?] in
                switch block {
                case .list(let list): list.items.flatMap { [$0.checkbox] + items(in: $0.blocks) }
                case .blockQuote(let children): items(in: children)
                default: []
                }
            }
        }
        return items(in: GlimmerParser.parse(markdown))
    }

    /// GitHub shows tasks inside quotes; cmark-gfm's scanner only looked from the start of the line.
    func testTasksInsideAQuoteAreTasks() {
        XCTAssertEqual(checkboxes("> - [x] Done\n> - [ ] Open\n>   > - [x] Nested"), [true, false, true])
    }

    /// Only the item's own brackets say whether it is done.
    func testATaskIsCheckedByItsOwnBrackets() {
        XCTAssertEqual(checkboxes("- [ ] Compare with [x] later\n- [x] Done"), [false, true])
    }
}

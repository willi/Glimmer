import XCTest
@testable import Glimmer

final class RendererEquivalenceTests: XCTestCase {
    func testRendererProducesNonEmptyOutput() {
        let markdown = """
        # Title

        This is **bold** and _italic_, with a [link](http://example.com "Title").

        - Item 1
        - Item 2

        > Quote
        """
        let attributed = Glimmer.parseToAttributedString(markdown)
        XCTAssertFalse(attributed.characters.isEmpty)
    }

    func testRendererHandlesTablesAndFootnotes() {
        let md = """
        | A | B |
        | - | -:|
        | 1 | 2 |

        Paragraph with footnote.[^1]

        [^1]: Footnote text
        """
        let attr = Glimmer.parseToAttributedString(md)
        XCTAssertFalse(attr.characters.isEmpty)
    }


    func testRendererEntryVsDirectBlocksEquality() {
        let markdown = "# H\n\nPara with [link](http://e).\n\n- a\n- b\n\n> q\n\n| H | X |\n| - | - |\n| 1 | 2 |"
        let a = Glimmer.parseToAttributedString(markdown)
        let blocks = MarkdownParser.parse(markdown)
        var r = MarkdownRenderer()
        let b = r.render(blocks: blocks, configuration: .default)
        XCTAssertEqual(a, b)
    }

    func testRepeatedRenderIsStable() {
        let markdown = "# Title\n\nThis is **bold** and _italic_.\n\n- Item 1\n- Item 2\n\n> Quote\n\n| A | B |\n| - | - |\n| 1 | 2 |\n\n[^1]\n\n[^1]: footnote"
        let first = Glimmer.parseToAttributedString(markdown)
        let second = Glimmer.parseToAttributedString(markdown)
        XCTAssertEqual(first, second)
    }
}

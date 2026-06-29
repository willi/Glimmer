import XCTest
@testable import Glimmer

final class ListTableParserTests: XCTestCase {
    func testListParsing() {
        let md = """
        - A
        - B
        1. C
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertTrue(blocks.contains { if case .list = $0 { return true } else { return false } })
    }

    func testOrderedListParsingAcceptsParenthesisDelimiter() throws {
        let blocks = MarkdownParser.parse("""
        1) One
        2) Two
        """)

        guard case .list(let ordered, _, let items) = try XCTUnwrap(blocks.first) else {
            return XCTFail("Expected ordered list")
        }

        XCTAssertTrue(ordered)
        XCTAssertEqual(items.map(\.marker), ["1)", "2)"])
    }

    func testUnicodeDigitOrderedListMarkerStillParses() throws {
        let blocks = MarkdownParser.parse("""
        ١. One
        ٢. Two
        """)

        guard case .list(let ordered, _, let items) = try XCTUnwrap(blocks.first) else {
            return XCTFail("Expected ordered list")
        }

        XCTAssertTrue(ordered)
        XCTAssertEqual(items.map(\.marker), ["١.", "٢."])
    }

    func testListMarkersRequireFollowingSpace() throws {
        let blocks = MarkdownParser.parse("""
        -not a list
        1.not ordered
        """)

        XCTAssertEqual(blocks.count, 1)
        guard case .paragraph(let children) = try XCTUnwrap(blocks.first) else {
            return XCTFail("Expected paragraph")
        }

        XCTAssertEqual(children, [.text("-not a list\n1.not ordered")])
    }

    func testDifferentUnorderedMarkersStartSeparateLists() throws {
        let blocks = MarkdownParser.parse("""
        - A
        * B
        """)

        XCTAssertEqual(blocks.count, 2)
        guard case .list(false, _, let firstItems) = blocks[0],
              case .list(false, _, let secondItems) = blocks[1] else {
            return XCTFail("Expected separate unordered lists")
        }

        XCTAssertEqual(firstItems.map(\.marker), ["-"])
        XCTAssertEqual(secondItems.map(\.marker), ["*"])
    }

    func testLooseOrderedListCoalescesIntoOneList() throws {
        // A loose ordered list (items separated by blank lines) must parse as a
        // single ordered list. Otherwise each item becomes its own single-item
        // list and ordered numbering restarts at "1." for every item.
        let blocks = MarkdownParser.parse("""
        1. First

        2. Second

        3. Third
        """)

        let orderedLists = blocks.compactMap { block -> [MarkdownParser.ListItem]? in
            if case .list(true, _, let items) = block { return items }
            return nil
        }
        XCTAssertEqual(orderedLists.count, 1, "Expected one ordered list, got \(orderedLists.count)")
        XCTAssertEqual(orderedLists.first?.map(\.marker), ["1.", "2.", "3."])

        guard case .list(true, let tight, _) = try XCTUnwrap(blocks.first) else {
            return XCTFail("Expected ordered list")
        }
        XCTAssertFalse(tight, "Blank-line-separated items make a loose list")
    }

    func testLooseListDoesNotStealTrailingParagraph() throws {
        // The blank line(s) after the last item, plus the following paragraph,
        // must remain a separate block (the subsequent-item loop rolls back past
        // skipped blanks when no continuing marker follows).
        let blocks = MarkdownParser.parse("""
        1. First

        2. Second

        Not a list item.
        """)

        guard case .list(true, _, let items) = try XCTUnwrap(blocks.first) else {
            return XCTFail("Expected ordered list first")
        }
        XCTAssertEqual(items.map(\.marker), ["1.", "2."])
        XCTAssertTrue(
            blocks.contains { if case .paragraph = $0 { return true } else { return false } },
            "Trailing paragraph should survive as its own block"
        )
    }

    func testTableParsing() {
        let md = """
        | H1 | H2 |
        |:---|---:|
        | a  |  b |
        """
        let blocks = MarkdownParser.parse(md)
        guard case .table(let header, let rows) = blocks.first(where: { if case .table = $0 { return true } else { return false } }) else {
            return XCTFail("Expected a table block")
        }
        XCTAssertEqual(header.count, 2)
        XCTAssertEqual(rows.count, 1)
    }

    func testTableParsingPreservesEmptyCellsAndAlignments() {
        let md = """
        | Left |  | Right |
        |:---:|---|---:|
        | a | | c |
        """
        let blocks = MarkdownParser.parse(md)
        guard case .table(let header, let rows) = blocks.first(where: { if case .table = $0 { return true } else { return false } }) else {
            return XCTFail("Expected a table block")
        }

        XCTAssertEqual(header.map(\.alignment), [.center, .left, .right])
        XCTAssertEqual(header.map(\.content), [[.text("Left")], [], [.text("Right")]])
        XCTAssertEqual(rows.first?.map(\.content), [[.text("a")], [], [.text("c")]])
    }

    func testTableParsingPreservesUnicodeCells() {
        let md = """
        | Greeting | Status |
        |---|---|
        | こんにちは | ✅ |
        """
        let blocks = MarkdownParser.parse(md)
        guard case .table(let header, let rows) = blocks.first(where: { if case .table = $0 { return true } else { return false } }) else {
            return XCTFail("Expected a table block")
        }

        XCTAssertEqual(header.map(\.content), [[.text("Greeting")], [.text("Status")]])
        XCTAssertEqual(rows.first?.map(\.content), [[.text("こんにちは")], [.text("✅")]])
    }

    func testTableParsingKeepsInlineMarkdownInASCIICells() throws {
        let md = """
        | Em | Link | Code | GitHub | SHA |
        |---|---|---|---|---|
        | *styled* | [site](https://example.com) | `code` | @octo #42 :rocket: owner/repo | deadbeefdeadbeefdeadbeefdeadbeefdeadbeef |
        """
        let blocks = MarkdownParser.parse(md, configuration: .github)
        guard case .table(_, let rows) = blocks.first else {
            return XCTFail("Expected a table block")
        }
        let cells = try XCTUnwrap(rows.first)

        XCTAssertEqual(cells.count, 5)
        XCTAssertTrue(cells[0].content.contains { if case .emphasis = $0 { return true } else { return false } })
        XCTAssertTrue(cells[1].content.contains { if case .link = $0 { return true } else { return false } })
        XCTAssertTrue(cells[2].content.contains { if case .code("code") = $0 { return true } else { return false } })
        XCTAssertTrue(cells[3].content.contains { if case .mention("octo") = $0 { return true } else { return false } })
        XCTAssertTrue(cells[3].content.contains { if case .issueReference(42) = $0 { return true } else { return false } })
        XCTAssertTrue(cells[3].content.contains { if case .repositoryReference("owner", "repo") = $0 { return true } else { return false } })
        XCTAssertTrue(cells[4].content.contains {
            if case .commitSHA("deadbeefdeadbeefdeadbeefdeadbeefdeadbeef", "deadbee") = $0 {
                return true
            }
            return false
        })
    }
}

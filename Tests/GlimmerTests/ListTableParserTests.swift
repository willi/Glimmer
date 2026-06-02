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
}


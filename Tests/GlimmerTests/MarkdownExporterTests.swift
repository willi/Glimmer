import XCTest
@testable import Glimmer

final class MarkdownExporterTests: XCTestCase {
    func testExporterPreservesTableAlignmentFromAST() {
        let markdown = """
        | A | B |
        | :-: | ---: |
        | 1 | 2 |
        """

        let blocks = MarkdownParser.parse(markdown)
        let exported = MarkdownExporter.export(blocks)
        let lines = exported.split(separator: "\n").map(String.init)

        XCTAssertGreaterThanOrEqual(lines.count, 2)
        let separatorCells = lines[1]
            .split(separator: "|", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        XCTAssertGreaterThanOrEqual(separatorCells.count, 2)
        XCTAssertTrue(separatorCells[0].hasPrefix(":") && separatorCells[0].hasSuffix(":"))
        XCTAssertTrue(separatorCells[1].hasSuffix(":"))
    }
}

import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerTableViewTests: XCTestCase {
    private let theme = GlimmerTheme.default

    private func cell(_ text: String, header: Bool = false) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: header ? theme.tableHeaderFont : theme.tableFont])
    }

    func testShortTableFillsTheWidth() {
        let table = GlimmerTableView(
            header: [cell("a", header: true), cell("b", header: true)],
            rows: [[cell("1"), cell("2")]],
            alignments: [.left, .right],
            theme: theme
        )
        let layout = table.layout(forWidth: 300)
        XCTAssertEqual(layout.contentWidth, 300, accuracy: 0.5)
        XCTAssertEqual(layout.rowHeights.count, 2)
        XCTAssertEqual(table.embedHeight(forWidth: 300), layout.height)

        let window = hostInWindow(table, width: 300, height: layout.height)
        XCTAssertLessThanOrEqual(table.scrollView.contentSize.width, 300.5)
        _ = window
    }

    func testWideTableScrollsHorizontally() {
        let header = (0..<6).map { cell("Column number \($0)", header: true) }
        let row = (0..<6).map { cell("Some longer cell value \($0)") }
        let table = GlimmerTableView(header: header, rows: [row], alignments: Array(repeating: .none, count: 6), theme: theme)
        let layout = table.layout(forWidth: 300)
        XCTAssertGreaterThan(layout.contentWidth, 300)
        let window = hostInWindow(table, width: 300, height: layout.height)
        XCTAssertGreaterThan(table.scrollView.contentSize.width, 300)
        _ = window
    }

    func testLongUnbreakableCellWrapsWithinMaxColumnWidth() {
        let table = GlimmerTableView(
            header: [cell("h", header: true)],
            rows: [[cell(String(repeating: "x", count: 300))]],
            alignments: [.none],
            theme: theme
        )
        let layout = table.layout(forWidth: 300)
        XCTAssertLessThanOrEqual(layout.columnWidths[0], max(theme.maxTableColumnWidth, 300) + 0.5)
        XCTAssertGreaterThan(layout.rowHeights[1], theme.tableFont.lineHeight * 2, "the long cell wraps onto several lines")
    }

    func testAlignmentsMapToLabels() {
        let table = GlimmerTableView(
            header: [cell("a", header: true), cell("b", header: true), cell("c", header: true)],
            rows: [[cell("1"), cell("2"), cell("3")]],
            alignments: [.left, .center, .right],
            theme: theme
        )
        XCTAssertEqual(table.cellLabels[1].map(\.textAlignment), [.left, .center, .right])
    }

    func testRaggedRowsArePadded() {
        let table = GlimmerTableView(
            header: [cell("a", header: true), cell("b", header: true)],
            rows: [[cell("only one")]],
            alignments: [.none, .none],
            theme: theme
        )
        XCTAssertEqual(table.cellLabels[1].count, 2)
    }

    func testLayoutIsCachedPerWidth() {
        let table = GlimmerTableView(header: [cell("a", header: true)], rows: [[cell("1")]], alignments: [.none], theme: theme)
        XCTAssertEqual(table.layout(forWidth: 300), table.layout(forWidth: 300))
        XCTAssertNotEqual(table.layout(forWidth: 300).columnWidths, table.layout(forWidth: 200).columnWidths)
    }
}

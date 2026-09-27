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

    func testGridChangesDoNotAnimate() {
        let cell = { (text: String) in NSAttributedString(string: text) }
        let table = GlimmerTableView(header: [cell("a"), cell("b")], rows: [[cell("1"), cell("2")]], alignments: [.none, .none], theme: .default)
        let window = hostInWindow(table, width: 300, height: 200)
        window.makeKeyAndVisible()
        settle(table)  // commits the grid layer: an uncommitted layer never animates
        XCTAssertNotNil(table.grid.presentation(), "the grid is on screen, so a path change could animate")
        let before = table.grid.path
        table.frame.size.width = 200
        table.layoutIfNeeded()
        XCTAssertNotEqual(table.grid.path, before, "the width change redrew the grid")
        XCTAssertNil(table.grid.animationKeys(), "the grid redraws in place")
        _ = window
    }

    func testUpdateKeepsLabelsForARaggedTableThatDidNotChange() {
        let cell = { (text: String) in NSAttributedString(string: text) }
        let header = [cell("a"), cell("b")]
        let rows = [[cell("1")]]
        let table = GlimmerTableView(header: header, rows: rows, alignments: [.none, .none], theme: .default)
        let label = table.cellLabels[1][0]
        table.update(to: .table(header: header, rows: rows, alignments: [.none, .none]))
        XCTAssertTrue(table.cellLabels[1][0] === label, "an unchanged ragged row keeps its labels")
        let bold = NSAttributedString(string: "1", attributes: [.font: UIFont.boldSystemFont(ofSize: 17)])
        table.update(to: .table(header: header, rows: [[bold]], alignments: [.none, .none]))
        XCTAssertEqual(table.cellLabels[1][0].attributedText?.attribute(.font, at: 0, effectiveRange: nil) as? UIFont,
                       UIFont.boldSystemFont(ofSize: 17), "a restyled cell updates")
    }
}

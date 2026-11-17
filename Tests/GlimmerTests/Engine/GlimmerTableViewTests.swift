import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerTableViewTests: XCTestCase {
    private let theme = GlimmerTheme.default

    private func cell(_ text: String, header: Bool = false) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: header ? theme.tableHeaderFont : theme.tableFont])
    }

    func testShortTableFillsTheWidthAfterResizing() {
        let table = GlimmerTableView(
            header: [cell("a", header: true), cell("b", header: true)],
            rows: [[cell("1"), cell("2")]],
            alignments: [.left, .right],
            theme: theme
        )
        let window = hostInWindow(table, width: 300, height: table.embedHeight(forWidth: 300))
        for width in [CGFloat(300), 200, 300] {
            table.frame.size.width = width
            table.layoutIfNeeded()
            let layout = table.layout(forWidth: width)
            XCTAssertEqual(layout.contentWidth, width, accuracy: 0.5)
            XCTAssertEqual(layout.rowHeights.count, 2)
            XCTAssertEqual(table.embedHeight(forWidth: width), layout.height)
            XCTAssertEqual(table.scrollView.contentSize.width, width, accuracy: 0.5)
        }
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

    func testColumnsShrinkToFitAndWrap() {
        let long = String(repeating: "word ", count: 20)
        let table = GlimmerTableView(
            header: [cell("a", header: true), cell("b", header: true)],
            rows: [[cell("x"), cell("y")], [cell(long), cell(long)]],
            alignments: [.none, .none],
            theme: theme
        )
        let layout = table.layout(forWidth: 320)
        XCTAssertLessThanOrEqual(layout.contentWidth, 320.5)
        XCTAssertGreaterThan(layout.rowHeights[2], layout.rowHeights[1] * 2, "the long cell wraps")
        let window = hostInWindow(table, width: 320, height: table.embedHeight(forWidth: 320))
        XCTAssertLessThanOrEqual(table.scrollView.contentSize.width, table.bounds.width + 0.5)
        _ = window
    }

    func testATableThatFitsAfterShrinkingNeverScrolls() {
        let long = "alpha beta gamma delta epsilon zeta eta theta"
        for width in [CGFloat(301.3), 333.7, 287.1, 320] {
            let table = GlimmerTableView(
                header: [cell("a", header: true), cell("b", header: true), cell("c", header: true)],
                rows: [[cell(long), cell(long + " iota"), cell("x")]],
                alignments: [.none, .none, .none],
                theme: theme
            )
            let window = hostInWindow(table, width: width, height: table.embedHeight(forWidth: width))
            XCTAssertLessThanOrEqual(table.layout(forWidth: width).contentWidth, width)
            XCTAssertLessThanOrEqual(table.scrollView.contentSize.width, table.bounds.width, "no slack at width \(width)")
            _ = window
        }
    }

    func testATableThatFitsIsUnchanged() {
        let table = GlimmerTableView(
            header: [cell("a", header: true), cell("bb", header: true)],
            rows: [[cell("1"), cell("22")]],
            alignments: [.none, .none],
            theme: theme
        )
        let wide = table.layout(forWidth: 600)
        XCTAssertEqual(wide.contentWidth, 600, accuracy: 0.5)
        XCTAssertEqual(wide.columnWidths[1] / wide.columnWidths[0], 1, accuracy: 0.01, "both columns sit at the 44 pt floor")
    }

    func testManyColumnsStillScroll() {
        let header = (0..<8).map { cell("Column number \($0)", header: true) }
        let table = GlimmerTableView(header: header, rows: [], alignments: Array(repeating: .none, count: 8), theme: theme)
        let layout = table.layout(forWidth: 320)
        for width in layout.columnWidths { XCTAssertEqual(width, theme.minTableColumnWidth, accuracy: 0.01) }
        let window = hostInWindow(table, width: 320, height: layout.height)
        XCTAssertGreaterThan(table.scrollView.contentSize.width, 320)
        _ = window
    }

    func testALongUnbrokenWordWrapsWithoutOverlap() {
        let table = GlimmerTableView(
            header: [cell("h", header: true)],
            rows: [[cell(String(repeating: "x", count: 300))]],
            alignments: [.none],
            theme: theme
        )
        let layout = table.layout(forWidth: 200)
        let window = hostInWindow(table, width: 200, height: layout.height)
        let label = table.cellLabels[1][0]
        XCTAssertLessThanOrEqual(label.frame.maxY, layout.height + 0.5)
        XCTAssertGreaterThanOrEqual(layout.rowHeights[1], label.frame.height)
        _ = window
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

    func testLinksInTableCellsHaveAnInteractiveTextView() throws {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil, reveal: .none))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: "| Site |\n| --- |\n| [Open](https://example.com) |")
        settle(view)
        let table = try XCTUnwrap(findSubview(GlimmerTableView.self, in: view))
        let cell = try XCTUnwrap(findSubview(UITextView.self, in: table), "a native text item must receive the link tap")
        XCTAssertTrue(cell.isSelectable)
        XCTAssertFalse(cell.isEditable)
        XCTAssertNotNil(cell.delegate)
        XCTAssertEqual(cell.textStorage.attribute(.link, at: 0, effectiveRange: nil) as? URL,
                       URL(string: "https://example.com"))
        _ = window
    }

    func testTableLinkActionsReachTheHostAndKeepNativeFallback() throws {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil, reveal: .none))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: "| Site |\n| --- |\n| [Open](https://example.com) |")
        settle(view)
        let table = try XCTUnwrap(findSubview(GlimmerTableView.self, in: view))
        let cell = try XCTUnwrap(findSubview(GlimmerTableCellTextView.self, in: table))
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        var tapped: URL?
        var openedNatively = false
        view.onLinkTap = { tapped = $0 }
        let native = UIAction { _ in openedNatively = true }
        let button = UIButton()
        button.addAction(try XCTUnwrap(cell.linkAction(for: url, atCharacter: 0, defaultAction: native)), for: .primaryActionTriggered)
        button.sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(tapped, url)
        XCTAssertFalse(openedNatively)

        let element = try XCTUnwrap(table.accessibilityDataTableCellElement(forRow: 1, column: 0) as? GlimmerTableCellElement)
        XCTAssertTrue(element.accessibilityTraits.contains(.link))
        XCTAssertFalse(element.accessibilityTraits.contains(.staticText), "a link must expose its interactive role to VoiceOver")
        tapped = nil
        XCTAssertTrue(element.accessibilityActivate())
        XCTAssertEqual(tapped, url, "VoiceOver uses the same host callback")
        XCTAssertEqual(table.accessibilityContainerType, .dataTable)
        XCTAssertEqual(table.accessibilityHeaderElements(forColumn: 0)?.count, 1)

        view.onLinkTap = nil
        XCTAssertTrue(cell.linkAction(for: url, atCharacter: 0, defaultAction: native) === native)
        let image = UIGraphicsImageRenderer(bounds: table.bounds).image { table.layer.render(in: $0.cgContext) }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Table with a native link cell"
        attachment.lifetime = .keepAlways
        add(attachment)
        _ = window
    }

    func testTableTokenActionsUseTheCellLocalRange() throws {
        let view = GlimmerView(configuration: GlimmerConfiguration(extensions: [GlimmerMentions()], imageLoader: nil, reveal: .none))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: "Text before the table.\n\n| Person |\n| --- |\n| Meet @ada |")
        settle(view)
        let table = try XCTUnwrap(findSubview(GlimmerTableView.self, in: view))
        let cell = try XCTUnwrap(findSubview(GlimmerTableCellTextView.self, in: table))
        let range = try XCTUnwrap(cell.linkRanges.first)
        let url = try XCTUnwrap(cell.textStorage.attribute(.link, at: range.location, effectiveRange: nil) as? URL)
        var tapped: GlimmerInlineToken?
        view.onTokenTap = { tapped = $0 }
        let native = UIAction { _ in XCTFail("internal token URLs must never open externally") }
        let button = UIButton()
        button.addAction(try XCTUnwrap(cell.linkAction(for: url, atCharacter: range.location, defaultAction: native)),
                         for: .primaryActionTriggered)
        button.sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(tapped?.payload["username"], "ada")
        view.onTokenTap = nil
        XCTAssertNil(cell.linkAction(for: url, atCharacter: range.location, defaultAction: native))
        _ = window
    }

    func testTableLinkAccessibilityFrameHitsTheLinkInAWideCell() throws {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil, reveal: .none))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: "| Site |\n| --- |\n| [GitHub](https://github.com) |")
        settle(view)
        let table = try XCTUnwrap(findSubview(GlimmerTableView.self, in: view))
        let cell = try XCTUnwrap(findSubview(GlimmerTableCellTextView.self, in: table))
        let element = try XCTUnwrap(table.accessibilityDataTableCellElement(forRow: 1, column: 0) as? GlimmerTableCellElement)
        let frame = element.accessibilityFrame
        let cellFrame = UIAccessibility.convertToScreenCoordinates(cell.bounds, in: cell)
        XCTAssertLessThan(frame.width, cellFrame.width / 2, "the link occupies only the leading part of its cell")
        let point = CGPoint(x: frame.midX - cellFrame.minX, y: frame.midY - cellFrame.minY)
        XCTAssertTrue(cell.hitTest(point, with: nil)?.isDescendant(of: cell) == true)
        let position = try XCTUnwrap(cell.closestPosition(to: point))
        let index = cell.offset(from: cell.beginningOfDocument, to: position)
        let linkRange = try XCTUnwrap(cell.linkRanges.first)
        XCTAssertTrue(NSLocationInRange(index, linkRange), "accessibility's center tap must land on a link glyph")
        _ = window
    }

    func testPlainTableCellsKeepTheLabelPathAndCanBecomeLinks() throws {
        let table = GlimmerTableView(header: [cell("Site")], rows: [[cell("plain")]], alignments: [.right], theme: theme)
        XCTAssertNil(findSubview(UITextView.self, in: table))
        let label = table.cellLabels[1][0]
        let linked = NSAttributedString(string: "Open", attributes: [.font: theme.tableFont, .link: URL(string: "https://example.com")!])
        table.update(to: .table(header: [cell("Site")], rows: [[linked]], alignments: [.right]))
        let textView = try XCTUnwrap(findSubview(GlimmerTableCellTextView.self, in: table))
        XCTAssertTrue(table.cellLabels[1][0] === label)
        XCTAssertTrue(label.isHidden)
        XCTAssertEqual(textView.textAlignment, .right)
        table.update(to: .table(header: [cell("Site")], rows: [[cell("plain")]], alignments: [.right]))
        XCTAssertFalse(label.isHidden)
        XCTAssertNil(findSubview(UITextView.self, in: table))
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

    func testAppendingARowKeepsEarlierLabels() {
        let header = [cell("Name"), cell("Value")]
        let rows = (1...3).map { [cell("row \($0)"), cell("\($0)")] }
        let table = GlimmerTableView(header: header, rows: rows, alignments: [.none, .none], theme: .default)
        let before = table.cellLabels.flatMap { $0 }
        table.update(to: .table(header: header, rows: rows + [[cell("row 4"), cell("4")]], alignments: [.none, .none]))
        XCTAssertEqual(table.cellLabels.count, 5)
        XCTAssertTrue(zip(before, table.cellLabels.prefix(4).flatMap { $0 }).allSatisfy { $0 === $1 }, "earlier rows keep their labels")
        XCTAssertEqual(table.cellLabels[4][0].attributedText?.string, "row 4")
        XCTAssertEqual((table.accessibilityElements ?? []).count, 10, "the new row reaches VoiceOver")
    }

    func testIncrementalLayoutMatchesAFreshTable() {
        let header = [cell("Name"), cell("Value")]
        var rows = (1...3).map { [cell("row \($0)"), cell("\($0)")] }
        let table = GlimmerTableView(header: header, rows: rows, alignments: [.none, .none], theme: .default)
        _ = table.layout(forWidth: 300)
        rows.append([cell("a much longer name that widens the first column and wraps"), cell("4")])
        table.update(to: .table(header: header, rows: rows, alignments: [.none, .none]))
        let fresh = GlimmerTableView(header: header, rows: rows, alignments: [.none, .none], theme: .default)
        XCTAssertEqual(table.layout(forWidth: 300), fresh.layout(forWidth: 300))
    }

    func testANegativeMinimumColumnWidthKeepsTheFloor() {
        var theme = self.theme
        theme.minTableColumnWidth = -10
        let long = String(repeating: "word ", count: 40)
        let table = GlimmerTableView(
            header: (0..<8).map { cell("h\($0)", header: true) },
            rows: [(0..<8).map { _ in cell(long) }],
            alignments: Array(repeating: .none, count: 8),
            theme: theme
        )
        let layout = table.layout(forWidth: 200)
        for width in layout.columnWidths { XCTAssertGreaterThanOrEqual(width, 44, "no column below the 44 pt floor") }
    }

    /// Each column's width while streaming: its widest cell's natural width, capped and floored as the table does.
    private func naturalWidths(_ rows: [[NSAttributedString]]) -> [CGFloat] {
        let padding = GlimmerTableView.cellPadding
        let cap = max(theme.maxTableColumnWidth, 44)
        let floor = max(theme.minTableColumnWidth, 44)
        var widths = Array(repeating: floor, count: rows.first?.count ?? 0)
        for row in rows {
            for (column, text) in row.enumerated() {
                let natural: CGFloat = min(ceil(text.size().width) + padding * 2, cap)
                widths[column] = max(widths[column], natural)
            }
        }
        return widths
    }

    func testAStreamingTableTakesItsColumnsNaturalWidthsAndFitsOnceItSettles() {
        let header = [cell("Item", header: true), cell("Detail", header: true), cell("Note", header: true)]
        let alignments: [GlimmerTable.Alignment] = [.none, .none, .none]
        var rows = [[cell("one"), cell("short"), cell("a")], [cell("two"), cell("brief"), cell("")]]
        let table = GlimmerTableView(header: header, rows: rows, alignments: alignments, theme: theme)
        table.isStreaming = true
        XCTAssertEqual(table.layout(forWidth: 320).columnWidths, naturalWidths([header] + rows),
                       "a header-only start does not stretch the columns to the box")
        var growing = ""
        for word in Array(repeating: ["alpha", "beta", "gamma", "delta", "epsilon"], count: 8).joined() {
            growing += (growing.isEmpty ? "" : " ") + word
            rows[rows.count - 1][2] = cell(growing)
            table.update(to: .table(header: header, rows: rows, alignments: alignments))
            let layout = table.layout(forWidth: 320)
            XCTAssertEqual(layout.columnWidths, naturalWidths([header] + rows), "natural widths at “\(growing)”")
        }
        XCTAssertEqual(table.layout(forWidth: 320).columnWidths[2], max(theme.maxTableColumnWidth, 44),
                       "the growing column stops at the cap")
        table.isStreaming = false
        let fresh = GlimmerTableView(header: header, rows: rows, alignments: alignments, theme: theme)
        XCTAssertEqual(table.layout(forWidth: 320), fresh.layout(forWidth: 320), "settling fits the table afresh")
        XCTAssertEqual(table.layout(forWidth: 320).contentWidth, 320, accuracy: 0.001, "the fitted table fills the box")
    }

    func testAGrowingStreamingCellNeverReWrapsAShownRow() {
        let header = [cell("Name", header: true), cell("Kind", header: true), cell("Note", header: true)]
        let alignments: [GlimmerTable.Alignment] = [.none, .none, .none]
        let long = String(repeating: "wrapping words ", count: 12)
        var rows = [
            [cell("one"), cell("plain"), cell("x")],
            [cell(long), cell("capped"), cell("y")],
            [cell("three"), cell("tail"), cell("a")],
        ]
        let table = GlimmerTableView(header: header, rows: rows, alignments: alignments, theme: theme)
        table.isStreaming = true
        var previous = table.layout(forWidth: 320)
        let singleLine = previous.rowHeights[1]
        XCTAssertGreaterThan(previous.rowHeights[2], singleLine, "the capped cell wraps")
        var growing = "a"
        for word in Array(repeating: ["alpha", "beta", "gamma", "delta", "epsilon"], count: 8).joined() {
            growing += " " + word
            rows[rows.count - 1][2] = cell(growing)
            let measured = table.measuredRowCount
            table.update(to: .table(header: header, rows: rows, alignments: alignments))
            let layout = table.layout(forWidth: 320)
            for row in 0..<(layout.rowHeights.count - 1) {
                XCTAssertEqual(layout.rowHeights[row], previous.rowHeights[row], "row \(row) changed at “\(growing)”")
            }
            XCTAssertEqual(table.measuredRowCount - measured, 1, "only the changed row is measured again at “\(growing)”")
            let natural: CGFloat = ceil(cell(growing).size().width) + GlimmerTableView.cellPadding * 2
            if natural < theme.maxTableColumnWidth {
                XCTAssertEqual(layout.rowHeights.last, singleLine, "a growing cell below the cap stays on one line")
            }
            previous = layout
        }
        XCTAssertGreaterThan(previous.rowHeights.last ?? 0, singleLine, "past the cap, the cell wraps")
    }

    func testAStreamingTableTooWideForTheBoxScrollsAndFitsOnceItSettles() {
        let header = (0..<3).map { cell("Column \($0)", header: true) }
        let rows = [(0..<3).map { cell("a fairly long cell value \($0)") }]
        let alignments = Array(repeating: GlimmerTable.Alignment.none, count: 3)
        let table = GlimmerTableView(header: header, rows: rows, alignments: alignments, theme: theme)
        table.isStreaming = true
        let width: CGFloat = 260
        let window = hostInWindow(table, width: width, height: table.embedHeight(forWidth: width))
        table.layoutIfNeeded()
        XCTAssertGreaterThan(table.scrollView.contentSize.width, table.bounds.width, "the streaming table scrolls")
        table.isStreaming = false
        table.layoutIfNeeded()
        XCTAssertEqual(table.scrollView.contentSize.width, width, accuracy: 0.001, "the settled table fits the box")
        _ = window
    }

    func testALastRowThatGrowsInPlaceUpdates() {
        let header = [cell("a"), cell("b")]
        let table = GlimmerTableView(header: header, rows: [[cell("1"), cell("2")]], alignments: [.none, .none], theme: .default)
        table.update(to: .table(header: header, rows: [[cell("1"), cell("23")]], alignments: [.none, .none]))
        XCTAssertEqual(table.cellLabels[1][1].attributedText?.string, "23")
        let ragged = GlimmerTableView(header: header, rows: [[cell("1")]], alignments: [.none, .none], theme: .default)
        ragged.update(to: .table(header: header, rows: [[cell("1"), cell("2")]], alignments: [.none, .none]))
        XCTAssertEqual(ragged.cellLabels[1][1].attributedText?.string, "2")
        XCTAssertEqual(ragged.layout(forWidth: 300),
                       GlimmerTableView(header: header, rows: [[cell("1"), cell("2")]], alignments: [.none, .none], theme: .default)
                           .layout(forWidth: 300))
    }
}

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

import Synchronization
import UIKit

/// A GFM table. Columns size to their content, capped at `maxTableColumnWidth`, and expand to fill the width when
/// the table is narrower than the text. Wider tables shrink their columns toward `minTableColumnWidth` and wrap
/// cells; only when that is not enough do they scroll horizontally. While the answer streams, columns keep their
/// content's width instead (see `isStreaming`).
@MainActor
final class GlimmerTableView: UIView, GlimmerEmbedView {
    struct Layout: Equatable {
        var columnWidths: [CGFloat]
        var rowHeights: [CGFloat]
        var contentWidth: CGFloat { columnWidths.reduce(0, +) }
        var height: CGFloat { rowHeights.reduce(0, +) }
    }

    static let cellPadding: CGFloat = 10
    private static let minimumColumnWidth: CGFloat = 44

    let scrollView = UIScrollView()
    private(set) var cellLabels: [[UILabel]] = []
    /// Plain cells keep UILabel's inexpensive path; linked cells need native text-item interaction.
    private var linkedCells: [ObjectIdentifier: GlimmerTableCellTextView] = [:]

    private let content = UIView()
    private let headerBackground = UIView()
    let grid = CAShapeLayer()
    private var cells: [[NSAttributedString]] = []
    private var alignments: [GlimmerTable.Alignment]
    private let theme: GlimmerTheme
    /// The layout last computed and the width it was computed for.
    private(set) var cachedLayout: (width: CGFloat, layout: Layout)?
    /// Per row, each cell's natural width (padded, capped); kept for rows that did not change.
    private var naturalRowWidths: [[CGFloat]] = []
    /// Per row, its height and the column widths it was measured at; kept for rows that did not change, and reused
    /// while their cells measure the same at the new widths (see `heightHolds`).
    private var measuredRows: [(columnWidths: [CGFloat], height: CGFloat)] = []
    /// How many rows have been measured, ever: tests read it to check which rows a change measures again.
    private(set) var measuredRowCount = 0
    /// VoiceOver's cells, built when it first asks and again after a change.
    private var cellElementsCache: [[GlimmerTableCellElement]]? {
        // Cleared when the table changes; readers off the main thread keep the last cells until new ones are built.
        didSet { if let cellElementsCache { accessibilitySnapshot.withLock { $0 = cellElementsCache } } }
    }
    /// The cells as the main thread last built them, for readers off it: UIKit's accessibility may read a view from a
    /// background queue, where a main-actor member traps, so the accessibility members are nonisolated and read this.
    nonisolated private let accessibilitySnapshot = Mutex<[[GlimmerTableCellElement]]>([])

    /// VoiceOver's cells, one per label, header row first.
    private var cellElements: [[GlimmerTableCellElement]] {
        if let cellElementsCache { return cellElementsCache }
        let elements = cellLabels.enumerated().map { row, labels in
            labels.enumerated().map { column, label in
                GlimmerTableCellElement(container: self, row: row, column: column, label: label,
                                        linkedText: linkedCells[ObjectIdentifier(label)])
            }
        }
        cellElementsCache = elements
        return elements
    }

    init(header: [NSAttributedString], rows: [[NSAttributedString]], alignments: [GlimmerTable.Alignment], theme: GlimmerTheme) {
        self.theme = theme
        self.alignments = alignments
        super.init(frame: .zero)

        layer.cornerRadius = theme.embedCornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        clipsToBounds = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        addSubview(scrollView)
        scrollView.addSubview(content)
        headerBackground.backgroundColor = theme.tableHeaderBackground
        content.addSubview(headerBackground)
        grid.fillColor = nil
        grid.lineWidth = 1
        content.layer.addSublayer(grid)

        accessibilityContainerType = .dataTable
        rebuildCells(header: header, rows: rows)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: GlimmerTableView, _: UITraitCollection) in
            view.updateColors()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(to embed: GlimmerEmbed) {
        guard case .table(let header, let rows, let alignments) = embed else { return }
        // Compared as `rebuildCells` stores them (padded to the widest row), styles included.
        let columns = max(header.count, rows.map(\.count).max() ?? 0, alignments.count)
        func padded(_ row: [NSAttributedString]) -> [NSAttributedString] {
            row + Array(repeating: NSAttributedString(), count: max(0, columns - row.count))
        }
        let incoming = [padded(header)] + rows.map(padded)
        let unchanged = alignments == self.alignments && incoming.count == cells.count
            && zip(incoming, cells).allSatisfy { new, old in
                new.count == old.count && zip(new, old).allSatisfy { $0.isEqual(to: $1) }
            }
        guard !unchanged else { return }
        guard alignments == self.alignments, incoming.first?.count == cells.first?.count else {
            // The columns changed (a header cell or an alignment): rebuild.
            self.alignments = alignments
            rebuildCells(header: header, rows: rows)
            cachedLayout = nil
            setNeedsLayout()
            return
        }
        let firstChanged = (0..<min(incoming.count, cells.count)).first { row in
            !zip(incoming[row], cells[row]).allSatisfy { $0.isEqual(to: $1) }
        } ?? min(incoming.count, cells.count)
        // Rows from the first change: update labels in place, add labels for new rows, drop labels for removed rows.
        for row in firstChanged..<incoming.count {
            if row < cellLabels.count {
                for (column, text) in incoming[row].enumerated() where !text.isEqual(to: cells[row][column]) {
                    updateLabel(cellLabels[row][column], text: text, column: column)
                }
            } else {
                cellLabels.append(incoming[row].enumerated().map { column, text in makeLabel(text, column: column) })
            }
        }
        for label in cellLabels.dropFirst(incoming.count).joined() { removeLabel(label) }
        cellLabels.removeSubrange(min(incoming.count, cellLabels.count)...)
        cells = incoming
        naturalRowWidths.removeSubrange(min(firstChanged, naturalRowWidths.count)...)
        measuredRows.removeSubrange(min(firstChanged, measuredRows.count)...)
        cellElementsCache = nil
        cachedLayout = nil
        setNeedsLayout()
    }

    /// Replaces every cell label: rows padded to the widest row, aligned per column.
    private func rebuildCells(header: [NSAttributedString], rows: [[NSAttributedString]]) {
        for label in cellLabels.joined() { removeLabel(label) }
        let columns = max(header.count, rows.map(\.count).max() ?? 0, alignments.count)
        func padded(_ row: [NSAttributedString]) -> [NSAttributedString] {
            row + Array(repeating: NSAttributedString(), count: max(0, columns - row.count))
        }
        cells = [padded(header)] + rows.map(padded)
        cellLabels = cells.map { row in row.enumerated().map { column, text in makeLabel(text, column: column) } }
        cellElementsCache = nil
        naturalRowWidths = []
        measuredRows = []
        updateColors()
    }

    private func makeLabel(_ text: NSAttributedString, column: Int) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        content.addSubview(label)
        updateLabel(label, text: text, column: column)
        return label
    }

    private func updateLabel(_ label: UILabel, text: NSAttributedString, column: Int) {
        let alignment = Self.textAlignment(column < alignments.count ? alignments[column] : .none)
        label.attributedText = text
        label.textAlignment = alignment
        let key = ObjectIdentifier(label)
        if GlimmerTableCellTextView.hasLinks(in: text) {
            let linked = linkedCells[key] ?? GlimmerTableCellTextView()
            linked.attributedText = text
            linked.textAlignment = alignment
            if linked.superview == nil { content.addSubview(linked) }
            linkedCells[key] = linked
            label.isHidden = true
        } else {
            linkedCells.removeValue(forKey: key)?.removeFromSuperview()
            label.isHidden = false
        }
    }

    private func removeLabel(_ label: UILabel) {
        linkedCells.removeValue(forKey: ObjectIdentifier(label))?.removeFromSuperview()
        label.removeFromSuperview()
    }

    nonisolated override var accessibilityElements: [Any]? {
        get { Array(accessibleCells().joined()) }
        set {}
    }

    /// The cells: built on the main thread when first asked; off it, as the main thread last built them.
    nonisolated private func accessibleCells() -> [[GlimmerTableCellElement]] {
        guard Thread.isMainThread else { return accessibilitySnapshot.withLock { $0 } }
        return MainActor.assumeIsolated { cellElements }
    }

    /// While true (the answer is streaming), each column is as wide as its widest cell (capped and floored, never
    /// stretched or shrunk to the box), and the table scrolls when they don't fit. A column then widens only when its
    /// own content grows, and a cell below the cap stays on one line, so rows already shown never re-wrap and only a
    /// changed row is measured again. A fit instead would move every column whenever one cell grew. Turning it off
    /// fits the table to the width, once.
    var isStreaming = false {
        didSet {
            guard isStreaming != oldValue else { return }
            cachedLayout = nil
            setNeedsLayout()
        }
    }

    /// Rows shown while a reveal runs (the header counts as one); nil shows all.
    var visibleUnitCount: Int? {
        didSet { if visibleUnitCount != oldValue { setNeedsLayout() } }
    }

    func embedHeight(forWidth width: CGFloat) -> CGFloat {
        let heights = layout(forWidth: width).rowHeights
        let count = visibleUnitCount.map { min(max($0, 1), heights.count) } ?? heights.count
        return heights.prefix(count).reduce(0, +)
    }

    func revealUnitRects(in box: CGRect) -> [CGRect] {
        var rects: [CGRect] = []
        var y: CGFloat = 0
        for height in layout(forWidth: box.width).rowHeights {
            rects.append(CGRect(x: 0, y: y, width: box.width, height: height))
            y += height
        }
        return extendingLastVisibleUnit(rects, in: box)
    }

    /// Column widths for `width`: narrower tables stretch to fill it, wider ones shrink the columns above `minimum`
    /// in proportion to how far each is above it, and only columns that are all at `minimum` still scroll.
    private static func fit(_ natural: [CGFloat], to width: CGFloat, minimum: CGFloat) -> [CGFloat] {
        let total: CGFloat = natural.reduce(0, +)
        guard total > 0 else { return natural }
        if total <= width {
            guard total < width else { return natural }
            let stretched: [CGFloat] = natural.map { column in column * width / total }
            return snapped(stretched, to: width, at: natural.count - 1)
        }
        let slack: [CGFloat] = natural.map { column in column - min(column, minimum) }
        let slackTotal: CGFloat = slack.reduce(0, +)
        guard slackTotal > 0 else { return natural }
        let shrink: CGFloat = min(total - width, slackTotal)
        let shrunk: [CGFloat] = zip(natural, slack).map { pair in
            let share: CGFloat = shrink * pair.1 / slackTotal
            return pair.0 - share
        }
        // Rounding drift must not leave a table that fits a hair wider than its box, which would let it scroll.
        guard shrink == total - width, let last = slack.lastIndex(where: { $0 > 0 }) else { return shrunk }
        return snapped(shrunk, to: width, at: last)
    }

    /// Whether a row measured at `old` column widths has the same height at `new`. A cell measures the same at any
    /// width that holds its whole text on one line: one at least its natural width, when that is below the cap.
    private static func heightHolds(from old: [CGFloat], to new: [CGFloat], naturals: [CGFloat], cap: CGFloat) -> Bool {
        guard old.count == new.count, naturals.count == new.count else { return false }
        for column in new.indices where old[column] != new[column] {
            let natural = naturals[column]
            guard natural < cap, min(old[column], new[column]) >= natural else { return false }
        }
        return true
    }

    /// `widths` with the column at `index` taking whatever makes the sum exactly `width`.
    private static func snapped(_ widths: [CGFloat], to width: CGFloat, at index: Int) -> [CGFloat] {
        var result = widths
        var others: CGFloat = 0
        for (column, columnWidth) in result.enumerated() where column != index {
            others += columnWidth
        }
        result[index] = width - others
        return result
    }

    func layout(forWidth width: CGFloat) -> Layout {
        if let cachedLayout, cachedLayout.width == width { return cachedLayout.layout }
        let padding = Self.cellPadding
        let columns = cells.first?.count ?? 0
        let maxColumn = max(theme.maxTableColumnWidth, Self.minimumColumnWidth)
        while naturalRowWidths.count < cells.count {
            let row: [CGFloat] = cells[naturalRowWidths.count].map { text in
                let padded: CGFloat = ceil(text.size().width) + padding * 2
                return min(padded, maxColumn)
            }
            naturalRowWidths.append(row)
        }
        var natural = Array(repeating: Self.minimumColumnWidth, count: columns)
        for row in naturalRowWidths {
            for (column, width) in row.enumerated() { natural[column] = max(natural[column], width) }
        }
        let minimum = max(theme.minTableColumnWidth, Self.minimumColumnWidth)
        let widths: [CGFloat]
        if isStreaming {
            widths = natural.map { column in max(column, minimum) }
        } else {
            widths = Self.fit(natural, to: width, minimum: minimum)
        }
        var heights: [CGFloat] = []
        for row in cells.indices {
            if row < measuredRows.count, Self.heightHolds(
                from: measuredRows[row].columnWidths, to: widths, naturals: naturalRowWidths[row], cap: maxColumn
            ) {
                heights.append(measuredRows[row].height)
                measuredRows[row].columnWidths = widths
                continue
            }
            let height = rowHeight(cells[row], columnWidths: widths)
            measuredRowCount += 1
            heights.append(height)
            if row < measuredRows.count {
                measuredRows[row] = (widths, height)
            } else {
                measuredRows.append((widths, height))
            }
        }
        let layout = Layout(columnWidths: widths, rowHeights: heights)
        cachedLayout = (width, layout)
        return layout
    }

    /// The tallest cell of `row` at `columnWidths`, padding included.
    private func rowHeight(_ row: [NSAttributedString], columnWidths: [CGFloat]) -> CGFloat {
        let padding = Self.cellPadding
        let cellHeights: [CGFloat] = row.enumerated().map { column, text in
            let textWidth: CGFloat = max(1, columnWidths[column] - padding * 2)
            let bounds: CGRect = text.boundingRect(
                with: CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            return ceil(bounds.height) + padding * 2
        }
        return cellHeights.max() ?? padding * 2
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let layout = layout(forWidth: bounds.width)
        let padding = Self.cellPadding
        scrollView.frame = bounds
        // While revealing, this view is shorter than the table and clips the rows below; never scroll vertically.
        scrollView.contentSize = CGSize(width: layout.contentWidth, height: min(layout.height, bounds.height))
        // A streaming table narrower than the box draws its last column to the edge; cells keep their measured widths.
        let drawnWidth = max(layout.contentWidth, bounds.width)
        content.frame = CGRect(x: 0, y: 0, width: drawnWidth, height: layout.height)
        headerBackground.frame = CGRect(x: 0, y: 0, width: drawnWidth, height: layout.rowHeights.first ?? 0)

        let path = UIBezierPath()
        var y: CGFloat = 0
        for (rowIndex, labels) in cellLabels.enumerated() {
            var x: CGFloat = 0
            for (column, label) in labels.enumerated() {
                label.frame = CGRect(
                    x: x + padding, y: y + padding,
                    width: max(0, layout.columnWidths[column] - padding * 2),
                    height: max(0, layout.rowHeights[rowIndex] - padding * 2)
                )
                linkedCells[ObjectIdentifier(label)]?.frame = label.frame
                x += layout.columnWidths[column]
                if column < labels.count - 1 {
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x, y: y + layout.rowHeights[rowIndex]))
                }
            }
            y += layout.rowHeights[rowIndex]
            if rowIndex < cellLabels.count - 1 {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: drawnWidth, y: y))
            }
        }
        grid.path = path.cgPath
        // Readers off the main thread get the cells' frames as laid out, not as last asked for.
        cellElementsCache?.joined().forEach { $0.refreshFrame() }
    }

    private func updateColors() {
        let border = theme.tableBorderColor.resolvedColor(with: traitCollection).cgColor
        layer.borderColor = border
        grid.strokeColor = border
    }

    private static func textAlignment(_ alignment: GlimmerTable.Alignment) -> NSTextAlignment {
        switch alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        case .none: .natural
        }
    }
}

extension GlimmerTableView: UIAccessibilityContainerDataTable {
    nonisolated func accessibilityRowCount() -> Int { accessibleCells().count }
    nonisolated func accessibilityColumnCount() -> Int { accessibleCells().first?.count ?? 0 }

    nonisolated func accessibilityDataTableCellElement(forRow row: Int, column: Int) -> (any UIAccessibilityContainerDataTableCell)? {
        let cells = accessibleCells()
        guard row < cells.count, column < cells[row].count else { return nil }
        return cells[row][column]
    }

    nonisolated func accessibilityHeaderElements(forColumn column: Int) -> [any UIAccessibilityContainerDataTableCell]? {
        guard let header = accessibleCells().first, column < header.count else { return nil }
        return [header[column]]
    }

    nonisolated func accessibilityHeaderElements(forRow row: Int) -> [any UIAccessibilityContainerDataTableCell]? { nil }
}

/// One table cell for VoiceOver: its text, its position, and where its label is on screen. The frame is read when
/// VoiceOver asks, so a table scrolled sideways still points at the right cell; off the main thread, the frame as the
/// main thread last read it.
final class GlimmerTableCellElement: UIAccessibilityElement, UIAccessibilityContainerDataTableCell {
    nonisolated let row: Int
    nonisolated let column: Int
    private weak var label: UILabel?
    nonisolated private let lastFrame = Mutex(CGRect.zero)

    private weak var linkedText: GlimmerTableCellTextView?

    init(container: GlimmerTableView, row: Int, column: Int, label: UILabel, linkedText: GlimmerTableCellTextView?) {
        self.row = row
        self.column = column
        self.label = label
        self.linkedText = linkedText
        super.init(accessibilityContainer: container)
        accessibilityLabel = label.attributedText?.string
        accessibilityTraits = row == 0 ? .header : .staticText
        if let linkedText {
            let links = linkedText.linkRanges
            // Expose the interactive role to accessibility's links rotor. A linked header keeps its heading role.
            if links.count == 1 { accessibilityTraits = row == 0 ? [.header, .link] : .link }
            accessibilityCustomActions = links.map { range in
                let name = linkedText.textStorage.attributedSubstring(from: range).string
                return UIAccessibilityCustomAction(name: name) { [weak linkedText] _ in
                    linkedText?.activateLink(atCharacter: range.location) ?? false
                }
            }
        }
    }

    override func accessibilityActivate() -> Bool {
        guard let linkedText, linkedText.linkRanges.count == 1, let range = linkedText.linkRanges.first else { return false }
        return linkedText.activateLink(atCharacter: range.location)
    }

    nonisolated override var accessibilityFrame: CGRect {
        get {
            guard Thread.isMainThread else { return lastFrame.withLock { $0 } }
            return MainActor.assumeIsolated { refreshFrame() }
        }
        set {}
    }

    /// The cell's frame on screen, recorded for readers off the main thread; the table records it on layout too.
    @discardableResult
    func refreshFrame() -> CGRect {
        let frame: CGRect
        if let linkedText, linkedText.linkRanges.count == 1, let range = linkedText.linkRanges.first,
           let linkFrame = linkedText.frameForLink(range) {
            frame = UIAccessibility.convertToScreenCoordinates(linkFrame, in: linkedText)
        } else {
            frame = label.map { UIAccessibility.convertToScreenCoordinates($0.bounds, in: $0) } ?? .zero
        }
        lastFrame.withLock { $0 = frame }
        return frame
    }

    nonisolated func accessibilityRowRange() -> NSRange { NSRange(location: row, length: 1) }
    nonisolated func accessibilityColumnRange() -> NSRange { NSRange(location: column, length: 1) }
}

import UIKit

/// A GFM table. Columns size to their content, capped at `maxTableColumnWidth`, and expand to fill the width when
/// the table is narrower than the text. Wider tables scroll horizontally.
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

    private let content = UIView()
    private let headerBackground = UIView()
    private let grid = CAShapeLayer()
    private var cells: [[NSAttributedString]] = []
    private var alignments: [GlimmerTable.Alignment]
    private let theme: GlimmerTheme
    private var cachedLayout: (width: CGFloat, layout: Layout)?

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

        rebuildCells(header: header, rows: rows)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: GlimmerTableView, _: UITraitCollection) in
            view.updateColors()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(to embed: GlimmerEmbed) {
        guard case .table(let header, let rows, let alignments) = embed else { return }
        let columns = cells.first?.count ?? 0
        let unchanged = rows.count + 1 == cells.count
            && alignments == self.alignments
            && rows.map { $0.map(\.string) } == cells.dropFirst().map { $0.prefix(max(columns, 0)).map(\.string) }
        guard !unchanged else { return }
        self.alignments = alignments
        rebuildCells(header: header, rows: rows)
        cachedLayout = nil
        setNeedsLayout()
    }

    /// Replaces every cell label: rows padded to the widest row, aligned per column.
    private func rebuildCells(header: [NSAttributedString], rows: [[NSAttributedString]]) {
        for label in cellLabels.joined() { label.removeFromSuperview() }
        let columns = max(header.count, rows.map(\.count).max() ?? 0, alignments.count)
        func padded(_ row: [NSAttributedString]) -> [NSAttributedString] {
            row + Array(repeating: NSAttributedString(), count: max(0, columns - row.count))
        }
        cells = [padded(header)] + rows.map(padded)
        cellLabels = cells.map { row in
            row.enumerated().map { column, text in
                let label = UILabel()
                label.numberOfLines = 0
                label.attributedText = text
                label.textAlignment = Self.textAlignment(column < alignments.count ? alignments[column] : .none)
                content.addSubview(label)
                return label
            }
        }
        updateColors()
    }

    func embedHeight(forWidth width: CGFloat) -> CGFloat { layout(forWidth: width).height }

    func layout(forWidth width: CGFloat) -> Layout {
        if let cachedLayout, cachedLayout.width == width { return cachedLayout.layout }
        let padding = Self.cellPadding
        let columns = cells.first?.count ?? 0
        let maxColumn = max(theme.maxTableColumnWidth, Self.minimumColumnWidth)
        var natural = Array(repeating: Self.minimumColumnWidth, count: columns)
        for row in cells {
            for (column, text) in row.enumerated() {
                natural[column] = max(natural[column], min(ceil(text.size().width) + padding * 2, maxColumn))
            }
        }
        let total = natural.reduce(0, +)
        let widths = total > 0 && total < width ? natural.map { $0 * width / total } : natural
        let rowHeights = cells.map { row in
            row.enumerated().map { column, text in
                let bounds = text.boundingRect(
                    with: CGSize(width: max(1, widths[column] - padding * 2), height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                return ceil(bounds.height) + padding * 2
            }.max() ?? padding * 2
        }
        let layout = Layout(columnWidths: widths, rowHeights: rowHeights)
        cachedLayout = (width, layout)
        return layout
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let layout = layout(forWidth: bounds.width)
        let padding = Self.cellPadding
        scrollView.frame = bounds
        scrollView.contentSize = CGSize(width: layout.contentWidth, height: layout.height)
        content.frame = CGRect(origin: .zero, size: scrollView.contentSize)
        headerBackground.frame = CGRect(x: 0, y: 0, width: layout.contentWidth, height: layout.rowHeights.first ?? 0)

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
                x += layout.columnWidths[column]
                if column < labels.count - 1 {
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x, y: y + layout.rowHeights[rowIndex]))
                }
            }
            y += layout.rowHeights[rowIndex]
            if rowIndex < cellLabels.count - 1 {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: layout.contentWidth, y: y))
            }
        }
        grid.path = path.cgPath
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

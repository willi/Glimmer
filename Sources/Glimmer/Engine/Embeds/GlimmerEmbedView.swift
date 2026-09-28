import UIKit

/// A view that renders one embedded block (code, table, image, rule) inside the text flow.
@MainActor
protocol GlimmerEmbedView: UIView {
    /// The height the view needs at `width`. Called during TextKit layout, so it must be cheap once warmed up.
    func embedHeight(forWidth width: CGFloat) -> CGFloat
    /// Shows `embed` in place: a code block or table that grew while streaming. Views ignore embeds of another kind.
    func update(to embed: GlimmerEmbed)
    /// Each reveal unit's rect (code lines, table rows) within `box` (the view's frame as TextKit lays it out, at
    /// origin zero), top to bottom and full width. The last visible unit's rect runs to the box's bottom edge. A view
    /// without units returns the box. It never reads the view's own frame, which lags TextKit's layout.
    func revealUnitRects(in box: CGRect) -> [CGRect]
    /// How many units show while a reveal runs; nil shows all. The view's height follows it.
    var visibleUnitCount: Int? { get set }
}

extension GlimmerEmbedView {
    /// Makes the last visible unit's rect reach the box's bottom edge (bottom padding, rounding).
    func extendingLastVisibleUnit(_ rects: [CGRect], in box: CGRect) -> [CGRect] {
        var rects = rects
        let visible = visibleUnitCount.map { min(max($0, 1), rects.count) } ?? rects.count
        if visible > 0 {
            let last = rects[visible - 1]
            rects[visible - 1].size.height = max(last.height, box.maxY - last.minY)
        }
        return rects
    }
}

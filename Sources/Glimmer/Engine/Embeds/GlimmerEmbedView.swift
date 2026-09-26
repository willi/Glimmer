import UIKit

/// A view that renders one embedded block (code, table, image, rule) inside the text flow.
@MainActor
protocol GlimmerEmbedView: UIView {
    /// The height the view needs at `width`. Called during TextKit layout, so it must be cheap once warmed up.
    func embedHeight(forWidth width: CGFloat) -> CGFloat
    /// Shows `embed` in place: a code block or table that grew while streaming. Views ignore embeds of another kind.
    func update(to embed: GlimmerEmbed)
}

import SwiftUI

/// A block quote: its blocks indented by the theme's `quoteIndent`, beside a bar in `quoteBarColor`.
struct GlimmerStaticQuoteView: View {
    /// The bar's width, as the engine draws it.
    private static let barWidth = GlimmerLayoutFragment.quoteBarWidth

    let blocks: [GlimmerStaticBlock]
    let theme: GlimmerTheme

    var body: some View {
        GlimmerStaticBlocksView(blocks: blocks, theme: theme)
            .padding(.leading, theme.quoteIndent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .leading) { bar }
    }

    private var bar: some View {
        let color = Color(uiColor: theme.quoteBarColor)
        return Rectangle()
            .fill(color)
            .frame(width: Self.barWidth)
    }
}

import SwiftUI

/// One list item: its marker, then its blocks, sharing the first line's baseline.
struct GlimmerStaticListItemView: View {
    let item: GlimmerStaticListItem
    let list: GlimmerStaticList
    let theme: GlimmerTheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            marker
            GlimmerStaticBlocksView(blocks: item.blocks, theme: theme)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Numbers end `markerGap` before the text; bullets and boxes start the column.
    private var marker: some View {
        let gap = list.isOrdered ? list.markerGap : 0
        return Text(item.marker)
            .lineLimit(1)
            .fixedSize()
            .frame(width: list.markerColumnWidth - gap, alignment: list.isOrdered ? .trailing : .leading)
            .padding(.trailing, gap)
    }
}

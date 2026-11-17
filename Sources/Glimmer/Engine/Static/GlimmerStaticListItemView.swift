import SwiftUI

/// One list item: its marker beside its first block, sharing the first line's baseline, and the item's later blocks
/// below, indented to the same column (a hanging indent).
struct GlimmerStaticListItemView: View {
    let item: GlimmerStaticListItem
    let list: GlimmerStaticList
    let theme: GlimmerTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            firstLine
            GlimmerStaticBlocksView(blocks: Array(item.blocks.dropFirst()), theme: theme)
                .padding(.leading, list.markerColumnWidth)
        }
    }

    /// The marker and the first block, one VoiceOver element unless the first block is a list.
    private var firstLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            marker
            GlimmerStaticBlocksView(blocks: Array(item.blocks.prefix(1)), theme: theme)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: item.groupsMarkerWithFirstBlock ? .combine : .contain)
    }

    /// Numbers end `markerGap` before the text; bullets and boxes start the column.
    private var marker: some View {
        let gap = list.isOrdered ? list.markerGap : 0
        return Text(item.marker)
            .lineLimit(1)
            .fixedSize()
            .frame(width: list.markerColumnWidth - gap, alignment: list.isOrdered ? .trailing : .leading)
            .padding(.trailing, gap)
            .accessibilityLabel(item.markerAccessibilityLabel.map { Text($0) } ?? Text(item.marker))
    }
}

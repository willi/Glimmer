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
        .accessibilityElement(children: childBehavior)
    }

    /// One element for the marker and the first block, unless the first block is a list.
    private var childBehavior: AccessibilityChildBehavior {
        item.groupsMarkerWithFirstBlock ? .combine : .contain
    }

    /// Numbers end `markerGap` before the text; bullets and boxes start the column.
    private var marker: some View {
        let gap: CGFloat = list.isOrdered ? list.markerGap : 0
        let width: CGFloat = list.markerColumnWidth - gap
        let alignment: Alignment = list.isOrdered ? .trailing : .leading
        return Text(item.marker)
            .lineLimit(1)
            .fixedSize()
            .frame(width: width, alignment: alignment)
            .padding(.trailing, gap)
            .accessibilityLabel(markerLabel)
    }

    /// What VoiceOver reads for the marker: a task box's state, or else the marker's text.
    private var markerLabel: Text {
        guard let label = item.markerAccessibilityLabel else { return Text(item.marker) }
        return Text(label)
    }
}

import SwiftUI

/// A list: each item's marker in a column, and every line of the item's blocks beside it (a hanging indent).
struct GlimmerStaticListView: View {
    let list: GlimmerStaticList
    let theme: GlimmerTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(list.items.indices, id: \.self) { index in
                let item: GlimmerStaticListItem = list.items[index]
                GlimmerStaticListItemView(item: item, list: list, theme: theme)
                    .padding(.top, item.spacingAbove)
            }
        }
    }
}

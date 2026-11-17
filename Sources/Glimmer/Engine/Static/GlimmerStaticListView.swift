import SwiftUI

/// A list: each item's marker in a column, and every line of the item's blocks beside it (a hanging indent).
struct GlimmerStaticListView: View {
    let list: GlimmerStaticList
    let theme: GlimmerTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(list.items.indices, id: \.self) { index in
                GlimmerStaticListItemView(item: list.items[index], list: list, theme: theme)
                    .padding(.top, list.items[index].spacingAbove)
            }
        }
    }
}

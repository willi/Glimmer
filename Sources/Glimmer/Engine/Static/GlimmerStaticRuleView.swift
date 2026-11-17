import SwiftUI

/// A thematic break: a 1 pt line centred in block spacing, as `GlimmerRuleView` draws it.
struct GlimmerStaticRuleView: View {
    let theme: GlimmerTheme

    var body: some View {
        let margin: CGFloat = theme.blockSpacing / 2
        return Rectangle()
            .fill(Color(uiColor: theme.tableBorderColor))
            .frame(height: 1)
            .padding(.vertical, margin)
            .accessibilityHidden(true)
    }
}

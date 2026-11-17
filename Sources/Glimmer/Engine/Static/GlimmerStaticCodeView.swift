import SwiftUI

/// A code block: its code on the theme's code block background, wrapped rather than scrolled.
struct GlimmerStaticCodeView: View {
    let code: AttributedString
    let theme: GlimmerTheme

    var body: some View {
        Text(code)
            .padding(theme.embedPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(uiColor: theme.codeBlockBackground),
                in: RoundedRectangle(cornerRadius: theme.embedCornerRadius, style: .continuous)
            )
    }
}

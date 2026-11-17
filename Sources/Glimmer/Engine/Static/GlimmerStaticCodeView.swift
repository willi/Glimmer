import SwiftUI

/// A code block: its code on the theme's code block background, wrapped rather than scrolled.
struct GlimmerStaticCodeView: View {
    let code: AttributedString
    let theme: GlimmerTheme

    var body: some View {
        let background = Color(uiColor: theme.codeBlockBackground)
        let shape = RoundedRectangle(cornerRadius: theme.embedCornerRadius, style: .continuous)
        return Text(code)
            .glimmerLineSpacing(theme.codeLineSpacing)
            .padding(theme.embedPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: shape)
    }
}

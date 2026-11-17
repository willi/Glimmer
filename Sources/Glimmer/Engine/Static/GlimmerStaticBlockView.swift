import SwiftUI

/// One block of a `GlimmerStaticText`.
struct GlimmerStaticBlockView: View {
    let block: GlimmerStaticBlock
    let theme: GlimmerTheme

    var body: some View {
        switch block.content {
        case .text(let text, let headingLevel):
            textBlock(text, headingLevel: headingLevel)
        case .code(let code):
            GlimmerStaticCodeView(code: code, theme: theme)
        case .table(let rows):
            GlimmerStaticTableView(rows: rows)
        case .rule:
            GlimmerStaticRuleView(theme: theme)
        case .quote(let blocks):
            GlimmerStaticQuoteView(blocks: blocks, theme: theme)
        case .list(let list):
            GlimmerStaticListView(list: list, theme: theme)
        }
    }

    /// A paragraph, or a heading that VoiceOver reads as one of its level, as `GlimmerView` marks its headings.
    @ViewBuilder
    private func textBlock(_ text: AttributedString, headingLevel: Int?) -> some View {
        if let headingLevel {
            let level: AccessibilityHeadingLevel = Self.accessibilityHeadingLevel(headingLevel)
            Text(text)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHeading(level)
        } else {
            Text(text)
        }
    }

    /// The SwiftUI heading level for a markdown heading level (1–6).
    static func accessibilityHeadingLevel(_ level: Int) -> AccessibilityHeadingLevel {
        switch level {
        case 1: .h1
        case 2: .h2
        case 3: .h3
        case 4: .h4
        case 5: .h5
        case 6: .h6
        default: .unspecified
        }
    }
}

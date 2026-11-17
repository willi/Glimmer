import SwiftUI

/// One block of a `GlimmerStaticText`.
struct GlimmerStaticBlockView: View {
    let block: GlimmerStaticBlock
    let theme: GlimmerTheme

    var body: some View {
        switch block.content {
        case .text(let text, let headingLevel):
            Text(text)
                .accessibilityAddTraits(headingLevel == nil ? [] : .isHeader)
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
}

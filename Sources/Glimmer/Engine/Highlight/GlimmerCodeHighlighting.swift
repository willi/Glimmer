import UIKit

/// Styled code for a code block. Pure and nonisolated: the composer calls it on the view's worker while an answer
/// streams, and the code view only when it was given no highlight.
enum GlimmerCodeHighlighting {
    static func highlightedCode(
        _ code: String, language: String?, theme: GlimmerTheme, highlighter: any GlimmerHighlighter
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = theme.lineHeightMultiple
        let result = NSMutableAttributedString(string: code, attributes: [
            .font: theme.codeFont,
            .foregroundColor: theme.textColor,
            .paragraphStyle: paragraph,
        ])
        for span in highlighter.highlight(code, language: language) where NSMaxRange(span.range) <= result.length {
            result.addAttribute(.foregroundColor, value: color(for: span.kind, theme: theme), range: span.range)
        }
        return result
    }

    private static func color(for kind: GlimmerHighlightSpan.Kind, theme: GlimmerTheme) -> UIColor {
        switch kind {
        case .keyword: theme.syntaxKeywordColor
        case .string: theme.syntaxStringColor
        case .comment: theme.syntaxCommentColor
        case .number: theme.syntaxNumberColor
        }
    }
}

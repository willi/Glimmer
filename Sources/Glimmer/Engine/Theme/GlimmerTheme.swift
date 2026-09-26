import UIKit

/// Visual styling for rendered markdown.
///
/// Fonts are base (unscaled) fonts; `scaled(for:)` applies Dynamic Type. Colors should be dynamic
/// (`UIColor` with light/dark variants) because Glimmer never re-renders just for an appearance change.
/// Start from `.default` and change what you need.
public struct GlimmerTheme: Sendable {
    public var bodyFont: UIFont
    public var codeFont: UIFont
    /// Heading fonts for levels 1–6 (index 0 is H1).
    public var headingFonts: [UIFont]
    public var tableFont: UIFont
    public var tableHeaderFont: UIFont
    /// Small UI text such as a code block's language label.
    public var captionFont: UIFont

    public var textColor: UIColor
    public var secondaryTextColor: UIColor
    public var linkColor: UIColor
    public var inlineCodeBackground: UIColor
    public var codeBlockBackground: UIColor
    public var quoteBarColor: UIColor
    public var tableBorderColor: UIColor
    public var tableHeaderBackground: UIColor
    public var syntaxKeywordColor: UIColor
    public var syntaxStringColor: UIColor
    public var syntaxCommentColor: UIColor
    public var syntaxNumberColor: UIColor

    public var lineHeightMultiple: CGFloat
    /// Space after a paragraph.
    public var paragraphSpacing: CGFloat
    /// Space after an item in a tight list.
    public var tightListSpacing: CGFloat
    /// Space around headings and embedded blocks.
    public var blockSpacing: CGFloat
    public var listIndent: CGFloat
    public var quoteIndent: CGFloat
    /// Inner padding of code blocks, tables and images.
    public var embedPadding: CGFloat
    public var embedCornerRadius: CGFloat
    public var maxTableColumnWidth: CGFloat
    /// Width ÷ height of the box reserved for an image before it loads.
    public var imagePlaceholderAspect: CGFloat
    public var maxImageHeight: CGFloat

    public var underlinesLinks: Bool
    public var showsCodeBlockHeader: Bool

    public func headingFont(level: Int) -> UIFont {
        headingFonts[min(max(level, 1), headingFonts.count) - 1]
    }

    /// A copy with every font — and the spacing that must grow with text — scaled for the traits' content size
    /// category.
    public func scaled(for traits: UITraitCollection) -> GlimmerTheme {
        func scale(_ font: UIFont, _ style: UIFont.TextStyle) -> UIFont {
            UIFontMetrics(forTextStyle: style).scaledFont(for: font, compatibleWith: traits)
        }
        func scale(_ value: CGFloat) -> CGFloat { UIFontMetrics.default.scaledValue(for: value, compatibleWith: traits) }
        // Each role follows its own Dynamic Type curve, so headings grow less than body text at accessibility sizes.
        let headingStyles: [UIFont.TextStyle] = [.title1, .title2, .title3, .headline, .subheadline, .footnote]
        var copy = self
        copy.paragraphSpacing = scale(paragraphSpacing)
        copy.tightListSpacing = scale(tightListSpacing)
        copy.blockSpacing = scale(blockSpacing)
        copy.listIndent = scale(listIndent)
        copy.quoteIndent = scale(quoteIndent)
        copy.embedPadding = scale(embedPadding)
        copy.bodyFont = scale(bodyFont, .body)
        copy.codeFont = scale(codeFont, .body)
        copy.headingFonts = headingFonts.enumerated().map { level, font in
            scale(font, headingStyles[min(level, headingStyles.count - 1)])
        }
        copy.tableFont = scale(tableFont, .subheadline)
        copy.tableHeaderFont = scale(tableHeaderFont, .subheadline)
        copy.captionFont = scale(captionFont, .footnote)
        return copy
    }
}

extension GlimmerTheme {
    /// Apple HIG defaults: system fonts and semantic colors.
    public static var `default`: GlimmerTheme {
        GlimmerTheme(
            bodyFont: .systemFont(ofSize: 17),
            codeFont: .monospacedSystemFont(ofSize: 15, weight: .regular),
            headingFonts: [
                .systemFont(ofSize: 28, weight: .bold),
                .systemFont(ofSize: 22, weight: .bold),
                .systemFont(ofSize: 20, weight: .semibold),
                .systemFont(ofSize: 17, weight: .semibold),
                .systemFont(ofSize: 15, weight: .semibold),
                .systemFont(ofSize: 13, weight: .semibold),
            ],
            tableFont: .systemFont(ofSize: 15),
            tableHeaderFont: .systemFont(ofSize: 15, weight: .semibold),
            captionFont: .systemFont(ofSize: 13, weight: .medium),
            textColor: .label,
            secondaryTextColor: .secondaryLabel,
            linkColor: .link,
            inlineCodeBackground: .tertiarySystemFill,
            codeBlockBackground: .secondarySystemBackground,
            quoteBarColor: .separator,
            tableBorderColor: .separator,
            tableHeaderBackground: .secondarySystemBackground,
            syntaxKeywordColor: .systemPink,
            syntaxStringColor: .systemRed,
            syntaxCommentColor: .secondaryLabel,
            syntaxNumberColor: .systemPurple,
            lineHeightMultiple: 1.2,
            paragraphSpacing: 12,
            tightListSpacing: 4,
            blockSpacing: 16,
            listIndent: 24,
            quoteIndent: 16,
            embedPadding: 12,
            embedCornerRadius: 12,
            maxTableColumnWidth: 260,
            imagePlaceholderAspect: 16.0 / 9.0,
            maxImageHeight: 320,
            underlinesLinks: false,
            showsCodeBlockHeader: true
        )
    }
}

/// Keys the settled-document cache: a different theme composes a different text.
extension GlimmerTheme: Hashable {}

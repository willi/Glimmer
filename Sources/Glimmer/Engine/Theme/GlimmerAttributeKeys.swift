import Foundation

extension NSAttributedString.Key {
    /// `true` on inline code. `GlimmerLayoutFragment` draws a pill behind it.
    static let glimmerInlineCode = NSAttributedString.Key("glimmer.inlineCode")
    /// Blockquote nesting depth (`Int`) on a whole paragraph. `GlimmerLayoutFragment` draws one bar per level.
    static let glimmerQuoteDepth = NSAttributedString.Key("glimmer.quoteDepth")
    /// On the paragraph that closes a blockquote: how many enclosing quote levels continue past it (`Int`).
    /// `GlimmerLayoutFragment` stops the bars of the ending levels at the text instead of running into the gap.
    static let glimmerQuoteContinues = NSAttributedString.Key("glimmer.quoteContinues")
    /// The markdown for a list marker (`"- "`, `"3. "`, `"- [x] "`) on the marker text, used by copy.
    static let glimmerListMarker = NSAttributedString.Key("glimmer.listMarker")
    /// Markdown source (`String`) for an attachment or chip, used by copy.
    static let glimmerSource = NSAttributedString.Key("glimmer.source")
    /// The markdown before a paragraph's content on its first line, before any list marker: quote markers and list
    /// indentation (`String`, on a whole paragraph). Used by copy.
    static let glimmerMarkdownPrefix = NSAttributedString.Key("glimmer.markdownPrefix")
    /// `true` on a whole paragraph inside a tight list's item: copy joins such paragraphs without a blank line.
    static let glimmerTightList = NSAttributedString.Key("glimmer.tightList")
    /// `true` on text inside `**…**`. The font is bold too, but so are headings; copy reads this mark.
    static let glimmerStrong = NSAttributedString.Key("glimmer.strong")
    /// `true` on text inside `*…*`.
    static let glimmerEmphasis = NSAttributedString.Key("glimmer.emphasis")
}

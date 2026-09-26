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
}

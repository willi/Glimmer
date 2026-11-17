import SwiftUI

/// Short, finished markdown laid out by SwiftUI, block by block, with no text view.
///
/// Where `Text(GlimmerView.attributedString(…))` runs every block into one string, this view stacks the blocks, so
/// lists keep a hanging indent:
/// - Paragraphs and headings are `Text`s, spaced as `GlimmerView` spaces them.
/// - A list's items sit beside their markers, every line indented by the theme's `listIndent` (more for wide
///   numbers). Nested lists indent again, and task items show ☑︎ or ☐.
/// - A block quote's text is in the theme's `secondaryTextColor`, beside a bar in its `quoteBarColor`.
/// - A code block is its code in the theme's code font, wrapped, on the `codeBlockBackground`.
/// - A table is one line of text per row, with its cells separated by tabs. A thematic break is a 1 pt rule.
/// - Images are left out, and an extension's chip or token becomes its `displayText`, as in `attributedString`.
///
/// Links are tappable: they go to `onLinkTap`, or without one to the environment's `openURL`. Modifiers that apply to
/// `Text` through the environment, such as `.lineLimit(_:)`, apply to each block's `Text`, so a one-paragraph document
/// truncates as a `Text` does. VoiceOver reads a list item's marker with its first block, as `GlimmerView` reads the
/// line, and a heading as a heading of its level.
///
/// Every run of text carries the theme's font and colour, so `.font(_:)` and `.foregroundStyle(_:)` on this view
/// change nothing: set them in the configuration's theme. A document of paragraphs, headings and tables is as wide as
/// its widest line; one with a list, quote, code block or rule fills the width it is offered.
///
/// It differs from `GlimmerView` in two edge cases: a list item that starts with a code block, table or rule shows its
/// marker beside that block, where `GlimmerView` puts the marker on a line above it; and the space above a heading
/// that follows an empty quote at the start of a document differs from `GlimmerView`'s.
///
/// Documents are built once per markdown, theme, text size, extensions and highlighter, and shared between views
/// (least recently used out). As with `GlimmerView`'s settled answers, only built-in and `Hashable` extensions and
/// highlighters can be shared: with any other, each view builds its own document, and a change to that dependency
/// alone needs a new view identity, for example `.id(extensionVersion)`.
public struct GlimmerStaticText: View {
    private let markdown: String
    private let configuration: GlimmerConfiguration
    private let onLinkTap: ((URL) -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var memo = GlimmerStaticDocumentMemo()

    /// Creates a view that lays out `markdown`.
    ///
    /// - Parameters:
    ///   - markdown: The markdown to show.
    ///   - configuration: The theme and extensions to use. Its image loader and policy are ignored.
    ///   - onLinkTap: Called with a tapped link's URL. Nil leaves link taps to the environment's `openURL`: a handler
    ///     installed higher up with `.environment(\.openURL, …)`, or else the system.
    public init(_ markdown: String, configuration: GlimmerConfiguration = .default, onLinkTap: ((URL) -> Void)? = nil) {
        self.markdown = markdown
        self.configuration = configuration
        self.onLinkTap = onLinkTap
    }

    /// The blocks, stacked.
    public var body: some View {
        let document: GlimmerStaticDocument = memo.document(
            markdown: markdown, configuration: configuration, dynamicTypeSize: dynamicTypeSize,
            cache: GlimmerStaticDocumentCache.shared
        )
        let linkColor = Color(uiColor: document.theme.linkColor)
        GlimmerStaticBlocksView(blocks: document.blocks, theme: document.theme)
            .tint(linkColor)
            .modifier(GlimmerStaticLinkRouting(onLinkTap: onLinkTap))
    }
}

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
/// Links are tappable. Modifiers that apply to `Text` through the environment, such as `.lineLimit(_:)`, apply to each
/// block's `Text`, so a one-paragraph document truncates as a `Text` does.
///
/// The document is built once for its markdown and text size. The configuration is read with them: to apply a
/// different one, give the view a new identity, for example `.id(themeVersion)`, as with `GlimmerText`.
public struct GlimmerStaticText: View {
    private let markdown: String
    private let configuration: GlimmerConfiguration
    private let onLinkTap: ((URL) -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var cache = GlimmerStaticDocumentCache()

    /// Creates a view that lays out `markdown`.
    ///
    /// - Parameters:
    ///   - markdown: The markdown to show.
    ///   - configuration: The theme and extensions to use. Its image loader and policy are ignored.
    ///   - onLinkTap: Called with a tapped link's URL. Nil opens links with the environment's `openURL` fallback,
    ///     the system.
    public init(_ markdown: String, configuration: GlimmerConfiguration = .default, onLinkTap: ((URL) -> Void)? = nil) {
        self.markdown = markdown
        self.configuration = configuration
        self.onLinkTap = onLinkTap
    }

    /// The blocks, stacked.
    public var body: some View {
        let document = cache.document(markdown: markdown, configuration: configuration, dynamicTypeSize: dynamicTypeSize)
        GlimmerStaticBlocksView(blocks: document.blocks, theme: document.theme)
            .tint(Color(uiColor: document.theme.linkColor))
            .environment(\.openURL, Self.openURLAction(onLinkTap: onLinkTap))
    }

    /// Hands a tapped link to `onLinkTap`, or to the system when there is none.
    static func openURLAction(onLinkTap: ((URL) -> Void)?) -> OpenURLAction {
        OpenURLAction { url in
            guard let onLinkTap else { return .systemAction }
            onLinkTap(url)
            return .handled
        }
    }
}

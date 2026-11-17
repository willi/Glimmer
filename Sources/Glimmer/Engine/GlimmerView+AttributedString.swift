import SwiftUI
import UIKit

extension GlimmerView {
    /// Markdown composed into an `AttributedString`, for short text that SwiftUI's `Text` shows without a text view.
    ///
    /// The configuration's extensions preprocess and scan the markdown, and its theme (scaled for `traitCollection`)
    /// styles it. The result is static and can't show everything a `GlimmerView` does:
    /// - Images are left out, with the space around them.
    /// - A code block becomes its code, in the theme's code font. A table becomes one line per row, with its cells
    ///   separated by tabs. A thematic break is dropped.
    /// - An extension's chip or token becomes its `displayText`, linked to the token's `url` when it has one.
    ///
    /// The fonts are scaled once, for `traitCollection`, and keep that size. Compute the string again when the text size
    /// changes (see `attributedString(for:configuration:dynamicTypeSize:)`), because `.current` is not reliably the
    /// hosting view's traits while a SwiftUI body runs.
    ///
    /// Every run carries both the UIKit attributes (`font`, `foregroundColor`) and the SwiftUI ones, so `Text` and a
    /// UIKit label read the same string.
    ///
    /// - Parameters:
    ///   - markdown: The markdown to compose.
    ///   - configuration: The theme and extensions to use. Its image loader and policy are ignored.
    ///   - traitCollection: The traits that scale the theme's fonts for Dynamic Type.
    @MainActor
    public static func attributedString(
        for markdown: String, configuration: GlimmerConfiguration = .default, traitCollection: UITraitCollection = .current
    ) -> AttributedString {
        let theme = configuration.theme.scaled(for: traitCollection)
        let composer = GlimmerPlainText.composer(theme: theme, configuration: configuration)
        let source = configuration.extensions.prepared(markdown, isStreaming: false)
        return GlimmerPlainText.standalone(composer.compose(GlimmerParser.parse(source)), theme: theme)
    }

    /// Markdown composed into an `AttributedString`, scaled for a SwiftUI Dynamic Type size.
    ///
    /// Read `@Environment(\.dynamicTypeSize)` in the view that shows the string and pass it here: the result has fixed
    /// font sizes, so it must be computed again when the text size changes, and a body that reads the environment value
    /// is re-evaluated then. Everything else is as in `attributedString(for:configuration:traitCollection:)`.
    ///
    /// - Parameters:
    ///   - markdown: The markdown to compose.
    ///   - configuration: The theme and extensions to use. Its image loader and policy are ignored.
    ///   - dynamicTypeSize: The text size to scale the theme's fonts for.
    @MainActor
    public static func attributedString(
        for markdown: String, configuration: GlimmerConfiguration = .default, dynamicTypeSize: DynamicTypeSize
    ) -> AttributedString {
        attributedString(
            for: markdown, configuration: configuration,
            traitCollection: UITraitCollection(preferredContentSizeCategory: dynamicTypeSize.contentSizeCategory)
        )
    }
}

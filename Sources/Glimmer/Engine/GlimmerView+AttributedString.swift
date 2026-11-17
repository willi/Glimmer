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
        let composer = GlimmerComposer(
            theme: theme, highlighter: configuration.highlighter, imageLoader: nil,
            imagePolicy: GlimmerHideImagesPolicy(), extensions: configuration.extensions
        )
        let source = configuration.extensions.prepared(markdown, isStreaming: false)
        let composed = NSMutableAttributedString(attributedString: composer.compose(GlimmerParser.parse(source)))
        GlimmerPlainText.flatten(composed, theme: theme)
        return GlimmerPlainText.attributedString(from: composed)
    }
}

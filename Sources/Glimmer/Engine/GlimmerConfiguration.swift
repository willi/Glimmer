import UIKit

/// Everything a `GlimmerView` needs besides the markdown itself.
public struct GlimmerConfiguration: Sendable {
    public var theme: GlimmerTheme
    public var extensions: [any GlimmerExtension]
    /// Loads standalone images. `nil` shows each image's alt text in its reserved box.
    public var imageLoader: (any GlimmerImageLoader)?
    public var highlighter: any GlimmerHighlighter

    public init(
        theme: GlimmerTheme = .default,
        extensions: [any GlimmerExtension] = [],
        imageLoader: (any GlimmerImageLoader)? = GlimmerURLSessionImageLoader(),
        highlighter: any GlimmerHighlighter = GlimmerBasicHighlighter()
    ) {
        self.theme = theme
        self.extensions = extensions
        self.imageLoader = imageLoader
        self.highlighter = highlighter
    }

    public static var `default`: GlimmerConfiguration { GlimmerConfiguration() }
}

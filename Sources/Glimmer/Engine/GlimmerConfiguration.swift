import UIKit

/// Everything a `GlimmerView` needs besides the markdown itself.
public struct GlimmerConfiguration: Sendable {
    public var theme: GlimmerTheme
    public var extensions: [any GlimmerExtension]
    /// Loads standalone images. `nil` shows each image's alt text in its reserved box.
    public var imageLoader: (any GlimmerImageLoader)?
    public var highlighter: any GlimmerHighlighter
    /// How streaming text appears. Reduce Motion always shows text immediately.
    public var reveal: GlimmerReveal
    /// Data detectors on the text (phone numbers, addresses, …). Off by default: they cost main-thread time.
    public var dataDetectors: UIDataDetectorTypes
    /// Whether the text offers the system Find interaction.
    public var allowsFind: Bool

    public init(
        theme: GlimmerTheme = .default,
        extensions: [any GlimmerExtension] = [],
        imageLoader: (any GlimmerImageLoader)? = GlimmerURLSessionImageLoader(),
        highlighter: any GlimmerHighlighter = GlimmerBasicHighlighter(),
        reveal: GlimmerReveal = .smooth(GlimmerRevealOptions()),
        dataDetectors: UIDataDetectorTypes = [],
        allowsFind: Bool = false
    ) {
        self.theme = theme
        self.extensions = extensions
        self.imageLoader = imageLoader
        self.highlighter = highlighter
        self.reveal = reveal
        self.dataDetectors = dataDetectors
        self.allowsFind = allowsFind
    }

    public static var `default`: GlimmerConfiguration { GlimmerConfiguration() }
}

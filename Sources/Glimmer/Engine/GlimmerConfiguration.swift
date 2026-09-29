import UIKit

/// Everything a `GlimmerView` needs besides the markdown itself.
public struct GlimmerConfiguration: Sendable {
    public var theme: GlimmerTheme
    public var extensions: [any GlimmerExtension]
    /// Loads images: standalone ones, in a reserved box, and ones inside a paragraph, in a line-height square. `nil`
    /// shows a standalone image's alt text in its box and leaves an inline placeholder.
    public var imageLoader: (any GlimmerImageLoader)?
    /// The shape of images inside text. Defaults to a circle; the reserved line-height square never changes size.
    public var inlineImageShape: GlimmerInlineImageShape
    public var highlighter: any GlimmerHighlighter
    /// How streaming text appears. Reduce Motion always shows text immediately.
    public var reveal: GlimmerReveal
    /// Data detectors on the text (phone numbers, addresses, …). Off by default: they cost main-thread time.
    public var dataDetectors: UIDataDetectorTypes
    /// Whether the text offers the system Find interaction.
    public var allowsFind: Bool
    /// Whether scrolling and streaming reuse the text TextKit already drew (iOS 27). On by default; turn it off if
    /// text ever shows stale pixels.
    public var reusesDrawnText: Bool

    public init(
        theme: GlimmerTheme = .default,
        extensions: [any GlimmerExtension] = [],
        imageLoader: (any GlimmerImageLoader)? = GlimmerURLSessionImageLoader(),
        inlineImageShape: GlimmerInlineImageShape = .circle,
        highlighter: any GlimmerHighlighter = GlimmerBasicHighlighter(),
        reveal: GlimmerReveal = .smooth(GlimmerRevealOptions()),
        dataDetectors: UIDataDetectorTypes = [],
        allowsFind: Bool = false,
        reusesDrawnText: Bool = true
    ) {
        self.theme = theme
        self.extensions = extensions
        self.imageLoader = imageLoader
        self.inlineImageShape = inlineImageShape
        self.highlighter = highlighter
        self.reveal = reveal
        self.dataDetectors = dataDetectors
        self.allowsFind = allowsFind
        self.reusesDrawnText = reusesDrawnText
    }

    public static var `default`: GlimmerConfiguration { GlimmerConfiguration() }
}

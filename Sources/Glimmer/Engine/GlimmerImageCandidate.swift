import Foundation

/// An image Glimmer is about to show, as a `GlimmerImagePolicy` sees it.
public struct GlimmerImageCandidate: Sendable, Hashable {
    /// Where an image came from.
    public enum Origin: Sendable, Hashable {
        /// Written as an image in the markdown, inline or reference-style: `![alt](url "title")`.
        case markdown
        /// Produced by an extension's token (`GlimmerInlineToken.Presentation.image`), such as an emoji shortcode.
        /// `kind` is the token's kind.
        case extensionToken(kind: String)
    }

    /// The URL as written, whatever its scheme: a relative name, a `file:` URL and a `data:` URL are asked about
    /// too.
    public var url: URL
    /// The alt text, without its markdown. For an extension's token, its `displayText`.
    public var alt: String
    /// The title, when the markdown gives one.
    public var title: String?
    /// Whether the markdown or an extension produced the image.
    public var origin: Origin

    /// Creates a candidate, for example to test a policy.
    public init(url: URL, alt: String, title: String? = nil, origin: Origin) {
        self.url = url
        self.alt = alt
        self.title = title
        self.origin = origin
    }
}

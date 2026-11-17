import Foundation

/// A link Glimmer is about to show, as a `GlimmerLinkPolicy` sees it.
public struct GlimmerLinkCandidate: Sendable, Hashable {
    /// The destination as the parser read it, after escapes and entities are decoded. A bare URL's destination is its
    /// full URL: `www.example.com` links to `http://www.example.com`.
    public let destination: String
    /// `destination` as a URL, or `nil` when it does not parse. A link whose destination does not parse is shown as
    /// text, and the policy is not asked about it.
    public let url: URL?
    /// The title, when the markdown gives one: `[text](url "title")`.
    public let title: String?

    /// Creates a candidate, for example to test a policy. `url` is `URL(string: destination)`.
    public init(destination: String, title: String? = nil) {
        self.destination = destination
        self.url = URL(string: destination)
        self.title = title
    }
}

import Foundation

/// What Glimmer does with an image, as decided by a `GlimmerImagePolicy`.
public enum GlimmerImageDecision: Sendable, Hashable {
    /// Load and show the image.
    case load
    /// Show the alt text as ordinary text, styled like the text around it. An image with empty alt text shows
    /// nothing. An extension's image shows its token's `displayText`: `:name:` for an emoji shortcode.
    case showAltText
    /// Show nothing.
    case hide
}

/// Decides which images Glimmer loads. Set one on `GlimmerConfiguration.imagePolicy`.
///
/// Markdown written by a language model can carry an image URL that leaks data the moment it is requested. With a
/// policy, Glimmer asks before it creates any image. An image that is not loaded is never requested, from the network
/// or from a cache, and reserves no space in the text.
///
/// The policy is asked from any thread, and more than once for the same image: each time the text is composed while
/// an answer streams, and again just before the load. Answer quickly, and always the same for the same image. Two
/// policies that compare equal must decide equally, because views with equal policies share composed answers.
public protocol GlimmerImagePolicy: Sendable, Hashable {
    /// What to do with `image`.
    func decision(for image: GlimmerImageCandidate) -> GlimmerImageDecision
}

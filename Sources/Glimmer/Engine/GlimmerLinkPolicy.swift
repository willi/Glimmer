import Foundation

/// What Glimmer does with a link, as decided by a `GlimmerLinkPolicy`.
public enum GlimmerLinkDecision: Sendable, Hashable {
    /// Show it as a link: in the link colour, underlined when the theme says so, and tappable.
    case link
    /// Show its text as ordinary text, styled like the text around it: no link colour, no underline, nothing to tap.
    /// Styles inside the link, such as bold, stay.
    case text
}

/// Decides which links in the markdown become links. Set one on `GlimmerConfiguration.linkPolicy`.
///
/// Markdown written by a language model can carry a link that does something the moment it is tapped: a custom URL
/// scheme that pays, posts or opens another app. With a policy, Glimmer asks about every link the markdown parser
/// finds before it composes it: inline and reference links (`[text](url)`), autolinks (`<url>`) and bare URLs
/// (`https://…`, `www.…`). A link whose URL does not parse is text, and the policy is not asked about it. A link the
/// policy refuses is ordinary text, and copies as its text without its URL. The policy is not asked about an
/// extension's token URLs, which the extension sets (in `attributedString` and `GlimmerStaticText` they become links),
/// or about what data detectors find.
///
/// The policy is asked from any thread, and more than once for the same link: each time the text is composed while an
/// answer streams. Answer quickly, and always the same for the same link. Two policies that compare equal must decide
/// equally, because views with equal policies share composed answers.
public protocol GlimmerLinkPolicy: Sendable, Hashable {
    /// What to do with `link`.
    func decision(for link: GlimmerLinkCandidate) -> GlimmerLinkDecision
}

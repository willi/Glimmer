import Foundation

/// `@username` mentions, by GitHub's rules: `@` then letters, digits and single hyphens, up to 39 characters, not in an
/// email address, a domain (`@example.com`), code or a link. A mention stays text, in the theme's mention colour, and
/// a tap reports it through `GlimmerView.onTokenTap` (kind "mention", payload "username"). Opt-in: add it to
/// `GlimmerConfiguration.extensions`.
public struct GlimmerMentions: GlimmerExtension {
    public init() {}

    // A mention can't follow a word character (an email) or be followed by a hyphen, a word character, or a dot and more
    // of a domain. NSRegularExpression: Swift regex literals don't do lookbehind.
    nonisolated(unsafe) private static let mention = try? NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_@])@([A-Za-z0-9](?:-?[A-Za-z0-9]){0,38})(?![A-Za-z0-9-]|\.[A-Za-z0-9])"#
    )
    nonisolated(unsafe) private static let partial = try? NSRegularExpression(pattern: #"(?<![A-Za-z0-9_@])@[A-Za-z0-9-]{0,39}\.?$"#)

    public var appliesInsideLinks: Bool { false }

    public func scan(_ text: String) -> [GlimmerInlineToken] {
        guard text.contains("@"), let expression = Self.mention else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text), let name = Range(match.range(at: 1), in: text) else { return nil }
            let username = String(text[name])
            return GlimmerInlineToken(
                range: range, kind: "mention", payload: ["username": username], displayText: "@" + username,
                source: "@" + username, presentation: .text(tappable: true)
            )
        }
    }

    /// A mention still being typed at the very end: it would turn into a domain or change colour once complete.
    public func streamingHoldBack(in markdown: String) -> Int {
        guard let last = markdown.last, last != " ", last != "\n", let expression = Self.partial else { return 0 }
        let tail = String(markdown.suffix(41))
        guard let match = expression.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail)),
              let range = Range(match.range, in: tail) else { return 0 }
        return tail[range].count
    }
}

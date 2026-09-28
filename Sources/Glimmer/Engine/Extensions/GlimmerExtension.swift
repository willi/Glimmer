import UIKit

/// A custom inline token found in a run of plain text (a mention, a citation, …).
public struct GlimmerInlineToken: Equatable, Sendable {
    /// Range in the text passed to `GlimmerExtension.scan(_:)`.
    public var range: Range<String.Index>
    public var kind: String
    public var payload: [String: String]
    /// Plain text used when there is no view, and for accessibility.
    public var displayText: String
    /// Markdown copied for this token.
    public var source: String
    /// What VoiceOver reads for the chip, e.g. "Mention, Ada". Defaults to `displayText`.
    public var accessibilityLabel: String?
    /// How the token shows: a chip (the default), text, or an inline image.
    public var presentation: Presentation

    public enum Presentation: Sendable, Equatable {
        /// The extension's view, or a label with `displayText`.
        case chip
        /// `displayText` as text; with `tappable`, in the theme's mention colour and reported through `onTokenTap`.
        case text(tappable: Bool)
        /// An inline image from the URL, a line-height square like any image inside a paragraph; `displayText` is its
        /// alt text.
        case image(URL)
    }

    public init(
        range: Range<String.Index>, kind: String, payload: [String: String] = [:], displayText: String, source: String,
        accessibilityLabel: String? = nil, presentation: Presentation = .chip
    ) {
        self.range = range
        self.kind = kind
        self.payload = payload
        self.displayText = displayText
        self.source = source
        self.accessibilityLabel = accessibilityLabel
        self.presentation = presentation
    }
}

/// Adds custom syntax to Glimmer.
public protocol GlimmerExtension: Sendable {
    /// Rewrites markdown before parsing, for example turning a custom token into a standard link.
    func preprocess(_ markdown: String) -> String
    /// Finds tokens in a run of plain text. Returned ranges must index into `text`.
    func scan(_ text: String) -> [GlimmerInlineToken]
    /// The view shown for a token, sized to the line height. Return nil to show `displayText` as a label.
    @MainActor func makeInlineView(for token: GlimmerInlineToken, theme: GlimmerTheme) -> UIView?
    /// Whether `scan` also runs on a link's text. Mentions don't: `[@ada](url)` stays a link.
    var appliesInsideLinks: Bool { get }
    /// How many characters at the end of a streaming answer to hold back: a token still being typed (`:rock`, `@gra`)
    /// that would restyle once complete. Keep it short; the reveal waits on it.
    func streamingHoldBack(in markdown: String) -> Int
}

extension GlimmerExtension {
    public func preprocess(_ markdown: String) -> String { markdown }
    public func scan(_ text: String) -> [GlimmerInlineToken] { [] }
    @MainActor public func makeInlineView(for token: GlimmerInlineToken, theme: GlimmerTheme) -> UIView? { nil }
    public var appliesInsideLinks: Bool { true }
    public func streamingHoldBack(in markdown: String) -> Int { 0 }
}

extension Sequence where Element == any GlimmerExtension {
    /// `markdown` without the tail the extensions hold back while streaming, then preprocessed by each extension.
    func prepared(_ markdown: String, isStreaming: Bool) -> String {
        var visible = markdown
        if isStreaming {
            let held = map { $0.streamingHoldBack(in: markdown) }.max() ?? 0
            // Capped so a misbehaving extension can't stall the reveal; 64 covers GitHub's longest mention and a period.
            if held > 0 { visible = String(markdown.dropLast(Swift.min(held, 64))) }
        }
        return reduce(visible) { $1.preprocess($0) }
    }
}

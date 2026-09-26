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

    public init(
        range: Range<String.Index>, kind: String, payload: [String: String] = [:], displayText: String, source: String,
        accessibilityLabel: String? = nil
    ) {
        self.range = range
        self.kind = kind
        self.payload = payload
        self.displayText = displayText
        self.source = source
        self.accessibilityLabel = accessibilityLabel
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
}

extension GlimmerExtension {
    public func preprocess(_ markdown: String) -> String { markdown }
    public func scan(_ text: String) -> [GlimmerInlineToken] { [] }
    @MainActor public func makeInlineView(for token: GlimmerInlineToken, theme: GlimmerTheme) -> UIView? { nil }
}

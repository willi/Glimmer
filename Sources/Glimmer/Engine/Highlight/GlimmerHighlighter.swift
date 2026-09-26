import Foundation

/// A colored range in a code block.
public struct GlimmerHighlightSpan: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case keyword, string, comment, number
    }

    /// UTF-16 range into the highlighted code.
    public var range: NSRange
    public var kind: Kind

    public init(range: NSRange, kind: Kind) {
        self.range = range
        self.kind = kind
    }
}

/// Supplies syntax colors for code blocks. Later spans win where spans overlap.
public protocol GlimmerHighlighter: Sendable {
    func highlight(_ code: String, language: String?) -> [GlimmerHighlightSpan]
}

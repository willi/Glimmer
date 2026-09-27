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
///
/// Glimmer calls `highlight(_:language:)` off the main thread, on each view's worker, and several views' workers can
/// call one highlighter at the same time: it must be safe to call concurrently. While an answer streams, it is called
/// again with the whole code, open last line included, for every update that touches the block, so its cost should
/// grow no faster than the code. A settled answer is highlighted once, on the main thread, when it is first shown.
public protocol GlimmerHighlighter: Sendable {
    func highlight(_ code: String, language: String?) -> [GlimmerHighlightSpan]
}

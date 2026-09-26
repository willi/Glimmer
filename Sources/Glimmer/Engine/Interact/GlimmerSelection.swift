import Foundation

/// A selection in an answer, as host menu actions receive it.
public struct GlimmerSelection: Sendable {
    /// UTF-16 offsets into the shown text.
    public let range: NSRange
    public let plainText: String
    public let markdown: String
}

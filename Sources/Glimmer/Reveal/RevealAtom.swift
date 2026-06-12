import SwiftUI

/// One revealable unit, in document order, with a stable identity (spec 4.1).
public struct RevealAtom: Identifiable, Sendable {
    public enum Kind: Sendable {
        /// A single word (or character, per granularity), fully styled.
        case text(AttributedString)
        /// Inter-word whitespace; visible with the preceding word, not counted.
        case space(AttributedString)
        /// Forced line break (soft/hard break, or after a line-granularity row).
        case lineBreak
        /// Whole-unit block (code/table/image/hr/...) — see `RevealBlock.node`.
        case block
    }

    /// Global, stable, monotonically assigned by document order. Appending
    /// text to the buffer only appends atoms; existing ids never change.
    public let id: Int
    public let kind: Kind
    /// Whether this atom counts toward `revealedCount` (words/chars/blocks: yes).
    public let isCountable: Bool
    /// 1-based ordinal among countable atoms for countable atoms; for
    /// non-countable atoms, the ordinal of the nearest preceding countable
    /// atom (0 if none). Visible iff `revealIndex <= revealedCount`.
    public let revealIndex: Int
    /// Link target, if this atom is part of a link (kept tappable, spec R7).
    public let url: URL?
}

/// A layout unit for the flow layout: one word (1 word atom or N char atoms),
/// one whitespace run, or one line break. Char-granularity styles animate per
/// atom but wrap per word.
public struct RevealWord: Identifiable, Sendable {
    /// The id of the first atom (stable for the same reasons atom ids are).
    public let id: Int
    public let atoms: [RevealAtom]
    public let isWhitespace: Bool
    public let isLineBreak: Bool
}

/// A block of the document with its reveal-relevant layout tag (spec 4.6).
public struct RevealBlock: Identifiable, Sendable {
    /// Ordinal of this block in the flattened document.
    public let id: Int
    public let kind: BlockKindTag
    /// Inline layout units; empty when `kind == .wholeBlock`... (see node).
    public let words: [RevealWord]
    /// The parsed node, set only for `.wholeBlock`, rendered via Glimmer's
    /// existing block view when revealed.
    public let node: MarkdownParser.BlockNode?
    /// The block becomes visible once `revealedCount >= firstRevealIndex`.
    public let firstRevealIndex: Int
}

/// The flattened reveal model for a buffer (spec §5, advanced hosts).
public struct RevealModel: Sendable {
    public let blocks: [RevealBlock]
    /// Total number of countable atoms (the driver's drain target).
    public let countableCount: Int

    public static let empty = RevealModel(blocks: [], countableCount: 0)
}

public extension Glimmer {
    /// Parses and flattens markdown into the reveal model used by
    /// `GlimmerRevealView` — exposed for advanced hosts (spec §5).
    static func revealModel(
        _ markdown: String,
        style: RevealStyle,
        configuration: MarkdownConfiguration = .default
    ) -> RevealModel {
        let blocks = parse(markdown, configuration: configuration)
        return RevealFlattener.flatten(
            blocks,
            granularity: style.granularity,
            configuration: configuration
        )
    }
}

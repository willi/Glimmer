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
        /// Whole-unit block (image/hr/html/...) — see `RevealBlock.node`.
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
    /// The parsed node, rendered via Glimmer's existing block view once the
    /// reveal treatment allows settled rendering.
    public let node: MarkdownParser.BlockNode?
    /// The block becomes visible once `revealedCount >= firstRevealIndex`.
    public let firstRevealIndex: Int

    /// Identity for SwiftUI diffing: changes when a streaming block changes
    /// shape (e.g. paragraph -> codeBlock once a code fence completes), so
    /// the new representation transitions in instead of mutating in place.
    public var viewIdentity: String {
        switch kind {
        case .paragraph: "\(id)-p"
        case .heading(let level): "\(id)-h\(level)"
        case .listItem(let marker, let depth): "\(id)-li\(depth)-\(marker)"
        case .blockquote(let depth): "\(id)-q\(depth)"
        case .codeBlock(let language): "\(id)-code-\(language ?? "")"
        case .table: "\(id)-table"
        case .wholeBlock: "\(id)-b"
        }
    }
}

/// The flattened reveal model for a buffer (spec §5, advanced hosts).
public struct RevealModel: Sendable {
    public let blocks: [RevealBlock]
    /// Total number of countable atoms (the driver's drain target).
    public let countableCount: Int
    /// Total atoms, including non-countable spaces and line breaks.
    let atomCount: Int

    init(blocks: [RevealBlock], countableCount: Int, atomCount: Int) {
        self.blocks = blocks
        self.countableCount = countableCount
        self.atomCount = atomCount
    }

    init(blocks: [RevealBlock], countableCount: Int) {
        self.init(
            blocks: blocks,
            countableCount: countableCount,
            atomCount: blocks.reduce(0) { total, block in
                total + block.words.reduce(0) { $0 + $1.atoms.count }
            }
        )
    }

    public static let empty = RevealModel(blocks: [], countableCount: 0, atomCount: 0)
}

extension RevealModel {
    func offsetBy(atomID atomOffset: Int, blockID blockOffset: Int, countable countableOffset: Int) -> RevealModel {
        guard atomOffset != 0 || blockOffset != 0 || countableOffset != 0 else {
            return self
        }

        let adjustedBlocks = blocks.map { block in
            let adjustedWords = block.words.map { word in
                let adjustedAtoms = word.atoms.map { atom in
                    RevealAtom(
                        id: atom.id + atomOffset,
                        kind: atom.kind,
                        isCountable: atom.isCountable,
                        revealIndex: atom.revealIndex + countableOffset,
                        url: atom.url
                    )
                }
                return RevealWord(
                    id: word.id + atomOffset,
                    atoms: adjustedAtoms,
                    isWhitespace: word.isWhitespace,
                    isLineBreak: word.isLineBreak
                )
            }

            let firstRevealIndex = block.firstRevealIndex == Int.max
                ? Int.max
                : block.firstRevealIndex + countableOffset
            return RevealBlock(
                id: block.id + blockOffset,
                kind: block.kind,
                words: adjustedWords,
                node: block.node,
                firstRevealIndex: firstRevealIndex
            )
        }

        return RevealModel(blocks: adjustedBlocks, countableCount: countableCount + countableOffset)
    }
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

import UIKit

/// A change to a document's text: replace `range` of the previous text with `replacement`.
struct GlimmerDocumentEdit {
    let range: NSRange
    let replacement: NSAttributedString
}

/// The document behind a streaming `GlimmerView`.
///
/// Each update re-parses from the start of the second-to-last top-level block, re-composes only blocks that differ,
/// and returns one edit covering the changed tail. Two blocks, not one: appended text can still pull the last block
/// into its predecessor (a lone `|` line parses as a paragraph until its cells arrive and it joins the table above).
/// Anything that is not an append, or that uses link reference definitions, re-parses in full. `text` always equals a
/// fresh `compose(parse(…))` of the same (healed) markdown.
@MainActor
final class GlimmerStreamingDocument {
    private(set) var text = NSMutableAttributedString()
    private(set) var blocks: [GlimmerBlock] = []
    /// UTF-16 offset in `text` where each block's composed text starts.
    private(set) var blockOffsets: [Int] = []

    private var fragments: [NSAttributedString] = []
    private var startLines: [Int] = []
    private var source = ""
    private let composer: GlimmerComposer

    init(composer: GlimmerComposer) {
        self.composer = composer
    }

    /// Moves the document to `markdown` (already preprocessed by extensions). Returns the edit that turns the previous
    /// `text` into the new one, or nil when nothing changed.
    func update(markdown: String, isStreaming: Bool) -> GlimmerDocumentEdit? {
        let newSource = isStreaming ? GlimmerTailHealer.heal(markdown) : markdown
        guard newSource != source else { return nil }
        let parsed = parse(newSource)
        source = newSource

        var firstChanged = parsed.searchFrom
        while firstChanged < min(blocks.count, parsed.blocks.count), blocks[firstChanged] == parsed.blocks[firstChanged] {
            firstChanged += 1
        }
        guard firstChanged < max(blocks.count, parsed.blocks.count) else {
            startLines = parsed.startLines
            return nil
        }

        let prefixLength = firstChanged > 0 ? blockOffsets[firstChanged - 1] + fragments[firstChanged - 1].length : 0
        var newFragments = Array(fragments[..<firstChanged])
        var newOffsets = Array(blockOffsets[..<firstChanged])
        var running = prefixLength
        for index in firstChanged..<parsed.blocks.count {
            let fragment = composer.composeBlock(parsed.blocks[index], isFirst: index == 0)
            newFragments.append(fragment)
            newOffsets.append(running)
            running += fragment.length
        }
        let newTextLength = max(0, running - 1)
        let editStart = min(prefixLength, text.length, newTextLength)

        // The new text from `editStart` to its end: the tail of the last kept block's newline, then the new blocks.
        let replacement = NSMutableAttributedString()
        if editStart < prefixLength, firstChanged > 0 {
            let previous = newFragments[firstChanged - 1]
            let keep = prefixLength - editStart
            replacement.append(previous.attributedSubstring(from: NSRange(location: previous.length - keep, length: keep)))
        }
        for fragment in newFragments[firstChanged...] { replacement.append(fragment) }
        let expectedLength = newTextLength - editStart
        if replacement.length > expectedLength {
            replacement.deleteCharacters(in: NSRange(location: expectedLength, length: replacement.length - expectedLength))
        }

        let edit = GlimmerDocumentEdit(range: NSRange(location: editStart, length: text.length - editStart), replacement: replacement)
        text.replaceCharacters(in: edit.range, with: replacement)
        blocks = parsed.blocks
        startLines = parsed.startLines
        fragments = newFragments
        blockOffsets = newOffsets
        return edit
    }

    // MARK: - Parsing

    /// Blocks and start lines for `newSource`, plus the first block index that could differ from the current blocks.
    private func parse(_ newSource: String) -> (blocks: [GlimmerBlock], startLines: [Int], searchFrom: Int) {
        let tailIndex = max(0, startLines.count - 2)
        if tailIndex < startLines.count,
           !Self.hasLinkReferenceDefinition(newSource),
           let oldTailStart = Self.index(ofLine: startLines[tailIndex], in: source),
           newSource.utf8.starts(with: source.utf8[..<oldTailStart]),
           let newTailStart = Self.index(ofLine: startLines[tailIndex], in: newSource) {
            let tailLine = startLines[tailIndex]
            let tail = GlimmerParser.parseWithLines(String(newSource[newTailStart...]))
            return (
                Array(blocks[..<tailIndex]) + tail.map(\.block),
                Array(startLines[..<tailIndex]) + tail.map { $0.startLine + tailLine - 1 },
                tailIndex
            )
        }
        let all = GlimmerParser.parseWithLines(newSource)
        return (all.map(\.block), all.map(\.startLine), 0)
    }

    /// Where 1-based `line` starts in `string`, or nil if the string has fewer lines.
    static func index(ofLine line: Int, in string: String) -> String.Index? {
        guard line > 1 else { return string.startIndex }
        var newlines = 0
        var index = string.utf8.startIndex
        while index < string.utf8.endIndex {
            if string.utf8[index] == UInt8(ascii: "\n") {
                newlines += 1
                if newlines == line - 1 { return string.utf8.index(after: index) }
            }
            index = string.utf8.index(after: index)
        }
        return nil
    }

    /// Link reference definitions can change earlier blocks, so a document using them always re-parses in full.
    static func hasLinkReferenceDefinition(_ markdown: String) -> Bool {
        markdown.contains(#/(?m)^ {0,3}\[[^\]]+\]:/#)
    }
}

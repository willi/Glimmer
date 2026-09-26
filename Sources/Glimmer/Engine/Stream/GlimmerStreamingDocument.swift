import UIKit

/// A change to a document's text: replace `range` of the previous text with `replacement`.
struct GlimmerDocumentEdit {
    let range: NSRange
    let replacement: NSAttributedString
    /// Attachments kept across the re-compose whose embeds grew, in document order.
    var embedUpdates: [GlimmerEmbedUpdate] = []
}

/// The document behind a streaming `GlimmerView`.
///
/// Each update re-parses from the start of the second-to-last top-level block, re-composes only blocks that differ,
/// and returns one edit covering the changed tail. Two blocks, not one: appended text can still pull the last block
/// into its predecessor (a lone `|` line parses as a paragraph until its cells arrive and it joins the table above).
/// Anything that is not an append, or that uses link reference definitions, re-parses in full. `text` always equals a
/// fresh `compose(parse(…))` of the same (healed) markdown.
///
/// One owner at a time: it is built on the main thread for a synchronous configure, then handed to a
/// `GlimmerDocumentWorker`, which alone uses it from then on.
final class GlimmerStreamingDocument: @unchecked Sendable {
    private(set) var text = NSMutableAttributedString()
    private(set) var blocks: [GlimmerBlock] = []
    /// UTF-16 offset in `text` where each block's composed text starts.
    private(set) var blockOffsets: [Int] = []

    private var fragments: [NSAttributedString] = []
    /// Each block's attachments, with the embeds they were composed with and their offsets in the block's fragment.
    private var blockAttachments: [[GlimmerEmbeddedAttachment]] = []

    /// Embeds that reveal in units: document offset → each unit's text length.
    var embedUnits: [Int: [Int]] {
        var units: [Int: [Int]] = [:]
        for record in embeddedAttachments {
            let lengths = record.embed.revealUnitLengths
            if !lengths.isEmpty { units[record.offset] = lengths }
        }
        return units
    }

    /// Every block attachment in `text`, at its document offset, with its current embed.
    var embeddedAttachments: [(offset: Int, attachment: GlimmerBlockAttachment, embed: GlimmerEmbed)] {
        zip(blockOffsets, blockAttachments).flatMap { blockOffset, records in
            records.map { (blockOffset + $0.offset, $0.attachment, $0.embed) }
        }
    }
    private var startLines: [Int] = []
    private var source = ""
    /// UTF-8 offset in `source` where the second-to-last block starts: where the next tail re-parse begins.
    private var tailOffset: Int?
    /// The unhealed markdown of the last update, to tell an append from a replacement.
    private var rawMarkdown = ""
    private var fenceScan = GlimmerTailHealer.FenceScan()
    /// Whether `rawMarkdown` defines link references; once one appears, every update re-parses in full.
    private var usesReferenceDefinitions = false
    private let composer: GlimmerComposer

    init(composer: GlimmerComposer) {
        self.composer = composer
    }

    /// Moves the document to `markdown` (already preprocessed by extensions). Returns the edit that turns the previous
    /// `text` into the new one, or nil when nothing changed.
    func update(markdown: String, isStreaming: Bool) -> GlimmerDocumentEdit? {
        let isAppend = Self.utf8(of: markdown, startsWith: rawMarkdown, count: rawMarkdown.utf8.count)
        noteReferenceDefinitions(in: markdown, isAppend: isAppend)
        if !isAppend || !isStreaming { fenceScan = GlimmerTailHealer.FenceScan() }
        rawMarkdown = markdown
        let newSource = isStreaming ? GlimmerTailHealer.heal(markdown, fenceScan: &fenceScan) : markdown
        guard newSource != source else { return nil }
        let parsed = parse(newSource)
        source = newSource
        tailOffset = parsed.tailOffset

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
        var newAttachments = Array(blockAttachments[..<min(firstChanged, blockAttachments.count)])
        var embedUpdates: [GlimmerEmbedUpdate] = []
        var running = prefixLength
        for index in firstChanged..<parsed.blocks.count {
            // Only this block's own previous attachments are offered back, so an unchanged block never loses one.
            let reuse = GlimmerAttachmentReuse(index < blockAttachments.count ? blockAttachments[index] : [])
            let fragment = composer.composeBlock(parsed.blocks[index], isFirst: index == 0, reusing: reuse)
            newFragments.append(fragment)
            newOffsets.append(running)
            newAttachments.append(reuse.emitted)
            embedUpdates += reuse.updates
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

        let edit = Self.trimmingUnchangedParagraphs(
            of: GlimmerDocumentEdit(range: NSRange(location: editStart, length: text.length - editStart), replacement: replacement,
                                    embedUpdates: embedUpdates),
            in: text
        )
        text.replaceCharacters(in: edit.range, with: edit.replacement)
        blocks = parsed.blocks
        startLines = parsed.startLines
        fragments = newFragments
        blockOffsets = newOffsets
        blockAttachments = newAttachments
        return edit
    }

    /// Drops the leading paragraphs of `edit` that already match `text`. A block re-composes whole — a long list
    /// when only its last item grew — but TextKit then re-lays out only the paragraphs that really changed.
    static func trimmingUnchangedParagraphs(of edit: GlimmerDocumentEdit, in text: NSAttributedString) -> GlimmerDocumentEdit {
        let old = text.attributedSubstring(from: edit.range)
        let new = edit.replacement
        let commonCharacters = (old.string as NSString).commonPrefix(with: new.string, options: .literal).utf16.count
        let newString = new.string as NSString
        func paragraphStart(before end: Int) -> Int {
            guard end > 0 else { return 0 }
            let newline = newString.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: end))
            return newline.location == NSNotFound ? 0 : NSMaxRange(newline)
        }
        // The paragraph where the text diverges changes; so may the ones before it (a tight list's old last item
        // changes its spacing). Walk back to the last paragraph whose attributes still match.
        var keep = paragraphStart(before: commonCharacters)
        while keep > 0 {
            let previous = paragraphStart(before: keep - 1)
            let range = NSRange(location: previous, length: keep - previous)
            if old.attributedSubstring(from: range).isEqual(to: new.attributedSubstring(from: range)) { break }
            keep = previous
        }
        // Everything kept must match, not just the paragraph checked last.
        guard keep > 0, old.attributedSubstring(from: NSRange(location: 0, length: keep))
            .isEqual(to: new.attributedSubstring(from: NSRange(location: 0, length: keep))) else { return edit }
        return GlimmerDocumentEdit(
            range: NSRange(location: edit.range.location + keep, length: edit.range.length - keep),
            replacement: new.attributedSubstring(from: NSRange(location: keep, length: new.length - keep)),
            embedUpdates: edit.embedUpdates
        )
    }

    // MARK: - Parsing

    /// Blocks and start lines for `newSource`, the first block index that could differ from the current blocks, and
    /// where the next update's tail re-parse starts.
    private func parse(_ newSource: String) -> (blocks: [GlimmerBlock], startLines: [Int], searchFrom: Int, tailOffset: Int?) {
        let tailIndex = max(0, startLines.count - 2)
        if tailIndex < startLines.count, !usesReferenceDefinitions, let tailOffset,
           Self.utf8(of: newSource, startsWith: source, count: tailOffset) {
            let tailLine = startLines[tailIndex]
            let newTailStart = newSource.utf8.index(newSource.startIndex, offsetBy: tailOffset)
            let tail = GlimmerParser.parseWithLines(String(newSource[newTailStart...]))
            let blocks = Array(blocks[..<tailIndex]) + tail.map(\.block)
            let lines = Array(startLines[..<tailIndex]) + tail.map { $0.startLine + tailLine - 1 }
            // The next tail usually starts inside this one: count lines from here rather than from the top.
            guard let nextLine = lines.isEmpty ? nil : lines[max(0, lines.count - 2)] else { return (blocks, lines, tailIndex, nil) }
            let nextOffset = nextLine >= tailLine
                ? Self.utf8Offset(ofLine: nextLine - tailLine + 1, in: newSource, from: newTailStart).map { tailOffset + $0 }
                : Self.utf8Offset(ofLine: nextLine, in: newSource, from: newSource.startIndex)
            return (blocks, lines, tailIndex, nextOffset)
        }
        let all = GlimmerParser.parseWithLines(newSource)
        let lines = all.map(\.startLine)
        let nextOffset = lines.isEmpty ? nil : Self.utf8Offset(ofLine: lines[max(0, lines.count - 2)], in: newSource, from: newSource.startIndex)
        return (all.map(\.block), lines, 0, nextOffset)
    }

    /// The UTF-8 offset, from `start`, where 1-based `line` (counted from `start`) begins; nil past the last line.
    static func utf8Offset(ofLine line: Int, in string: String, from start: String.Index) -> Int? {
        let utf8 = string.utf8
        var index = start
        var remaining = line - 1
        while remaining > 0 {
            guard let newline = utf8[index...].firstIndex(of: UInt8(ascii: "\n")) else { return nil }
            index = utf8.index(after: newline)
            remaining -= 1
        }
        return utf8.distance(from: start, to: index)
    }

    /// Whether the first `count` UTF-8 bytes of `string` equal those of `prefix`.
    static func utf8(of string: String, startsWith prefix: String, count: Int) -> Bool {
        guard count > 0 else { return true }
        guard string.utf8.count >= count, prefix.utf8.count >= count else { return false }
        return string.utf8.withContiguousStorageIfAvailable { lhs in
            prefix.utf8.withContiguousStorageIfAvailable { rhs in
                memcmp(lhs.baseAddress!, rhs.baseAddress!, count) == 0
            }
        }.flatMap { $0 } ?? string.utf8.prefix(count).elementsEqual(prefix.utf8.prefix(count))
    }

    /// Link reference definitions can change earlier blocks, so once one appears every update re-parses in full. An
    /// append is checked from the line it extends, not from the top.
    private func noteReferenceDefinitions(in markdown: String, isAppend: Bool) {
        guard !isAppend || !usesReferenceDefinitions else { return }
        var checkFrom = markdown.startIndex
        if isAppend, let lastNewline = rawMarkdown.utf8.lastIndex(of: UInt8(ascii: "\n")) {
            checkFrom = markdown.utf8.index(markdown.startIndex, offsetBy: rawMarkdown.utf8.distance(from: rawMarkdown.startIndex, to: lastNewline) + 1)
        }
        let found = Self.hasLinkReferenceDefinition(markdown[checkFrom...])
        usesReferenceDefinitions = isAppend ? usesReferenceDefinitions || found : found
    }

    static func hasLinkReferenceDefinition(_ markdown: Substring) -> Bool {
        markdown.contains(#/(?m)^ {0,3}\[[^\]]+\]:/#)
    }
}

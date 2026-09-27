import Foundation

/// Closes markdown that is still being typed at the end of a streaming buffer, so half-finished syntax renders in its
/// final style instead of as raw markers that restyle a moment later. Only an open code fence or the last paragraph is
/// touched; everything before it is returned unchanged. Apply it only while streaming.
enum GlimmerTailHealer {
    /// Fence state carried across calls on a growing buffer, so each call scans only lines it has not seen. Reset it
    /// (assign a fresh value) whenever the buffer is replaced rather than appended to.
    struct FenceScan {
        /// UTF-8 offset just past the last complete line scanned.
        fileprivate var scannedTo = 0
        fileprivate var open: OpenFence?
    }

    fileprivate struct OpenFence {
        let marker: Character
        let count: Int
        let prefix: String
    }

    static func heal(_ markdown: String) -> String {
        var scan = FenceScan()
        return heal(markdown, fenceScan: &scan)
    }

    /// Heals `markdown`, which extends the buffer `fenceScan` last saw.
    static func heal(_ markdown: String, fenceScan: inout FenceScan) -> String {
        if let fence = openFence(in: markdown, scan: &fenceScan) {
            return markdown + (markdown.hasSuffix("\n") ? "" : "\n") + fence
        }
        let tailStart = lastParagraphStart(in: markdown)
        var tail = String(markdown[tailStart...])
        tail = holdBackTableHeader(tail)
        tail = holdBackOpeningPipe(tail)
        tail = holdBackSetextUnderline(tail)
        tail = holdBackFootnoteStarts(tail)
        tail = holdBackPartialBreakTag(tail)
        tail = healLinks(tail)
        tail = closeInlineDelimiters(tail)
        return String(markdown[..<tailStart]) + tail
    }

    /// Where the paragraph still being typed starts: after the last blank line, or at the last line opening a list
    /// item, whichever is later. Inline syntax cannot span either, so nothing before it needs healing — and a long
    /// answer is not re-scanned on every update.
    private static func lastParagraphStart(in markdown: String) -> String.Index {
        var lineEnd = markdown.endIndex
        var isLastLine = true
        while true {
            let lineStart = markdown[..<lineEnd].lastIndex(of: "\n").map { markdown.index(after: $0) } ?? markdown.startIndex
            if lineStart == lineEnd, !isLastLine { return markdown.index(after: lineEnd) }
            if lineStart == markdown.startIndex || containerPrefix(of: markdown[lineStart..<lineEnd]).opensListItem {
                return lineStart
            }
            lineEnd = markdown.index(before: lineStart)
            isLastLine = false
        }
    }

    // MARK: - Code fences

    /// The line that would close a fence still open at the end of `markdown`, or nil. It repeats the opener's quote
    /// markers and indentation, so a fence inside a list item or a quote closes there instead of starting a new block.
    static func openFence(in markdown: String) -> String? {
        var scan = FenceScan()
        return openFence(in: markdown, scan: &scan)
    }

    private static func openFence(in markdown: String, scan: inout FenceScan) -> String? {
        let utf8 = markdown.utf8
        var lineStart = utf8.index(utf8.startIndex, offsetBy: min(scan.scannedTo, utf8.count))
        while let newline = utf8[lineStart...].firstIndex(of: UInt8(ascii: "\n")) {
            scan.open = fenceState(after: markdown[lineStart..<newline], from: scan.open)
            lineStart = utf8.index(after: newline)
            scan.scannedTo = utf8.distance(from: utf8.startIndex, to: lineStart)
        }
        // The last line may still change, so it is scanned every time but never committed.
        return fenceState(after: markdown[lineStart...], from: scan.open).map { $0.prefix + String(repeating: $0.marker, count: $0.count) }
    }

    /// The open fence after `line`, given the open fence before it.
    private static func fenceState(after line: Substring, from open: OpenFence?) -> OpenFence? {
        let (prefix, content, _) = containerPrefix(of: line)
        guard let first = content.first, first == "`" || first == "~" else { return open }
        let run = content.prefix { $0 == first }.count
        guard run >= 3 else { return open }
        let rest = content.dropFirst(run)
        if let open {
            return first == open.marker && run >= open.count && rest.allSatisfy({ $0 == " " }) ? nil : open
        }
        return first == "~" || !rest.contains("`") ? OpenFence(marker: first, count: run, prefix: prefix) : nil
    }

    /// Splits a line into its container prefix — indentation, quote markers, list markers — and its content. The
    /// prefix comes back as a continuation line would write it: quote markers kept, list markers turned into spaces.
    private static func containerPrefix(of line: Substring) -> (prefix: String, content: Substring, opensListItem: Bool) {
        var prefix = ""
        var rest = line
        var opensListItem = false
        while let first = rest.first {
            if first == " " || first == ">" {
                prefix.append(first)
                rest = rest.dropFirst()
            } else if first == "\t" {
                prefix.append("    ")
                rest = rest.dropFirst()
            } else if "-*+".contains(first), rest.dropFirst().first == " " {
                prefix.append("  ")
                rest = rest.dropFirst(2)
                opensListItem = true
            } else if let number = orderedListMarkerLength(rest) {
                prefix.append(String(repeating: " ", count: number))
                rest = rest.dropFirst(number)
                opensListItem = true
            } else {
                break
            }
        }
        return (prefix, rest, opensListItem)
    }

    /// The length of an ordered list marker and its space (`12. `) at the start of `text`, or nil.
    private static func orderedListMarkerLength(_ text: Substring) -> Int? {
        let digits = text.prefix { $0.isASCII && $0.isNumber }.count
        guard (1...9).contains(digits) else { return nil }
        let after = text.dropFirst(digits)
        guard let delimiter = after.first, delimiter == "." || delimiter == ")", after.dropFirst().first == " " else { return nil }
        return digits + 2
    }

    // MARK: - Tables

    /// A table header waiting for its delimiter row (`| a | b |`, or `| a | b |` over a partial `|--`) renders raw
    /// pipes if shown early; hold it back until the delimiter row is complete.
    private static func holdBackTableHeader(_ tail: String) -> String {
        var lines = tail.components(separatedBy: "\n")
        let pipeLines = lines.indices.filter { lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("|") }
        guard let header = pipeLines.first, let last = pipeLines.last,
              lines[(last + 1)...].allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return tail }
        switch pipeLines.count {
        case 1:
            break
        case 2 where last == header + 1 && isIncompleteDelimiterRow(lines[last], columns: cells(of: lines[header]).count):
            break
        default:
            return tail
        }
        lines.removeSubrange(header...)
        return lines.joined(separator: "\n") + (header > 0 ? "\n" : "")
    }

    /// A last line that is only a pipe (a table row just begun) parses as a paragraph "|" below the table, then joins
    /// the table when its first cell arrives; hold it back until then.
    private static func holdBackOpeningPipe(_ tail: String) -> String {
        guard let newline = tail.lastIndex(of: "\n") else { return tail }
        let lastLine = tail[tail.index(after: newline)...]
        guard lastLine.trimmingCharacters(in: .whitespaces) == "|" else { return tail }
        return String(tail[...newline])
    }

    /// Whether `line` is a delimiter row still being typed: only `|`, `-`, `:` and spaces, but not yet one valid cell
    /// per column.
    private static func isIncompleteDelimiterRow(_ line: String, columns: Int) -> Bool {
        guard line.allSatisfy({ "|-: ".contains($0) }) else { return false }
        let cells = cells(of: line)
        return cells.count != columns || !cells.allSatisfy { $0.contains(#/^\s*:?-+:?\s*$/#) }
    }

    /// The cells of a pipe table row, without its outer pipes.
    private static func cells(of row: String) -> [Substring] {
        var body = Substring(row.trimmingCharacters(in: .whitespaces))
        if body.hasPrefix("|") { body = body.dropFirst() }
        if body.hasSuffix("|") { body = body.dropLast() }
        guard !body.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return body.split(separator: "|", omittingEmptySubsequences: false)
    }

    /// A line of only `-` or `=` right under paragraph text is a setext underline, or the start of a list item or
    /// rule; shown early it would flip the paragraph above into a heading and back. Hold it back until the next line.
    private static func holdBackSetextUnderline(_ tail: String) -> String {
        var lines = tail.components(separatedBy: "\n")
        guard lines.count >= 2, let last = lines.last,
              last.contains(#/^ {0,3}(-+|=+) *$/#),
              !lines[lines.count - 2].trimmingCharacters(in: .whitespaces).isEmpty else { return tail }
        lines.removeLast()
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Links and images

    /// A footnote marker still being typed (`[^`, `[^lab`) waits until it closes, and so does a last line that is only a
    /// marker (`[^1]`, `[^1]:`): it may be a definition starting, which would take the line away again.
    private static func holdBackFootnoteStarts(_ tail: String) -> String {
        if let match = tail.firstMatch(of: #/(?m)^[ ]{0,3}\[\^[^\]\s]+\]:?[ \t]*$/#), match.range.upperBound == tail.endIndex {
            return String(tail[..<match.range.lowerBound])
        }
        if let match = tail.firstMatch(of: #/\[\^[^\]\s]*$/#) {
            return String(tail[..<match.range.lowerBound])
        }
        return tail
    }

    /// A `<br>` still arriving (`<`, `<b`, `<br /`) waits: shown as text, it would turn into a line break.
    private static func holdBackPartialBreakTag(_ tail: String) -> String {
        guard tail.last != ">", let match = tail.firstMatch(of: #/<(?:[bB](?:[rR]\s*/?)?)?$/#) else { return tail }
        return String(tail[..<match.range.lowerBound])
    }

    private static func healLinks(_ tail: String) -> String {
        // `![alt` or `![alt](partial` — hold the whole image back until it is complete.
        if let match = tail.firstMatch(of: #/!\[[^\]]*(\]\([^)\s]*)?$/#) {
            return String(tail[..<match.range.lowerBound])
        }
        // `[text](partial` — close the destination so the text already renders as a link.
        if tail.firstMatch(of: #/\[[^\]]*\]\([^)\s]*$/#) != nil {
            return tail + ")"
        }
        // `[text]` — may still become a link (or an extension token); hold it back for a moment. A complete footnote
        // marker `[^label]` shows at once.
        if let match = tail.firstMatch(of: #/\[[^\]]*\]$/#), !tail[match.range].hasPrefix("[^") {
            return String(tail[..<match.range.lowerBound])
        }
        // `[partial` — drop the bracket and keep the text.
        if let match = tail.firstMatch(of: #/\[[^\]]*$/#) {
            var healed = tail
            healed.remove(at: match.range.lowerBound)
            return healed
        }
        return tail
    }

    // MARK: - Emphasis, strikethrough, code spans

    /// Closes `**`, `*`, `__`, `_`, `~~` and `` ` `` left open, innermost first, before any trailing whitespace (a closer after a
    /// space would not be right-flanking). A dangling opener with nothing after it is dropped instead.
    private static func closeInlineDelimiters(_ tail: String) -> String {
        var body = tail
        var trailing = ""
        func moveTrailingWhitespace() {
            while let last = body.last, last.isWhitespace {
                trailing.insert(last, at: trailing.startIndex)
                body.removeLast()
            }
        }
        moveTrailingWhitespace()
        var open = openDelimiters(in: body)
        while let last = open.last, body.hasSuffix(last) {
            body.removeLast(last.count)
            open.removeLast()
            moveTrailingWhitespace()
        }
        return body + open.reversed().joined() + trailing
    }

    private static func openDelimiters(in text: String) -> [String] {
        var open: [String] = []
        let characters = Array(text)
        var index = 0
        var atLineStart = true
        func toggle(_ marker: String) {
            if let existing = open.lastIndex(of: marker) { open.remove(at: existing) } else { open.append(marker) }
        }
        func next(_ offset: Int) -> Character? {
            index + offset < characters.count ? characters[index + offset] : nil
        }
        /// Underscores between letters or digits never open or close emphasis (`snake_case` stays literal).
        func isIntraword(at position: Int, length: Int) -> Bool {
            let before = position > 0 ? characters[position - 1] : " "
            let after = position + length < characters.count ? characters[position + length] : " "
            return (before.isLetter || before.isNumber) && (after.isLetter || after.isNumber)
        }
        while index < characters.count {
            let character = characters[index]
            if open.last == "`" {
                if character == "`" { open.removeLast() }
                index += 1
                atLineStart = false
                continue
            }
            switch character {
            case "\n":
                atLineStart = true
                index += 1
                continue
            case " ", "\t":
                index += 1
                continue
            case "`":
                open.append("`")
            case "*" where next(1) == "*":
                toggle("**")
                index += 2
                atLineStart = false
                continue
            case "*" where atLineStart && next(1) == " ":
                break // a list bullet, not emphasis
            case "*":
                toggle("*")
            case "_" where next(1) == "_":
                if !isIntraword(at: index, length: 2) { toggle("__") }
                index += 2
                atLineStart = false
                continue
            case "_":
                if !isIntraword(at: index, length: 1) { toggle("_") }
            case "~" where next(1) == "~":
                toggle("~~")
                index += 2
                atLineStart = false
                continue
            default:
                break
            }
            atLineStart = false
            index += 1
        }
        return open
    }
}

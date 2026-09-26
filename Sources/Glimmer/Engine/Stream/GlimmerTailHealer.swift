import Foundation

/// Closes markdown that is still being typed at the end of a streaming buffer, so half-finished syntax renders in its
/// final style instead of as raw markers that restyle a moment later. Only an open code fence or the last paragraph is
/// touched; everything before it is returned unchanged. Apply it only while streaming.
enum GlimmerTailHealer {
    static func heal(_ markdown: String) -> String {
        if let fence = openFence(in: markdown) {
            return markdown + (markdown.hasSuffix("\n") ? "" : "\n") + fence
        }
        let tailStart = markdown.range(of: "\n\n", options: .backwards)?.upperBound ?? markdown.startIndex
        var tail = String(markdown[tailStart...])
        tail = holdBackTableHeader(tail)
        tail = healLinks(tail)
        tail = closeInlineDelimiters(tail)
        return String(markdown[..<tailStart]) + tail
    }

    // MARK: - Code fences

    /// The fence that would close a fence still open at the end of `markdown`, or nil.
    static func openFence(in markdown: String) -> String? {
        var open: (marker: Character, count: Int)?
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let content = line.drop { $0 == " " }
            guard line.count - content.count <= 3, let first = content.first, first == "`" || first == "~" else { continue }
            let run = content.prefix { $0 == first }.count
            guard run >= 3 else { continue }
            let rest = content.dropFirst(run)
            if let current = open {
                if first == current.marker, run >= current.count, rest.allSatisfy({ $0 == " " }) { open = nil }
            } else if first == "~" || !rest.contains("`") {
                open = (first, run)
            }
        }
        return open.map { String(repeating: $0.marker, count: $0.count) }
    }

    // MARK: - Tables

    /// A lone `| a | b |` line is a table header waiting for its delimiter row; shown early it renders raw pipes.
    private static func holdBackTableHeader(_ tail: String) -> String {
        var lines = tail.components(separatedBy: "\n")
        let pipeLines = lines.indices.filter { lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("|") }
        guard pipeLines.count == 1, let index = pipeLines.first,
              lines[(index + 1)...].allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return tail }
        lines.removeSubrange(index...)
        return lines.joined(separator: "\n") + (index > 0 ? "\n" : "")
    }

    // MARK: - Links and images

    private static func healLinks(_ tail: String) -> String {
        // `![alt` or `![alt](partial` — hold the whole image back until it is complete.
        if let match = tail.firstMatch(of: #/!\[[^\]]*(\]\([^)\s]*)?$/#) {
            return String(tail[..<match.range.lowerBound])
        }
        // `[text](partial` — close the destination so the text already renders as a link.
        if tail.firstMatch(of: #/\[[^\]]*\]\([^)\s]*$/#) != nil {
            return tail + ")"
        }
        // `[text]` — may still become a link (or an extension token); hold it back for a moment.
        if let match = tail.firstMatch(of: #/\[[^\]]*\]$/#) {
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

    /// Closes `**`, `*`, `~~` and `` ` `` left open, innermost first, before any trailing whitespace (a closer after a
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

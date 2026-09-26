import UIKit

/// Turns composed text back into markdown or plain text, for copy and `GlimmerView.markdownSource(for:)`. It reads
/// what the composer records: each paragraph's container prefix (`glimmerMarkdownPrefix`), list markers
/// (`glimmerListMarker`), heading levels, tight lists, quote ends, inline styles, and the markdown source of embeds,
/// chips and inline images. A paragraph's block syntax is written only when the range includes its start.
enum GlimmerMarkdownSerializer {
    static func markdown(from text: NSAttributedString, range: NSRange) -> String {
        serialize(text, range: range, asMarkdown: true)
    }

    static func plainText(from text: NSAttributedString, range: NSRange) -> String {
        serialize(text, range: range, asMarkdown: false)
    }

    // MARK: - Paragraphs

    private struct Paragraph {
        /// The paragraph without its terminating newline.
        let content: NSRange
        let prefix: String
        let isTight: Bool
        /// Quote levels that continue past this paragraph, when it closes a quote.
        let quoteContinues: Int?
        let headingLevel: Int?
        /// Only a list marker: the item opens with a list or an embed, written on the next line.
        let isMarkerOnly: Bool

        init(_ text: NSAttributedString, range whole: NSRange) {
            var content = whole
            if content.length > 0, (text.string as NSString).character(at: NSMaxRange(content) - 1) == 0x0A {
                content.length -= 1
            }
            self.content = content
            let attributes = text.attributes(at: whole.location, effectiveRange: nil)
            prefix = attributes[.glimmerMarkdownPrefix] as? String ?? ""
            isTight = attributes[.glimmerTightList] as? Bool ?? false
            quoteContinues = attributes[.glimmerQuoteContinues] as? Int
            headingLevel = (attributes[.accessibilityTextHeadingLevel] as? Int).flatMap { $0 > 0 ? $0 : nil }
            var marker = NSRange()
            isMarkerOnly = content.length > 0
                && text.attribute(.glimmerListMarker, at: content.location, longestEffectiveRange: &marker, in: content) != nil
                && NSMaxRange(marker) >= NSMaxRange(content)
        }
    }

    private static func serialize(_ text: NSAttributedString, range: NSRange, asMarkdown: Bool) -> String {
        let string = text.string as NSString
        let wanted = NSIntersectionRange(range, NSRange(location: 0, length: string.length))
        guard wanted.length > 0 else { return "" }
        var output = ""
        var previous: Paragraph?
        var location = wanted.location
        while location < NSMaxRange(wanted) {
            let whole = string.paragraphRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(whole)
            let paragraph = Paragraph(text, range: whole)
            let includesStart = wanted.location <= paragraph.content.location
            let selected = NSIntersectionRange(paragraph.content, wanted)
            // A selection that starts on a paragraph's newline takes nothing from that paragraph.
            guard selected.length > 0 || includesStart else { continue }
            if let previous { output += separator(after: previous, before: paragraph, asMarkdown: asMarkdown) }
            output += write(paragraph, selected: selected, includesStart: includesStart, in: text, asMarkdown: asMarkdown)
            previous = paragraph
        }
        return output
    }

    /// One newline inside a tight list or after a marker-only line, else a blank line carrying the containers both
    /// paragraphs share.
    private static func separator(after first: Paragraph, before second: Paragraph, asMarkdown: Bool) -> String {
        guard asMarkdown else { return "\n" }
        if first.isMarkerOnly || (first.isTight && second.isTight) { return "\n" }
        var shared = String(zip(first.prefix, second.prefix).prefix { $0 == $1 }.map(\.0))
        if let continuing = first.quoteContinues {
            // The first paragraph closes quote levels: only the ones that continue carry across the blank line.
            var kept = ""
            var quotes = 0
            for character in shared {
                if character == ">" {
                    guard quotes < continuing else { break }
                    quotes += 1
                }
                kept.append(character)
            }
            shared = kept
        }
        while shared.last == " " { shared.removeLast() }
        return "\n" + shared + "\n"
    }

    private static func write(
        _ paragraph: Paragraph, selected: NSRange, includesStart: Bool, in text: NSAttributedString, asMarkdown: Bool
    ) -> String {
        let string = text.string as NSString
        var marker = ""
        var body = ""
        var segments: [Segment] = []
        func flush() {
            body += asMarkdown ? inlineMarkdown(segments) : segments.map(\.text).joined()
            segments.removeAll()
        }
        if selected.length > 0 {
            text.enumerateAttributes(in: selected, options: []) { attributes, run, _ in
                if let source = attributes[.glimmerListMarker] as? String {
                    if includesStart { marker = source }
                } else if let attachment = attributes[.attachment] as? GlimmerBlockAttachment {
                    flush()
                    body += asMarkdown ? attributes[.glimmerSource] as? String ?? "" : plainText(of: attachment.embed)
                } else if let chip = attributes[.attachment] as? GlimmerInlineAttachment {
                    flush()
                    body += asMarkdown ? chip.token.source : chip.token.displayText
                } else if let source = attributes[.glimmerSource] as? String {
                    // An inline image's alt text: written once, however its runs split.
                    var whole = NSRange()
                    _ = text.attribute(.glimmerSource, at: run.location, longestEffectiveRange: &whole, in: selected)
                    flush()
                    if whole.location == run.location { body += asMarkdown ? source : string.substring(with: whole) }
                } else {
                    segments.append(Segment(text: string.substring(with: run), style: Style(attributes)))
                }
            }
            flush()
        }
        guard asMarkdown else { return marker + body.replacingOccurrences(of: "\u{2028}", with: "\n") }
        // Later lines of the paragraph (an embed's source, a hard break) continue inside its containers.
        let continuation = includesStart ? paragraph.prefix + String(repeating: " ", count: marker.count) : ""
        body = body.replacingOccurrences(of: "\u{2028}", with: "\\\n")
            .replacingOccurrences(of: "\n", with: "\n" + continuation)
        guard includesStart else { return body }
        let heading = paragraph.headingLevel.map { String(repeating: "#", count: $0) + " " } ?? ""
        return paragraph.prefix + marker + heading + escapingBlockStart(body)
    }

    // MARK: - Inline runs

    private struct Segment {
        var text: String
        let style: Style
    }

    private struct Style: Equatable {
        /// Outermost first.
        let marks: [Mark]
        let isCode: Bool

        init(_ attributes: [NSAttributedString.Key: Any]) {
            var marks: [Mark] = []
            if let url = attributes[.link] as? URL { marks.append(.link(url)) }
            if attributes[.glimmerStrong] as? Bool == true { marks.append(.strong) }
            if attributes[.glimmerEmphasis] as? Bool == true { marks.append(.emphasis) }
            if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 { marks.append(.strikethrough) }
            self.marks = marks
            isCode = attributes[.glimmerInlineCode] as? Bool ?? false
        }
    }

    private enum Mark: Equatable {
        case link(URL), strong, emphasis, strikethrough

        var opening: String {
            switch self {
            case .link: "["
            case .strong: "**"
            case .emphasis: "*"
            case .strikethrough: "~~"
            }
        }

        var closing: String {
            switch self {
            case .link(let url): "](\(GlimmerMarkdownSerializer.destination(url)))"
            case .strong: "**"
            case .emphasis: "*"
            case .strikethrough: "~~"
            }
        }
    }

    /// Writes styled runs, opening and closing marks as the style changes, so nesting comes back as it was parsed
    /// (`**a *b* c**`). A delimiter never has whitespace on its inner side (`** bold**` would not parse): edge
    /// whitespace moves outside it.
    private static func inlineMarkdown(_ segments: [Segment]) -> String {
        // One piece per style: two code spans side by side would read as one span.
        var merged: [Segment] = []
        for segment in segments {
            if let last = merged.last, last.style == segment.style {
                merged[merged.count - 1].text += segment.text
            } else {
                merged.append(segment)
            }
        }
        var output = ""
        var open: [Mark] = []
        func close(from index: Int) {
            let trailing = String(output.reversed().prefix(while: \.isWhitespace).reversed())
            output.removeLast(trailing.count)
            for mark in open[index...].reversed() { output += mark.closing }
            open.removeSubrange(index...)
            output += trailing
        }
        for segment in merged {
            if let stale = open.firstIndex(where: { !segment.style.marks.contains($0) }) { close(from: stale) }
            var piece = segment.style.isCode ? codeSpan(segment.text) : escaped(segment.text)
            let opening = segment.style.marks.filter { !open.contains($0) }
            if !opening.isEmpty {
                let leading = String(piece.prefix(while: \.isWhitespace))
                piece.removeFirst(leading.count)
                output += leading
                // Whitespace alone opens nothing; the next styled piece opens the marks.
                if !piece.isEmpty {
                    output += opening.map(\.opening).joined()
                    open += opening
                }
            }
            output += piece
        }
        if !open.isEmpty { close(from: 0) }
        return output
    }

    private static func codeSpan(_ code: String) -> String {
        let fence = String(repeating: "`", count: longestBacktickRun(in: code) + 1)
        // A span that starts or ends with a backtick, or with a space at both ends, needs a space inside the fence.
        let pads = code.hasPrefix("`") || code.hasSuffix("`")
            || (code.hasPrefix(" ") && code.hasSuffix(" ") && code.contains { $0 != " " })
        let pad = pads ? " " : ""
        return fence + pad + code + pad + fence
    }

    static func longestBacktickRun(in text: String) -> Int {
        var longest = 0
        var current = 0
        for character in text {
            current = character == "`" ? current + 1 : 0
            longest = max(longest, current)
        }
        return longest
    }

    private static func destination(_ url: URL) -> String {
        let string = url.absoluteString
        return string.contains { $0 == " " || $0 == "(" || $0 == ")" } ? "<\(string)>" : string
    }

    /// Backslash-escapes characters that could start inline syntax.
    private static func escaped(_ text: String) -> String {
        var result = ""
        for character in text {
            if "\\`*_[]<~".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }

    /// Escapes a paragraph start that would read as block syntax: a heading, a quote, a bullet or a numbered item.
    private static func escapingBlockStart(_ body: String) -> String {
        if body.hasPrefix("#") || body.hasPrefix(">") { return "\\" + body }
        if body == "-" || body == "+" || body.hasPrefix("- ") || body.hasPrefix("+ ") { return "\\" + body }
        if let match = body.prefixMatch(of: #/(\d{1,9})[.)](?: |$)/#) {
            return String(match.1) + "\\" + body[match.1.endIndex...]
        }
        return body
    }

    // MARK: - Embeds

    private static func plainText(of embed: GlimmerEmbed) -> String {
        switch embed {
        case .codeBlock(_, let code):
            code
        case .table(let header, let rows, _):
            ([header] + rows).map { $0.map(\.string).joined(separator: "\t") }.joined(separator: "\n")
        case .image(_, let alt):
            alt
        case .thematicBreak:
            "---"
        }
    }
}

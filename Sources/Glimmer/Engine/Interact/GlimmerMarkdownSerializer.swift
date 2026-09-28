import UIKit

/// Turns composed text back into markdown or plain text, for copy and `GlimmerView.markdownSource(for:)`. It reads
/// what the composer records: each paragraph's container prefix (`glimmerMarkdownPrefix`), list markers
/// (`glimmerListMarker`), heading levels, tight lists, quote ends, inline styles, and the markdown source of embeds,
/// chips and inline images. A paragraph's block syntax is written only when the range includes its start.
enum GlimmerMarkdownSerializer {
    static func markdown(from text: NSAttributedString, range: NSRange) -> String {
        serialize(text, range: range, asMarkdown: true)
    }

    /// `forAccessibility` reads chips by their accessibility label, as VoiceOver reads a settled chip.
    static func plainText(from text: NSAttributedString, range: NSRange, forAccessibility: Bool = false) -> String {
        serialize(text, range: range, asMarkdown: false, forAccessibility: forAccessibility)
    }

    // MARK: - Paragraphs

    private struct Paragraph {
        /// The paragraph without its terminating newline.
        let content: NSRange
        let prefix: String
        /// Each enclosing list's tightness, outermost first.
        let tightness: [Bool]
        /// Starts with a list marker.
        let hasMarker: Bool
        /// The marker paragraph of a list's first item.
        let opensList: Bool
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
            tightness = attributes[.glimmerListTightness] as? [Bool] ?? []
            hasMarker = content.length > 0 && text.attribute(.glimmerListMarker, at: content.location, effectiveRange: nil) != nil
            opensList = attributes[.glimmerListOpens] as? Bool ?? false
            quoteContinues = attributes[.glimmerQuoteContinues] as? Int
            headingLevel = (attributes[.accessibilityTextHeadingLevel] as? Int).flatMap { $0 > 0 ? $0 : nil }
            var marker = NSRange()
            isMarkerOnly = content.length > 0
                && text.attribute(.glimmerListMarker, at: content.location, longestEffectiveRange: &marker, in: content) != nil
                && NSMaxRange(marker) >= NSMaxRange(content)
        }
    }

    private static func serialize(
        _ text: NSAttributedString, range: NSRange, asMarkdown: Bool, forAccessibility: Bool = false
    ) -> String {
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
            // An embed with no source (the rule above footnotes) is decoration: it writes nothing, not even a gap.
            if paragraph.content.length > 0, text.attribute(.attachment, at: paragraph.content.location, effectiveRange: nil) is GlimmerBlockAttachment,
               text.attribute(.glimmerSource, at: paragraph.content.location, effectiveRange: nil) as? String == "" {
                continue
            }
            let includesStart = wanted.location <= paragraph.content.location
            let selected = NSIntersectionRange(paragraph.content, wanted)
            // A selection that starts on a paragraph's newline, or on a marker-only line's tab, takes nothing from it.
            guard selected.length > 0 || includesStart else { continue }
            let written = write(paragraph, selected: selected, includesStart: includesStart, in: text,
                                asMarkdown: asMarkdown, forAccessibility: forAccessibility)
            guard includesStart || !written.isEmpty else { continue }
            if let previous { output += separator(after: previous, before: paragraph, asMarkdown: asMarkdown) }
            output += written
            previous = paragraph
        }
        return output
    }

    /// One newline after a marker-only line or where the list holding both paragraphs is tight, else a blank line
    /// carrying the containers both paragraphs share.
    private static func separator(after first: Paragraph, before second: Paragraph, asMarkdown: Bool) -> String {
        guard asMarkdown else { return "\n" }
        if first.isMarkerOnly { return "\n" }
        if let level = gapLevel(before: second), second.tightness[level] { return "\n" }
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

    /// The list whose looseness decides the gap before `second`: its own list when it starts a later item of it, the
    /// enclosing item's list when it opens a nested list, and its innermost list when it continues an item. Nil
    /// outside lists and before a top-level list's first item.
    private static func gapLevel(before second: Paragraph) -> Int? {
        let depth = second.tightness.count - 1
        guard depth >= 0 else { return nil }
        guard second.hasMarker, second.opensList else { return depth }
        return depth > 0 ? depth - 1 : nil
    }

    private static func write(
        _ paragraph: Paragraph, selected: NSRange, includesStart: Bool, in text: NSAttributedString, asMarkdown: Bool,
        forAccessibility: Bool
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
                    // VoiceOver reads a footnote's number, not its markdown.
                    if includesStart, forAccessibility, source.hasPrefix("[^") {
                        // The marker spans runs (its number, then its tab): read the whole of it.
                        var whole = NSRange()
                        _ = text.attribute(.glimmerListMarker, at: run.location, longestEffectiveRange: &whole, in: paragraph.content)
                        marker = string.substring(with: whole).replacingOccurrences(of: "\t", with: "") + " "
                    } else if includesStart {
                        marker = source
                    }
                } else if let attachment = attributes[.attachment] as? GlimmerBlockAttachment {
                    flush()
                    body += asMarkdown ? attributes[.glimmerSource] as? String ?? "" : plainText(of: attachment.embed)
                } else if let image = attributes[.attachment] as? GlimmerInlineImageAttachment {
                    // Markdown writes the image inside its styles and link; plain text its alt text. VoiceOver reads
                    // the spoken-only alt text that follows it instead.
                    let source = attributes[.glimmerSource] as? String ?? ""
                    segments.append(Segment(text: asMarkdown ? source : forAccessibility ? "" : image.alt,
                                            style: Style(attributes), isVerbatim: true))
                } else if attributes[.glimmerSpokenOnly] as? Bool == true {
                    // Text only VoiceOver reads: part of the accessibility label, never of a copy.
                    if forAccessibility { segments.append(Segment(text: string.substring(with: run), style: Style(attributes))) }
                } else if let chip = attributes[.attachment] as? GlimmerInlineAttachment {
                    let token = chip.token
                    segments.append(Segment(
                        text: asMarkdown ? token.source : forAccessibility ? token.accessibilityLabel ?? token.displayText : token.displayText,
                        style: Style(attributes), isVerbatim: true
                    ))
                } else if let source = attributes[.glimmerSource] as? String {
                    // A token shown as text, a footnote marker, an image's fallback alt text: its source, verbatim,
                    // inside the run's styles and link (`**Thanks @ada!**`), once per run (`:tada::tada:`).
                    segments.append(Segment(text: asMarkdown ? source : string.substring(with: run),
                                            style: Style(attributes), isVerbatim: true))
                } else {
                    segments.append(Segment(text: string.substring(with: run), style: Style(attributes)))
                }
            }
            flush()
        }
        guard asMarkdown else { return marker + body.replacingOccurrences(of: "\u{2028}", with: "\n") }
        // Later lines of the paragraph (an embed's source, a hard break) continue inside its containers.
        let continuation = includesStart ? paragraph.prefix + continuation(ofMarker: marker) : ""
        if body.contains("\u{2028}") {
            // Each line after a hard break starts a line of the pasted markdown, so it escapes block syntax too.
            let lines = body.components(separatedBy: "\u{2028}")
            body = ([lines[0]] + lines.dropFirst().map(escapingBlockStart)).joined(separator: "\\\n" + continuation)
        } else {
            body = body.replacingOccurrences(of: "\n", with: "\n" + continuation)
        }
        // A marker alone on its line (the item opens with a list or an embed) needs no trailing space.
        if paragraph.isMarkerOnly { while marker.last == " " { marker.removeLast() } }
        guard includesStart else { return body }
        let heading = paragraph.headingLevel.map { String(repeating: "#", count: $0) + " " } ?? ""
        return paragraph.prefix + marker + heading + escapingBlockStart(body)
    }

    /// What a list item's later lines start with: spaces to its content column, where a task checkbox counts as
    /// content (`- [x] ` → two spaces, as GFM reads it), and any quote the item opens (`- > ` → `  > `).
    static func continuation(ofMarker marker: String) -> String {
        // A footnote's later lines are indented four spaces, as its definition's are.
        if marker.hasPrefix("[^") { return "    " }
        guard let space = marker.firstIndex(of: " ") else { return String(repeating: " ", count: marker.count) }
        var rest = String(marker[marker.index(after: space)...])
        if rest.hasPrefix("[ ] ") || rest.hasPrefix("[x] ") || rest.hasPrefix("[X] ") { rest.removeFirst(4) }
        return String(repeating: " ", count: marker.distance(from: marker.startIndex, to: space) + 1) + rest
    }

    // MARK: - Inline runs

    private struct Segment {
        var text: String
        let style: Style
        /// Markdown written as is (a token's source), not escaped as text.
        var isVerbatim = false
    }

    private struct Style: Equatable {
        /// Outermost first.
        let marks: [Mark]
        let isCode: Bool

        init(_ attributes: [NSAttributedString.Key: Any]) {
            var marks: [Mark] = []
            // A token's link is how UIKit reaches it, not part of the markdown.
            if let url = attributes[.link] as? URL, !GlimmerTokenBox.isInternalLink(url) { marks.append(.link(url)) }
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
        // One piece per style: two code spans side by side would read as one span. Text is escaped before merging, so
        // a verbatim source joins its neighbours unescaped; code stays raw until its span is written.
        var merged: [Segment] = []
        for segment in segments {
            let inLink = segment.style.marks.contains { if case .link = $0 { true } else { false } }
            let text = segment.style.isCode || segment.isVerbatim ? segment.text : escaped(segment.text, inLink: inLink)
            if let last = merged.last, last.style == segment.style {
                merged[merged.count - 1].text += text
            } else {
                merged.append(Segment(text: text, style: segment.style))
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
            var piece = segment.style.isCode ? codeSpan(segment.text) : segment.text
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

    /// Backslash-escapes characters that could start inline syntax. An underscore between two letters or digits
    /// never opens emphasis in CommonMark, and `&` only matters before something that could be an entity.
    private static func escaped(_ text: String, inLink: Bool) -> String {
        let characters = Array(text)
        var result = ""
        for (index, character) in characters.enumerated() {
            let before = index > 0 ? characters[index - 1] : nil
            let after = index + 1 < characters.count ? characters[index + 1] : nil
            switch character {
            case "\\", "`", "*", "[", "]", "<", "~":
                result.append("\\")
            case "_":
                let isWordCharacter = { (neighbor: Character?) in neighbor?.isLetter == true || neighbor?.isNumber == true }
                if !(isWordCharacter(before) && isWordCharacter(after)) { result.append("\\") }
            case "&":
                if let after, after.isLetter || after == "#" { result.append("\\") }
            case "@", ":", "#":
                // Would start an extension's token (a mention, a shortcode, a reference) on the way back in: the text
                // was one only if it is not a token here. A word before it (an email, a time) never starts one. Link
                // text keeps `@` and `#`: mention-like extensions skip links.
                let startsWord = before.map { !($0.isLetter || $0.isNumber) } ?? true
                if startsWord, !(inLink && character != ":"), let after, character == ":" ? closesShortcode(characters, from: index) : after.isLetter || after.isNumber,
                   character != "#" || after.isNumber {
                    result.append("\\")
                }
            default:
                break
            }
            result.append(character)
        }
        return result
    }

    /// Whether `:` at `index` opens a `:shortcode:`: a run of letters, digits, `_`, `+` or `-`, then `:`.
    private static func closesShortcode(_ characters: [Character], from index: Int) -> Bool {
        var cursor = index + 1
        while cursor < characters.count, characters[cursor].isLetter || characters[cursor].isNumber || "_+-".contains(characters[cursor]) {
            cursor += 1
        }
        return cursor > index + 1 && cursor < characters.count && characters[cursor] == ":"
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
        case .codeBlock(_, let code, _):
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

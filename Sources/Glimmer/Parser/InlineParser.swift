import Foundation

/// Handles parsing of inline markdown elements
public struct InlineParser {

    // MARK: - Main Inline Parsing

    public static func parseInlineOptimized(_ text: String, configuration: MarkdownConfiguration = .default) -> [MarkdownParser.InlineNode] {
        var state = ParserState(text: text)
        return parseInlineElements(&state, configuration: configuration)
    }
    // Fast-path is now per-state using ParserState.asciiFastPath

    static func parseInlineElements(_ state: inout ParserState, configuration: MarkdownConfiguration) -> [MarkdownParser.InlineNode] {
        var inlines: [MarkdownParser.InlineNode] = []
        var iterationCount = 0
        let maxIterations = configuration.maxInlineIterations


        // Decide ASCII fast-path once per state if not already set
        if state.asciiFastPath == false {
            state.asciiFastPath = ParsingHelpers.isASCII(state.text)
        }

        while !state.isAtEnd {
            iterationCount += 1
            if iterationCount > maxIterations {
                // Add remaining text as plain text and break
                let remaining = state.remainingSubstring()
                if !remaining.isEmpty { inlines.append(.text(remaining)) }
                break
            }

            let mark = state.mark()
            guard let ch = state.current() else { break }

            if let extensionInline = parseExtensionInline(&state, configuration: configuration) {
                state.flushFragmentBuffer(&inlines)
                inlines.append(extensionInline)
                continue
            }

            switch ch {
            case "\\":
                state.advance()
                if let escaped = state.current() {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(.text(String(escaped)))
                    state.advance()
                } else {
                    state.appendToFragmentBuffer("\\")
                }

            case "`":
                if let code = parseInlineCode(&state) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(code)
                } else {
                    state.appendToFragmentBuffer("`")
                    state.advance()
                }

            case "*", "_":
                if let emphasis = parseEmphasis(&state, delimiter: ch, configuration: configuration) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(emphasis)
                } else {
                    state.appendToFragmentBuffer(ch)
                    state.advance()
                }

            case "~":
                if let strikethrough = parseStrikethrough(&state, configuration: configuration) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(strikethrough)
                } else {
                    state.appendToFragmentBuffer(ch)
                    state.advance()
                }

            case "[":
                if configuration.enableFootnotes, let next = state.peek(1), next == "^" {
                    if let footnote = parseFootnoteReference(&state) {
                        state.flushFragmentBuffer(&inlines)
                        inlines.append(footnote)
                    } else {
                        state.appendToFragmentBuffer(ch)
                        state.advance()
                    }
                } else if let link = parseLink(&state, configuration: configuration) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(link)
                } else {
                    state.appendToFragmentBuffer(ch)
                    state.advance()
                }

            case "!":
                if let next = state.peek(1), next == "[" {
                    if let image = parseImage(&state, configuration: configuration) {
                        state.flushFragmentBuffer(&inlines)
                        inlines.append(image)
                    } else {
                        state.appendToFragmentBuffer(ch)
                        state.advance()
                    }
                } else {
                    state.appendToFragmentBuffer(ch)
                    state.advance()
                }

            case "<":
                if let autolink = parseUnifiedAutolink(&state, angleBracketMode: true) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(autolink)
                } else if let tag = parseHTMLTag(&state) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(tag)
                } else {
                    state.appendToFragmentBuffer(ch)
                    state.advance()
                }

            case "@":
                if configuration.enableMentions, let mention = parseMention(&state) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(mention)
                } else {
                    state.appendToFragmentBuffer(ch)
                    state.advance()
                }

            case "#":
                if configuration.enableIssueReferences, let issue = parseIssueReference(&state) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(issue)
                } else {
                    state.appendToFragmentBuffer(ch)
                    state.advance()
                }

            case ":":
                if configuration.enableEmojiShortcodes, let emoji = parseEmojiShortcode(&state) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(emoji)
                } else {

                    state.appendToFragmentBuffer(ch)
                    state.advance()
                }

            case "h", "m", "f", "w":
                // Prefer repository references first
                if configuration.enableRepositoryReferences, let repo = parseRepositoryReference(&state) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(repo)
                } else if configuration.enableAutolinks, let autolink = parseUnifiedAutolink(&state, angleBracketMode: false) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(autolink)
                } else {
                    state.appendToFragmentBuffer(ch)
                    state.advance()
                }

            default:
                if configuration.enableRepositoryReferences, ch.isLetter, let repo = parseRepositoryReference(&state) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(repo)
                } else if configuration.enableCommitSHAs, ParsingHelpers.isHexChar(ch), let sha = parseCommitSHA(&state) {
                    state.flushFragmentBuffer(&inlines)
                    inlines.append(sha)
                } else {
                    state.appendToFragmentBuffer(ch)
                    state.advance()
                }
            }

            // Safety check: ensure we made progress
            if state.currentIndex == mark.index {
                // Fallback consume one char
                if let c = state.current() { state.appendToFragmentBuffer(c); state.advance() }
            }
        }

        state.flushFragmentBuffer(&inlines)
        return inlines
    }

    static func parseExtensionInline(_ state: inout ParserState, configuration: MarkdownConfiguration) -> MarkdownParser.InlineNode? {
        guard !configuration.markdownExtensions.isEmpty, let ch = state.current() else { return nil }

        for markdownExtension in configuration.markdownExtensions
            where markdownExtension.shouldAttemptInlineParse(for: ch) {
            let context = MarkdownExtensionInlineContext(
                source: state.text,
                startIndex: state.currentIndex
            )
            guard let match = markdownExtension.parseInline(context),
                  match.endIndex > state.currentIndex,
                  match.endIndex <= state.endIndex else {
                continue
            }

            state.move(to: match.endIndex)
            return .extensionInline(
                MarkdownParser.ExtensionNode(
                    namespace: markdownExtension.id,
                    name: match.name,
                    literal: match.literal,
                    fields: match.fields
                )
            )
        }

        return nil
    }

    // MARK: - Inline Element Parsers

    static func parseInlineCode(_ state: inout ParserState) -> MarkdownParser.InlineNode? {

        let mark = state.mark()

        // Count opening backticks
        var opening = 0
        while let ch = state.current(), ch == "`" { opening += 1; state.advance() }
        guard opening > 0 else { state.restore(mark); return nil }

        var code = ""; code.reserveCapacity(32)
        while let ch = state.current() {
            if ch == "`" {
                // Count closing backticks
                var closing = 0
                while let c = state.current(), c == "`" { closing += 1; state.advance() }
                if closing == opening {
                    return .code(code.trimmingCharacters(in: .whitespaces))
                } else {
                    // Not matching, treat them as literal backticks
                    for _ in 0..<closing { code.append("`") }
                }
            } else {
                code.append(ch)
                state.advance()
            }
        }

        // No matching closing backticks
        state.restore(mark)
        return nil
    }

    static func parseEmphasis(_ state: inout ParserState, delimiter: Character, configuration: MarkdownConfiguration) -> MarkdownParser.InlineNode? {

        let mark = state.mark()
        // Optimistically try 3, 2, 1 without pre-counting; helper will validate
        if let r = parseEmphasisWithCount(&state, delimiter: delimiter, count: 3, configuration: configuration) { return r }
        state.restore(mark)
        if let r = parseEmphasisWithCount(&state, delimiter: delimiter, count: 2, configuration: configuration) { return r }
        state.restore(mark)
        if let r = parseEmphasisWithCount(&state, delimiter: delimiter, count: 1, configuration: configuration) { return r }
        state.restore(mark)
        return nil
    }

    private static func parseEmphasisWithCount(_ state: inout ParserState, delimiter: Character, count: Int, configuration: MarkdownConfiguration) -> MarkdownParser.InlineNode? {
        let mark = state.mark()
        // Consume opening delimiters
        for _ in 0..<count {
            guard let ch = state.current(), ch == delimiter else { state.restore(mark); return nil }
            state.advance()
        }

        // Don't allow emphasis to start with whitespace
        if let ch = state.current(), ch == " " { state.restore(mark); return nil }

        let contentStartIndex = state.currentIndex
        var pendingDepth = 0
        while let ch = state.current() {
            if ch == delimiter {
                // Count run of delimiters
                let closeStartIndex = state.currentIndex
                var closeCount = 0
                while let c = state.current(), c == delimiter { closeCount += 1; state.advance() }
                if closeCount >= count && pendingDepth == 0 {
                    let content = state.substring(from: contentStartIndex, to: closeStartIndex)
                    if content.hasSuffix(" ") {
                        // Treat these delimiters as literal content and continue scanning
                        // Roll back to closeStartIndex and append one delimiter, then continue
                        state.move(to: closeStartIndex)
                        // Consume one delimiter into content and continue
                        state.advance()
                        continue
                    }
                    var innerState = ParserState(text: content)
                    let inner = parseInlineElements(&innerState, configuration: configuration)
                    // We already consumed the full delimiter run; position is correct
                    switch count {
                    case 1: return .emphasis(children: inner)
                    case 2, 3: return .strong(children: inner)
                    default: return nil
                    }
                } else {
                    if closeCount == count { pendingDepth += 1 }
                }
            } else if ch == "\\" {
                // Skip escaped next character if present
                state.advance(); if state.current() != nil { state.advance() }
            } else {
                state.advance()
            }
        }
        state.restore(mark)
        return nil
    }

    static func parseStrikethrough(_ state: inout ParserState, configuration: MarkdownConfiguration) -> MarkdownParser.InlineNode? {

        let mark = state.mark()

        guard state.current() == "~", state.peek(1) == "~" else { return nil }
        state.advance(); state.advance() // consume opening ~~

        // Find closing ~~
        let contentStartIndex = state.currentIndex
        while let ch = state.current(), let next = state.peek(1) {
            if ch == "~" && next == "~" {
                // emit content between contentStartIndex and currentIndex
                let content = state.substring(from: contentStartIndex, to: state.currentIndex)
                state.advance(); state.advance() // consume closing ~~

                var innerState = ParserState(text: content)
                let innerContent = parseInlineElements(&innerState, configuration: configuration)
                return .strikethrough(children: innerContent)
            }
            state.advance()
        }

        state.restore(mark)
        return nil
    }

    static func parseLink(_ state: inout ParserState, configuration: MarkdownConfiguration) -> MarkdownParser.InlineNode? {

        let mark = state.mark()
        guard state.current() == "[" else { return nil }
        state.advance()

        // Parse link text with nested brackets
        var linkText = ""; linkText.reserveCapacity(128)
        var depth = 1
        while let ch = state.current(), depth > 0 {
            if ch == "\\" { state.advance(); if let next = state.current() { linkText.append(next); state.advance() } }
            else if ch == "[" { depth += 1; linkText.append(ch); state.advance() }
            else if ch == "]" { depth -= 1; if depth > 0 { linkText.append(ch) }; state.advance() }
            else { linkText.append(ch); state.advance() }
        }
        guard depth == 0 else { state.restore(mark); return nil }

        // Inline destination: (URL [title])
        if state.current() == "(" {
            state.advance()
            // Capture balanced content inside parentheses
            guard let (inner, after) = ParsingHelpers.scanBalanced(in: state.text, from: state.currentIndex, end: state.endIndex, open: "(", close: ")", allowEscape: true) else {
                state.restore(mark); return nil
            }
            // Parse inner: URL [title]
            var idx2 = inner.startIndex
            ParsingHelpers.skipSpaces(in: inner, from: &idx2, end: inner.endIndex)
            // URL up to first space/tab (ASCII fast path when possible)
            let rest = inner[idx2...]
            let spaceIdx: String.Index = {
                if ParsingHelpers.isASCII(inner) {
                    return ParsingHelpers.firstASCIISpaceOrTab(in: inner, from: idx2, end: inner.endIndex)
                } else {
                    return rest.firstIndex(where: { $0 == " " || $0 == "\t" }) ?? inner.endIndex
                }
            }()
            let urlPart = String(inner[idx2..<spaceIdx])
            // Unescape backslash escapes in URL
            var unescaped = ""
            var uidx = urlPart.startIndex
            while uidx < urlPart.endIndex {
                let ch = urlPart[uidx]
                if ch == "\\" {
                    let n = urlPart.index(after: uidx)
                    if n < urlPart.endIndex { unescaped.append(urlPart[n]); uidx = urlPart.index(after: n) } else { break }
                } else { unescaped.append(ch); uidx = urlPart.index(after: uidx) }
            }
            var title: String? = nil
            if spaceIdx < inner.endIndex {
                var tIdx = spaceIdx
                ParsingHelpers.skipSpaces(in: inner, from: &tIdx, end: inner.endIndex)
                if tIdx < inner.endIndex {
                    let tdelim = inner[tIdx]
                    if tdelim == Character("\"") || tdelim == Character("'") || tdelim == Character("(") {
                        let startT = inner.index(after: tIdx)
                        if let (t, afterT) = ParsingHelpers.scanQuoted(in: inner, from: startT, end: inner.endIndex, delimiter: tdelim) {
                            title = t
                            tIdx = afterT
                            ParsingHelpers.skipSpaces(in: inner, from: &tIdx, end: inner.endIndex)
                        } else {
                            state.restore(mark); return nil
                        }
                    }
                }
            }
            // Commit state to after closing ')'
            state.move(to: after)
            var linkState = ParserState(text: linkText)
            let textContent = parseInlineElements(&linkState, configuration: configuration)
            if let parsedURL = URL(string: unescaped) {
                return .link(url: parsedURL, title: title, children: textContent)
            } else {
                state.restore(mark); return nil
            }
        } else if state.current() == "[" {
            // Reference style link not resolved in this implementation
            state.advance()
            while let c = state.current(), c != "]" { state.advance() }
            if state.current() == "]" { state.advance(); state.restore(mark); return nil }
        }
        state.restore(mark)
        return nil
    }

    static func parseImage(_ state: inout ParserState, configuration: MarkdownConfiguration) -> MarkdownParser.InlineNode? {

        let mark = state.mark()
        guard state.current() == "!", state.peek(1) == "[" else { return nil }
        state.advance(); state.advance() // consume ![

        var altText = ""; altText.reserveCapacity(128)
        var depth = 1
        while let ch = state.current(), depth > 0 {
            if ch == "\\" { state.advance(); if let n = state.current() { altText.append(n); state.advance() } }
            else if ch == "[" { depth += 1; altText.append(ch); state.advance() }
            else if ch == "]" { depth -= 1; if depth > 0 { altText.append(ch) }; state.advance() }
            else { altText.append(ch); state.advance() }
        }
        guard depth == 0 else { state.restore(mark); return nil }

        if state.current() == "(" {
            state.advance()
            guard let (inner, after) = ParsingHelpers.scanBalanced(in: state.text, from: state.currentIndex, end: state.endIndex, open: "(", close: ")", allowEscape: true) else {
                state.restore(mark); return nil
            }
            var idx2 = inner.startIndex
            ParsingHelpers.skipSpaces(in: inner, from: &idx2, end: inner.endIndex)
            let rest = inner[idx2...]
            let spaceIdx: String.Index = {
                if ParsingHelpers.isASCII(inner) {
                    return ParsingHelpers.firstASCIISpaceOrTab(in: inner, from: idx2, end: inner.endIndex)
                } else {
                    return rest.firstIndex(where: { $0 == " " || $0 == "\t" }) ?? inner.endIndex
                }
            }()
            let urlPart = String(inner[idx2..<spaceIdx])
            var unescaped = ""
            var uidx = urlPart.startIndex
            while uidx < urlPart.endIndex {
                let ch = urlPart[uidx]
                if ch == "\\" {
                    let n = urlPart.index(after: uidx)
                    if n < urlPart.endIndex { unescaped.append(urlPart[n]); uidx = urlPart.index(after: n) } else { break }
                } else { unescaped.append(ch); uidx = urlPart.index(after: uidx) }
            }
            var title: String? = nil
            if spaceIdx < inner.endIndex {
                var tIdx = spaceIdx
                ParsingHelpers.skipSpaces(in: inner, from: &tIdx, end: inner.endIndex)
                if tIdx < inner.endIndex {
                    let tdelim = inner[tIdx]
                    if tdelim == Character("\"") || tdelim == Character("'") || tdelim == Character("(") {
                        let startT = inner.index(after: tIdx)
                        if let (t, afterT) = ParsingHelpers.scanQuoted(in: inner, from: startT, end: inner.endIndex, delimiter: tdelim) {
                            title = t
                            tIdx = afterT
                            ParsingHelpers.skipSpaces(in: inner, from: &tIdx, end: inner.endIndex)
                        } else { state.restore(mark); return nil }
                    }
                }
            }
            state.move(to: after)
            if let parsedURL = URL(string: unescaped) { return .image(url: parsedURL, alt: altText, title: title) }
            state.restore(mark); return nil
        }
        state.restore(mark)
        return nil
    }

    static func parseFootnoteReference(_ state: inout ParserState) -> MarkdownParser.InlineNode? {

        let mark = state.mark()
        guard state.current() == "[", state.peek(1) == "^" else { return nil }
        state.advance(); state.advance()
        var idxLab = state.currentIndex
        let endLab = state.endIndex
        let label: String
        if state.asciiFastPath {
            label = ParsingHelpers.scanWhileUTF8(in: state.text, from: &idxLab, end: endLab, while: { b in b != 0x5D /*]*/ && b != 0x0A /*\n*/ })
        } else {
            label = ParsingHelpers.scanWhile(in: state.text, from: &idxLab, end: endLab, while: { ch in ch != "]" && ch != "\n" })
        }
        state.move(to: idxLab)
        guard state.current() == "]" else { state.restore(mark); return nil }
        state.advance()
        guard !label.isEmpty else { state.restore(mark); return nil }
        return .footnoteReference(label: label)
    }

    static func parseHTMLTag(_ state: inout ParserState) -> MarkdownParser.InlineNode? {

        let mark = state.mark()
        guard state.current() == "<" else { return nil }
        state.advance()
        if state.current() == "/" { state.advance() }
        var tIdx = state.currentIndex
        let tEnd = state.endIndex
        let tagName: String
        if state.asciiFastPath {
            tagName = ParsingHelpers.scanWhileUTF8(in: state.text, from: &tIdx, end: tEnd, while: { b in ParsingHelpers.isASCIIAlpha(b) })
        } else {
            tagName = ParsingHelpers.scanWhile(in: state.text, from: &tIdx, end: tEnd, while: { ch in ch.isLetter })
        }
        state.move(to: tIdx)
        guard !tagName.isEmpty else { state.restore(mark); return nil }
        var tmpIdx = state.currentIndex
        let tmpEnd = state.endIndex
        if state.asciiFastPath {
            _ = ParsingHelpers.scanWhileUTF8(in: state.text, from: &tmpIdx, end: tmpEnd, while: { b in b != 0x3E /*>*/ })
        } else {
            _ = ParsingHelpers.scanWhile(in: state.text, from: &tmpIdx, end: tmpEnd, while: { ch in ch != ">" })
        }
        state.move(to: tmpIdx)
        guard state.current() == ">" else { state.restore(mark); return nil }
        state.advance()
        let html = state.substring(from: mark.index, to: state.currentIndex)
        return .html(html)
    }

    // (legacy OLD_ autolink helpers removed)

    static func parseMention(_ state: inout ParserState) -> MarkdownParser.InlineNode? {
        let mark = state.mark()
        guard state.current() == "@" else { return nil }

        // Reject if preceded by [A-Za-z0-9_-]
        if mark.index > state.text.startIndex {
            let prev = state.text[state.text.index(before: mark.index)]
            if prev.isLetter || prev.isNumber || prev == "_" || prev == "-" { return nil }
        }

        state.advance() // consume '@'

        // Scan username characters
        var idx = state.currentIndex
        let end = state.endIndex
        let scanned: String
        if state.asciiFastPath {
            scanned = ParsingHelpers.scanWhileUTF8(in: state.text, from: &idx, end: end, while: { b in
                ParsingHelpers.isASCIIAlnum(b) || b == 0x2D /*-*/ || b == 0x5F /*_*/
            })
        } else {
            scanned = ParsingHelpers.scanWhile(in: state.text, from: &idx, end: end, while: { ch in
                ch.isLetter || ch.isNumber || ch == "-" || ch == "_"
            })
        }
        let username = scanned
        state.move(to: idx)

        guard !username.isEmpty else { state.restore(mark); return nil }

        // Disambiguate emails: if next is '.' followed by domain-like chars, not a mention
        if let ch = state.current(), ch == "." {
            var idx = state.currentIndex
            var hasDomainChars = false
            if state.asciiFastPath,
               let uStart = idx.samePosition(in: state.text.utf8),
               let uEnd = state.endIndex.samePosition(in: state.text.utf8) {
                var uidx = uStart
                while uidx < uEnd {
                    uidx = state.text.utf8.index(after: uidx)
                    if uidx >= uEnd { break }
                    let b = state.text.utf8[uidx]
                    if (b >= 0x30 && b <= 0x39) || // 0-9
                       (b >= 0x41 && b <= 0x5A) || // A-Z
                       (b >= 0x61 && b <= 0x7A) || // a-z
                       b == 0x2D || b == 0x2E { // - .
                        hasDomainChars = true
                    } else { break }
                }
            } else {
                while idx < state.endIndex {
                    idx = state.text.index(after: idx)
                    if idx >= state.endIndex { break }
                    let c = state.text[idx]
                    if c.isLetter || c.isNumber || c == "-" || c == "." { hasDomainChars = true }
                    else { break }
                }
            }
            if hasDomainChars { state.restore(mark); return nil }
        }

        return .mention(username: username)
    }

    static func parseIssueReference(_ state: inout ParserState) -> MarkdownParser.InlineNode? {
        let mark = state.mark()
        guard state.current() == "#" else { return nil }
        // Preceded by alnum or '#' => not an issue
        if mark.index > state.text.startIndex {
            let prev = state.text[state.text.index(before: mark.index)]
            if prev.isLetter || prev.isNumber || prev == "#" { return nil }
        }
        state.advance()
        var idxNum = state.currentIndex
        let endNum = state.endIndex
        let digits: String
        if state.asciiFastPath {
            digits = ParsingHelpers.scanWhileUTF8(in: state.text, from: &idxNum, end: endNum, while: { b in ParsingHelpers.isASCIIDigit(b) })
        } else {
            digits = ParsingHelpers.scanWhile(in: state.text, from: &idxNum, end: endNum, while: { ch in ch.isNumber })
        }
        state.move(to: idxNum)
        guard !digits.isEmpty, let n = Int(digits) else { state.restore(mark); return nil }
        return .issueReference(number: n)
    }

    static func parseEmojiShortcode(_ state: inout ParserState) -> MarkdownParser.InlineNode? {
        let mark = state.mark()
        guard state.current() == ":" else { return nil }
        state.advance()
        var idxName = state.currentIndex
        let endName = state.endIndex
        let name: String
        if state.asciiFastPath {
            name = ParsingHelpers.scanWhileUTF8(in: state.text, from: &idxName, end: endName, while: { b in
                ParsingHelpers.isASCIIAlnum(b) || b == 0x5F /*_*/ || b == 0x2D /*-*/ || b == 0x2B /*+*/
            })
        } else {
            name = ParsingHelpers.scanWhile(in: state.text, from: &idxName, end: endName, while: { ch in
                ch.isLetter || ch.isNumber || ch == "_" || ch == "-" || ch == "+"
            })
        }
        state.move(to: idxName)
        guard state.current() == ":" else { state.restore(mark); return nil }
        state.advance()
        guard !name.isEmpty else { state.restore(mark); return nil }

        if let emoji = GitHubEmojis.emojiMap[name] {
            if emoji.hasPrefix(":") && emoji.hasSuffix(":") {
                if let imageUrl = GitHubEmojis.emojiURL(for: name), let url = URL(string: imageUrl) {
                    return .image(url: url, alt: ":\(name):", title: nil)
                }
            }
            return .text(emoji)
        }
        if let imageUrl = GitHubEmojis.emojiURL(for: name), let url = URL(string: imageUrl) {
            return .image(url: url, alt: ":\(name):", title: nil)
        }
        state.restore(mark)
        return nil
    }

    static func parseCommitSHA(_ state: inout ParserState) -> MarkdownParser.InlineNode? {
        let mark = state.mark()
        // Start boundary: previous char should not be alphanumeric
        if mark.index > state.text.startIndex {
            let prev = state.text[state.text.index(before: mark.index)]
            if prev.isLetter || prev.isNumber { return nil }
        }
        var idx = state.currentIndex
        let end = state.endIndex
        let sha: String
        if state.asciiFastPath {
            sha = ParsingHelpers.scanWhileUTF8(in: state.text, from: &idx, end: end, while: { b in ParsingHelpers.isASCIIHex(b) }, maxCount: 40)
        } else {
            sha = ParsingHelpers.scanWhile(in: state.text, from: &idx, end: end, while: { ch in ParsingHelpers.isHexChar(ch) }, maxCount: 40)
        }
        state.move(to: idx)
        guard sha.count >= 7 && sha.count <= 40 else { state.restore(mark); return nil }
        if let next = state.current(), (next.isLetter || next.isNumber) { state.restore(mark); return nil }
        let shortSha = String(sha.prefix(7))
        return .commitSHA(sha: sha, short: shortSha)
    }

    static func parseRepositoryReference(_ state: inout ParserState) -> MarkdownParser.InlineNode? {
        let mark = state.mark()

        // owner
        var idx = state.currentIndex
        let end = state.endIndex
        guard let first = state.current(), first.isLetter else { return nil }
        let owner: String
        if state.asciiFastPath {
            owner = ParsingHelpers.scanWhileUTF8(in: state.text, from: &idx, end: end, while: { b in
                ParsingHelpers.isASCIIAlnum(b) || b == 0x2D /*-*/ || b == 0x5F /*_*/
            })
        } else {
            owner = ParsingHelpers.scanWhile(in: state.text, from: &idx, end: end, while: { ch in
                ch.isLetter || ch.isNumber || ch == "-" || ch == "_"
            })
        }
        state.move(to: idx)
        // /
        guard state.current() == "/" else { state.restore(mark); return nil }
        state.advance()
        // repo
        guard let r0 = state.current(), (r0.isLetter || r0.isNumber) else { state.restore(mark); return nil }
        idx = state.currentIndex
        let repo: String
        if state.asciiFastPath {
            repo = ParsingHelpers.scanWhileUTF8(in: state.text, from: &idx, end: end, while: { b in
                ParsingHelpers.isASCIIAlnum(b) || b == 0x2D /*-*/ || b == 0x5F /*_*/ || b == 0x2E /*.*/
            })
        } else {
            repo = ParsingHelpers.scanWhile(in: state.text, from: &idx, end: end, while: { ch in
                ch.isLetter || ch.isNumber || ch == "-" || ch == "_" || ch == "."
            })
        }
        state.move(to: idx)
        guard !owner.isEmpty && !repo.isEmpty else { state.restore(mark); return nil }

        // Optional #number => PR reference
        if state.current() == "#" {
            state.advance()
            var dIdx = state.currentIndex
            let dEnd = state.endIndex
            let digits: String
            if state.asciiFastPath {
                digits = ParsingHelpers.scanWhileUTF8(in: state.text, from: &dIdx, end: dEnd, while: { b in ParsingHelpers.isASCIIDigit(b) })
            } else {
                digits = ParsingHelpers.scanWhile(in: state.text, from: &dIdx, end: dEnd, while: { ch in ch.isNumber })
            }
            state.move(to: dIdx)
            if let num = Int(digits) { return .pullRequestReference(owner: owner, repo: repo, number: num) }
        }

        // Context check: if preceded by @ / : then not a standalone repo ref
        if mark.index > state.text.startIndex {
            let prev = state.text[state.text.index(before: mark.index)]
            if prev == "@" || prev == "/" || prev == ":" { state.restore(mark); return nil }
        }
        return .repositoryReference(owner: owner, repo: repo)
    }

    // MARK: - Helper Methods

    // Unified autolink parser supporting angle-bracket and extended autolinks
    static func parseUnifiedAutolink(_ state: inout ParserState, angleBracketMode: Bool) -> MarkdownParser.InlineNode? {
        let startMark = state.mark()
        if angleBracketMode {
            guard state.current() == "<" else { return nil }
            state.advance()
        }
        let startIndex = state.currentIndex

        @inline(__always)
        func hasPrefix(_ prefix: String) -> Bool {
            var idx = startIndex
            for ch in prefix {
                if idx >= state.endIndex || state.text[idx] != ch { return false }
                idx = state.text.index(after: idx)
            }
            return true
        }

        enum Scheme { case httpLike, www, mailto, angle }
        let scheme: Scheme?
        if angleBracketMode { scheme = .angle }
        else if hasPrefix("http://") || hasPrefix("https://") || hasPrefix("ftp://") { scheme = .httpLike }
        else if hasPrefix("mailto:") { scheme = .mailto }
        else if hasPrefix("www.") { scheme = .www }
        else { scheme = nil }

        guard let schemeType = scheme else { return nil }

        @inline(__always)
        func isLikelyAngleEmail(_ value: String) -> Bool {
            guard !value.contains(":"),
                  let at = value.firstIndex(of: "@"),
                  at > value.startIndex else { return false }
            let domainStart = value.index(after: at)
            guard domainStart < value.endIndex else { return false }
            let domain = value[domainStart...]
            return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
        }

        var idx = startIndex
        var openParens = 0, closeParens = 0
        var openBrackets = 0, closeBrackets = 0
        if state.asciiFastPath,
           let uStart = startIndex.samePosition(in: state.text.utf8),
           let uEnd = state.endIndex.samePosition(in: state.text.utf8) {
            var uidx = uStart
            scanLoopASCII: while uidx < uEnd {
                let b = state.text.utf8[uidx]
                switch b {
                case 0x20, 0x0A, 0x09: // space, \n, \t
                    break scanLoopASCII
                case 0x3C, 0x3E: // <, >
                    // Angle bracket breaks regardless
                    break scanLoopASCII
                case 0x28: // (
                    openParens &+= 1; uidx = state.text.utf8.index(after: uidx)
                case 0x29: // )
                    closeParens &+= 1; uidx = state.text.utf8.index(after: uidx)
                case 0x5B: // [
                    openBrackets &+= 1; uidx = state.text.utf8.index(after: uidx)
                case 0x5D: // ]
                    closeBrackets &+= 1; uidx = state.text.utf8.index(after: uidx)
                default:
                    uidx = state.text.utf8.index(after: uidx)
                }
            }
            if let newIdx = String.Index(uidx, within: state.text) { idx = newIdx }
        } else {
            scanLoop: while idx < state.endIndex {
                let ch = state.text[idx]
                switch ch {
                case " ", "\n", "\t":
                    break scanLoop
                case "<", ">":
                    break scanLoop
                case "(": openParens += 1; idx = state.text.index(after: idx)
                case ")": closeParens += 1; idx = state.text.index(after: idx)
                case "[": openBrackets += 1; idx = state.text.index(after: idx)
                case "]": closeBrackets += 1; idx = state.text.index(after: idx)
                default: idx = state.text.index(after: idx)
                }
            }
        }

        var endIndex = idx
        if angleBracketMode {
            if idx >= state.endIndex || state.text[idx] != ">" {
                state.restore(startMark)
                return nil
            }
        }

        while endIndex > startIndex {
            let prev = state.text[state.text.index(before: endIndex)]
            if prev == "." || prev == "," || prev == ";" || prev == ":" || prev == "?" || prev == "!" {
                endIndex = state.text.index(before: endIndex)
            } else { break }
        }
        var extraCloseParens = max(0, closeParens - openParens)
        while extraCloseParens > 0 && endIndex > startIndex && state.text[state.text.index(before: endIndex)] == ")" {
            endIndex = state.text.index(before: endIndex)
            extraCloseParens -= 1
        }
        var extraCloseBrackets = max(0, closeBrackets - openBrackets)
        while extraCloseBrackets > 0 && endIndex > startIndex && state.text[state.text.index(before: endIndex)] == "]" {
            endIndex = state.text.index(before: endIndex)
            extraCloseBrackets -= 1
        }

        if endIndex <= startIndex { state.restore(startMark); return nil }

        let urlText = state.substring(from: startIndex, to: endIndex)
        // Determine autolink type and destination URL
        var linkURL: URL?
        var displayText = urlText
        var linkType: MarkdownParser.AutolinkType = .url
        switch schemeType {
        case .httpLike:
            linkType = .url
            linkURL = URL(string: urlText)
        case .www:
            linkType = .www
            linkURL = URL(string: "http://\(urlText)")
        case .mailto:
            linkType = .email
            // Strip leading mailto: from display
            if urlText.lowercased().hasPrefix("mailto:") {
                displayText = String(urlText.dropFirst("mailto:".count))
            }
            linkURL = URL(string: urlText)
        case .angle:
            // Angle-bracket: decide by content
            if isLikelyAngleEmail(urlText) {
                linkType = .email
                displayText = urlText
                linkURL = URL(string: "mailto:\(urlText)")
            } else {
                guard let colonIndex = urlText.firstIndex(of: ":") else {
                    state.restore(startMark)
                    return nil
                }
                let schemeText = urlText[..<colonIndex]
                guard !schemeText.isEmpty,
                      let first = schemeText.first,
                      first.isLetter,
                      schemeText.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "." || $0 == "-" }) else {
                    state.restore(startMark)
                    return nil
                }
                linkType = .url
                linkURL = URL(string: urlText)
            }
        }
        guard let finalURL = linkURL else { state.restore(startMark); return nil }

        if angleBracketMode {
            state.move(to: idx)
            if state.current() == ">" { state.advance() }
        } else {
            state.move(to: endIndex)
        }
        return .autolink(finalURL, linkType, originalText: displayText)
    }
}

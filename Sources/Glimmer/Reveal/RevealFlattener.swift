import SwiftUI

/// Walks the parsed AST in document order and emits `RevealAtom`s grouped
/// into `RevealWord`s and `RevealBlock`s (spec 4.1). Ids are ordinal and
/// therefore stable across buffer growth: appending markdown only appends
/// atoms (the in-progress last word may change text; its id stays).
struct RevealFlattener {
    let granularity: RevealGranularity
    let configuration: MarkdownConfiguration

    private var nextAtomID = 0
    private var nextBlockID = 0
    private var countables = 0
    private var initialAtomID = 0
    private var initialCountableCount = 0
    private var blocks: [RevealBlock] = []
    private var renderer = MarkdownRenderer()

    private static let wordsPerLine = 4
    private static let htmlBreakTags: Set<String> = ["<br>", "<br/>", "<br />"]

    static func flatten(
        _ nodes: [MarkdownParser.BlockNode],
        granularity: RevealGranularity,
        configuration: MarkdownConfiguration
    ) -> RevealModel {
        flatten(
            nodes,
            granularity: granularity,
            configuration: configuration,
            atomIDOffset: 0,
            blockIDOffset: 0,
            countableOffset: 0
        )
    }

    static func flatten(
        _ nodes: [MarkdownParser.BlockNode],
        granularity: RevealGranularity,
        configuration: MarkdownConfiguration,
        atomIDOffset: Int,
        blockIDOffset: Int,
        countableOffset: Int
    ) -> RevealModel {
        var flattener = RevealFlattener(granularity: granularity, configuration: configuration)
        flattener.nextAtomID = atomIDOffset
        flattener.nextBlockID = blockIDOffset
        flattener.countables = countableOffset
        flattener.initialAtomID = atomIDOffset
        flattener.initialCountableCount = countableOffset
        return flattener.run(nodes)
    }

    private mutating func run(_ nodes: [MarkdownParser.BlockNode]) -> RevealModel {
        if !configuration.markdownExtensions.isEmpty {
            renderer.beginSession(configuration: configuration)
        }
        blocks.reserveCapacity(nodes.count)
        emit(nodes)
        return RevealModel(
            blocks: blocks,
            countableCount: countables - initialCountableCount,
            atomCount: nextAtomID - initialAtomID
        )
    }

    // MARK: - Block walk

    private mutating func emit(_ nodes: [MarkdownParser.BlockNode]) {
        for node in nodes {
            switch node {
            case .heading(let level, let children, _):
                let font = level - 1 < configuration.headingFonts.count
                    ? configuration.headingFonts[level - 1] : .headline
                appendInlineBlock(kind: .heading(level: level), children: children, baseFont: font, node: node)

            case .paragraph(let children):
                if children.contains(where: { if case .image = $0 { return true } else { return false } }) {
                    // Inline images reveal as a whole block (spec 4.6).
                    appendWholeBlock(node)
                } else {
                    appendInlineBlock(
                        kind: .paragraph,
                        children: children,
                        baseFont: configuration.baseFont,
                        node: node
                    )
                }

            case .blockquote:
                appendWholeBlock(node)

            case .list:
                appendWholeBlock(node)

            case .codeBlock, .table, .taskList, .horizontalRule, .html:
                appendWholeBlock(node)

            case .footnoteDefinition:
                continue // footnote sections are not revealed (documented limitation)
            }
        }
    }

    // MARK: - Inline flattening

    private mutating func appendInlineBlock(
        kind: BlockKindTag,
        children: [MarkdownParser.InlineNode],
        baseFont: Font?,
        node: MarkdownParser.BlockNode? = nil
    ) {
        if !configuration.markdownExtensions.isEmpty, containsExtensionInline(children) {
            let content = renderer.renderInlines(children, configuration: configuration, baseFont: baseFont)
            appendRenderedInlineBlock(kind: kind, content: content, node: node)
            return
        }

        var builder = InlineTokenBuilder(configuration: configuration, baseFont: baseFont)
        builder.append(children)
        appendInlineBlock(kind: kind, tokens: builder.finish(), node: node)
    }

    private mutating func appendRenderedInlineBlock(
        kind: BlockKindTag,
        content: AttributedString,
        node: MarkdownParser.BlockNode? = nil
    ) {
        // One pass over the block's runs decides whether any per-word link
        // resolution is needed at all; most blocks contain no links, and the
        // per-word run scans were a measured hotspot.
        let hasLinks = content.runs.contains { $0.link != nil }
        var words: [RevealWord] = []
        switch granularity {
        case .word:
            let tokens = content.revealTokens()
            words.reserveCapacity(tokens.count)
            for token in tokens {
                words.append(makeWord(
                    from: token.slice, isWhitespace: token.isWhitespace,
                    containsNewline: token.containsNewline, hasLinks: hasLinks
                ))
            }
        case .character:
            let tokens = content.revealTokens()
            words.reserveCapacity(tokens.count)
            for token in tokens {
                if token.isWhitespace {
                    words.append(makeWord(
                        from: token.slice, isWhitespace: true,
                        containsNewline: token.containsNewline, hasLinks: hasLinks
                    ))
                } else {
                    appendCharacterWord(
                        from: token.slice,
                        url: nil,
                        scanLinks: hasLinks,
                        into: &words
                    )
                }
            }
        case .line:
            appendLines(from: content, into: &words)
        }
        // A block with no countable atoms (e.g. an empty heading mid-stream)
        // must never gate open on its own; re-flattening assigns a real index
        // once content arrives.
        let first = firstRevealIndex(in: words)
        let blockID = nextBlockID
        nextBlockID += 1
        blocks.append(RevealBlock(id: blockID, kind: kind, words: words, node: node, firstRevealIndex: first))
    }

    private mutating func appendInlineBlock(
        kind: BlockKindTag,
        tokens: [InlineRevealToken],
        node: MarkdownParser.BlockNode? = nil
    ) {
        var words: [RevealWord] = []
        switch granularity {
        case .word:
            words.reserveCapacity(tokens.count)
            for token in tokens {
                words.append(makeWord(from: token))
            }
        case .character:
            words.reserveCapacity(tokens.count)
            for token in tokens {
                if token.isWhitespace {
                    words.append(makeWord(from: token))
                } else {
                    appendCharacterWord(
                        from: token.content,
                        url: token.url,
                        scanLinks: false,
                        into: &words
                    )
                }
            }
        case .line:
            appendLines(from: tokens, into: &words)
        }

        // A block with no countable atoms (e.g. an empty heading mid-stream)
        // must never gate open on its own; re-flattening assigns a real index
        // once content arrives.
        let first = firstRevealIndex(in: words)
        let blockID = nextBlockID
        nextBlockID += 1
        blocks.append(RevealBlock(id: blockID, kind: kind, words: words, node: node, firstRevealIndex: first))
    }

    private func firstRevealIndex(in words: [RevealWord]) -> Int {
        for word in words {
            for atom in word.atoms where atom.isCountable {
                return atom.revealIndex
            }
        }
        return Int.max
    }

    /// Groups words into lines of `wordsPerLine`, each line one countable atom
    /// followed by a forced break (line-slide style, spec appendix).
    /// Line atoms carry no link URL — line-slide reveals are not tappable (documented limitation).
    private mutating func appendLines(from content: AttributedString, into words: inout [RevealWord]) {
        var line = AttributedString()
        var wordCount = 0
        var pendingSpace: AttributedString?

        func flushLine() {
            guard wordCount > 0 else { return }
            let atom = makeAtom(kind: .text(line), countable: true, url: nil)
            words.append(RevealWord(id: atom.id, atoms: [atom], isWhitespace: false, isLineBreak: false))
            let br = makeAtom(kind: .lineBreak, countable: false, url: nil)
            words.append(RevealWord(id: br.id, atoms: [br], isWhitespace: false, isLineBreak: true))
            line = AttributedString()
            wordCount = 0
            pendingSpace = nil
        }

        for token in content.revealTokens() {
            if token.isWhitespace {
                if wordCount > 0 { pendingSpace = token.slice }
            } else {
                if let space = pendingSpace {
                    line.append(space)
                    pendingSpace = nil
                }
                line.append(token.slice)
                wordCount += 1
                if wordCount == Self.wordsPerLine { flushLine() }
            }
        }
        flushLine()
    }

    /// Same line grouping as the rendered `AttributedString` path, but over
    /// direct inline tokens so we avoid rendering and then slicing the whole block.
    private mutating func appendLines(from tokens: [InlineRevealToken], into words: inout [RevealWord]) {
        var line = AttributedString()
        var wordCount = 0
        var pendingSpace: AttributedString?

        func flushLine() {
            guard wordCount > 0 else { return }
            let atom = makeAtom(kind: .text(line), countable: true, url: nil)
            words.append(RevealWord(id: atom.id, atoms: [atom], isWhitespace: false, isLineBreak: false))
            let br = makeAtom(kind: .lineBreak, countable: false, url: nil)
            words.append(RevealWord(id: br.id, atoms: [br], isWhitespace: false, isLineBreak: true))
            line = AttributedString()
            wordCount = 0
            pendingSpace = nil
        }

        for token in tokens {
            if token.isWhitespace {
                if wordCount > 0 { pendingSpace = token.content }
            } else {
                if let space = pendingSpace {
                    line.append(space)
                    pendingSpace = nil
                }
                line.append(token.content)
                wordCount += 1
                if wordCount == Self.wordsPerLine { flushLine() }
            }
        }
        flushLine()
    }

    private mutating func makeWord(from token: InlineRevealToken) -> RevealWord {
        if token.isWhitespace {
            if token.containsNewline {
                let atom = makeAtom(kind: .lineBreak, countable: false, url: nil)
                return RevealWord(id: atom.id, atoms: [atom], isWhitespace: false, isLineBreak: true)
            }
            let atom = makeAtom(kind: .space(token.content), countable: false, url: nil)
            return RevealWord(id: atom.id, atoms: [atom], isWhitespace: true, isLineBreak: false)
        }
        let atom = makeAtom(kind: .text(token.content), countable: true, url: token.url)
        return RevealWord(id: atom.id, atoms: [atom], isWhitespace: false, isLineBreak: false)
    }

    private mutating func appendCharacterWord(
        from content: AttributedString,
        url: URL?,
        scanLinks: Bool,
        into words: inout [RevealWord]
    ) {
        var atoms: [RevealAtom] = []
        for run in content.runs {
            let attributes = run.attributes
            let runURL = scanLinks ? run.link : url
            for character in String(content[run.range].characters) {
                let text = AttributedString(String(character), attributes: attributes)
                atoms.append(makeAtom(kind: .text(text), countable: true, url: runURL))
            }
        }
        guard !atoms.isEmpty else { return }
        words.append(RevealWord(id: atoms[0].id, atoms: atoms, isWhitespace: false, isLineBreak: false))
    }

    private mutating func makeWord(
        from slice: AttributedString,
        isWhitespace: Bool,
        containsNewline: Bool,
        hasLinks: Bool
    ) -> RevealWord {
        if isWhitespace {
            if containsNewline {
                let atom = makeAtom(kind: .lineBreak, countable: false, url: nil)
                return RevealWord(id: atom.id, atoms: [atom], isWhitespace: false, isLineBreak: true)
            }
            let atom = makeAtom(kind: .space(slice), countable: false, url: nil)
            return RevealWord(id: atom.id, atoms: [atom], isWhitespace: true, isLineBreak: false)
        }
        let atom = makeAtom(kind: .text(slice), countable: true, url: hasLinks ? linkURL(in: slice) : nil)
        return RevealWord(id: atom.id, atoms: [atom], isWhitespace: false, isLineBreak: false)
    }

    /// The first link found in any run of the slice (a word can straddle a
    /// link boundary, so the first run alone is not enough).
    private func linkURL(in slice: AttributedString) -> URL? {
        for run in slice.runs {
            if let url = run.link { return url }
        }
        return nil
    }

    private mutating func makeAtom(kind: RevealAtom.Kind, countable: Bool, url: URL?) -> RevealAtom {
        if countable { countables += 1 }
        let atom = RevealAtom(id: nextAtomID, kind: kind, isCountable: countable, revealIndex: countables, url: url)
        nextAtomID += 1
        return atom
    }

    private mutating func appendWholeBlock(_ node: MarkdownParser.BlockNode) {
        let atom = makeAtom(kind: .block, countable: true, url: nil)
        let word = RevealWord(id: atom.id, atoms: [atom], isWhitespace: false, isLineBreak: false)
        let blockID = nextBlockID
        nextBlockID += 1
        blocks.append(RevealBlock(
            id: blockID, kind: .wholeBlock, words: [word], node: node, firstRevealIndex: atom.revealIndex
        ))
    }

    private func containsExtensionInline(_ nodes: [MarkdownParser.InlineNode]) -> Bool {
        for node in nodes {
            switch node {
            case .emphasis(let children),
                 .strong(let children),
                 .strikethrough(let children),
                 .link(_, _, let children):
                if containsExtensionInline(children) { return true }
            case .extensionInline:
                return true
            default:
                continue
            }
        }
        return false
    }

    private struct InlineRevealToken {
        var content: AttributedString
        let isWhitespace: Bool
        var containsNewline: Bool
        var url: URL?
    }

    private struct InlineRenderContext {
        let baseFont: Font?
        let forcedFont: Font?
        let isStrikethrough: Bool
        let linkURL: URL?

        func withEmphasis() -> InlineRenderContext {
            guard forcedFont == nil else { return self }
            return InlineRenderContext(
                baseFont: baseFont,
                forcedFont: (baseFont ?? .body).italic(),
                isStrikethrough: isStrikethrough,
                linkURL: linkURL
            )
        }

        func withStrong() -> InlineRenderContext {
            guard forcedFont == nil else { return self }
            return InlineRenderContext(
                baseFont: baseFont,
                forcedFont: (baseFont ?? .body).bold(),
                isStrikethrough: isStrikethrough,
                linkURL: linkURL
            )
        }

        func withStrikethrough() -> InlineRenderContext {
            InlineRenderContext(
                baseFont: baseFont,
                forcedFont: forcedFont ?? baseFont,
                isStrikethrough: true,
                linkURL: linkURL
            )
        }

        func withLink(_ url: URL) -> InlineRenderContext {
            InlineRenderContext(
                baseFont: baseFont,
                forcedFont: forcedFont,
                isStrikethrough: isStrikethrough,
                linkURL: url
            )
        }
    }

    private struct InlineTokenBuilder {
        let configuration: MarkdownConfiguration
        let baseFont: Font?

        private var tokens: [InlineRevealToken] = []
        private var currentToken: InlineRevealToken?

        init(configuration: MarkdownConfiguration, baseFont: Font?) {
            self.configuration = configuration
            self.baseFont = baseFont
        }

        mutating func append(_ nodes: [MarkdownParser.InlineNode]) {
            append(
                nodes,
                context: InlineRenderContext(
                    baseFont: baseFont,
                    forcedFont: nil,
                    isStrikethrough: false,
                    linkURL: nil
                )
            )
        }

        mutating func finish() -> [InlineRevealToken] {
            flushCurrentToken()
            return tokens
        }

        private mutating func append(_ nodes: [MarkdownParser.InlineNode], context: InlineRenderContext) {
            for node in nodes {
                append(node, context: context)
            }
        }

        private mutating func append(_ node: MarkdownParser.InlineNode, context: InlineRenderContext) {
            switch node {
            case .text(let text):
                appendText(text, context: context, style: .plainText)

            case .emphasis(let children):
                append(children, context: context.withEmphasis())

            case .strong(let children):
                append(children, context: context.withStrong())

            case .strikethrough(let children):
                append(children, context: context.withStrikethrough())

            case .code(let code):
                appendText(code, context: context, style: .code)

            case .link(let url, _, let children):
                append(children, context: context.withLink(url))

            case .image(let url, let alt, _):
                appendText("[Image: \(alt.isEmpty ? url.absoluteString : alt)]", context: context, style: .inlineContextOnly)

            case .autolink(let url, _, let originalText):
                appendText(originalText, context: context.withLink(url), style: .inlineContextOnly)

            case .mention(let username):
                appendText("@\(username)", context: context, style: .mention)

            case .issueReference(let number):
                appendText("#\(number)", context: context, style: .issue)

            case .commitSHA(_, let short):
                appendText(short, context: context, style: .commit)

            case .repositoryReference(let owner, let repo):
                appendText("\(owner)/\(repo)", context: context, style: .repository)

            case .pullRequestReference(let owner, let repo, let number):
                appendText("\(owner)/\(repo)#\(number)", context: context, style: .pullRequest)

            case .lineBreak, .softBreak:
                appendText("\n", context: context, style: .inlineContextOnly)

            case .html(let tag):
                if RevealFlattener.htmlBreakTags.contains(tag.lowercased()) {
                    appendText("\n", context: context, style: .inlineContextOnly)
                } else {
                    appendText(tag, context: context, style: .inlineContextOnly)
                }

            case .footnoteReference(let label):
                let displayLabel = label.starts(with: "inline-") ? "*" : label
                appendText("[\(displayLabel)]", context: context, style: .footnote(label: label))

            case .extensionInline(let node):
                appendText(node.literal, context: context, style: .inlineContextOnly)
            }
        }

        private mutating func appendText(_ text: String, context: InlineRenderContext, style: InlineStyle) {
            guard !text.isEmpty else { return }

            if text.utf8.allSatisfy({ $0 < 0x80 }) {
                appendASCIIText(text, context: context, style: style)
                return
            }

            appendUnicodeText(text, context: context, style: style)
        }

        private mutating func appendASCIIText(_ text: String, context: InlineRenderContext, style: InlineStyle) {
            let bytes = text.utf8
            var runStart = text.startIndex
            var byteIndex = bytes.startIndex
            var runIsWhitespace = Self.isASCIIWhitespace(bytes[byteIndex])
            var runHasNewline = runIsWhitespace && Self.isASCIINewline(bytes[byteIndex])
            byteIndex = bytes.index(after: byteIndex)

            while byteIndex < bytes.endIndex {
                let byte = bytes[byteIndex]
                let isWhitespace = Self.isASCIIWhitespace(byte)
                if isWhitespace != runIsWhitespace {
                    let textIndex = String.Index(byteIndex, within: text)!
                    appendPiece(
                        String(text[runStart..<textIndex]),
                        isWhitespace: runIsWhitespace,
                        containsNewline: runHasNewline,
                        context: context,
                        style: style
                    )
                    runStart = textIndex
                    runIsWhitespace = isWhitespace
                    runHasNewline = false
                }
                if isWhitespace && Self.isASCIINewline(byte) {
                    runHasNewline = true
                }
                byteIndex = bytes.index(after: byteIndex)
            }

            appendPiece(
                String(text[runStart..<text.endIndex]),
                isWhitespace: runIsWhitespace,
                containsNewline: runHasNewline,
                context: context,
                style: style
            )
        }

        private mutating func appendUnicodeText(_ text: String, context: InlineRenderContext, style: InlineStyle) {
            var runStart = text.startIndex
            var runIsWhitespace = text[runStart].isWhitespace
            var runHasNewline = runIsWhitespace && text[runStart].isNewline
            var index = text.index(after: runStart)

            while index < text.endIndex {
                let character = text[index]
                let isWhitespace = character.isWhitespace
                if isWhitespace != runIsWhitespace {
                    appendPiece(
                        String(text[runStart..<index]),
                        isWhitespace: runIsWhitespace,
                        containsNewline: runHasNewline,
                        context: context,
                        style: style
                    )
                    runStart = index
                    runIsWhitespace = isWhitespace
                    runHasNewline = false
                }
                if isWhitespace && character.isNewline {
                    runHasNewline = true
                }
                index = text.index(after: index)
            }

            appendPiece(
                String(text[runStart..<text.endIndex]),
                isWhitespace: runIsWhitespace,
                containsNewline: runHasNewline,
                context: context,
                style: style
            )
        }

        private static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
            byte == 0x20 || (byte >= 0x09 && byte <= 0x0D)
        }

        private static func isASCIINewline(_ byte: UInt8) -> Bool {
            byte >= 0x0A && byte <= 0x0D
        }

        private mutating func appendPiece(
            _ text: String,
            isWhitespace: Bool,
            containsNewline: Bool,
            context: InlineRenderContext,
            style: InlineStyle
        ) {
            let attributed = attributedText(text, context: context, style: style)
            let url = context.linkURL ?? style.url

            if var current = currentToken, current.isWhitespace == isWhitespace {
                current.content.append(attributed)
                current.containsNewline = current.containsNewline || containsNewline
                if current.url == nil {
                    current.url = url
                }
                currentToken = current
                return
            }

            flushCurrentToken()
            currentToken = InlineRevealToken(
                content: attributed,
                isWhitespace: isWhitespace,
                containsNewline: containsNewline,
                url: url
            )
        }

        private mutating func flushCurrentToken() {
            if let currentToken {
                tokens.append(currentToken)
                self.currentToken = nil
            }
        }

        private func attributedText(
            _ text: String,
            context: InlineRenderContext,
            style: InlineStyle
        ) -> AttributedString {
            var value = AttributedString(text)
            style.apply(to: &value, configuration: configuration)

            if let linkURL = context.linkURL {
                var linkAttributes = AttributeContainer()
                linkAttributes.link = linkURL
                linkAttributes.foregroundColor = configuration.linkColor
                linkAttributes.underlineStyle = .single
                value.mergeAttributes(linkAttributes)
            }

            if let forcedFont = context.forcedFont {
                value.font = forcedFont
            } else if style.appliesBaseFont, let baseFont = context.baseFont {
                value.font = baseFont
            }

            if context.isStrikethrough {
                value.strikethroughStyle = .single
            }

            return value
        }
    }

    private enum InlineStyle {
        case plainText
        case code
        case mention
        case issue
        case commit
        case repository
        case pullRequest
        case footnote(label: String)
        case inlineContextOnly

        var appliesBaseFont: Bool {
            if case .plainText = self {
                return true
            }
            return false
        }

        var url: URL? {
            if case .footnote(let label) = self {
                return URL(string: "#footnote-\(label)")
            }
            return nil
        }

        func apply(to value: inout AttributedString, configuration: MarkdownConfiguration) {
            switch self {
            case .plainText:
                if configuration.textColor != .primary {
                    value.foregroundColor = configuration.textColor
                }

            case .code:
                value.font = configuration.codeFont
                value.backgroundColor = configuration.codeBackgroundColor

            case .mention:
                value.foregroundColor = configuration.mentionColor
                value.font = .body.bold()

            case .issue:
                value.foregroundColor = configuration.issueColor
                value.font = .body.bold()

            case .commit:
                value.foregroundColor = configuration.linkColor
                value.font = .system(.body, design: .monospaced)

            case .repository, .pullRequest:
                value.foregroundColor = configuration.linkColor
                value.font = .body.bold()

            case .footnote(let label):
                value.font = .system(.caption2)
                value.baselineOffset = 6
                value.link = URL(string: "#footnote-\(label)")
                value.foregroundColor = configuration.linkColor

            case .inlineContextOnly:
                break
            }
        }
    }
}

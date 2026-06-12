import SwiftUI

/// Walks the parsed AST in document order and emits `RevealAtom`s grouped
/// into `RevealWord`s and `RevealBlock`s (spec 4.1). Ids are ordinal and
/// therefore stable across buffer growth: appending markdown only appends
/// atoms (the in-progress last word may change text; its id stays).
struct RevealFlattener {
    let granularity: RevealGranularity
    let configuration: MarkdownConfiguration

    private var nextAtomID = 0
    private var countables = 0
    private var blocks: [RevealBlock] = []
    private var renderer = MarkdownRenderer()

    private static let unorderedMarkers = ["• ", "◦ ", "▪ ", "▫ "]
    private static let wordsPerLine = 4

    static func flatten(
        _ nodes: [MarkdownParser.BlockNode],
        granularity: RevealGranularity,
        configuration: MarkdownConfiguration
    ) -> RevealModel {
        var flattener = RevealFlattener(granularity: granularity, configuration: configuration)
        return flattener.run(nodes)
    }

    private mutating func run(_ nodes: [MarkdownParser.BlockNode]) -> RevealModel {
        renderer.beginSession(configuration: configuration)
        emit(nodes, listDepth: 0, quoteDepth: 0)
        return RevealModel(blocks: blocks, countableCount: countables)
    }

    // MARK: - Block walk

    private mutating func emit(_ nodes: [MarkdownParser.BlockNode], listDepth: Int, quoteDepth: Int) {
        for node in nodes {
            switch node {
            case .heading(let level, let children, _):
                let font = level - 1 < configuration.headingFonts.count
                    ? configuration.headingFonts[level - 1] : .headline
                let content = renderer.renderInlines(children, configuration: configuration, baseFont: font)
                appendInlineBlock(kind: .heading(level: level), content: content)

            case .paragraph(let children):
                if children.contains(where: { if case .image = $0 { return true } else { return false } }) {
                    // Inline images reveal as a whole block (spec 4.6).
                    appendWholeBlock(node)
                } else {
                    let content = renderer.renderInlines(
                        children, configuration: configuration, baseFont: configuration.baseFont
                    )
                    let kind: BlockKindTag = quoteDepth > 0 ? .blockquote(depth: quoteDepth) : .paragraph
                    appendInlineBlock(kind: kind, content: content)
                }

            case .blockquote(let children):
                emit(children, listDepth: listDepth, quoteDepth: quoteDepth + 1)

            case .list(let ordered, _, let items):
                emitList(ordered: ordered, items: items, depth: listDepth, quoteDepth: quoteDepth)

            case .codeBlock, .table, .taskList, .horizontalRule, .html:
                appendWholeBlock(node)

            case .footnoteDefinition:
                continue // footnote sections are not revealed (documented limitation)
            }
        }
    }

    private mutating func emitList(
        ordered: Bool,
        items: [MarkdownParser.ListItem],
        depth: Int,
        quoteDepth: Int
    ) {
        for (index, item) in items.enumerated() {
            let marker = ordered
                ? "\(index + 1). "
                : Self.unorderedMarkers[min(depth, Self.unorderedMarkers.count - 1)]
            for (childIndex, child) in item.content.enumerated() {
                switch child {
                case .paragraph(let children):
                    let content = renderer.renderInlines(
                        children, configuration: configuration, baseFont: configuration.baseFont
                    )
                    // Only the first paragraph shows the marker; later ones indent blank.
                    let m = childIndex == 0 ? marker : String(repeating: " ", count: marker.count)
                    appendInlineBlock(kind: .listItem(marker: m, depth: depth), content: content)
                case .list(let nestedOrdered, _, let nestedItems):
                    emitList(ordered: nestedOrdered, items: nestedItems, depth: depth + 1, quoteDepth: quoteDepth)
                default:
                    appendWholeBlock(child)
                }
            }
        }
    }

    // MARK: - Inline flattening

    private mutating func appendInlineBlock(kind: BlockKindTag, content: AttributedString) {
        var words: [RevealWord] = []
        switch granularity {
        case .word:
            for token in content.revealTokens() {
                words.append(makeWord(from: token.slice, isWhitespace: token.isWhitespace))
            }
        case .character:
            for token in content.revealTokens() {
                if token.isWhitespace {
                    words.append(makeWord(from: token.slice, isWhitespace: true))
                } else {
                    var atoms: [RevealAtom] = []
                    for ch in token.slice.revealCharacters() {
                        atoms.append(makeAtom(kind: .text(ch), countable: true, url: linkURL(in: ch)))
                    }
                    guard !atoms.isEmpty else { continue }
                    words.append(RevealWord(id: atoms[0].id, atoms: atoms, isWhitespace: false, isLineBreak: false))
                }
            }
        case .line:
            appendLines(from: content, into: &words)
        }
        // A block with no countable atoms (e.g. an empty heading mid-stream)
        // must never gate open on its own; re-flattening assigns a real index
        // once content arrives.
        let first = words.flatMap(\.atoms).first(where: \.isCountable)?.revealIndex ?? Int.max
        blocks.append(RevealBlock(id: blocks.count, kind: kind, words: words, node: nil, firstRevealIndex: first))
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

    private mutating func makeWord(from slice: AttributedString, isWhitespace: Bool) -> RevealWord {
        if isWhitespace {
            if slice.characters.contains(where: \.isNewline) {
                let atom = makeAtom(kind: .lineBreak, countable: false, url: nil)
                return RevealWord(id: atom.id, atoms: [atom], isWhitespace: false, isLineBreak: true)
            }
            let atom = makeAtom(kind: .space(slice), countable: false, url: nil)
            return RevealWord(id: atom.id, atoms: [atom], isWhitespace: true, isLineBreak: false)
        }
        let atom = makeAtom(kind: .text(slice), countable: true, url: linkURL(in: slice))
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
        blocks.append(RevealBlock(
            id: blocks.count, kind: .wholeBlock, words: [word], node: node, firstRevealIndex: atom.revealIndex
        ))
    }
}

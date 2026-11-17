import SwiftUI
import UIKit

/// Walks parsed blocks into `GlimmerStaticBlock`s. Each block's text is composed by `GlimmerComposer` and flattened as
/// `GlimmerView.attributedString` flattens it; the indents, markers and gaps the composer would put in paragraph styles
/// become the stack's instead, with the same values.
struct GlimmerStaticDocumentBuilder {
    /// Where a block sits, for its colours, markers and spacing.
    struct Context {
        /// Overrides the theme's `paragraphSpacing` (in a tight list), as in `GlimmerComposer.Context`.
        var paragraphSpacing: CGFloat?
        var quoteDepth = 0
        var listDepth = 0
        /// In the footnote definitions: the footnote font and the secondary text colour.
        var isFootnote = false
    }

    private let theme: GlimmerTheme
    private let composer: GlimmerComposer
    /// The space after the last block built, as its paragraph style would leave it. Nil until a block is built.
    private var trailing: CGFloat?

    init(theme: GlimmerTheme, composer: GlimmerComposer) {
        self.theme = theme
        self.composer = composer
    }

    mutating func build(_ blocks: [GlimmerBlock], context: Context) -> [GlimmerStaticBlock] {
        var output: [GlimmerStaticBlock] = []
        for block in blocks {
            output += build(block, context: context)
        }
        return output
    }

    // MARK: - Blocks

    private mutating func build(_ block: GlimmerBlock, context: Context) -> [GlimmerStaticBlock] {
        switch block {
        case .paragraph, .htmlBlock:
            return text(block, headingLevel: nil, context: context)
        case .heading(let level, _):
            return text(block, headingLevel: level, context: context)
        case .codeBlock:
            return [embed(.code(runs(of: block, context: context)))]
        case .table:
            return [embed(.table(lines(of: runs(of: block, context: context))))]
        case .thematicBreak:
            return [embed(.rule)]
        case .blockQuote(let blocks):
            return quote(blocks, context: context)
        case .list(let list):
            return self.list(list, context: context)
        case .footnoteDefinitions(let notes):
            return footnotes(notes, context: context)
        }
    }

    private mutating func text(_ block: GlimmerBlock, headingLevel: Int?, context: Context) -> [GlimmerStaticBlock] {
        let text = runs(of: block, context: context)
        // A paragraph of hidden images composes to nothing, and the engine leaves it out with its spacing.
        guard !text.characters.isEmpty else { return [] }
        // A heading's space above collapses into the space after the text above it (CSS margin collapsing).
        let gap = headingLevel == nil ? trailing ?? 0 : trailing.map { max($0, theme.blockSpacing) } ?? 0
        trailing = context.paragraphSpacing ?? theme.paragraphSpacing
        return [GlimmerStaticBlock(content: .text(text, headingLevel: headingLevel), spacingAbove: gap)]
    }

    /// A code block, table or rule: block spacing after, as the composer gives an embed.
    private mutating func embed(_ content: GlimmerStaticBlock.Content) -> GlimmerStaticBlock {
        let gap = trailing ?? 0
        trailing = theme.blockSpacing
        return GlimmerStaticBlock(content: content, spacingAbove: gap)
    }

    private mutating func quote(_ blocks: [GlimmerBlock], context: Context) -> [GlimmerStaticBlock] {
        var inner = context
        inner.quoteDepth += 1
        var children = build(blocks, context: inner)
        guard let first = children.first else { return [] }
        children[0].spacingAbove = 0
        // Only the outermost quote's end gets block spacing, as in `GlimmerComposer.markQuoteEnd`.
        if context.quoteDepth == 0 { trailing = theme.blockSpacing }
        return [GlimmerStaticBlock(content: .quote(children), spacingAbove: first.spacingAbove)]
    }

    private mutating func list(_ list: GlimmerList, context: Context) -> [GlimmerStaticBlock] {
        var inner = context
        inner.listDepth += 1
        let markers = list.items.enumerated().map { offset, item in
            marker(kind: list.kind, index: offset, checkbox: item.checkbox, context: inner)
        }
        let isOrdered = if case .ordered = list.kind { true } else { false }
        var reserved: CGFloat = 0
        if case .ordered(let start) = list.kind {
            reserved = composer(for: inner).reservedNumberWidth(digits: max(2, String(start + list.items.count - 1).count))
        }
        return items(
            list.items.map(\.blocks), markers: markers, isOrdered: isOrdered, isTight: list.isTight,
            reservedMarkerWidth: reserved, context: context
        )
    }

    /// The notes after the last block, as the composer shows them: a rule, then an ordered list in reference order, in
    /// the footnote font and the secondary text colour.
    private mutating func footnotes(_ notes: [GlimmerFootnote], context: Context) -> [GlimmerStaticBlock] {
        guard composer.rendersFootnoteDefinitions, !notes.isEmpty else { return [] }
        let rule = embed(.rule)
        var inner = context
        inner.isFootnote = true
        let numbered = notes.map { (note: $0, number: composer.footnotes.number(for: $0.label)) }.sorted { $0.number < $1.number }
        let font = composer(for: inner).theme.bodyFont
        let markers = numbered.map { marker("\($0.number).", font: font, color: theme.secondaryTextColor) }
        let reserved = composer(for: inner).reservedNumberWidth(digits: max(2, String(numbered.count).count))
        let list = items(
            numbered.map(\.note.blocks), markers: markers, isOrdered: true,
            isTight: notes.allSatisfy { $0.blocks.count <= 1 }, reservedMarkerWidth: reserved, context: inner
        )
        return [rule] + list
    }

    /// A list's items, spaced as the composer spaces them, with a marker column as wide as its widest marker needs.
    private mutating func items(
        _ contents: [[GlimmerBlock]], markers: [Marker], isOrdered: Bool, isTight: Bool,
        reservedMarkerWidth: CGFloat, context: Context
    ) -> [GlimmerStaticBlock] {
        var inner = context
        inner.listDepth += 1
        inner.paragraphSpacing = isTight ? theme.tightListSpacing : nil
        var items: [GlimmerStaticListItem] = []
        for (blocks, marker) in zip(contents, markers) {
            var children = build(blocks, context: inner)
            let gap: CGFloat
            if let first = children.first {
                gap = first.spacingAbove
                children[0].spacingAbove = 0
            } else {
                // An empty item still shows its marker, on a paragraph of its own.
                gap = trailing ?? 0
                trailing = inner.paragraphSpacing ?? theme.paragraphSpacing
            }
            items.append(GlimmerStaticListItem(marker: marker.text, spacingAbove: gap, blocks: children))
        }
        guard !items.isEmpty else { return [] }
        let listGap = items[0].spacingAbove
        items[0].spacingAbove = 0
        if isTight { trailing = context.paragraphSpacing ?? theme.paragraphSpacing }
        let metrics = composer(for: inner)
        let widest = markers.map(\.width).max() ?? 0
        let column = max(theme.listIndent, ceil(max(widest, reservedMarkerWidth) + metrics.markerGap))
        let list = GlimmerStaticList(isOrdered: isOrdered, markerColumnWidth: column, markerGap: metrics.markerGap, items: items)
        return [GlimmerStaticBlock(content: .list(list), spacingAbove: listGap)]
    }

    // MARK: - Text

    /// The block's text, composed alone and flattened, without the paragraph styles the stack replaces.
    private func runs(of block: GlimmerBlock, context: Context) -> AttributedString {
        let composed = NSMutableAttributedString(
            attributedString: composer(for: context).composeBlock(block, isFirst: true, precedingSpacing: nil)
        )
        if composed.string.hasSuffix("\n") {
            composed.deleteCharacters(in: NSRange(location: composed.length - 1, length: 1))
        }
        composed.removeAttribute(.paragraphStyle, range: NSRange(location: 0, length: composed.length))
        return GlimmerPlainText.standalone(composed, theme: composer(for: context).theme)
    }

    /// The composer for a context: dimmed inside a quote, smaller in the footnotes. Copies share the footnote numbers.
    private func composer(for context: Context) -> GlimmerComposer {
        var copy = composer
        if context.isFootnote { copy.theme.bodyFont = theme.footnoteFont }
        if context.isFootnote || context.quoteDepth > 0 { copy.theme.textColor = theme.secondaryTextColor }
        return copy
    }

    /// A table's rows: its flattened text split at line breaks.
    private func lines(of text: AttributedString) -> [AttributedString] {
        var lines: [AttributedString] = []
        var start = text.startIndex
        for index in text.characters.indices where text.characters[index] == "\n" {
            lines.append(AttributedString(text[start..<index]))
            start = text.characters.index(after: index)
        }
        lines.append(AttributedString(text[start..<text.endIndex]))
        return lines
    }

    // MARK: - Markers

    /// A marker's text and its drawn width.
    private typealias Marker = (text: AttributedString, width: CGFloat)

    private func marker(kind: GlimmerList.Kind, index: Int, checkbox: Bool?, context: Context) -> Marker {
        let styled = composer(for: context).theme
        if let checkbox {
            // The characters `GlimmerView.attributedString` uses, tinted as the engine tints its boxes.
            return marker(checkbox ? "\u{2611}\u{FE0E}" : "\u{2610}", font: styled.bodyFont,
                          color: checkbox ? theme.linkColor : theme.secondaryTextColor)
        }
        switch kind {
        case .bullet:
            let bullets = GlimmerComposer.bullets
            return marker(bullets[(context.listDepth - 1) % bullets.count], font: styled.bodyFont, color: styled.textColor)
        case .ordered(let start):
            return marker("\(start + index).", font: styled.bodyFont, color: styled.textColor)
        }
    }

    private func marker(_ symbol: String, font: UIFont, color: UIColor) -> Marker {
        let styled = NSAttributedString(string: symbol, attributes: [.font: font, .foregroundColor: color])
        return (GlimmerPlainText.attributedString(from: styled), styled.size().width)
    }
}

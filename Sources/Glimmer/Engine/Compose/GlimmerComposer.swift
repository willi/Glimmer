import UIKit

/// Turns a `GlimmerBlock` tree into one attributed string for a `GlimmerTextView`.
///
/// Prose becomes text with paragraph styles; code blocks, tables, standalone images and rules become full-width
/// `GlimmerBlockAttachment`s. The theme must already be scaled for Dynamic Type (`GlimmerTheme.scaled(for:)`).
struct GlimmerComposer {
    var theme: GlimmerTheme
    var highlighter: any GlimmerHighlighter = GlimmerBasicHighlighter()
    var imageLoader: (any GlimmerImageLoader)? = nil
    var extensions: [any GlimmerExtension] = []

    struct Context {
        var indent: CGFloat = 0
        var quoteDepth = 0
        var listDepth = 0
        /// Overrides `paragraphSpacing` (tight lists).
        var paragraphSpacing: CGFloat?
        /// True while composing the document's first top-level block (no heading space above it).
        var isDocumentStart = false
        /// Width of the innermost list's marker column: its text starts this far right of the marker.
        var listStep: CGFloat = 0
        /// Markers end a fixed gap before the text (numbers) instead of starting the marker column (bullets).
        var alignsMarkersToText = false
        /// Attachments offered back while re-composing a block, and the record of the ones emitted. Nil composes fresh.
        var reuse: GlimmerAttachmentReuse?
        /// Markdown written before a paragraph's content on continuation lines: quote markers and list indentation.
        var markdownPrefix = ""
        /// Markdown written before the marker on an item's first line (the enclosing container's prefix).
        var markerLinePrefix = ""
        /// Inside a tight list's item.
        var isTight = false
    }

    func compose(_ blocks: [GlimmerBlock]) -> NSAttributedString {
        let output = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() { output.append(composeBlock(block, isFirst: index == 0)) }
        if output.length > 0 { output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1)) }
        return output
    }

    /// One top-level block, ending in "\n". `compose(_:)` is exactly these joined with the final "\n" removed, which
    /// is what lets `GlimmerStreamingDocument` re-compose only the blocks that changed.
    func composeBlock(_ block: GlimmerBlock, isFirst: Bool) -> NSAttributedString {
        composeBlock(block, isFirst: isFirst, reusing: nil)
    }

    /// Like `composeBlock(_:isFirst:)`, and offers `reuse`'s attachments back for embeds that continue them.
    func composeBlock(_ block: GlimmerBlock, isFirst: Bool, reusing reuse: GlimmerAttachmentReuse?) -> NSAttributedString {
        let output = NSMutableAttributedString()
        var context = Context()
        context.isDocumentStart = isFirst
        context.reuse = reuse
        append(block, context: context, marker: nil, to: output)
        return output
    }

    /// Styled text for a run of inlines, without paragraph styling. Table cells use this.
    func compose(inlines: [GlimmerInline], font: UIFont) -> NSAttributedString {
        let output = NSMutableAttributedString()
        appendInlines(inlines, attributes: [.font: font, .foregroundColor: theme.textColor], to: output)
        return output
    }

    // MARK: - Blocks

    private func append(_ block: GlimmerBlock, context: Context, marker: NSAttributedString?, to output: NSMutableAttributedString) {
        switch block {
        case .paragraph(let inlines):
            if let image = standaloneImage(inlines) {
                appendEmbed(.image(source: image.url, alt: image.alt), source: "![\(image.alt)](\(image.url.absoluteString))",
                            context: context, marker: marker, to: output)
            } else {
                appendTextParagraph(inlines, font: theme.bodyFont, context: context, marker: marker, to: output)
            }
        case .heading(let level, let inlines):
            appendTextParagraph(inlines, font: theme.headingFont(level: level), context: context, marker: marker,
                                headingLevel: level, spacingBefore: output.length > 0 || !context.isDocumentStart ? theme.blockSpacing : 0, to: output)
        case .blockQuote(let blocks):
            var inner = context
            inner.indent += theme.quoteIndent
            inner.quoteDepth += 1
            inner.markdownPrefix += "> "
            // A quote that opens a list item is written "- > …": the marker's source carries the quote's ">".
            let quotedMarker = marker.map { marker in
                let copy = NSMutableAttributedString(attributedString: marker)
                let source = copy.attribute(.glimmerListMarker, at: 0, effectiveRange: nil) as? String ?? ""
                copy.addAttribute(.glimmerListMarker, value: source + "> ", range: NSRange(location: 0, length: copy.length))
                return copy as NSAttributedString
            }
            let start = output.length
            for (index, child) in blocks.enumerated() {
                append(child, context: inner, marker: index == 0 ? quotedMarker : nil, to: output)
            }
            if output.length > start { markQuoteEnd(continuingLevels: context.quoteDepth, in: output) }
        case .list(let list):
            if let marker { appendTextParagraph([], font: theme.bodyFont, context: context, marker: marker, to: output) }
            appendList(list, context: context, to: output)
        case .codeBlock(let language, let code):
            appendEmbed(.codeBlock(language: language, code: code), source: Self.fencedSource(code, language: language),
                        context: context, marker: marker, to: output)
        case .table(let table):
            let embed = tableEmbed(table)
            appendEmbed(embed, source: tableSource(embed), context: context, marker: marker, to: output)
        case .thematicBreak:
            appendEmbed(.thematicBreak, source: "---", context: context, marker: marker, to: output)
        case .htmlBlock(let html):
            appendTextParagraph([.text(html.trimmingCharacters(in: .newlines))], font: theme.bodyFont, context: context,
                                marker: marker, to: output)
        }
    }

    private func appendList(_ list: GlimmerList, context: Context, to output: NSMutableAttributedString) {
        var inner = context
        inner.listDepth += 1
        let markers = list.items.enumerated().map { offset, item in
            listMarker(kind: list.kind, index: offset, checkbox: item.checkbox, context: inner)
        }
        // At least `listIndent`, and always a gap after the widest marker (wide numbers, large text sizes). Numbers get
        // room for two digits up front, so items already shown do not shift right when item 10 streams in.
        var widestMarker = markers.map { $0.attributedSubstring(from: NSRange(location: 0, length: $0.length - 1)).size().width }.max() ?? 0
        if case .ordered(let start) = list.kind {
            let digits = max(2, String(start + list.items.count - 1).count)
            widestMarker = max(widestMarker, reservedNumberWidth(digits: digits))
        }
        inner.listStep = max(theme.listIndent, ceil(widestMarker + markerGap))
        inner.indent += inner.listStep
        if case .ordered = list.kind { inner.alignsMarkersToText = true } else { inner.alignsMarkersToText = false }
        inner.paragraphSpacing = list.isTight ? theme.tightListSpacing : nil
        for (offset, item) in list.items.enumerated() {
            let marker = markers[offset]
            // The item's content is indented by its marker's source width, which is what continuation lines need.
            let markerSource = marker.attribute(.glimmerListMarker, at: 0, effectiveRange: nil) as? String ?? ""
            var itemContext = inner
            itemContext.markerLinePrefix = context.markdownPrefix
            itemContext.markdownPrefix = context.markdownPrefix + String(repeating: " ", count: markerSource.count)
            itemContext.isTight = list.isTight
            if item.blocks.isEmpty {
                appendTextParagraph([], font: theme.bodyFont, context: itemContext, marker: marker, to: output)
            }
            for (index, block) in item.blocks.enumerated() {
                append(block, context: itemContext, marker: index == 0 ? marker : nil, to: output)
            }
        }
        if list.isTight { setSpacingOfLastParagraph(context.paragraphSpacing ?? theme.paragraphSpacing, in: output) }
    }

    private func appendTextParagraph(
        _ inlines: [GlimmerInline], font: UIFont, context: Context, marker: NSAttributedString?,
        headingLevel: Int? = nil, spacingBefore: CGFloat = 0, to output: NSMutableAttributedString
    ) {
        let start = output.length
        let attributes = baseAttributes(font: font, context: context)
        if let marker { output.append(marker) }
        appendInlines(inlines, attributes: attributes, to: output)
        output.append(NSAttributedString(string: "\n", attributes: attributes))
        let range = NSRange(location: start, length: output.length - start)
        let style = paragraphStyle(context: context, marker: marker)
        style.paragraphSpacingBefore = spacingBefore
        output.addAttribute(.paragraphStyle, value: style, range: range)
        if context.quoteDepth > 0 { output.addAttribute(.glimmerQuoteDepth, value: context.quoteDepth, range: range) }
        if let headingLevel { output.addAttribute(.accessibilityTextHeadingLevel, value: headingLevel, range: range) }
        stampMarkdown(context: context, hasMarker: marker != nil, range: range, in: output)
    }

    private func appendEmbed(
        _ embed: GlimmerEmbed, source: String, context: Context, marker: NSAttributedString?,
        to output: NSMutableAttributedString
    ) {
        if let marker { appendTextParagraph([], font: theme.bodyFont, context: context, marker: marker, to: output) }
        let start = output.length
        let attachment = context.reuse?.attachment(for: embed)
            ?? GlimmerBlockAttachment(embed: embed, theme: theme, highlighter: highlighter, imageLoader: imageLoader)
        context.reuse?.record(attachment, embed: embed, at: output.length)
        output.append(NSAttributedString(attachment: attachment))
        output.append(NSAttributedString(string: "\n"))
        let range = NSRange(location: start, length: output.length - start)
        let style = paragraphStyle(context: context, marker: nil)
        style.lineHeightMultiple = 1
        style.paragraphSpacing = theme.blockSpacing
        output.addAttributes([.paragraphStyle: style, .font: theme.bodyFont, .glimmerSource: source], range: range)
        if context.quoteDepth > 0 { output.addAttribute(.glimmerQuoteDepth, value: context.quoteDepth, range: range) }
        stampMarkdown(context: context, hasMarker: false, range: range, in: output)
    }

    /// Records what copy needs to write this paragraph back as markdown.
    private func stampMarkdown(context: Context, hasMarker: Bool, range: NSRange, in output: NSMutableAttributedString) {
        output.addAttribute(.glimmerMarkdownPrefix, value: hasMarker ? context.markerLinePrefix : context.markdownPrefix, range: range)
        if context.isTight { output.addAttribute(.glimmerTightList, value: true, range: range) }
    }

    // MARK: - Styles

    func baseAttributes(font: UIFont, context: Context) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: context.quoteDepth > 0 ? theme.secondaryTextColor : theme.textColor]
    }

    /// The space between a list marker and its item's text.
    private var markerGap: CGFloat { ceil(theme.bodyFont.pointSize * 0.4) }

    private func paragraphStyle(context: Context, marker: NSAttributedString?) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = theme.lineHeightMultiple
        style.headIndent = context.indent
        if let marker {
            // Numbers share a right edge, like a browser's list: "10." grows to the left, not into the gap.
            let width = marker.attributedSubstring(from: NSRange(location: 0, length: marker.length - 1)).size().width
            style.firstLineHeadIndent = context.alignsMarkersToText
                ? max(0, context.indent - markerGap - width)
                : max(0, context.indent - context.listStep)
            style.tabStops = [NSTextTab(textAlignment: .natural, location: context.indent, options: [:])]
        } else {
            style.firstLineHeadIndent = context.indent
        }
        style.paragraphSpacing = context.paragraphSpacing ?? theme.paragraphSpacing
        return style
    }

    /// Marks the paragraph that closes a quote with how many enclosing quote levels continue past it, so the
    /// ending levels' bars stop at the text. A quote that closes completely gets block spacing below it.
    private func markQuoteEnd(continuingLevels: Int, in output: NSMutableAttributedString) {
        guard output.length > 0 else { return }
        let range = output.mutableString.paragraphRange(for: NSRange(location: output.length - 1, length: 0))
        let existing = output.attribute(.glimmerQuoteContinues, at: range.location, effectiveRange: nil) as? Int
        output.addAttribute(.glimmerQuoteContinues, value: min(existing ?? continuingLevels, continuingLevels), range: range)
        if continuingLevels == 0 { setSpacingOfLastParagraph(theme.blockSpacing, in: output) }
    }

    private func setSpacingOfLastParagraph(_ spacing: CGFloat, in output: NSMutableAttributedString) {
        guard output.length > 0 else { return }
        let range = output.mutableString.paragraphRange(for: NSRange(location: output.length - 1, length: 0))
        guard let current = output.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle,
              let style = current.mutableCopy() as? NSMutableParagraphStyle else { return }
        style.paragraphSpacing = spacing
        output.addAttribute(.paragraphStyle, value: style, range: range)
    }

    /// The width of the widest `digits`-digit number marker in the body font, such as "88.".
    private func reservedNumberWidth(digits: Int) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: theme.bodyFont]
        let widestDigit = (0...9).map { NSAttributedString(string: "\($0)", attributes: attributes).size().width }.max() ?? 0
        return widestDigit * CGFloat(digits) + NSAttributedString(string: ".", attributes: attributes).size().width
    }

    private func listMarker(kind: GlimmerList.Kind, index: Int, checkbox: Bool?, context: Context) -> NSAttributedString {
        let color = context.quoteDepth > 0 ? theme.secondaryTextColor : theme.textColor
        let marker = NSMutableAttributedString()
        let source: String
        if let checkbox {
            let symbol = UIImage(systemName: checkbox ? "checkmark.square.fill" : "square")?
                .withTintColor(checkbox ? theme.linkColor : theme.secondaryTextColor, renderingMode: .alwaysOriginal)
            let box = NSTextAttachment()
            box.image = symbol
            let side = ceil(theme.bodyFont.capHeight + 6)
            box.bounds = CGRect(x: 0, y: (theme.bodyFont.capHeight - side) / 2, width: side, height: side)
            marker.append(NSAttributedString(attachment: box))
            source = checkbox ? "- [x] " : "- [ ] "
        } else {
            switch kind {
            case .bullet:
                let bullets = ["•", "◦", "▪︎"]
                // One color for every marker, like a browser's ::marker: the text's, dimmed inside quotes.
                marker.append(NSAttributedString(string: bullets[(context.listDepth - 1) % bullets.count], attributes: [
                    .font: theme.bodyFont, .foregroundColor: color,
                ]))
                source = "- "
            case .ordered(let start):
                let number = start + index
                marker.append(NSAttributedString(string: "\(number).", attributes: [.font: theme.bodyFont, .foregroundColor: color]))
                source = "\(number). "
            }
        }
        marker.append(NSAttributedString(string: "\t", attributes: [.font: theme.bodyFont]))
        marker.addAttribute(.glimmerListMarker, value: source, range: NSRange(location: 0, length: marker.length))
        return marker
    }

    // MARK: - Embeds

    private func standaloneImage(_ inlines: [GlimmerInline]) -> (url: URL, alt: String)? {
        let meaningful = inlines.filter { inline in
            switch inline {
            case .softBreak, .lineBreak: false
            case .text(let text): !text.trimmingCharacters(in: .whitespaces).isEmpty
            default: true
            }
        }
        guard meaningful.count == 1, case .image(let source, _, let alt) = meaningful[0], let url = URL(string: source) else {
            return nil
        }
        return (url, alt)
    }

    private func tableEmbed(_ table: GlimmerTable) -> GlimmerEmbed {
        .table(
            header: table.header.map { compose(inlines: $0, font: theme.tableHeaderFont) },
            rows: table.rows.map { row in row.map { compose(inlines: $0, font: theme.tableFont) } },
            alignments: table.alignments
        )
    }

    /// A fence longer than any backtick run in the code, so code that shows a fence copies intact.
    static func fencedSource(_ code: String, language: String?) -> String {
        let fence = String(repeating: "`", count: max(3, GlimmerMarkdownSerializer.longestBacktickRun(in: code) + 1))
        return "\(fence)\(language ?? "")\n\(code)\n\(fence)"
    }

    /// The table's markdown, each composed cell written back with its styles, code and links, pipes escaped.
    private func tableSource(_ embed: GlimmerEmbed) -> String {
        guard case .table(let header, let rows, let alignments) = embed else { return "" }
        func line(_ cells: [NSAttributedString]) -> String {
            let written = cells.map { cell in
                GlimmerMarkdownSerializer.markdown(from: cell, range: NSRange(location: 0, length: cell.length))
                    .replacingOccurrences(of: "|", with: "\\|")
            }
            return "| " + written.joined(separator: " | ") + " |"
        }
        let divider = "| " + alignments.map { alignment in
            switch alignment {
            case .left: ":---"
            case .center: ":---:"
            case .right: "---:"
            case .none: "---"
            }
        }.joined(separator: " | ") + " |"
        return ([line(header), divider] + rows.map(line)).joined(separator: "\n")
    }
}

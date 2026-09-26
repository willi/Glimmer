import UIKit

/// Turns a `GlimmerBlock` tree into one attributed string for a `GlimmerTextView`.
///
/// Prose becomes text with paragraph styles; code blocks, tables, standalone images and rules become full-width
/// `GlimmerBlockAttachment`s. The theme must already be scaled for Dynamic Type (`GlimmerTheme.scaled(for:)`).
@MainActor
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
        /// Width of the innermost list's marker column: its text starts this far right of the marker.
        var listStep: CGFloat = 0
    }

    func compose(_ blocks: [GlimmerBlock]) -> NSAttributedString {
        let output = NSMutableAttributedString()
        for block in blocks { append(block, context: Context(), marker: nil, to: output) }
        if output.string.hasSuffix("\n") {
            output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1))
        }
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
                                headingLevel: level, spacingBefore: output.length > 0 ? theme.blockSpacing : 0, to: output)
        case .blockQuote(let blocks):
            var inner = context
            inner.indent += theme.quoteIndent
            inner.quoteDepth += 1
            let start = output.length
            for (index, child) in blocks.enumerated() {
                append(child, context: inner, marker: index == 0 ? marker : nil, to: output)
            }
            if output.length > start { markQuoteEnd(continuingLevels: context.quoteDepth, in: output) }
        case .list(let list):
            if let marker { appendTextParagraph([], font: theme.bodyFont, context: context, marker: marker, to: output) }
            appendList(list, context: context, to: output)
        case .codeBlock(let language, let code):
            appendEmbed(.codeBlock(language: language, code: code), source: "```\(language ?? "")\n\(code)\n```",
                        context: context, marker: marker, to: output)
        case .table(let table):
            appendEmbed(tableEmbed(table), source: tableSource(table), context: context, marker: marker, to: output)
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
        // At least `listIndent`, and always a gap after the widest marker (wide numbers, large text sizes).
        let widestMarker = markers.map { $0.attributedSubstring(from: NSRange(location: 0, length: $0.length - 1)).size().width }.max() ?? 0
        inner.listStep = max(theme.listIndent, ceil(widestMarker + theme.bodyFont.pointSize * 0.4))
        inner.indent += inner.listStep
        inner.paragraphSpacing = list.isTight ? theme.tightListSpacing : nil
        for (offset, item) in list.items.enumerated() {
            let marker = markers[offset]
            if item.blocks.isEmpty {
                appendTextParagraph([], font: theme.bodyFont, context: inner, marker: marker, to: output)
            }
            for (index, block) in item.blocks.enumerated() {
                append(block, context: inner, marker: index == 0 ? marker : nil, to: output)
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
        let style = paragraphStyle(context: context, hasMarker: marker != nil)
        style.paragraphSpacingBefore = spacingBefore
        output.addAttribute(.paragraphStyle, value: style, range: range)
        if context.quoteDepth > 0 { output.addAttribute(.glimmerQuoteDepth, value: context.quoteDepth, range: range) }
        if let headingLevel { output.addAttribute(.accessibilityTextHeadingLevel, value: headingLevel, range: range) }
    }

    private func appendEmbed(
        _ embed: GlimmerEmbed, source: String, context: Context, marker: NSAttributedString?,
        to output: NSMutableAttributedString
    ) {
        if let marker { appendTextParagraph([], font: theme.bodyFont, context: context, marker: marker, to: output) }
        let start = output.length
        let attachment = GlimmerBlockAttachment(embed: embed, theme: theme, highlighter: highlighter, imageLoader: imageLoader)
        output.append(NSAttributedString(attachment: attachment))
        output.append(NSAttributedString(string: "\n"))
        let range = NSRange(location: start, length: output.length - start)
        let style = paragraphStyle(context: context, hasMarker: false)
        style.lineHeightMultiple = 1
        style.paragraphSpacing = theme.blockSpacing
        output.addAttributes([.paragraphStyle: style, .font: theme.bodyFont, .glimmerSource: source], range: range)
        if context.quoteDepth > 0 { output.addAttribute(.glimmerQuoteDepth, value: context.quoteDepth, range: range) }
    }

    // MARK: - Styles

    func baseAttributes(font: UIFont, context: Context) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: context.quoteDepth > 0 ? theme.secondaryTextColor : theme.textColor]
    }

    private func paragraphStyle(context: Context, hasMarker: Bool) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = theme.lineHeightMultiple
        style.headIndent = context.indent
        style.firstLineHeadIndent = hasMarker ? max(0, context.indent - context.listStep) : context.indent
        style.tabStops = hasMarker ? [NSTextTab(textAlignment: .natural, location: context.indent, options: [:])] : []
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
                marker.append(NSAttributedString(string: bullets[(context.listDepth - 1) % bullets.count], attributes: [
                    .font: theme.bodyFont, .foregroundColor: theme.secondaryTextColor,
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

    private func tableSource(_ table: GlimmerTable) -> String {
        func line(_ cells: [[GlimmerInline]]) -> String {
            "| " + cells.map { GlimmerInline.plainText($0) }.joined(separator: " | ") + " |"
        }
        let divider = "| " + table.alignments.map { alignment in
            switch alignment {
            case .left: ":---"
            case .center: ":---:"
            case .right: "---:"
            case .none: "---"
            }
        }.joined(separator: " | ") + " |"
        return ([line(table.header), divider] + table.rows.map(line)).joined(separator: "\n")
    }
}

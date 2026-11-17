import UIKit

/// Turns a `GlimmerBlock` tree into one attributed string for a `GlimmerTextView`.
///
/// Prose becomes text with paragraph styles; code blocks, tables, standalone images and rules become full-width
/// `GlimmerBlockAttachment`s. The theme must already be scaled for Dynamic Type (`GlimmerTheme.scaled(for:)`).
struct GlimmerComposer {
    var theme: GlimmerTheme
    var highlighter: any GlimmerHighlighter = GlimmerBasicHighlighter()
    var imageLoader: (any GlimmerImageLoader)? = nil
    /// The host's say over which images load. Nil loads every image.
    var imagePolicy: (any GlimmerImagePolicy)? = nil
    var inlineImageShape: GlimmerInlineImageShape = .circle
    /// The host's say over which links are links. Nil links every one.
    var linkPolicy: (any GlimmerLinkPolicy)? = nil
    var extensions: [any GlimmerExtension] = []
    /// Whether the host takes image taps: an inline image's spoken alt text then links to the image for VoiceOver.
    var linksImagesForTaps = false
    /// Footnote numbers by first reference. Shared by copies of this composer, so a streaming document's recomposed
    /// blocks keep the numbers earlier blocks gave.
    var footnotes = GlimmerFootnoteNumbers()
    /// Whether footnote definitions render (after the last block). A streaming document turns this off until the
    /// answer settles: body text keeps arriving after a definition.
    var rendersFootnoteDefinitions = true

    struct Context {
        var indent: CGFloat = 0
        var quoteDepth = 0
        var listDepth = 0
        /// Overrides `paragraphSpacing` (tight lists).
        var paragraphSpacing: CGFloat?
        /// True while composing the document's first top-level block (no heading space above it).
        var isDocumentStart = false
        /// The space after the text composed before this top-level block, if any. A heading's space above collapses into it.
        var precedingSpacing: CGFloat?
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
        /// Each enclosing list's tightness, outermost first.
        var listTightness: [Bool] = []
        /// In a list's first item: its marker paragraph opens the list.
        var opensList = false
    }

    func compose(_ blocks: [GlimmerBlock]) -> NSAttributedString {
        let output = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            let isFirst = startsDocument(index: index, in: blocks, precedingLength: output.length)
            output.append(composeBlock(block, isFirst: isFirst, precedingSpacing: Self.trailingSpacing(of: output)))
        }
        if output.length > 0 { output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1)) }
        return output
    }

    /// Whether the block at `index` of `blocks` opens the document, with `precedingLength` characters composed before
    /// it. Under an image policy the blocks before it may all have been left out, and the first block that shows text
    /// is then the one with no heading space above it. A block that shows nothing with or without a policy, such as
    /// an empty quote, is not one the policy left out: what follows it is spaced as it is with no policy.
    func startsDocument(index: Int, in blocks: [GlimmerBlock], precedingLength: Int) -> Bool {
        if index == 0 { return true }
        guard imagePolicy != nil, precedingLength == 0 else { return false }
        return !blocks[..<index].contains(where: Self.showsNothingByItself)
    }

    /// Whether a block composes to nothing whatever the image policy says.
    private static func showsNothingByItself(_ block: GlimmerBlock) -> Bool {
        switch block {
        case .blockQuote(let blocks): blocks.allSatisfy(showsNothingByItself)
        // Notes compose to nothing only when they are not rendered here at all.
        case .footnoteDefinitions: true
        default: false
        }
    }

    /// The policy bound to an image it decided to load, for the check before the load. Nil without a policy.
    func imageGate(url: URL, alt: String, title: String?, origin: GlimmerImageCandidate.Origin) -> GlimmerImageGate? {
        imagePolicy.map {
            GlimmerImageGate(policy: $0, candidate: GlimmerImageCandidate(url: url, alt: alt, title: title, origin: origin))
        }
    }

    /// What to do with an image. With no policy every image loads, as it did before policies existed. A policy that
    /// cannot be asked, because the URL does not parse, fails closed to the alt text.
    func imageDecision(url: URL?, alt: String, title: String?, origin: GlimmerImageCandidate.Origin) -> GlimmerImageDecision {
        guard let imagePolicy else { return .load }
        guard let url else { return .showAltText }
        return imagePolicy.decision(for: GlimmerImageCandidate(url: url, alt: alt, title: title, origin: origin))
    }

    /// Where a link goes, or nil to compose it as text: its destination does not parse, or the link policy refuses it.
    /// With no policy every link that parses is a link, as it was before policies existed.
    func linkURL(destination: String, title: String?) -> URL? {
        let url = URL(string: destination)
        guard let linkPolicy, url != nil else { return url }
        let candidate = GlimmerLinkCandidate(destination: destination, title: title)
        return linkPolicy.decision(for: candidate) == .link ? url : nil
    }

    /// One top-level block, ending in "\n". `compose(_:)` is these joined with the final "\n" removed, which is
    /// what lets `GlimmerStreamingDocument` re-compose only the blocks that changed. That holds only if each caller
    /// passes `trailingSpacing(of:)` for the text composed before the block (nil for none): a heading's space above
    /// depends on it.
    func composeBlock(_ block: GlimmerBlock, isFirst: Bool, precedingSpacing: CGFloat?) -> NSAttributedString {
        composeBlock(block, isFirst: isFirst, precedingSpacing: precedingSpacing, reusing: nil)
    }

    /// The space after the last paragraph of composed text, or nil for none. A heading composed next collapses its
    /// space above into it, so a streaming document passes the last block it kept.
    static func trailingSpacing(of text: NSAttributedString) -> CGFloat? {
        guard text.length > 0 else { return nil }
        let style = text.attribute(.paragraphStyle, at: text.length - 1, effectiveRange: nil) as? NSParagraphStyle
        return style?.paragraphSpacing
    }

    /// Like `composeBlock(_:isFirst:precedingSpacing:)`, and offers `reuse`'s attachments back for embeds that continue them.
    func composeBlock(
        _ block: GlimmerBlock, isFirst: Bool, precedingSpacing: CGFloat?, reusing reuse: GlimmerAttachmentReuse?
    ) -> NSAttributedString {
        let output = NSMutableAttributedString()
        var context = Context()
        context.isDocumentStart = isFirst
        context.precedingSpacing = precedingSpacing
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
            let image = standaloneImage(inlines)
            if let image, image.decision == .load {
                appendEmbed(.image(source: image.url, alt: image.alt),
                            source: GlimmerMarkdownSerializer.imageSource(source: image.url.absoluteString, alt: image.alt),
                            context: context, marker: marker,
                            imageGate: imageGate(url: image.url, alt: image.alt, title: image.title, origin: .markdown), to: output)
            } else {
                // One the policy does not load composes as text like any other paragraph, so no image box is
                // reserved for it. The answer it already gave goes along, so it is asked once.
                appendTextParagraph(inlines, font: theme.bodyFont, context: context, marker: marker,
                                    soleImageDecision: image?.decision, to: output)
            }
        case .heading(let level, let inlines):
            appendTextParagraph(inlines, font: theme.headingFont(level: level), context: context, marker: marker,
                                headingLevel: level, spacingBefore: headingSpacingBefore(output: output, context: context), to: output)
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
            let highlighted = GlimmerCodeHighlighting.highlightedCode(code, language: language, theme: theme, highlighter: highlighter)
            appendEmbed(.codeBlock(language: language, code: code, highlighted: highlighted),
                        source: Self.fencedSource(code, language: language), context: context, marker: marker, to: output)
        case .table(let table):
            let embed = tableEmbed(table)
            appendEmbed(embed, source: tableSource(embed), context: context, marker: marker, to: output)
        case .thematicBreak:
            appendEmbed(.thematicBreak, source: "---", context: context, marker: marker, to: output)
        case .htmlBlock(let html):
            appendTextParagraph([.text(html.trimmingCharacters(in: .newlines))], font: theme.bodyFont, context: context,
                                marker: marker, to: output)
        case .footnoteDefinitions(let notes):
            appendFootnotes(notes, context: context, to: output)
        }
    }

    /// The space above a heading: `blockSpacing` less the space the text above it already leaves, so the gap is the
    /// larger of the two, as in CSS margin collapsing. None at the start of the document.
    private func headingSpacingBefore(output: NSAttributedString, context: Context) -> CGFloat {
        guard output.length > 0 || !context.isDocumentStart else { return 0 }
        let above = Self.trailingSpacing(of: output) ?? context.precedingSpacing ?? 0
        return max(0, theme.blockSpacing - above)
    }

    /// The notes after the answer's last block: a thin rule, then an ordered list in marker order, in the footnote
    /// font and the secondary text colour, with no heading (remark-gfm's is visually hidden too).
    private func appendFootnotes(_ notes: [GlimmerFootnote], context: Context, to output: NSMutableAttributedString) {
        guard rendersFootnoteDefinitions, !notes.isEmpty else { return }
        appendEmbed(.thematicBreak, source: "", context: context, marker: nil, to: output)
        var noteComposer = self
        noteComposer.theme.bodyFont = theme.footnoteFont
        noteComposer.theme.textColor = theme.secondaryTextColor
        let numbered = notes.map { (note: $0, number: footnotes.number(for: $0.label)) }.sorted { $0.number < $1.number }
        // Tight unless a note has several blocks: its paragraphs need blank lines between them, on screen and in copy.
        let list = GlimmerList(kind: .ordered(start: 1), isTight: notes.allSatisfy { $0.blocks.count <= 1 },
                               items: numbered.map { GlimmerListItem(blocks: $0.note.blocks) })
        var inner = context
        inner.listDepth += 1
        let markers = numbered.map { noteComposer.footnoteMarker(number: $0.number, label: $0.note.label, context: inner) }
        noteComposer.appendList(list, context: context, markers: markers, to: output)
    }

    private func footnoteMarker(number: Int, label: String, context: Context) -> NSAttributedString {
        let marker = NSMutableAttributedString(string: "\(number).", attributes: [.font: theme.bodyFont, .foregroundColor: theme.textColor])
        marker.append(NSAttributedString(string: "\t", attributes: [.font: theme.bodyFont]))
        marker.addAttribute(.glimmerListMarker, value: "[^\(label)]: ", range: NSRange(location: 0, length: marker.length))
        return marker
    }

    private func appendList(
        _ list: GlimmerList, context: Context, markers given: [NSAttributedString]? = nil, to output: NSMutableAttributedString
    ) {
        var inner = context
        inner.listDepth += 1
        let markers = given ?? list.items.enumerated().map { offset, item in
            listMarker(kind: list.kind, index: offset, checkbox: item.checkbox, context: inner)
        }
        // At least `listIndent`, and always a gap after the widest marker (wide numbers, large text sizes). Numbers get
        // room for two digits up front, so items already shown do not shift right when item 10 streams in.
        var widestMarker = markers.map { visibleWidth(of: $0) }.max() ?? 0
        if case .ordered(let start) = list.kind {
            let digits = max(2, String(start + list.items.count - 1).count)
            widestMarker = max(widestMarker, reservedNumberWidth(digits: digits))
        }
        inner.listStep = max(theme.listIndent, ceil(widestMarker + markerGap))
        inner.indent += inner.listStep
        if case .ordered = list.kind { inner.alignsMarkersToText = true } else { inner.alignsMarkersToText = false }
        inner.paragraphSpacing = list.isTight ? theme.tightListSpacing : theme.looseListSpacing
        for (offset, item) in list.items.enumerated() {
            let marker = markers[offset]
            // The item's later lines are indented to its content column, which is what continuation lines need.
            let markerSource = marker.attribute(.glimmerListMarker, at: 0, effectiveRange: nil) as? String ?? ""
            var itemContext = inner
            itemContext.markerLinePrefix = context.markdownPrefix
            itemContext.markdownPrefix = context.markdownPrefix + GlimmerMarkdownSerializer.continuation(ofMarker: markerSource)
            itemContext.listTightness = context.listTightness + [list.isTight]
            itemContext.opensList = offset == 0
            if item.blocks.isEmpty {
                appendTextParagraph([], font: theme.bodyFont, context: itemContext, marker: marker, to: output)
            }
            for (index, block) in item.blocks.enumerated() {
                append(block, context: itemContext, marker: index == 0 ? marker : nil, to: output)
            }
        }
        if list.isTight || theme.looseListSpacing != nil { setSpacingOfLastParagraph(context.paragraphSpacing ?? theme.paragraphSpacing, in: output) }
    }

    private func appendTextParagraph(
        _ inlines: [GlimmerInline], font: UIFont, context: Context, marker: NSAttributedString?,
        headingLevel: Int? = nil, spacingBefore: CGFloat = 0, soleImageDecision: GlimmerImageDecision? = nil,
        to output: NSMutableAttributedString
    ) {
        let start = output.length
        let attributes = baseAttributes(font: font, context: context)
        if let marker { output.append(marker) }
        let contentStart = output.length
        let keptAnImageFromShowing = appendInlines(
            inlines, attributes: attributes, reuse: context.reuse, soleImageDecision: soleImageDecision, to: output
        )
        // A paragraph that held only images the policy did not load is left out, so no blank line stands in for them.
        // A list item keeps its marker.
        if keptAnImageFromShowing, marker == nil, Self.isBlank(output, from: contentStart) {
            output.deleteCharacters(in: NSRange(location: start, length: output.length - start))
            return
        }
        output.append(NSAttributedString(string: "\n", attributes: attributes))
        let range = NSRange(location: start, length: output.length - start)
        let style = paragraphStyle(context: context, marker: marker)
        style.paragraphSpacingBefore = spacingBefore
        applyLineSpacing(headingLevel == nil ? theme.lineSpacing : theme.headingLineSpacing, to: style)
        output.addAttribute(.paragraphStyle, value: style, range: range)
        if context.quoteDepth > 0 { output.addAttribute(.glimmerQuoteDepth, value: context.quoteDepth, range: range) }
        if let headingLevel { output.addAttribute(.accessibilityTextHeadingLevel, value: headingLevel, range: range) }
        stampMarkdown(context: context, hasMarker: marker != nil, range: range, in: output)
    }

    private func appendEmbed(
        _ embed: GlimmerEmbed, source: String, context: Context, marker: NSAttributedString?,
        imageGate: GlimmerImageGate? = nil, to output: NSMutableAttributedString
    ) {
        if let marker { appendTextParagraph([], font: theme.bodyFont, context: context, marker: marker, to: output) }
        let start = output.length
        let attachment = context.reuse?.attachment(for: embed)
            ?? GlimmerBlockAttachment(
                embed: embed, theme: theme, highlighter: highlighter, imageLoader: imageLoader, imageGate: imageGate
            )
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
        if !context.listTightness.isEmpty { output.addAttribute(.glimmerListTightness, value: context.listTightness, range: range) }
        if hasMarker, context.opensList { output.addAttribute(.glimmerListOpens, value: true, range: range) }
    }

    // MARK: - Styles

    func baseAttributes(font: UIFont, context: Context) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: context.quoteDepth > 0 ? theme.secondaryTextColor : theme.textColor]
    }

    /// The space between a list marker and its item's text.
    var markerGap: CGFloat { ceil(theme.bodyFont.pointSize * 0.4) }

    private func paragraphStyle(context: Context, marker: NSAttributedString?) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = theme.lineHeightMultiple
        style.headIndent = context.indent
        if let marker {
            // Numbers share a right edge, like a browser's list: "10." grows to the left, not into the gap.
            let width = visibleWidth(of: marker)
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

    /// A role's additive line spacing, or nothing for `nil`, which keeps `lineHeightMultiple`.
    ///
    /// TextKit 2 puts `lineSpacing` above each of the paragraph's lines, its first line too unless that starts the
    /// text, and none below its last line. Taking the same amount off the space above the paragraph leaves it only
    /// between the paragraph's own lines, so the gaps between blocks (paragraph spacing, a heading's collapsed space
    /// above) stay as they are. At the start of the text TextKit adds none, and ignores the negative space above.
    private func applyLineSpacing(_ spacing: CGFloat?, to style: NSMutableParagraphStyle) {
        guard let spacing else { return }
        style.lineHeightMultiple = 1
        style.lineSpacing = spacing
        style.paragraphSpacingBefore -= spacing
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

    /// A marker's drawn width: without its trailing tab, and without text only VoiceOver reads.
    private func visibleWidth(of marker: NSAttributedString) -> CGFloat {
        let visible = NSMutableAttributedString(attributedString: marker.attributedSubstring(from: NSRange(location: 0, length: marker.length - 1)))
        visible.enumerateAttribute(.glimmerSpokenOnly, in: NSRange(location: 0, length: visible.length), options: .reverse) { value, range, _ in
            if value as? Bool == true { visible.deleteCharacters(in: range) }
        }
        return visible.size().width
    }

    /// The width of the widest `digits`-digit number marker in the body font, such as "88.".
    func reservedNumberWidth(digits: Int) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: theme.bodyFont]
        let widestDigit = (0...9).map { NSAttributedString(string: "\($0)", attributes: attributes).size().width }.max() ?? 0
        return widestDigit * CGFloat(digits) + NSAttributedString(string: ".", attributes: attributes).size().width
    }

    /// Bullet markers by list depth, repeating after the last.
    static let bullets = ["•", "◦", "▪︎"]

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
            // VoiceOver builds a line's label from its text and skips the image, so the state is text: tiny and clear.
            marker.append(NSAttributedString(string: checkbox ? GlimmerStrings.checked : GlimmerStrings.unchecked, attributes: [
                .font: theme.bodyFont.withSize(0.01), .foregroundColor: UIColor.clear, .glimmerSpokenOnly: true,
            ]))
            source = checkbox ? "- [x] " : "- [ ] "
        } else {
            switch kind {
            case .bullet:
                let bullets = Self.bullets
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

    /// The image of a paragraph that holds nothing else, with the policy's decision for it. Nil when the paragraph
    /// holds more, or the image's URL does not parse.
    private func standaloneImage(
        _ inlines: [GlimmerInline]
    ) -> (url: URL, alt: String, title: String?, decision: GlimmerImageDecision)? {
        let meaningful = inlines.filter { inline in
            switch inline {
            case .softBreak, .lineBreak: false
            case .text(let text): !text.trimmingCharacters(in: .whitespaces).isEmpty
            default: true
            }
        }
        guard meaningful.count == 1, case .image(let source, let title, let alt) = meaningful[0],
              let url = URL(string: source) else {
            return nil
        }
        return (url, alt, title, imageDecision(url: url, alt: alt, title: title, origin: .markdown))
    }

    /// Whether everything from `location` on is spaces, tabs and line breaks.
    private static func isBlank(_ text: NSAttributedString, from location: Int) -> Bool {
        (text.string as NSString).substring(from: location).allSatisfy { $0 == " " || $0 == "\t" || $0 == "\u{2028}" }
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

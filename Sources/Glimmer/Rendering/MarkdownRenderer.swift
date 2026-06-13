import SwiftUI
import os

public struct MarkdownRenderer {
    // State to hold footnote definitions found during rendering
    private var footnoteDefinitions: [String: [MarkdownParser.BlockNode]] = [:]
    // Reused common fragments
    private static let newline = AttributedString("\n")
    private static let doubleNewline = AttributedString("\n\n")
    private static let tableSep = AttributedString(" | ")
    // Attribute caches for this render session (computed from configuration)
    private var cachedMentionAttrs: AttributeContainer?
    private var cachedIssueAttrs: AttributeContainer?
    private var cachedRepoAttrs: AttributeContainer?
    private var cachedPRAttrs: AttributeContainer?
    private var cachedCommitAttrs: AttributeContainer?
    private var cachedBlockquoteAttrs: AttributeContainer?
    private var cachedTableHeaderAttrs: AttributeContainer?
    private var cachedCodeInlineAttrs: AttributeContainer?

    // MARK: - Render Cache
    private final class RCNode {
        let key: String
        var value: AttributedString
        weak var prev: RCNode?
        var next: RCNode?

        init(key: String, value: AttributedString) {
            self.key = key
            self.value = value
        }
    }

    private struct RCState {
        var dict: [String: RCNode] = [:]
        var head: RCNode?
        var tail: RCNode?
    }

    private static let renderCache = OSAllocatedUnfairLock(initialState: RCState())
    private static let stats = OSAllocatedUnfairLock(initialState: (hits: 0, misses: 0))

    private static func rcAppendToTail(_ state: inout RCState, _ node: RCNode) {
        node.prev = state.tail
        node.next = nil
        if let tail = state.tail {
            tail.next = node
        } else {
            state.head = node
        }
        state.tail = node
    }

    private static func rcDetach(_ state: inout RCState, _ node: RCNode) {
        let prev = node.prev
        let next = node.next
        if let prev = prev {
            prev.next = next
        } else {
            state.head = next
        }
        if let next = next {
            next.prev = prev
        } else {
            state.tail = prev
        }
        node.prev = nil
        node.next = nil
    }

    private static func rcMoveToTail(_ state: inout RCState, _ node: RCNode) {
        guard state.tail !== node else { return }
        rcDetach(&state, node)
        rcAppendToTail(&state, node)
    }

    public mutating func render(blocks: [MarkdownParser.BlockNode], configuration: MarkdownConfiguration) -> AttributedString {
        beginSession(configuration: configuration)
        var result = AttributedString()

        // First pass: render main content and collect footnote definitions
        let mainContent = renderBlocks(blocks, configuration: configuration)
        result += mainContent

        // Render footnotes if any were found
        if !footnoteDefinitions.isEmpty {
            result += renderFootnoteSection(configuration: configuration)
        }

        return result
    }

    /// Primes the per-session attribute caches so inline rendering can be used
    /// standalone (outside `render(blocks:)`), e.g. by the reveal flattener.
    public mutating func beginSession(configuration: MarkdownConfiguration) {
        sessionStyleKey = styleKey(configuration)
        cachedMentionAttrs = mentionAttributes(configuration: configuration)
        cachedIssueAttrs = issueAttributes(configuration: configuration)
        cachedRepoAttrs = repoAttributes(configuration: configuration)
        cachedPRAttrs = prAttributes(configuration: configuration)
        cachedCommitAttrs = commitAttributes(configuration: configuration)
        cachedBlockquoteAttrs = blockquoteAttributes(configuration: configuration)
        cachedTableHeaderAttrs = tableHeaderAttributes(configuration: configuration)
        cachedCodeInlineAttrs = codeInlineAttributes(configuration: configuration)
    }
    
    private mutating func renderBlocks(_ blocks: [MarkdownParser.BlockNode], configuration: MarkdownConfiguration) -> AttributedString {
        var result = AttributedString()
        for (index, block) in blocks.enumerated() {
            if case .footnoteDefinition(let label, let children) = block {
                footnoteDefinitions[label] = children
                continue // Skip rendering them inline
            }
            
            if index > 0 { result.append(Self.doubleNewline) }
            let rendered = renderBlock(block, configuration: configuration)
            result.append(rendered)
        }
        return result
    }

    private var sessionStyleKey: String?

    private mutating func renderBlock(_ block: MarkdownParser.BlockNode, configuration: MarkdownConfiguration) -> AttributedString {
        if configuration.enableRenderCaching, let key = renderCacheKey(for: block, styleKey: sessionStyleKey ?? styleKey(configuration)) {
            if let cached = Self.renderCache.withLock({ state -> AttributedString? in
                guard let node = state.dict[key] else { return nil }
                Self.rcMoveToTail(&state, node)
                return node.value
            }) {
                Self.stats.withLock { $0.hits += 1 }
                return cached
            }
            let rendered = renderBlockUncached(block, configuration: configuration)
            Self.renderCache.withLock { state in
                if let existing = state.dict[key] {
                    existing.value = rendered
                    Self.rcMoveToTail(&state, existing)
                } else {
                    let node = RCNode(key: key, value: rendered)
                    state.dict[key] = node
                    Self.rcAppendToTail(&state, node)
                }

                let limit = max(1, configuration.maxRenderCacheEntries)
                while state.dict.count > limit, let evict = state.head {
                    Self.rcDetach(&state, evict)
                    state.dict.removeValue(forKey: evict.key)
                }
            }
            Self.stats.withLock { $0.misses += 1 }
            return rendered
        } else {
            return renderBlockUncached(block, configuration: configuration)
        }
    }

    // Actual rendering logic formerly in renderBlock
    private mutating func renderBlockUncached(_ block: MarkdownParser.BlockNode, configuration: MarkdownConfiguration) -> AttributedString {
        switch block {
        case .heading(let level, let children, _):
            return renderHeading(level: level, children: children, configuration: configuration)
            
        case .paragraph(let children):
            return renderInlines(children, configuration: configuration)
            
        case .blockquote(let children):
            var aggregated = AttributedString()
            for child in children {
                let childRendered = renderBlock(child, configuration: configuration)
                aggregated.append(childRendered)
            }
            if let attrs = cachedBlockquoteAttrs { aggregated.mergeAttributes(attrs) }
            return aggregated
            
        case .codeBlock(_, let content):
            var code = AttributedString(content)
            code.font = configuration.codeFont
            code.backgroundColor = configuration.codeBlockTheme.background
            return code
            
        case .list(let ordered, _, let items):
            return renderList(ordered: ordered, items: items, depth: 0, configuration: configuration)
            
        case .taskList(let items):
            return renderTaskList(items, configuration: configuration)
            
        case .table(let header, let rows):
            return renderTable(header: header, rows: rows, configuration: configuration)
            
        case .horizontalRule:
            return AttributedString("―――――――――――――――――――――――――――――――")
            
        case .html(let content):
            return AttributedString(content)
            
        case .footnoteDefinition:
            // This is handled in the first pass, so we render nothing here.
            return AttributedString()
        }
    }

    // MARK: - Cache Key Helpers
    private func renderCacheKey(for block: MarkdownParser.BlockNode, styleKey: String) -> String? {
        // Only cache leaf-like blocks where the output is localized and stable
        switch block {
        case .heading(let level, let children, let id):
            return "h|\(level)|\(inlineSemanticHash(children))|\(id ?? "")|\(styleKey)"
        case .paragraph(let children):
            return "p|\(inlineSemanticHash(children))|\(styleKey)"
        case .codeBlock(let language, let content):
            var hasher = Hasher(); content.hash(into: &hasher)
            let h = hasher.finalize()
            return "c|\(language ?? "")|\(h)|\(styleKey)"
        case .table(let header, let rows):
            // Preserve inline semantics (including links and formatting), not just visible text.
            return "t|\(tableSemanticHash(header: header, rows: rows))|\(styleKey)"
        case .horizontalRule:
            return "hr|\(styleKey)"
        default:
            // Skip caching for composite blocks like list/blockquote where partial invalidation is trickier
            return nil
        }
    }

    private func styleKey(_ configuration: MarkdownConfiguration) -> String {
        // Compact style fingerprint; sufficient for cache segmentation
        var hasher = Hasher()
        configuration.baseFont.hash(into: &hasher)
        configuration.codeFont.hash(into: &hasher)
        configuration.headingFonts.hash(into: &hasher)
        configuration.textColor.hash(into: &hasher)
        configuration.linkColor.hash(into: &hasher)
        configuration.mentionColor.hash(into: &hasher)
        configuration.issueColor.hash(into: &hasher)
        configuration.codeBackgroundColor.hash(into: &hasher)
        configuration.blockquoteColor.hash(into: &hasher)
        configuration.codeBlockTheme.hash(into: &hasher)
        configuration.markdownExtensions.hash(into: &hasher)
        return String(hasher.finalize())
    }

    private func inlineSemanticHash(_ nodes: [MarkdownParser.InlineNode]) -> Int {
        var hasher = Hasher()
        hashInlines(nodes, into: &hasher)
        return hasher.finalize()
    }

    private func tableSemanticHash(header: [MarkdownParser.TableCell], rows: [[MarkdownParser.TableCell]]) -> Int {
        var hasher = Hasher()
        hasher.combine(header.count)
        for cell in header {
            hashTableCell(cell, into: &hasher)
        }
        hasher.combine(rows.count)
        for row in rows {
            hasher.combine(row.count)
            for cell in row {
                hashTableCell(cell, into: &hasher)
            }
        }
        return hasher.finalize()
    }

    private func hashTableCell(_ cell: MarkdownParser.TableCell, into hasher: inout Hasher) {
        hasher.combine(tableAlignmentCode(cell.alignment))
        hashInlines(cell.content, into: &hasher)
    }

    private func tableAlignmentCode(_ alignment: MarkdownParser.TableAlignment) -> Int {
        switch alignment {
        case .left: return 0
        case .center: return 1
        case .right: return 2
        case .none: return 3
        }
    }

    private func autolinkTypeCode(_ type: MarkdownParser.AutolinkType) -> Int {
        switch type {
        case .url: return 0
        case .www: return 1
        case .email: return 2
        }
    }

    private func hashInlines(_ nodes: [MarkdownParser.InlineNode], into hasher: inout Hasher) {
        hasher.combine(nodes.count)
        for n in nodes {
            switch n {
            case .text(let text):
                hasher.combine(0)
                hasher.combine(text)
            case .emphasis(let children):
                hasher.combine(1)
                hashInlines(children, into: &hasher)
            case .strong(let children):
                hasher.combine(2)
                hashInlines(children, into: &hasher)
            case .strikethrough(let children):
                hasher.combine(3)
                hashInlines(children, into: &hasher)
            case .code(let code):
                hasher.combine(4)
                hasher.combine(code)
            case .link(let url, let title, let children):
                hasher.combine(5)
                hasher.combine(url.absoluteString)
                hasher.combine(title ?? "")
                hashInlines(children, into: &hasher)
            case .image(let url, let alt, let title):
                hasher.combine(6)
                hasher.combine(url.absoluteString)
                hasher.combine(alt)
                hasher.combine(title ?? "")
            case .autolink(let url, let type, let originalText):
                hasher.combine(7)
                hasher.combine(url.absoluteString)
                hasher.combine(autolinkTypeCode(type))
                hasher.combine(originalText)
            case .mention(let username):
                hasher.combine(8)
                hasher.combine(username)
            case .issueReference(let number):
                hasher.combine(9)
                hasher.combine(number)
            case .commitSHA(let sha, let short):
                hasher.combine(10)
                hasher.combine(sha)
                hasher.combine(short)
            case .repositoryReference(let owner, let repo):
                hasher.combine(11)
                hasher.combine(owner)
                hasher.combine(repo)
            case .pullRequestReference(let owner, let repo, let number):
                hasher.combine(12)
                hasher.combine(owner)
                hasher.combine(repo)
                hasher.combine(number)
            case .lineBreak:
                hasher.combine(13)
            case .softBreak:
                hasher.combine(14)
            case .html(let html):
                hasher.combine(15)
                hasher.combine(html)
            case .footnoteReference(let label):
                hasher.combine(16)
                hasher.combine(label)
            case .extensionInline(let node):
                hasher.combine(17)
                hasher.combine(node)
            }
        }
    }

    // MARK: - Public Cache Controls
    public static func clearRenderCache() {
        renderCache.withLock { state in
            state.dict.removeAll()
            state.head = nil
            state.tail = nil
        }
        stats.withLock { $0.hits = 0; $0.misses = 0 }
    }

    public static func getRenderCacheStats() -> (hits: Int, misses: Int) {
        return stats.withLock { ($0.hits, $0.misses) }
    }
    
    private func renderHeading(level: Int, children: [MarkdownParser.InlineNode], configuration: MarkdownConfiguration) -> AttributedString {
        let headingFont = level - 1 < configuration.headingFonts.count ? configuration.headingFonts[level - 1] : .headline
        var heading = renderInlines(children, configuration: configuration, baseFont: headingFont)
        heading.mergeAttributes(headingAttributes(font: headingFont))
        return heading
    }

    private struct InlineRenderContext {
        let baseFont: Font?
        let forcedFont: Font?
        let isStrikethrough: Bool

        func withEmphasis() -> InlineRenderContext {
            guard forcedFont == nil else { return self }
            return InlineRenderContext(
                baseFont: baseFont,
                forcedFont: (baseFont ?? .body).italic(),
                isStrikethrough: isStrikethrough
            )
        }

        func withStrong() -> InlineRenderContext {
            guard forcedFont == nil else { return self }
            return InlineRenderContext(
                baseFont: baseFont,
                forcedFont: (baseFont ?? .body).bold(),
                isStrikethrough: isStrikethrough
            )
        }

        func withStrikethrough() -> InlineRenderContext {
            InlineRenderContext(
                baseFont: baseFont,
                forcedFont: forcedFont ?? baseFont,
                isStrikethrough: true
            )
        }
    }

    public func renderInlines(_ nodes: [MarkdownParser.InlineNode], configuration: MarkdownConfiguration, baseFont: Font? = nil) -> AttributedString {
        var result = AttributedString()
        let context = InlineRenderContext(baseFont: baseFont, forcedFont: nil, isStrikethrough: false)
        appendInlines(nodes, to: &result, configuration: configuration, context: context)
        return result
    }

    private func appendInlines(
        _ nodes: [MarkdownParser.InlineNode],
        to result: inout AttributedString,
        configuration: MarkdownConfiguration,
        context: InlineRenderContext
    ) {
        for node in nodes {
            appendInline(node, to: &result, configuration: configuration, context: context)
        }
    }

    private func appendInline(
        _ node: MarkdownParser.InlineNode,
        to result: inout AttributedString,
        configuration: MarkdownConfiguration,
        context: InlineRenderContext
    ) {
        switch node {
        case .text(let text):
            var value = AttributedString(text)
            if let forcedFont = context.forcedFont {
                value.font = forcedFont
            } else if let baseFont = context.baseFont {
                value.font = baseFont
            }
            value.foregroundColor = configuration.textColor
            if context.isStrikethrough {
                value.strikethroughStyle = .single
            }
            result.append(value)

        case .emphasis(let children):
            appendInlines(children, to: &result, configuration: configuration, context: context.withEmphasis())

        case .strong(let children):
            appendInlines(children, to: &result, configuration: configuration, context: context.withStrong())

        case .strikethrough(let children):
            appendInlines(children, to: &result, configuration: configuration, context: context.withStrikethrough())

        case .code(let code):
            var codeText = AttributedString(code)
            if let attrs = cachedCodeInlineAttrs { codeText.mergeAttributes(attrs) }
            applyInlineContext(&codeText, context: context)
            result.append(codeText)

        case .link(let url, _, let children):
            var content = AttributedString()
            appendInlines(children, to: &content, configuration: configuration, context: context)
            var linked = styledLink(content, url: url, configuration: configuration)
            applyInlineContext(&linked, context: context)
            result.append(linked)

        case .image(let url, let alt, _):
            var image = AttributedString("[Image: \(alt.isEmpty ? url.absoluteString : alt)]")
            applyInlineContext(&image, context: context)
            result.append(image)

        case .autolink(let url, _, let originalText):
            var autolink = styledLink(AttributedString(originalText), url: url, configuration: configuration)
            applyInlineContext(&autolink, context: context)
            result.append(autolink)

        case .mention(let username):
            var mention = AttributedString("@\(username)")
            if let attrs = cachedMentionAttrs { mention.mergeAttributes(attrs) }
            applyInlineContext(&mention, context: context)
            result.append(mention)

        case .issueReference(let number):
            var issue = AttributedString("#\(number)")
            if let attrs = cachedIssueAttrs { issue.mergeAttributes(attrs) }
            applyInlineContext(&issue, context: context)
            result.append(issue)

        case .commitSHA(_, let short):
            var commit = AttributedString(short)
            if let attrs = cachedCommitAttrs { commit.mergeAttributes(attrs) }
            applyInlineContext(&commit, context: context)
            result.append(commit)

        case .repositoryReference(let owner, let repo):
            var repository = AttributedString("\(owner)/\(repo)")
            if let attrs = cachedRepoAttrs { repository.mergeAttributes(attrs) }
            applyInlineContext(&repository, context: context)
            result.append(repository)

        case .pullRequestReference(let owner, let repo, let number):
            var pullRequest = AttributedString("\(owner)/\(repo)#\(number)")
            if let attrs = cachedPRAttrs { pullRequest.mergeAttributes(attrs) }
            applyInlineContext(&pullRequest, context: context)
            result.append(pullRequest)

        case .lineBreak, .softBreak:
            var lineBreak = AttributedString("\n")
            applyInlineContext(&lineBreak, context: context)
            result.append(lineBreak)

        case .html(let tag):
            if tag.lowercased() == "<br>" || tag.lowercased() == "<br/>" || tag.lowercased() == "<br />" {
                var lineBreak = AttributedString("\n")
                applyInlineContext(&lineBreak, context: context)
                result.append(lineBreak)
            } else {
                var html = AttributedString(tag)
                applyInlineContext(&html, context: context)
                result.append(html)
            }

        case .footnoteReference(let label):
            let displayLabel = label.starts(with: "inline-") ? "*" : label
            var ref = AttributedString("[\(displayLabel)]")
            ref.mergeAttributes(footnoteRefAttributes(label: label, configuration: configuration))
            applyInlineContext(&ref, context: context)
            result.append(ref)

        case .extensionInline(let node):
            if var rendered = renderExtensionInline(node, configuration: configuration) {
                applyInlineContext(&rendered, context: context)
                result.append(rendered)
            } else {
                var literal = AttributedString(node.literal)
                if let forcedFont = context.forcedFont {
                    literal.font = forcedFont
                } else if let baseFont = context.baseFont {
                    literal.font = baseFont
                }
                literal.foregroundColor = configuration.textColor
                if context.isStrikethrough {
                    literal.strikethroughStyle = .single
                }
                result.append(literal)
            }
        }
    }

    private func renderExtensionInline(
        _ node: MarkdownParser.ExtensionNode,
        configuration: MarkdownConfiguration
    ) -> AttributedString? {
        for markdownExtension in configuration.markdownExtensions where markdownExtension.id == node.namespace {
            if let rendered = markdownExtension.renderInline(node) {
                return rendered
            }
        }
        return nil
    }

    private func applyInlineContext(_ value: inout AttributedString, context: InlineRenderContext) {
        if let forcedFont = context.forcedFont {
            value.font = forcedFont
        }
        if context.isStrikethrough {
            value.strikethroughStyle = .single
        }
    }

    // MARK: - Style Helpers
    private func styledLink(_ content: AttributedString, url: URL, configuration: MarkdownConfiguration) -> AttributedString {
        var link = content
        // Merge a prebuilt attribute container instead of setting fields separately
        let attrs = linkAttributes(url: url, configuration: configuration)
        link.mergeAttributes(attrs)
        return link
    }

    private func linkAttributes(url: URL, configuration: MarkdownConfiguration) -> AttributeContainer {
        var container = AttributeContainer()
        container.link = url
        container.foregroundColor = configuration.linkColor
        container.underlineStyle = .single
        return container
    }

    private func mentionAttributes(configuration: MarkdownConfiguration) -> AttributeContainer {
        var container = AttributeContainer()
        container.foregroundColor = configuration.mentionColor
        container.font = .body.bold()
        return container
    }

    private func codeInlineAttributes(configuration: MarkdownConfiguration) -> AttributeContainer {
        var container = AttributeContainer()
        container.font = configuration.codeFont
        container.backgroundColor = configuration.codeBackgroundColor
        return container
    }

    private func issueAttributes(configuration: MarkdownConfiguration) -> AttributeContainer {
        var container = AttributeContainer()
        container.foregroundColor = configuration.issueColor
        container.font = .body.bold()
        return container
    }

    private func repoAttributes(configuration: MarkdownConfiguration) -> AttributeContainer {
        var container = AttributeContainer()
        container.foregroundColor = configuration.linkColor
        container.font = .body.bold()
        return container
    }

    private func prAttributes(configuration: MarkdownConfiguration) -> AttributeContainer {
        var container = AttributeContainer()
        container.foregroundColor = configuration.linkColor
        container.font = .body.bold()
        return container
    }

    private func commitAttributes(configuration: MarkdownConfiguration) -> AttributeContainer {
        var container = AttributeContainer()
        container.foregroundColor = configuration.linkColor
        container.font = .system(.body, design: .monospaced)
        return container
    }

    private func blockquoteAttributes(configuration: MarkdownConfiguration) -> AttributeContainer {
        var container = AttributeContainer()
        container.foregroundColor = configuration.blockquoteColor
        return container
    }

    private func headingAttributes(font: Font) -> AttributeContainer {
        var container = AttributeContainer()
        container.font = font
        return container
    }

    private func tableHeaderAttributes(configuration: MarkdownConfiguration) -> AttributeContainer {
        var container = AttributeContainer()
        container.font = .body.bold()
        return container
    }

    private func footnoteRefAttributes(label: String, configuration: MarkdownConfiguration) -> AttributeContainer {
        var container = AttributeContainer()
        container.font = .system(.caption2)
        container.baselineOffset = 6
        container.link = URL(string: "#footnote-\(label)")
        container.foregroundColor = configuration.linkColor
        return container
    }
    
    private mutating func renderFootnoteSection(configuration: MarkdownConfiguration) -> AttributedString {
        var result = AttributedString("\n\n---\n\n")
        
        let sortedFootnotes = footnoteDefinitions.keys.sorted()
        
        for label in sortedFootnotes {
            guard let content = footnoteDefinitions[label] else { continue }
            
            // Define the anchor for the link
            var footnote = AttributedString()
            var anchor = AttributedString("^")
            anchor.link = URL(string: "#footnote-ref-\(label)")
            footnote.append(anchor)
            var labelStr = AttributedString(" \(label): ")
            labelStr.font = .body.bold()
            footnote.append(labelStr)
            var contentStr = renderBlocks(content, configuration: configuration)
            contentStr.font = .footnote
            footnote.append(contentStr)
            result.append(footnote)
            result.append(AttributedString("\n\n"))
        }
        
        return result
    }
    
    private mutating func renderList(ordered: Bool, items: [MarkdownParser.ListItem], depth: Int = 0, configuration: MarkdownConfiguration) -> AttributedString {
        var result = AttributedString()
        
        // Different bullet styles for different nesting levels
        let unorderedMarkers = ["• ", "◦ ", "▪ ", "▫ "]
        
        for (index, item) in items.enumerated() {
            if index > 0 { result += Self.newline }
            
            // Add indentation based on depth
            let indentation = String(repeating: "    ", count: depth)
            result += AttributedString(indentation)
            
            // Choose appropriate marker based on depth
            let marker: String
            if ordered {
                switch depth % 4 {
                case 0:
                    marker = "\(index + 1). "
                case 1:
                    marker = "\(Character(UnicodeScalar(97 + index)!)). " // a. b. c.
                case 2:
                    marker = "\(ListFormatting.romanNumeral(index + 1)). " // i. ii. iii.
                default:
                    marker = "\(index + 1)) "
                }
            } else {
                marker = unorderedMarkers[min(depth, unorderedMarkers.count - 1)]
            }
            result += AttributedString(marker)
            
            // Render item content
            var isFirstBlock = true
            for block in item.content {
                switch block {
                case .paragraph(let children):
                    // For the first paragraph, render inline with the marker
                    if isFirstBlock {
                        result += renderInlines(children, configuration: configuration)
                    } else {
                        // For subsequent paragraphs, add proper indentation
                        result += Self.newline
                        result += AttributedString(String(repeating: "    ", count: depth + 1))
                        result += renderInlines(children, configuration: configuration)
                    }
                    
                case .list(let nestedOrdered, _, let nestedItems):
                    // Always put nested lists on a new line
                    result += Self.newline
                    result += renderList(ordered: nestedOrdered, items: nestedItems, depth: depth + 1, configuration: configuration)
                    
                default:
                    // For other blocks, add newline and indentation
                    if !isFirstBlock {
                        result += Self.newline
                        result += AttributedString(String(repeating: "    ", count: depth + 1))
                    }
                    result += renderBlock(block, configuration: configuration)
                }
                
                isFirstBlock = false
            }
        }
        
        return result
    }
    
    private func renderTaskList(_ items: [MarkdownParser.TaskListItem], configuration: MarkdownConfiguration) -> AttributedString {
        var result = AttributedString()
        for (index, item) in items.enumerated() {
            var line = AttributedString()
            if index > 0 { line.append(Self.newline) }
            let checkbox = item.isChecked ? "☑ " : "☐ "
            line.append(AttributedString(checkbox))
            let content = renderInlines(item.content, configuration: configuration)
            line.append(content)
            result.append(line)
        }
        return result
    }
    
    private func renderTable(header: [MarkdownParser.TableCell], rows: [[MarkdownParser.TableCell]], configuration: MarkdownConfiguration) -> AttributedString {
        var result = AttributedString()
        // Header line
        var headerLine = AttributedString()
        for (index, cell) in header.enumerated() {
            if index > 0 { headerLine.append(Self.tableSep) }
            var cellContent = renderInlines(cell.content, configuration: configuration)
            if let attrs = cachedTableHeaderAttrs { cellContent.mergeAttributes(attrs) }
            headerLine.append(cellContent)
        }
        headerLine.append(Self.newline)
        result.append(headerLine)
        // Rows
        for row in rows {
            var rowLine = AttributedString()
            for (index, cell) in row.enumerated() {
                if index > 0 { rowLine.append(Self.tableSep) }
                let cellContent = renderInlines(cell.content, configuration: configuration)
                rowLine.append(cellContent)
            }
            rowLine.append(Self.newline)
            result.append(rowLine)
        }
        return result
    }
}

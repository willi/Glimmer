import SwiftUI
import os

public struct MarkdownRenderer {
    // State to hold footnote definitions found during rendering
    private var footnoteDefinitions: [String: [MarkdownParser.BlockNode]] = [:]
    // Reused common fragments
    private static let newline = AttributedString("\n")
    private static let doubleNewline = AttributedString("\n\n")
    private static let tableSep = AttributedString(" | ")
    private static let unorderedListMarkers = ["• ", "◦ ", "▪ ", "▫ "]
    private static let documentRenderCacheMinimumBlockCount = 32
    private static let maxDocumentRenderCacheEntries = 8
    // Attribute caches for this render session (computed from configuration)
    private var cachedMentionAttrs: AttributeContainer?
    private var cachedIssueAttrs: AttributeContainer?
    private var cachedRepoAttrs: AttributeContainer?
    private var cachedPRAttrs: AttributeContainer?
    private var cachedCommitAttrs: AttributeContainer?
    private var cachedBlockquoteAttrs: AttributeContainer?
    private var cachedTableHeaderAttrs: AttributeContainer?
    private var cachedCodeInlineAttrs: AttributeContainer?
    private var suppressNestedRenderCaching = false

    /// Reveal-only: when true, inline images with `alt == "avatar"` render as a
    /// single avatar-marker character (`AttributedString.glimmerAvatarMarker`)
    /// instead of `[Image: avatar]` text, and inline rendering bypasses the
    /// shared inline cache so markers never leak into export / settled output.
    /// Defaults to false; only the reveal flattener's private renderer sets it.
    var emitAvatarMarkers = false

    // MARK: - Render Cache
    private final class RCNode: @unchecked Sendable {
        let key: String
        var value: AttributedString
        weak var prev: RCNode?
        var next: RCNode?

        init(key: String, value: AttributedString) {
            self.key = key
            self.value = value
        }
    }

    private struct RCState: @unchecked Sendable {
        var dict: [String: RCNode] = [:]
        var head: RCNode?
        var tail: RCNode?
    }

    private static let renderCache = OSAllocatedUnfairLock(initialState: RCState())
    private static let documentRenderCache = OSAllocatedUnfairLock(initialState: RCState())
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
        footnoteDefinitions.removeAll(keepingCapacity: true)

        if configuration.enableRenderCaching,
           blocks.count >= Self.documentRenderCacheMinimumBlockCount {
            let currentStyleKey = sessionStyleKey ?? styleKey(configuration)
            let key = documentRenderCacheKey(for: blocks, styleKey: currentStyleKey)
            if let cached = Self.documentRenderCache.withLock({ state -> AttributedString? in
                guard let node = state.dict[key] else { return nil }
                Self.rcMoveToTail(&state, node)
                return node.value
            }) {
                Self.stats.withLock { $0.hits += 1 }
                return cached
            }

            let previousSuppression = suppressNestedRenderCaching
            suppressNestedRenderCaching = true
            let rendered = renderDocumentUncached(blocks: blocks, configuration: configuration)
            suppressNestedRenderCaching = previousSuppression
            Self.documentRenderCache.withLock { state in
                if let existing = state.dict[key] {
                    existing.value = rendered
                    Self.rcMoveToTail(&state, existing)
                } else {
                    let node = RCNode(key: key, value: rendered)
                    state.dict[key] = node
                    Self.rcAppendToTail(&state, node)
                }

                while state.dict.count > Self.maxDocumentRenderCacheEntries, let evict = state.head {
                    Self.rcDetach(&state, evict)
                    state.dict.removeValue(forKey: evict.key)
                }
            }
            Self.stats.withLock { $0.misses += 1 }
            return rendered
        }

        return renderDocumentUncached(blocks: blocks, configuration: configuration)
    }

    private mutating func renderDocumentUncached(
        blocks: [MarkdownParser.BlockNode],
        configuration: MarkdownConfiguration
    ) -> AttributedString {
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
        if !suppressNestedRenderCaching,
           configuration.enableRenderCaching,
           shouldCacheRenderedBlock(block),
           let key = renderCacheKey(for: block, styleKey: sessionStyleKey ?? styleKey(configuration)) {
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
        case .blockquote(let children):
            return "bq|\(blocksSemanticHash(children))|\(styleKey)"
        case .list(let ordered, let tight, let items):
            return "l|\(ordered)|\(tight)|\(listItemsSemanticHash(items))|\(styleKey)"
        case .taskList(let items):
            return "tl|\(taskListSemanticHash(items))|\(styleKey)"
        case .horizontalRule:
            return "hr|\(styleKey)"
        default:
            return nil
        }
    }

    private func documentRenderCacheKey(for blocks: [MarkdownParser.BlockNode], styleKey: String) -> String {
        "doc|\(blocks.count)|\(blocksSemanticHash(blocks))|\(styleKey)"
    }

    private func shouldCacheRenderedBlock(_ block: MarkdownParser.BlockNode) -> Bool {
        switch block {
        case .heading, .paragraph, .codeBlock, .table, .blockquote, .list, .taskList:
            return true
        case .horizontalRule:
            return false
        case .html, .footnoteDefinition:
            return false
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

    private func blocksSemanticHash(_ blocks: [MarkdownParser.BlockNode]) -> Int {
        var hasher = Hasher()
        hashBlocks(blocks, into: &hasher)
        return hasher.finalize()
    }

    private func listItemsSemanticHash(_ items: [MarkdownParser.ListItem]) -> Int {
        var hasher = Hasher()
        hasher.combine(items.count)
        for item in items {
            hashListItem(item, into: &hasher)
        }
        return hasher.finalize()
    }

    private func taskListSemanticHash(_ items: [MarkdownParser.TaskListItem]) -> Int {
        var hasher = Hasher()
        hasher.combine(items.count)
        for item in items {
            hasher.combine(item.isChecked)
            hashInlines(item.content, into: &hasher)
        }
        return hasher.finalize()
    }

    private func hashTableCell(_ cell: MarkdownParser.TableCell, into hasher: inout Hasher) {
        hasher.combine(tableAlignmentCode(cell.alignment))
        hashInlines(cell.content, into: &hasher)
    }

    private func hashBlocks(_ blocks: [MarkdownParser.BlockNode], into hasher: inout Hasher) {
        hasher.combine(blocks.count)
        for block in blocks {
            hashBlock(block, into: &hasher)
        }
    }

    private func hashBlock(_ block: MarkdownParser.BlockNode, into hasher: inout Hasher) {
        switch block {
        case .heading(let level, let children, let id):
            hasher.combine(0)
            hasher.combine(level)
            hashInlines(children, into: &hasher)
            hasher.combine(id ?? "")
        case .paragraph(let children):
            hasher.combine(1)
            hashInlines(children, into: &hasher)
        case .blockquote(let children):
            hasher.combine(2)
            hashBlocks(children, into: &hasher)
        case .codeBlock(let language, let content):
            hasher.combine(3)
            hasher.combine(language ?? "")
            hasher.combine(content)
        case .list(let ordered, let tight, let items):
            hasher.combine(4)
            hasher.combine(ordered)
            hasher.combine(tight)
            hasher.combine(items.count)
            for item in items {
                hashListItem(item, into: &hasher)
            }
        case .taskList(let items):
            hasher.combine(5)
            hasher.combine(items.count)
            for item in items {
                hasher.combine(item.isChecked)
                hashInlines(item.content, into: &hasher)
            }
        case .table(let header, let rows):
            hasher.combine(6)
            hasher.combine(tableSemanticHash(header: header, rows: rows))
        case .horizontalRule:
            hasher.combine(7)
        case .html(let content):
            hasher.combine(8)
            hasher.combine(content)
        case .footnoteDefinition(let label, let children):
            hasher.combine(9)
            hasher.combine(label)
            hashBlocks(children, into: &hasher)
        }
    }

    private func hashListItem(_ item: MarkdownParser.ListItem, into hasher: inout Hasher) {
        hasher.combine(item.marker)
        hasher.combine(item.isTask)
        hasher.combine(item.isChecked ?? false)
        hasher.combine(item.isChecked == nil)
        hashBlocks(item.content, into: &hasher)
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
        documentRenderCache.withLock { state in
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
        var heading = renderInlines(children, configuration: configuration)
        heading.mergeAttributes(headingAttributes(font: headingFont))
        return heading
    }

    private struct InlineRenderContext {
        let baseFont: Font?
        let forcedFont: Font?
        let isStrikethrough: Bool
        let linkAttributes: AttributeContainer?

        func withEmphasis() -> InlineRenderContext {
            guard forcedFont == nil else { return self }
            return InlineRenderContext(
                baseFont: baseFont,
                forcedFont: (baseFont ?? .body).italic(),
                isStrikethrough: isStrikethrough,
                linkAttributes: linkAttributes
            )
        }

        func withStrong() -> InlineRenderContext {
            guard forcedFont == nil else { return self }
            return InlineRenderContext(
                baseFont: baseFont,
                forcedFont: (baseFont ?? .body).bold(),
                isStrikethrough: isStrikethrough,
                linkAttributes: linkAttributes
            )
        }

        func withStrikethrough() -> InlineRenderContext {
            InlineRenderContext(
                baseFont: baseFont,
                forcedFont: forcedFont ?? baseFont,
                isStrikethrough: true,
                linkAttributes: linkAttributes
            )
        }

        func withLink(_ url: URL, configuration: MarkdownConfiguration) -> InlineRenderContext {
            guard linkAttributes == nil else { return self }
            var container = AttributeContainer()
            container.link = url
            container.foregroundColor = configuration.linkColor
            if configuration.linkUnderline {
                container.underlineStyle = .single
            }
            return InlineRenderContext(
                baseFont: baseFont,
                forcedFont: forcedFont,
                isStrikethrough: isStrikethrough,
                linkAttributes: container
            )
        }
    }

    private enum InlineSegmentStyle {
        case plainText
        case code
        case autolink(URL)
        case mention
        case issue
        case commit
        case repository
        case pullRequest
        case footnote(label: String)
        case inlineContextOnly
    }

    private struct InlineRenderSegment {
        let characterCount: Int
        let style: InlineSegmentStyle
        let context: InlineRenderContext
    }

    public func renderInlines(
        _ nodes: [MarkdownParser.InlineNode],
        configuration: MarkdownConfiguration,
        baseFont: Font? = nil
    ) -> AttributedString {
        guard !emitAvatarMarkers else {
            // Marker output carries a custom attribute and is reveal-only: never
            // read from or write to the shared inline cache.
            return renderInlinesUncached(nodes, configuration: configuration, baseFont: baseFont)
        }

        guard !suppressNestedRenderCaching,
              configuration.enableRenderCaching,
              sessionStyleKey != nil else {
            return renderInlinesUncached(nodes, configuration: configuration, baseFont: baseFont)
        }

        let key = MarkdownInlineAttributedCache.key(
            nodes: nodes,
            configuration: configuration,
            baseFont: baseFont,
            mode: .plain
        )
        if let cached = MarkdownInlineAttributedCache.value(for: key) {
            return cached
        }

        let rendered = renderInlinesUncached(nodes, configuration: configuration, baseFont: baseFont)
        MarkdownInlineAttributedCache.insert(rendered, for: key)
        return rendered
    }

    private func renderInlinesUncached(
        _ nodes: [MarkdownParser.InlineNode],
        configuration: MarkdownConfiguration,
        baseFont: Font? = nil
    ) -> AttributedString {
        if nodes.count == 1,
           case .text(let text) = nodes[0] {
            return renderPlainTextInline(text, configuration: configuration, baseFont: baseFont)
        }

        if let coalesced = renderInlinesCoalesced(nodes, configuration: configuration, baseFont: baseFont) {
            return coalesced
        }

        var result = AttributedString()
        let context = InlineRenderContext(
            baseFont: baseFont,
            forcedFont: nil,
            isStrikethrough: false,
            linkAttributes: nil
        )
        appendInlines(nodes, to: &result, configuration: configuration, context: context)
        return result
    }

    private func renderPlainTextInline(
        _ text: String,
        configuration: MarkdownConfiguration,
        baseFont: Font?
    ) -> AttributedString {
        var value = AttributedString(text)
        if let baseFont {
            value.font = baseFont
        }
        applyPlainTextColor(&value, configuration: configuration)
        return value
    }

    private func renderInlinesCoalesced(
        _ nodes: [MarkdownParser.InlineNode],
        configuration: MarkdownConfiguration,
        baseFont: Font?
    ) -> AttributedString? {
        var text = ""
        var segments: [InlineRenderSegment] = []
        segments.reserveCapacity(nodes.count)

        let context = InlineRenderContext(
            baseFont: baseFont,
            forcedFont: nil,
            isStrikethrough: false,
            linkAttributes: nil
        )
        guard appendInlinesToPlan(
            nodes,
            text: &text,
            segments: &segments,
            configuration: configuration,
            context: context
        ) else {
            return nil
        }

        var result = AttributedString(text)
        var index = result.startIndex
        for segment in segments where segment.characterCount > 0 {
            let next = result.characters.index(index, offsetBy: segment.characterCount)
            let range = index..<next
            applySegment(segment, to: &result, range: range, configuration: configuration)
            index = next
        }
        return result
    }

    private func appendInlinesToPlan(
        _ nodes: [MarkdownParser.InlineNode],
        text: inout String,
        segments: inout [InlineRenderSegment],
        configuration: MarkdownConfiguration,
        context: InlineRenderContext
    ) -> Bool {
        for node in nodes {
            guard appendInlineToPlan(
                node,
                text: &text,
                segments: &segments,
                configuration: configuration,
                context: context
            ) else {
                return false
            }
        }
        return true
    }

    private func appendInlineToPlan(
        _ node: MarkdownParser.InlineNode,
        text: inout String,
        segments: inout [InlineRenderSegment],
        configuration: MarkdownConfiguration,
        context: InlineRenderContext
    ) -> Bool {
        switch node {
        case .text(let value):
            appendTextSegment(value, style: .plainText, context: context, text: &text, segments: &segments)

        case .emphasis(let children):
            return appendInlinesToPlan(
                children,
                text: &text,
                segments: &segments,
                configuration: configuration,
                context: context.withEmphasis()
            )

        case .strong(let children):
            return appendInlinesToPlan(
                children,
                text: &text,
                segments: &segments,
                configuration: configuration,
                context: context.withStrong()
            )

        case .strikethrough(let children):
            return appendInlinesToPlan(
                children,
                text: &text,
                segments: &segments,
                configuration: configuration,
                context: context.withStrikethrough()
            )

        case .code(let code):
            appendTextSegment(code, style: .code, context: context, text: &text, segments: &segments)

        case .link(let url, _, let children):
            return appendInlinesToPlan(
                children,
                text: &text,
                segments: &segments,
                configuration: configuration,
                context: context.withLink(url, configuration: configuration)
            )

        case .image(let url, let alt, _):
            if emitAvatarMarkers, alt.caseInsensitiveCompare("avatar") == .orderedSame {
                // Force the non-coalesced path so the avatar marker can carry its
                // custom attribute (the coalesced planner only handles plain text).
                return false
            }
            appendTextSegment(
                "[Image: \(alt.isEmpty ? url.absoluteString : alt)]",
                style: .inlineContextOnly,
                context: context,
                text: &text,
                segments: &segments
            )

        case .autolink(let url, _, let originalText):
            appendTextSegment(originalText, style: .autolink(url), context: context, text: &text, segments: &segments)

        case .mention(let username):
            appendTextSegment("@\(username)", style: .mention, context: context, text: &text, segments: &segments)

        case .issueReference(let number):
            appendTextSegment("#\(number)", style: .issue, context: context, text: &text, segments: &segments)

        case .commitSHA(_, let short):
            appendTextSegment(short, style: .commit, context: context, text: &text, segments: &segments)

        case .repositoryReference(let owner, let repo):
            appendTextSegment("\(owner)/\(repo)", style: .repository, context: context, text: &text, segments: &segments)

        case .pullRequestReference(let owner, let repo, let number):
            appendTextSegment(
                "\(owner)/\(repo)#\(number)",
                style: .pullRequest,
                context: context,
                text: &text,
                segments: &segments
            )

        case .lineBreak, .softBreak:
            appendTextSegment("\n", style: .inlineContextOnly, context: context, text: &text, segments: &segments)

        case .html(let tag):
            let lowercased = tag.lowercased()
            if lowercased == "<br>" || lowercased == "<br/>" || lowercased == "<br />" {
                appendTextSegment("\n", style: .inlineContextOnly, context: context, text: &text, segments: &segments)
            } else {
                appendTextSegment(tag, style: .inlineContextOnly, context: context, text: &text, segments: &segments)
            }

        case .footnoteReference(let label):
            let displayLabel = label.starts(with: "inline-") ? "*" : label
            appendTextSegment(
                "[\(displayLabel)]",
                style: .footnote(label: label),
                context: context,
                text: &text,
                segments: &segments
            )

        case .extensionInline:
            return false
        }

        return true
    }

    private func appendTextSegment(
        _ value: String,
        style: InlineSegmentStyle,
        context: InlineRenderContext,
        text: inout String,
        segments: inout [InlineRenderSegment]
    ) {
        guard !value.isEmpty else { return }
        text.append(value)
        segments.append(InlineRenderSegment(characterCount: value.count, style: style, context: context))
    }

    private func applySegment(
        _ segment: InlineRenderSegment,
        to result: inout AttributedString,
        range: Range<AttributedString.Index>,
        configuration: MarkdownConfiguration
    ) {
        switch segment.style {
        case .plainText:
            if let forcedFont = segment.context.forcedFont {
                result[range].font = forcedFont
            } else if let baseFont = segment.context.baseFont {
                result[range].font = baseFont
            }
            if configuration.textColor != .primary {
                result[range].foregroundColor = configuration.textColor
            }

        case .code:
            if let attrs = cachedCodeInlineAttrs { result[range].mergeAttributes(attrs) }

        case .autolink(let url):
            result[range].mergeAttributes(linkAttributes(url: url, configuration: configuration))

        case .mention:
            if let attrs = cachedMentionAttrs { result[range].mergeAttributes(attrs) }

        case .issue:
            if let attrs = cachedIssueAttrs { result[range].mergeAttributes(attrs) }

        case .commit:
            if let attrs = cachedCommitAttrs { result[range].mergeAttributes(attrs) }

        case .repository:
            if let attrs = cachedRepoAttrs { result[range].mergeAttributes(attrs) }

        case .pullRequest:
            if let attrs = cachedPRAttrs { result[range].mergeAttributes(attrs) }

        case .footnote(let label):
            result[range].mergeAttributes(footnoteRefAttributes(label: label, configuration: configuration))

        case .inlineContextOnly:
            break
        }

        if let linkAttributes = segment.context.linkAttributes {
            result[range].mergeAttributes(linkAttributes)
        }
        applyInlineContext(to: &result, range: range, context: segment.context)
    }

    private func applyInlineContext(
        to result: inout AttributedString,
        range: Range<AttributedString.Index>,
        context: InlineRenderContext
    ) {
        if let forcedFont = context.forcedFont {
            result[range].font = forcedFont
        }
        if context.isStrikethrough {
            result[range].strikethroughStyle = .single
        }
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
            applyPlainTextColor(&value, configuration: configuration)
            applyLinkContext(&value, context: context, configuration: configuration)
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
            applyLinkContext(&codeText, context: context, configuration: configuration)
            applyInlineContext(&codeText, context: context)
            result.append(codeText)

        case .link(let url, _, let children):
            appendInlines(
                children,
                to: &result,
                configuration: configuration,
                context: context.withLink(url, configuration: configuration)
            )

        case .image(let url, let alt, _):
            if emitAvatarMarkers, alt.caseInsensitiveCompare("avatar") == .orderedSame {
                // Reveal-only: render avatars as a tappable circular avatar view, so
                // emit the marker char carrying the image URL plus the wrapping link
                // (`applyLinkContext` adds `.link`, which keeps the marker its own word
                // and lets the reveal renderer resolve the tap target).
                var marker = AttributedString.glimmerAvatarMarker(imageURL: url, linkURL: nil)
                applyLinkContext(&marker, context: context, configuration: configuration)
                result.append(marker)
            } else {
                var image = AttributedString("[Image: \(alt.isEmpty ? url.absoluteString : alt)]")
                applyLinkContext(&image, context: context, configuration: configuration)
                applyInlineContext(&image, context: context)
                result.append(image)
            }

        case .autolink(let url, _, let originalText):
            var autolink = styledLink(AttributedString(originalText), url: url, configuration: configuration)
            applyLinkContext(&autolink, context: context, configuration: configuration)
            applyInlineContext(&autolink, context: context)
            result.append(autolink)

        case .mention(let username):
            var mention = AttributedString("@\(username)")
            if let attrs = cachedMentionAttrs { mention.mergeAttributes(attrs) }
            applyLinkContext(&mention, context: context, configuration: configuration)
            applyInlineContext(&mention, context: context)
            result.append(mention)

        case .issueReference(let number):
            var issue = AttributedString("#\(number)")
            if let attrs = cachedIssueAttrs { issue.mergeAttributes(attrs) }
            applyLinkContext(&issue, context: context, configuration: configuration)
            applyInlineContext(&issue, context: context)
            result.append(issue)

        case .commitSHA(_, let short):
            var commit = AttributedString(short)
            if let attrs = cachedCommitAttrs { commit.mergeAttributes(attrs) }
            applyLinkContext(&commit, context: context, configuration: configuration)
            applyInlineContext(&commit, context: context)
            result.append(commit)

        case .repositoryReference(let owner, let repo):
            var repository = AttributedString("\(owner)/\(repo)")
            if let attrs = cachedRepoAttrs { repository.mergeAttributes(attrs) }
            applyLinkContext(&repository, context: context, configuration: configuration)
            applyInlineContext(&repository, context: context)
            result.append(repository)

        case .pullRequestReference(let owner, let repo, let number):
            var pullRequest = AttributedString("\(owner)/\(repo)#\(number)")
            if let attrs = cachedPRAttrs { pullRequest.mergeAttributes(attrs) }
            applyLinkContext(&pullRequest, context: context, configuration: configuration)
            applyInlineContext(&pullRequest, context: context)
            result.append(pullRequest)

        case .lineBreak, .softBreak:
            var lineBreak = AttributedString("\n")
            applyLinkContext(&lineBreak, context: context, configuration: configuration)
            applyInlineContext(&lineBreak, context: context)
            result.append(lineBreak)

        case .html(let tag):
            if tag.lowercased() == "<br>" || tag.lowercased() == "<br/>" || tag.lowercased() == "<br />" {
                var lineBreak = AttributedString("\n")
                applyLinkContext(&lineBreak, context: context, configuration: configuration)
                applyInlineContext(&lineBreak, context: context)
                result.append(lineBreak)
            } else {
                var html = AttributedString(tag)
                applyLinkContext(&html, context: context, configuration: configuration)
                applyInlineContext(&html, context: context)
                result.append(html)
            }

        case .footnoteReference(let label):
            let displayLabel = label.starts(with: "inline-") ? "*" : label
            var ref = AttributedString("[\(displayLabel)]")
            ref.mergeAttributes(footnoteRefAttributes(label: label, configuration: configuration))
            applyLinkContext(&ref, context: context, configuration: configuration)
            applyInlineContext(&ref, context: context)
            result.append(ref)

        case .extensionInline(let node):
            if var rendered = renderExtensionInline(node, configuration: configuration) {
                applyLinkContext(&rendered, context: context, configuration: configuration)
                applyInlineContext(&rendered, context: context)
                result.append(rendered)
            } else {
                var literal = AttributedString(node.literal)
                if let forcedFont = context.forcedFont {
                    literal.font = forcedFont
                } else if let baseFont = context.baseFont {
                    literal.font = baseFont
                }
                applyPlainTextColor(&literal, configuration: configuration)
                applyLinkContext(&literal, context: context, configuration: configuration)
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

    private func applyLinkContext(
        _ value: inout AttributedString,
        context: InlineRenderContext,
        configuration: MarkdownConfiguration
    ) {
        guard let linkAttributes = context.linkAttributes else { return }
        value.mergeAttributes(linkAttributes)
    }

    private func applyPlainTextColor(_ value: inout AttributedString, configuration: MarkdownConfiguration) {
        guard configuration.textColor != .primary else { return }
        value.foregroundColor = configuration.textColor
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
        if configuration.linkUnderline {
            container.underlineStyle = .single
        }
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
        let indentation = depth > 0 ? AttributedString(String(repeating: "    ", count: depth)) : nil
        let continuationIndentation = AttributedString(String(repeating: "    ", count: depth + 1))
        let unorderedMarker = AttributedString(Self.unorderedListMarkers[min(depth, Self.unorderedListMarkers.count - 1)])
        
        for (index, item) in items.enumerated() {
            if index > 0 { result.append(Self.newline) }
            
            // Add indentation based on depth
            if let indentation {
                result.append(indentation)
            }
            
            // Choose appropriate marker based on depth
            if ordered {
                let marker: String
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
                result.append(AttributedString(marker))
            } else {
                result.append(unorderedMarker)
            }
            
            // Render item content
            var isFirstBlock = true
            for block in item.content {
                switch block {
                case .paragraph(let children):
                    // For the first paragraph, render inline with the marker
                    if isFirstBlock {
                        result.append(renderInlines(children, configuration: configuration))
                    } else {
                        // For subsequent paragraphs, add proper indentation
                        result.append(Self.newline)
                        result.append(continuationIndentation)
                        result.append(renderInlines(children, configuration: configuration))
                    }
                    
                case .list(let nestedOrdered, _, let nestedItems):
                    // Always put nested lists on a new line
                    result.append(Self.newline)
                    result.append(renderList(ordered: nestedOrdered, items: nestedItems, depth: depth + 1, configuration: configuration))
                    
                default:
                    // For other blocks, add newline and indentation
                    if !isFirstBlock {
                        result.append(Self.newline)
                        result.append(continuationIndentation)
                    }
                    result.append(renderBlock(block, configuration: configuration))
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

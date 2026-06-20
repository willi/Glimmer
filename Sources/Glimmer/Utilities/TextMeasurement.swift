import CoreText
import SwiftUI
import os

extension NSAttributedString {
    private static let textKitLineFragmentPadding: CGFloat = 5

    func preciseWidth() -> CGFloat {
        coreTextPreciseWidth()
    }

    func coreTextPreciseWidthForTesting() -> CGFloat {
        coreTextPreciseWidth()
    }

    func textKitPreciseWidthForTesting() -> CGFloat {
        textKitPreciseWidth()
    }

    private func coreTextPreciseWidth() -> CGFloat {
        guard length > 0 else { return 0 }

        let text = string
        guard text.rangeOfCharacter(from: .newlines) != nil else {
            return ceil(Self.measureCoreTextLine(self) + Self.textKitLineFragmentPadding)
        }

        let nsText = text as NSString
        let fullLength = nsText.length
        var lineStart = 0
        var maxWidth: CGFloat = 0

        while lineStart <= fullLength {
            let searchRange = NSRange(location: lineStart, length: fullLength - lineStart)
            let newlineRange = nsText.rangeOfCharacter(from: .newlines, options: [], range: searchRange)
            let lineRange: NSRange

            if newlineRange.location == NSNotFound {
                lineRange = NSRange(location: lineStart, length: fullLength - lineStart)
                lineStart = fullLength + 1
            } else {
                lineRange = NSRange(location: lineStart, length: newlineRange.location - lineStart)
                lineStart = newlineRange.location + newlineRange.length
            }

            guard lineRange.length > 0 else { continue }
            maxWidth = max(maxWidth, Self.measureCoreTextLine(attributedSubstring(from: lineRange)))
        }

        return ceil(maxWidth + Self.textKitLineFragmentPadding)
    }

    private func textKitPreciseWidth() -> CGFloat {
        let textLayoutManager = NSTextLayoutManager()
        let textContainer = NSTextContainer(size: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        let textContentStorage = NSTextContentStorage()
        
        textContentStorage.attributedString = self
        textContentStorage.addTextLayoutManager(textLayoutManager)
        textLayoutManager.textContainer = textContainer
        
        var width: CGFloat = 0
        textLayoutManager.enumerateTextLayoutFragments(from: textContentStorage.documentRange.location, 
                                                       options: [.ensuresLayout]) { fragment in
            width = max(width, fragment.layoutFragmentFrame.maxX)
            return true
        }
        
        return ceil(width)
    }

    private static func measureCoreTextLine(_ attributedString: NSAttributedString) -> CGFloat {
        let line = CTLineCreateWithAttributedString(attributedString)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        guard width.isFinite else { return 0 }
        return ceil(CGFloat(width))
    }
}

public struct TextMeasurement {
    // MARK: - Table Width Cache

    private struct TableWidthCacheKey: Hashable, Sendable {
        let tableHash: Int
        let fontHash: Int
    }

    private final class WidthCacheNode: @unchecked Sendable {
        let key: TableWidthCacheKey
        var value: [CGFloat]
        weak var prev: WidthCacheNode?
        var next: WidthCacheNode?

        init(key: TableWidthCacheKey, value: [CGFloat]) {
            self.key = key
            self.value = value
        }
    }

    private struct WidthCacheState: @unchecked Sendable {
        var dict: [TableWidthCacheKey: WidthCacheNode] = [:]
        var head: WidthCacheNode?
        var tail: WidthCacheNode?
        var hits: Int = 0
        var misses: Int = 0
    }

    private static let widthCacheCapacity = 128
    private static let widthCacheLock = OSAllocatedUnfairLock(initialState: WidthCacheState())

    private static func appendToTail(_ state: inout WidthCacheState, _ node: WidthCacheNode) {
        node.prev = state.tail
        node.next = nil
        if let tail = state.tail {
            tail.next = node
        } else {
            state.head = node
        }
        state.tail = node
    }

    private static func detachNode(_ state: inout WidthCacheState, _ node: WidthCacheNode) {
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

    private static func moveToTail(_ state: inout WidthCacheState, _ node: WidthCacheNode) {
        guard state.tail !== node else { return }
        detachNode(&state, node)
        appendToTail(&state, node)
    }

    private static func makeTableWidthCacheKey(
        header: [MarkdownParser.TableCell],
        rows: [[MarkdownParser.TableCell]],
        baseFont: Font
    ) -> TableWidthCacheKey {
        var tableHasher = Hasher()
        tableHasher.combine(header.count)
        for cell in header {
            hashInlines(cell.content, into: &tableHasher)
        }
        tableHasher.combine(rows.count)
        for row in rows {
            tableHasher.combine(row.count)
            for cell in row {
                hashInlines(cell.content, into: &tableHasher)
            }
        }

        var fontHasher = Hasher()
        fontHasher.combine(baseFont)

        return TableWidthCacheKey(
            tableHash: tableHasher.finalize(),
            fontHash: fontHasher.finalize()
        )
    }

    private static func hashInlines(_ nodes: [MarkdownParser.InlineNode], into hasher: inout Hasher) {
        hasher.combine(nodes.count)
        for node in nodes {
            switch node {
            case .text(let string):
                hasher.combine(0); hasher.combine(string)
            case .strong(let children):
                hasher.combine(1); hashInlines(children, into: &hasher)
            case .emphasis(let children):
                hasher.combine(2); hashInlines(children, into: &hasher)
            case .strikethrough(let children):
                hasher.combine(3); hashInlines(children, into: &hasher)
            case .code(let code):
                hasher.combine(4); hasher.combine(code)
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
                hasher.combine(originalText)
                switch type {
                case .url: hasher.combine(0)
                case .www: hasher.combine(1)
                case .email: hasher.combine(2)
                }
            case .mention(let username):
                hasher.combine(8); hasher.combine(username)
            case .issueReference(let number):
                hasher.combine(9); hasher.combine(number)
            case .commitSHA(let sha, let short):
                hasher.combine(10); hasher.combine(sha); hasher.combine(short)
            case .repositoryReference(let owner, let repo):
                hasher.combine(11); hasher.combine(owner); hasher.combine(repo)
            case .pullRequestReference(let owner, let repo, let number):
                hasher.combine(12)
                hasher.combine(owner)
                hasher.combine(repo)
                hasher.combine(number)
            case .lineBreak:
                hasher.combine(13)
            case .softBreak:
                hasher.combine(14)
            case .html(let tag):
                hasher.combine(15); hasher.combine(tag)
            case .footnoteReference(let label):
                hasher.combine(16); hasher.combine(label)
            case .extensionInline(let node):
                hasher.combine(17); hasher.combine(node)
            }
        }
    }
    
    /// Calculate column widths for a table
    public static func calculateColumnWidths(
        header: [MarkdownParser.TableCell],
        rows: [[MarkdownParser.TableCell]],
        baseFont: Font
    ) -> [CGFloat] {
        let key = makeTableWidthCacheKey(header: header, rows: rows, baseFont: baseFont)

        if let cached = widthCacheLock.withLock({ state -> [CGFloat]? in
            guard let node = state.dict[key] else { return nil }
            state.hits += 1
            moveToTail(&state, node)
            return node.value
        }) {
            return cached
        }

        let calculated = calculateColumnWidthsUncached(header: header, rows: rows, baseFont: baseFont)
        widthCacheLock.withLock { state in
            state.misses += 1
            if let existing = state.dict[key] {
                existing.value = calculated
                moveToTail(&state, existing)
            } else {
                let node = WidthCacheNode(key: key, value: calculated)
                state.dict[key] = node
                appendToTail(&state, node)
            }

            while state.dict.count > widthCacheCapacity, let evict = state.head {
                detachNode(&state, evict)
                state.dict.removeValue(forKey: evict.key)
            }
        }

        return calculated
    }

    static func constrainColumnWidthsForWrapping(
        _ columnWidths: [CGFloat],
        availableWidth: CGFloat
    ) -> [CGFloat] {
        guard availableWidth.isFinite, availableWidth > 0, !columnWidths.isEmpty else {
            return columnWidths
        }

        let visibleColumnCount = CGFloat(min(max(columnWidths.count, 1), 4))
        let minimumReadableWidth = min(120, max(72, floor(availableWidth / visibleColumnCount)))
        let measuredMaximumWrappedWidth: CGFloat
        if columnWidths.count == 1 {
            measuredMaximumWrappedWidth = max(minimumReadableWidth, availableWidth)
        } else {
            measuredMaximumWrappedWidth = max(minimumReadableWidth, min(720, availableWidth * 0.55))
        }
        let maximumWrappedWidth = max(minimumReadableWidth, floor(measuredMaximumWrappedWidth))

        var constrainedWidths = columnWidths.map { width -> CGFloat in
            guard width.isFinite, width > 0 else { return minimumReadableWidth }
            return min(max(width, minimumReadableWidth), maximumWrappedWidth)
        }

        let constrainedTotalWidth = constrainedWidths.reduce(0, +)
        if constrainedTotalWidth < availableWidth {
            let extraWidth = (availableWidth - constrainedTotalWidth) / CGFloat(constrainedWidths.count)
            constrainedWidths = constrainedWidths.map { $0 + extraWidth }
        }

        return constrainedWidths.map { ceil($0) }
    }

    private static func calculateColumnWidthsUncached(
        header: [MarkdownParser.TableCell],
        rows: [[MarkdownParser.TableCell]],
        baseFont: Font,
        measure: ([MarkdownParser.InlineNode], Font) -> CGFloat = measureInlineNodes
    ) -> [CGFloat] {
        // Determine the maximum number of columns (handle misaligned tables)
        let maxColumns = max(header.count, rows.map { $0.count }.max() ?? 0)
        var columnWidths = [CGFloat](repeating: 0, count: maxColumns)
        
        // Measure header widths
        for (index, cell) in header.enumerated() {
            // Headers in tables are displayed with bold base font in MarkdownTableCell
            // but the content can have its own styling (bold, italic, code, etc.)
            // We need to measure with the base bold font as the default
            let headerWidth = measure(cell.content, baseFont.bold())
            // Add padding: 24pt (12pt left + 12pt right) plus 2pt for borders
            columnWidths[index] = headerWidth + 26
        }
        
        // Measure row widths
        for row in rows {
            for (index, cell) in row.enumerated() where index < maxColumns {
                let width = measure(cell.content, baseFont)
                // Add padding: 24pt (12pt left + 12pt right) plus 2pt for borders
                columnWidths[index] = max(columnWidths[index], width + 26)
            }
        }
        
        // Apply minimum widths based on content
        let finalWidths = columnWidths.enumerated().map { index, width -> CGFloat in
            // Always ensure we have at least the calculated width
            if width > 0 {
                // Use the calculated width (which already includes padding and buffer)
                return width
            } else {
                // Empty columns get minimal width: padding + borders
                return 26
            }
        }
        return finalWidths
    }

    // Internal testing hooks
    static func clearColumnWidthCacheForTesting() {
        widthCacheLock.withLock { state in
            state.dict.removeAll()
            state.head = nil
            state.tail = nil
            state.hits = 0
            state.misses = 0
        }
    }

    static func columnWidthCacheStatsForTesting() -> (hits: Int, misses: Int, entries: Int) {
        widthCacheLock.withLock { state in
            (state.hits, state.misses, state.dict.count)
        }
    }

    static func calculateColumnWidthsUncachedForTesting(
        header: [MarkdownParser.TableCell],
        rows: [[MarkdownParser.TableCell]],
        baseFont: Font
    ) -> [CGFloat] {
        calculateColumnWidthsUncached(header: header, rows: rows, baseFont: baseFont)
    }

    static func calculateColumnWidthsUncachedWithTextKitForTesting(
        header: [MarkdownParser.TableCell],
        rows: [[MarkdownParser.TableCell]],
        baseFont: Font
    ) -> [CGFloat] {
        calculateColumnWidthsUncached(
            header: header,
            rows: rows,
            baseFont: baseFont,
            measure: measureInlineNodesWithTextKitForTesting
        )
    }
    
    /// Measure the width of inline nodes with proper formatting
    public static func measureInlineNodes(_ nodes: [MarkdownParser.InlineNode], baseFont: Font) -> CGFloat {
        inlineAttributedString(for: nodes, baseFont: baseFont).preciseWidth()
    }

    static func measureInlineNodesWithCoreTextForTesting(_ nodes: [MarkdownParser.InlineNode], baseFont: Font) -> CGFloat {
        inlineAttributedString(for: nodes, baseFont: baseFont).coreTextPreciseWidthForTesting()
    }

    static func measureInlineNodesWithTextKitForTesting(_ nodes: [MarkdownParser.InlineNode], baseFont: Font) -> CGFloat {
        inlineAttributedString(for: nodes, baseFont: baseFont).textKitPreciseWidthForTesting()
    }

    private static func inlineAttributedString(
        for nodes: [MarkdownParser.InlineNode],
        baseFont: Font
    ) -> NSAttributedString {
        var attributedString = AttributedString()
        
        for node in nodes {
            attributedString += renderInlineNode(node, baseFont: baseFont)
        }
        
        return NSAttributedString(attributedString)
    }
    
    /// Render inline node to attributed string (matching MarkdownInlineView logic)
    private static func renderInlineNode(_ node: MarkdownParser.InlineNode, baseFont: Font, isBold: Bool = false, isItalic: Bool = false, isStrikethrough: Bool = false) -> AttributedString {
        switch node {
        case .text(let string):
            var text = AttributedString(string)
            if isBold && isItalic {
                text.font = baseFont.bold().italic()
            } else if isBold {
                text.font = baseFont.bold()
            } else if isItalic {
                text.font = baseFont.italic()
            } else {
                text.font = baseFont
            }
            if isStrikethrough {
                text.strikethroughStyle = .single
            }
            return text
            
        case .strong(let children):
            var result = AttributedString()
            for child in children {
                result += renderInlineNode(child, baseFont: baseFont, isBold: true, isItalic: isItalic, isStrikethrough: isStrikethrough)
            }
            return result
            
        case .emphasis(let children):
            var result = AttributedString()
            for child in children {
                result += renderInlineNode(child, baseFont: baseFont, isBold: isBold, isItalic: true, isStrikethrough: isStrikethrough)
            }
            return result
            
        case .strikethrough(let children):
            var result = AttributedString()
            for child in children {
                result += renderInlineNode(child, baseFont: baseFont, isBold: isBold, isItalic: isItalic, isStrikethrough: true)
            }
            return result
            
        case .code(let code):
            var text = AttributedString(code)
            // Apply code font with bold/italic modifiers if needed
            let codeFont = Font.system(.body, design: .monospaced)
            if isBold && isItalic {
                text.font = codeFont.bold().italic()
            } else if isBold {
                text.font = codeFont.bold()
            } else if isItalic {
                text.font = codeFont.italic()
            } else {
                text.font = codeFont
            }
            if isStrikethrough {
                text.strikethroughStyle = .single
            }
            return text
            
        case .link(_, _, let children):
            var result = AttributedString()
            for child in children {
                result += renderInlineNode(child, baseFont: baseFont, isBold: isBold, isItalic: isItalic, isStrikethrough: isStrikethrough)
            }
            // Links have underline but we still need to measure their width
            result.underlineStyle = .single
            return result
            
        case .mention(let username):
            var text = AttributedString("@\(username)")
            text.font = baseFont.bold()
            return text
            
        case .issueReference(let number):
            var text = AttributedString("#\(number)")
            text.font = baseFont.bold()
            return text
            
        case .commitSHA(_, let short):
            var text = AttributedString(short)
            text.font = Font.system(.body, design: .monospaced)
            return text
            
        case .repositoryReference(let owner, let repo):
            var text = AttributedString("\(owner)/\(repo)")
            text.font = baseFont.bold()
            return text
            
        case .pullRequestReference(let owner, let repo, let number):
            var text = AttributedString("\(owner)/\(repo)#\(number)")
            text.font = baseFont.bold()
            return text
            
        case .image(_, let alt, _):
            var text = AttributedString(alt.isEmpty ? "[Image]" : alt)
            text.font = baseFont
            return text
            
        case .autolink(_, _, let originalText):
            var text = AttributedString(originalText)
            text.font = baseFont
            text.underlineStyle = .single
            return text
            
        case .lineBreak, .softBreak:
            return AttributedString("\n")
            
        case .html(let tag):
            if tag.lowercased() == "<br>" || tag.lowercased() == "<br/>" || tag.lowercased() == "<br />" {
                return AttributedString("\n")
            }
            return AttributedString(tag)
            
        case .footnoteReference(let label):
            // Use [*] for inline footnotes, [label] for regular ones
            let displayLabel = label.starts(with: "inline-") ? "*" : label
            var text = AttributedString("[\(displayLabel)]")
            text.font = .system(.caption2)
            text.baselineOffset = 6 // Superscript effect
            return text

        case .extensionInline(let node):
            var text = AttributedString(node.literal)
            text.font = baseFont
            return text
        }
    }
}

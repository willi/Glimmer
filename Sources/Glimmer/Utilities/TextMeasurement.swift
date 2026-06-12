import SwiftUI
import os

// Extension for precise width calculation using NSTextLayoutManager
extension NSAttributedString {
    func preciseWidth() -> CGFloat {
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
}

public struct TextMeasurement {
    // MARK: - Table Width Cache

    private struct TableWidthCacheKey: Hashable {
        let tableHash: Int
        let fontHash: Int
    }

    private final class WidthCacheNode {
        let key: TableWidthCacheKey
        var value: [CGFloat]
        weak var prev: WidthCacheNode?
        var next: WidthCacheNode?

        init(key: TableWidthCacheKey, value: [CGFloat]) {
            self.key = key
            self.value = value
        }
    }

    private struct WidthCacheState {
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

    private static func calculateColumnWidthsUncached(
        header: [MarkdownParser.TableCell],
        rows: [[MarkdownParser.TableCell]],
        baseFont: Font
    ) -> [CGFloat] {
        // Determine the maximum number of columns (handle misaligned tables)
        let maxColumns = max(header.count, rows.map { $0.count }.max() ?? 0)
        var columnWidths = [CGFloat](repeating: 0, count: maxColumns)
        
        // Measure header widths
        for (index, cell) in header.enumerated() {
            // Headers in tables are displayed with bold base font in MarkdownTableCell
            // but the content can have its own styling (bold, italic, code, etc.)
            // We need to measure with the base bold font as the default
            let headerWidth = measureInlineNodes(cell.content, baseFont: baseFont.bold())
            // Add padding: 24pt (12pt left + 12pt right) plus 2pt for borders
            columnWidths[index] = headerWidth + 26
        }
        
        // Measure row widths
        for row in rows {
            for (index, cell) in row.enumerated() where index < maxColumns {
                let width = measureInlineNodes(cell.content, baseFont: baseFont)
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
    
    /// Measure the width of inline nodes with proper formatting
    public static func measureInlineNodes(_ nodes: [MarkdownParser.InlineNode], baseFont: Font) -> CGFloat {
        // Create attributed string the same way MarkdownInlineView does
        var attributedString = AttributedString()
        
        for node in nodes {
            attributedString += renderInlineNode(node, baseFont: baseFont)
        }
        
        // Measure the complete attributed string
        let nsAttributedString = NSAttributedString(attributedString)
        
        // Use precise width calculation
        return nsAttributedString.preciseWidth()
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
        }
    }
}

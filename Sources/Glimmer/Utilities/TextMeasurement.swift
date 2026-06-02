import SwiftUI

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
    
    /// Calculate column widths for a table
    public static func calculateColumnWidths(
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

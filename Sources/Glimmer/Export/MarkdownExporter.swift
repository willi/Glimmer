import Foundation

/// Exports AST nodes back to markdown format
public struct MarkdownExporter {
    
    /// Export options for customizing output
    public struct ExportOptions: Sendable {
        /// Use ATX-style headers (#) instead of Setext-style (underlines)
        public var useATXHeaders: Bool = true
        
        /// Preferred list marker for unordered lists
        public var unorderedListMarker: String = "-"
        
        /// Preferred emphasis marker
        public var emphasisMarker: String = "*"
        
        /// Preferred strong emphasis marker
        public var strongMarker: String = "**"
        
        /// Include trailing newline
        public var includeTrailingNewline: Bool = true
        
        /// Indent size for nested content
        public var indentSize: Int = 2
        
        /// Line width for wrapping (0 = no wrapping)
        public var lineWidth: Int = 0
        
        public init() {}
        
        public static let `default` = ExportOptions()
    }
    
    // MARK: - Public API
    
    /// Export blocks to markdown string
    public static func export(_ blocks: [MarkdownParser.BlockNode], options: ExportOptions = .default) -> String {
        var result = ""
        var previousBlock: MarkdownParser.BlockNode?
        
        for block in blocks {
            // Add spacing between blocks if needed
            if let previous = previousBlock {
                result += blockSpacing(from: previous, to: block)
            }
            
            result += exportBlock(block, options: options, depth: 0)
            previousBlock = block
        }
        
        if options.includeTrailingNewline && !result.hasSuffix("\n") {
            result += "\n"
        }
        
        return result
    }
    
    /// Export a single block to markdown
    public static func exportBlock(_ block: MarkdownParser.BlockNode, options: ExportOptions = .default, depth: Int = 0) -> String {
        let indent = String(repeating: " ", count: depth * options.indentSize)
        
        switch block {
        case .heading(let level, let content, let id):
            return exportHeading(level: level, content: content, id: id, options: options, indent: indent)
            
        case .paragraph(let content):
            return exportParagraph(content: content, options: options, indent: indent)
            
        case .blockquote(let blocks):
            return exportBlockquote(blocks: blocks, options: options, indent: indent)
            
        case .list(let ordered, _, let items):
            return exportList(ordered: ordered, items: items, options: options, indent: indent)
            
        case .codeBlock(let language, let content):
            return exportCodeBlock(code: content, language: language ?? "", indent: indent)
            
        case .table(let header, let rows):
            // Preserve parsed table alignments from header cells.
            let alignments = header.map(\.alignment)
            return exportTable(headers: header, rows: rows, alignments: alignments, options: options, indent: indent)
            
        case .horizontalRule:
            return indent + "---\n"
            
        case .footnoteDefinition(let label, let content):
            return exportFootnoteDefinition(label: label, content: content, options: options, indent: indent)
            
        case .html(let html):
            return indent + html + "\n"
            
        case .taskList(let items):
            // Export task list as a regular list with task items
            let listItems = items.map { item in
                MarkdownParser.ListItem(
                    marker: "-",
                    content: [.paragraph(children: item.content)],
                    isTask: true,
                    isChecked: item.isChecked
                )
            }
            return exportList(ordered: false, items: listItems, options: options, indent: indent)
        }
    }
    
    // MARK: - Block Exporters
    
    private static func exportHeading(level: Int, content: [MarkdownParser.InlineNode], id: String?, options: ExportOptions, indent: String) -> String {
        let text = exportInlines(content, options: options)
        
        if options.useATXHeaders || level > 2 {
            // ATX-style headers
            let hashes = String(repeating: "#", count: level)
            return "\(indent)\(hashes) \(text)\n"
        } else {
            // Setext-style headers (only for levels 1 and 2)
            let underline = level == 1 ? "=" : "-"
            let underlineLength = text.count
            return "\(indent)\(text)\n\(indent)\(String(repeating: underline, count: underlineLength))\n"
        }
    }
    
    private static func exportParagraph(content: [MarkdownParser.InlineNode], options: ExportOptions, indent: String) -> String {
        let text = exportInlines(content, options: options)
        
        if options.lineWidth > 0 {
            // Wrap lines
            return wrapText(text, width: options.lineWidth, indent: indent) + "\n"
        } else {
            return indent + text + "\n"
        }
    }
    
    private static func exportBlockquote(blocks: [MarkdownParser.BlockNode], options: ExportOptions, indent: String) -> String {
        var result = ""
        
        for block in blocks {
            let blockContent = exportBlock(block, options: options, depth: 0)
            let lines = blockContent.split(separator: "\n", omittingEmptySubsequences: false)
            
            for line in lines {
                if line.isEmpty {
                    result += indent + ">\n"
                } else {
                    result += indent + "> " + line + "\n"
                }
            }
        }
        
        return result
    }
    
    private static func exportList(ordered: Bool, items: [MarkdownParser.ListItem], options: ExportOptions, indent: String) -> String {
        var result = ""
        
        for (index, item) in items.enumerated() {
            let marker = ordered ? "\(index + 1)." : options.unorderedListMarker
            let prefix = indent + marker + " "
            
            // Add task list marker if needed
            if item.isTask {
                let checkbox = item.isChecked ?? false ? "[x]" : "[ ]"
                result += prefix + checkbox + " "
            } else {
                result += prefix
            }
            
            // Export item content
            if let firstBlock = item.content.first {
                // First block goes on the same line
                let firstContent = exportBlock(firstBlock, options: options, depth: 0)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                result += firstContent + "\n"
                
                // Subsequent blocks are indented
                for block in item.content.dropFirst() {
                    let blockIndent = String(repeating: " ", count: prefix.count)
                    let blockContent = exportBlock(block, options: options, depth: 0)
                    let lines = blockContent.split(separator: "\n", omittingEmptySubsequences: false)
                    
                    for line in lines {
                        if !line.isEmpty {
                            result += blockIndent + line + "\n"
                        } else {
                            result += "\n"
                        }
                    }
                }
            } else {
                result += "\n"
            }
        }
        
        return result
    }
    
    private static func exportCodeBlock(code: String, language: String?, indent: String) -> String {
        let fence = "```"
        var result = indent + fence
        
        if let lang = language {
            result += lang
        }
        result += "\n"
        
        // Add code lines
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            result += indent + line + "\n"
        }
        
        result += indent + fence + "\n"
        return result
    }
    
    private static func exportTable(headers: [MarkdownParser.TableCell], rows: [[MarkdownParser.TableCell]], alignments: [MarkdownParser.TableAlignment], options: ExportOptions, indent: String) -> String {
        var result = ""
        
        // Calculate column widths
        var columnWidths: [Int] = []
        for (index, header) in headers.enumerated() {
            let headerText = exportInlines(header.content, options: options)
            var maxWidth = headerText.count
            
            for row in rows {
                if index < row.count {
                    let cellText = exportInlines(row[index].content, options: options)
                    maxWidth = max(maxWidth, cellText.count)
                }
            }
            
            columnWidths.append(max(maxWidth, 3)) // Minimum width of 3 for alignment markers
        }
        
        // Export header row
        result += indent + "|"
        for (index, header) in headers.enumerated() {
            let text = exportInlines(header.content, options: options)
            let padding = columnWidths[index] - text.count
            result += " " + text + String(repeating: " ", count: padding) + " |"
        }
        result += "\n"
        
        // Export separator row
        result += indent + "|"
        for (index, alignment) in alignments.enumerated() {
            let width = index < columnWidths.count ? columnWidths[index] : 3
            
            switch alignment {
            case .left:
                result += " :" + String(repeating: "-", count: width - 1) + " |"
            case .center:
                result += " :" + String(repeating: "-", count: width - 2) + ": |"
            case .right:
                result += " " + String(repeating: "-", count: width - 1) + ": |"
            case .none:
                result += " " + String(repeating: "-", count: width) + " |"
            }
        }
        result += "\n"
        
        // Export data rows
        for row in rows {
            result += indent + "|"
            for (index, cell) in row.enumerated() {
                let text = exportInlines(cell.content, options: options)
                let width = index < columnWidths.count ? columnWidths[index] : text.count
                let padding = width - text.count
                result += " " + text + String(repeating: " ", count: padding) + " |"
            }
            result += "\n"
        }
        
        return result
    }
    
    private static func exportFootnoteDefinition(label: String, content: [MarkdownParser.BlockNode], options: ExportOptions, indent: String) -> String {
        var result = indent + "[^\(label)]: "
        
        if let firstBlock = content.first {
            let firstContent = exportBlock(firstBlock, options: options, depth: 0)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            result += firstContent + "\n"
            
            // Subsequent blocks are indented
            for block in content.dropFirst() {
                let blockContent = exportBlock(block, options: options, depth: 1)
                result += blockContent
            }
        } else {
            result += "\n"
        }
        
        return result
    }
    
    // MARK: - Inline Exporters
    
    /// Export inline nodes to markdown string
    public static func exportInlines(_ inlines: [MarkdownParser.InlineNode], options: ExportOptions = .default) -> String {
        var result = ""
        
        for inline in inlines {
            result += exportInline(inline, options: options)
        }
        
        return result
    }
    
    private static func exportInline(_ inline: MarkdownParser.InlineNode, options: ExportOptions) -> String {
        switch inline {
        case .text(let text):
            return escapeMarkdown(text)
            
        case .emphasis(let content):
            let text = exportInlines(content, options: options)
            return "\(options.emphasisMarker)\(text)\(options.emphasisMarker)"
            
        case .strong(let content):
            let text = exportInlines(content, options: options)
            return "\(options.strongMarker)\(text)\(options.strongMarker)"
            
        case .strikethrough(let content):
            let text = exportInlines(content, options: options)
            return "~~\(text)~~"
            
        case .code(let code):
            let backticks = code.contains("`") ? "``" : "`"
            return "\(backticks)\(code)\(backticks)"
            
        case .link(let url, let title, let children):
            let linkText = exportInlines(children, options: options)
            if let title = title {
                return "[\(linkText)](\(url.absoluteString) \"\(title)\")"
            } else {
                return "[\(linkText)](\(url.absoluteString))"
            }
            
        case .image(let url, let alt, let title):
            if let title = title {
                return "![\(alt)](\(url.absoluteString) \"\(title)\")"
            } else {
                return "![\(alt)](\(url.absoluteString))"
            }
            
        case .html(let html):
            return html
            
        case .lineBreak:
            return "  \n"
            
        case .mention(let username):
            return "@\(username)"
            
        case .issueReference(let number):
            return "#\(number)"
            
        case .commitSHA(let sha, _):
            return sha
            
        case .autolink(_, _, let originalText):
            return originalText
            
        case .softBreak:
            // Soft breaks are represented as spaces in markdown
            return " "
            
        case .repositoryReference(let owner, let repo):
            return "\(owner)/\(repo)"
            
        case .pullRequestReference(let owner, let repo, let number):
            return "\(owner)/\(repo)#\(number)"
            
        case .footnoteReference(let label):
            return "[^\(label)]"

        case .extensionInline(let node):
            return node.literal
        }
    }
    
    // MARK: - Helper Methods
    
    private static func blockSpacing(from previous: MarkdownParser.BlockNode, to current: MarkdownParser.BlockNode) -> String {
        // Determine appropriate spacing between blocks
        switch (previous, current) {
        case (.paragraph, .paragraph):
            return "\n"
        case (.heading, _):
            return "\n"
        case (_, .heading):
            return "\n"
        case (.codeBlock, _):
            return "\n"
        case (_, .codeBlock):
            return "\n"
        case (.list, .list):
            return ""  // Lists can be adjacent
        default:
            return "\n"
        }
    }
    
    private static func escapeMarkdown(_ text: String) -> String {
        // Escape special markdown characters
        var escaped = text
        let specialChars = ["\\", "`", "*", "_", "{", "}", "[", "]", "(", ")", "#", "+", "-", ".", "!", "|"]
        
        for char in specialChars {
            escaped = escaped.replacingOccurrences(of: char, with: "\\\(char)")
        }
        
        return escaped
    }
    
    private static func wrapText(_ text: String, width: Int, indent: String) -> String {
        guard width > 0 else { return indent + text }
        
        var result = ""
        var currentLine = indent
        let words = text.split(separator: " ")
        
        for word in words {
            let wordLength = word.count
            
            if currentLine.count + wordLength + 1 > width {
                // Start new line
                result += currentLine + "\n"
                currentLine = indent + String(word)
            } else {
                // Add to current line
                if currentLine.count > indent.count {
                    currentLine += " "
                }
                currentLine += String(word)
            }
        }
        
        if currentLine.count > indent.count {
            result += currentLine
        }
        
        return result
    }
}

// MARK: - Convenience Extensions

public extension Glimmer {
    /// Export parsed markdown AST back to markdown string
    static func exportToMarkdown(_ blocks: [MarkdownParser.BlockNode], options: MarkdownExporter.ExportOptions = .default) -> String {
        return MarkdownExporter.export(blocks, options: options)
    }
}

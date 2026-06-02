import Foundation

/// Streaming parser for processing markdown in chunks
public class StreamingMarkdownParser {
    private var pendingText = ""
    private var configuration: MarkdownConfiguration
    private var currentCodeBlock: CodeBlockState?
    private var currentList: ListState?
    private var currentBlockquote: BlockquoteState?
    private var pendingTableHeader: String?
    private var currentTableLines: [String]?
    private var parsedBlocks: [MarkdownParser.BlockNode] = []
    
    // State tracking for partial blocks
    private struct CodeBlockState {
        let fence: String
        let language: String?
        var lines: [String]
        let startLine: Int
    }
    
    private struct ListState {
        let ordered: Bool
        var items: [String]
        let marker: String
        let startLine: Int
    }
    
    private struct BlockquoteState {
        var lines: [String]
        let startLine: Int
    }
    
    public init(configuration: MarkdownConfiguration = .default) {
        self.configuration = configuration
    }
    
    /// Parse a chunk of markdown and emit completed blocks
    public func parseChunk(_ chunk: String) -> [MarkdownParser.BlockNode] {
        pendingText += chunk
        var completedBlocks: [MarkdownParser.BlockNode] = []
        
        // Process text line by line
        while let lineEnd = pendingText.firstIndex(of: "\n") {
            let line = String(pendingText[..<lineEnd])
            pendingText.removeFirst(pendingText.distance(from: pendingText.startIndex, to: lineEnd) + 1)
            
            if let blocks = processLine(line) {
                completedBlocks.append(contentsOf: blocks)
            }
        }
        
        return completedBlocks
    }
    
    /// Finish parsing and return any remaining blocks
    public func finish() -> [MarkdownParser.BlockNode] {
        var finalBlocks: [MarkdownParser.BlockNode] = []
        
        // Process any remaining text as a line
        if !pendingText.isEmpty {
            if let blocks = processLine(pendingText) {
                finalBlocks.append(contentsOf: blocks)
            }
            pendingText = ""
        }

        // Flush pending table state when stream ends.
        if pendingTableHeader != nil {
            let header = pendingTableHeader!
            pendingTableHeader = nil
            if let blocks = processNewLine(header) {
                finalBlocks.append(contentsOf: blocks)
            }
        }
        if currentTableLines != nil {
            finalBlocks.append(contentsOf: flushCurrentTableOrFallback())
            currentTableLines = nil
        }
        
        // Close any open blocks
        if let codeBlock = currentCodeBlock {
            // Unclosed code block
            let code = codeBlock.lines.joined(separator: "\n")
            finalBlocks.append(.codeBlock(language: codeBlock.language, content: code))
            currentCodeBlock = nil
        }
        
        if let list = currentList {
            // Complete the list
            let blocks = parseListItems(list.items, ordered: list.ordered)
            finalBlocks.append(contentsOf: blocks)
            currentList = nil
        }
        
        if let blockquote = currentBlockquote {
            // Complete the blockquote
            let content = blockquote.lines.joined(separator: "\n")
            let blocks = MarkdownParser.parse(content, configuration: configuration)
            finalBlocks.append(.blockquote(children: blocks))
            currentBlockquote = nil
        }
        
        return finalBlocks
    }
    
    /// Reset the parser state
    public func reset() {
        pendingText = ""
        currentCodeBlock = nil
        currentList = nil
        currentBlockquote = nil
        parsedBlocks = []
    }
    
    // MARK: - Private Methods
    
    private func processLine(_ line: String) -> [MarkdownParser.BlockNode]? {
        var result: [MarkdownParser.BlockNode] = []
        
        // Handle streaming table collection first
        if var lines = currentTableLines {
            if line.contains("|") {
                lines.append(line)
                currentTableLines = lines
                return result.isEmpty ? nil : result
            } else {
                // Flush collected table (with fallback)
                result.append(contentsOf: flushCurrentTableOrFallback())
                currentTableLines = nil
                // Continue processing this non-table line below
            }
        }

        // Pending header lookahead: store potential header and wait for next line
        if pendingTableHeader != nil {
            let header = pendingTableHeader!
            pendingTableHeader = nil
            if isTableSeparator(line) {
                currentTableLines = [header, line]
                return result.isEmpty ? nil : result
            } else {
                // Not a table; flush header as normal content
                if let blocks = processNewLine(header) {
                    result.append(contentsOf: blocks)
                }
                // Fall through to process current line
            }
        }

        // Detect potential table start (header with pipes)
        if currentCodeBlock == nil && currentList == nil && currentBlockquote == nil {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("|") && !trimmed.isEmpty {
                pendingTableHeader = line
                return result.isEmpty ? nil : result
            }
        }

        // Check if we're in a code block
        if var codeBlock = currentCodeBlock {
            if line.hasPrefix(codeBlock.fence) {
                // End of code block
                let code = codeBlock.lines.joined(separator: "\n")
                result.append(.codeBlock(language: codeBlock.language, content: code))
                currentCodeBlock = nil
            } else {
                // Add line to code block
                codeBlock.lines.append(line)
                currentCodeBlock = codeBlock
            }
            return result.isEmpty ? nil : result
        }
        
        // Check for code block start
        if line.hasPrefix("```") || line.hasPrefix("~~~") {
            // Close any open blocks first
            result.append(contentsOf: closeCurrentBlocks())
            
            let fence = String(line.prefix(3))
            let language = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            currentCodeBlock = CodeBlockState(
                fence: fence,
                language: language.isEmpty ? nil : language,
                lines: [],
                startLine: 0
            )
            return result.isEmpty ? nil : result
        }
        
        // Check if we're in a blockquote
        if var blockquote = currentBlockquote {
            if line.hasPrefix(">") {
                // Continue blockquote
                let content = line.dropFirst().trimmingCharacters(in: CharacterSet(charactersIn: " "))
                blockquote.lines.append(String(content))
                currentBlockquote = blockquote
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                // Empty line might continue or end blockquote
                blockquote.lines.append("")
                currentBlockquote = blockquote
            } else {
                // End of blockquote
                let content = blockquote.lines.joined(separator: "\n")
                let blocks = MarkdownParser.parse(content, configuration: configuration)
                result.append(.blockquote(children: blocks))
                currentBlockquote = nil
                
                // Process this line as new content
                if let newBlocks = processNewLine(line) {
                    result.append(contentsOf: newBlocks)
                }
            }
            return result.isEmpty ? nil : result
        }
        
        // Check for blockquote start
        if line.hasPrefix(">") {
            // Close any open blocks first
            result.append(contentsOf: closeCurrentBlocks())
            
            let content = line.dropFirst().trimmingCharacters(in: CharacterSet(charactersIn: " "))
            currentBlockquote = BlockquoteState(
                lines: [String(content)],
                startLine: 0
            )
            return result.isEmpty ? nil : result
        }
        
        // Check if we're in a list
        if var list = currentList {
            if let listMarker = detectListMarker(line) {
                if (list.ordered && listMarker.ordered) || (!list.ordered && listMarker.marker == list.marker) {
                    // Continue list
                    list.items.append(listMarker.content)
                    currentList = list
                } else {
                    // Different list type, end current list
                    let blocks = parseListItems(list.items, ordered: list.ordered)
                    result.append(contentsOf: blocks)
                    
                    // Start new list
                    currentList = ListState(
                        ordered: listMarker.ordered,
                        items: [listMarker.content],
                        marker: listMarker.marker,
                        startLine: 0
                    )
                }
            } else if line.hasPrefix("  ") || line.hasPrefix("\t") {
                // Continuation of list item
                if !list.items.isEmpty {
                    let continuation = line.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
                    list.items[list.items.count - 1] += "\n" + continuation
                    currentList = list
                }
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                // Empty line in list
                if !list.items.isEmpty {
                    list.items[list.items.count - 1] += "\n"
                    currentList = list
                }
            } else {
                // End of list
                let blocks = parseListItems(list.items, ordered: list.ordered)
                result.append(contentsOf: blocks)
                currentList = nil
                
                // Process this line as new content
                if let newBlocks = processNewLine(line) {
                    result.append(contentsOf: newBlocks)
                }
            }
            return result.isEmpty ? nil : result
        }
        
        // Check for list start
        if let listMarker = detectListMarker(line) {
            // Close any open blocks first
            result.append(contentsOf: closeCurrentBlocks())
            
            currentList = ListState(
                ordered: listMarker.ordered,
                items: [listMarker.content],
                marker: listMarker.marker,
                startLine: 0
            )
            return result.isEmpty ? nil : result
        }
        
        // Process as new line
        if let blocks = processNewLine(line) {
            result.append(contentsOf: blocks)
        }
        
        return result.isEmpty ? nil : result
    }

    private func flushCurrentTableOrFallback() -> [MarkdownParser.BlockNode] {
        guard let lines = currentTableLines, lines.count >= 2 else { return [] }
        if let (headers, rows, _) = GFMExtensions.parseTable(lines: lines, configuration: configuration) {
            return [.table(header: headers, rows: rows)]
        }
        // Fallback: emit captured lines as paragraphs
        var blocks: [MarkdownParser.BlockNode] = []
        for l in lines {
            if let b = processNewLine(l) {
                blocks.append(contentsOf: b)
            }
        }
        return blocks
    }

    private func isTableSeparator(_ line: String) -> Bool {
        // A simple check: must contain '|' and at least three '-' in any cell, with optional ':' for alignment
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return false }
        // Remove pipes ends and split cells
        let parts = trimmed.split(separator: "|", omittingEmptySubsequences: false)
        var hasValid = false
        for raw in parts {
            let cell = raw.trimmingCharacters(in: .whitespaces)
            if cell.isEmpty { continue }
            // valid if matches /^:?-{3,}:?$/
            let stripped = cell.replacingOccurrences(of: ":", with: "")
            if stripped.count >= 3 && stripped.allSatisfy({ $0 == "-" }) {
                hasValid = true
            } else {
                return false
            }
        }
        return hasValid
    }
    
    private func processNewLine(_ line: String) -> [MarkdownParser.BlockNode]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // Empty line
        if trimmed.isEmpty {
            return nil
        }
        
        // Heading
        if trimmed.hasPrefix("#") {
            var level = 0
            for char in trimmed {
                if char == "#" {
                    level += 1
                } else {
                    break
                }
            }
            
            if level > 0 && level <= 6 {
                let content = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
                var state = ParserState(text: String(content))
                let inlines = InlineParser.parseInlineElements(&state, configuration: configuration)
                
                let headingId = ParsingHelpers.slugifyHeading(String(content))
                
                return [.heading(level: level, children: inlines, id: headingId.isEmpty ? nil : headingId)]
            }
        }
        
        // Horizontal rule
        if isHorizontalRule(trimmed) {
            return [.horizontalRule]
        }
        
        // Table (simplified detection)
        if trimmed.contains("|") {
            // For streaming, we'll parse tables as paragraphs
            // Full table parsing requires multiple lines
            var state = ParserState(text: trimmed)
            let inlines = InlineParser.parseInlineElements(&state, configuration: configuration)
            return [.paragraph(children: inlines)]
        }
        
        // Default to paragraph
        var state = ParserState(text: trimmed)
        let inlines = InlineParser.parseInlineElements(&state, configuration: configuration)
        return [.paragraph(children: inlines)]
    }
    
    private func closeCurrentBlocks() -> [MarkdownParser.BlockNode] {
        var blocks: [MarkdownParser.BlockNode] = []
        
        if let codeBlock = currentCodeBlock {
            let code = codeBlock.lines.joined(separator: "\n")
            blocks.append(.codeBlock(language: codeBlock.language, content: code))
            currentCodeBlock = nil
        }
        
        if let list = currentList {
            blocks.append(contentsOf: parseListItems(list.items, ordered: list.ordered))
            currentList = nil
        }
        
        if let blockquote = currentBlockquote {
            let content = blockquote.lines.joined(separator: "\n")
            let quotedBlocks = MarkdownParser.parse(content, configuration: configuration)
            blocks.append(.blockquote(children: quotedBlocks))
            currentBlockquote = nil
        }
        
        return blocks
    }
    
    private func detectListMarker(_ line: String) -> (marker: String, content: String, ordered: Bool)? {
        let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
        
        // Unordered list
        if trimmed.hasPrefix("- ") {
            return ("-", String(trimmed.dropFirst(2)), false)
        }
        if trimmed.hasPrefix("* ") {
            return ("*", String(trimmed.dropFirst(2)), false)
        }
        if trimmed.hasPrefix("+ ") {
            return ("+", String(trimmed.dropFirst(2)), false)
        }
        
        // Ordered list
        var numberEnd = 0
        for char in trimmed {
            if char.isNumber {
                numberEnd += 1
            } else {
                break
            }
        }
        
        if numberEnd > 0 && numberEnd < trimmed.count {
            let afterNumber = trimmed.index(trimmed.startIndex, offsetBy: numberEnd)
            if afterNumber < trimmed.endIndex {
                let nextChar = trimmed[afterNumber]
                if nextChar == "." || nextChar == ")" {
                    let markerEnd = trimmed.index(after: afterNumber)
                    if markerEnd < trimmed.endIndex && trimmed[markerEnd] == " " {
                        let marker = String(trimmed[..<markerEnd])
                        let content = String(trimmed[trimmed.index(after: markerEnd)...])
                        return (marker, content, true)
                    }
                }
            }
        }
        
        return nil
    }
    
    private func isHorizontalRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // Check for at least 3 consecutive -, *, or _
        let patterns = ["---", "***", "___"]
        for pattern in patterns {
            if trimmed.hasPrefix(pattern) {
                // Check if the rest of the line only contains the same character or spaces
                let char = pattern.first!
                let rest = trimmed.dropFirst(3)
                for c in rest {
                    if c != char && c != " " {
                        return false
                    }
                }
                return true
            }
        }
        
        return false
    }
    
    private func parseListItems(_ items: [String], ordered: Bool) -> [MarkdownParser.BlockNode] {
        var listItems: [MarkdownParser.ListItem] = []
        
        for item in items {
            // Check for task list marker
            var isTask = false
            var isChecked = false
            var content = item
            
            if content.hasPrefix("[ ] ") {
                isTask = true
                isChecked = false
                content = String(content.dropFirst(4))
            } else if content.hasPrefix("[x] ") || content.hasPrefix("[X] ") {
                isTask = true
                isChecked = true
                content = String(content.dropFirst(4))
            }
            
            // Parse item content
            let blocks = MarkdownParser.parse(content, configuration: configuration)
            let marker = ordered ? "1." : "-"  // Default marker
            listItems.append(MarkdownParser.ListItem(
                marker: marker,
                content: blocks,
                isTask: isTask,
                isChecked: isChecked
            ))
        }
        
        return [.list(ordered: ordered, tight: true, items: listItems)]
    }
}

// MARK: - Convenience Extensions

public extension StreamingMarkdownParser {
    /// Parse markdown from a stream/sequence of chunks
    func parse<S: Sequence>(chunks: S) -> [MarkdownParser.BlockNode] where S.Element == String {
        var allBlocks: [MarkdownParser.BlockNode] = []
        
        for chunk in chunks {
            allBlocks.append(contentsOf: parseChunk(chunk))
        }
        
        allBlocks.append(contentsOf: finish())
        return allBlocks
    }
    
    /// Parse markdown from async stream
    func parse<S: AsyncSequence>(stream: S) async -> [MarkdownParser.BlockNode] where S.Element == String {
        var allBlocks: [MarkdownParser.BlockNode] = []
        
        do {
            for try await chunk in stream {
                allBlocks.append(contentsOf: parseChunk(chunk))
            }
        } catch {
            // Log error in debug builds
            #if DEBUG
            print("[StreamingMarkdownParser] ERROR: Failed to read stream - \(error)")
            #endif
        }
        
        allBlocks.append(contentsOf: finish())
        return allBlocks
    }
}

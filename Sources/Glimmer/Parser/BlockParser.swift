import Foundation

/// Handles parsing of block-level markdown elements
public struct BlockParser {
    
    // MARK: - Block Parsing
    
    static func parseBlocks(_ state: inout ParserState, configuration: MarkdownConfiguration) -> [MarkdownParser.BlockNode] {
        var blocks: [MarkdownParser.BlockNode] = []
        var iterationCount = 0
        let maxIterations = configuration.maxBlockIterations
        
        
        while !state.isAtEnd {
            iterationCount += 1
            if iterationCount > maxIterations {
                // Breaking after max iterations to prevent infinite loop
                break
            }
            
            // Skip empty lines
            while !state.isAtEnd && state.isAtEmptyLine() {
                state.advanceLine()
            }
            
            if state.isAtEnd {
                break
            }
            
            if let block = parseBlock(&state, configuration: configuration) {
                blocks.append(block)
            } else {
                // If we can't parse a block, skip the line to avoid infinite loop
                state.advanceLine()
            }
        }
        
        return blocks
    }

    // Parse blocks and capture their starting line numbers (1-based)
    static func parseBlocksLocated(_ state: inout ParserState, configuration: MarkdownConfiguration) -> [MarkdownParser.LocatedBlock] {
        var located: [MarkdownParser.LocatedBlock] = []
        var iterationCount = 0
        let maxIterations = configuration.maxBlockIterations

        
        while !state.isAtEnd {
            iterationCount += 1
            if iterationCount > maxIterations { break }

            while !state.isAtEnd && state.isAtEmptyLine() {
                state.advanceLine()
            }
            if state.isAtEnd { break }

            let startLine = state.line
            if let block = parseBlock(&state, configuration: configuration) {
                located.append(.init(node: block, startLine: startLine))
            } else {
                state.advanceLine()
            }
        }
        return located
    }
    
    static func parseBlock(_ state: inout ParserState, configuration: MarkdownConfiguration) -> MarkdownParser.BlockNode? {
        
        let savedIndex = state.currentIndex
        
        // Skip leading whitespace (up to 3 spaces for block elements)
        var leadingSpaces = 0
        while let ch = state.current(), ch == " ", leadingSpaces < 3 {
            state.advance()
            leadingSpaces += 1
        }
        
        // Check for indented code block (4+ spaces)
        if leadingSpaces >= 3, let ch = state.current(), ch == " " {
            state.move(to: savedIndex)
            return parseIndentedCodeBlock(&state)
        }
        
        // Try parsing different block types
        if let heading = parseATXHeading(&state, configuration: configuration) {
            return heading
        }
        
        if let codeBlock = parseFencedCodeBlock(&state) {
            return codeBlock
        }
        
        if let blockquote = parseBlockquote(&state, configuration: configuration) {
            return blockquote
        }
        
        if let list = parseList(&state, configuration: configuration) {
            return list
        }
        
        if let table = parseTable(&state, configuration: configuration) {
            return table
        }
        
        if let hr = parseHorizontalRule(&state) {
            return hr
        }
        
        if let setextHeading = parseSetextHeading(&state, configuration: configuration) {
            return setextHeading
        }
        
        if configuration.enableFootnotes {
            if let footnote = parseFootnoteDefinition(&state, configuration: configuration) {
                return footnote
            }
        }
        
        // Default to paragraph
        state.move(to: savedIndex)
        return parseParagraph(&state, configuration: configuration)
    }
    
    // MARK: - Specific Block Parsers
    
    static func parseATXHeading(_ state: inout ParserState, configuration: MarkdownConfiguration) -> MarkdownParser.BlockNode? {
        let savedIndex = state.currentIndex
        
        // Count the number of # characters
        var level = 0
        while let ch = state.current(), ch == "#", level < 6 {
            state.advance()
            level += 1
        }
        
        // Not a heading if no # or more than 6
        if level == 0 || level > 6 {
            state.move(to: savedIndex)
            return nil
        }
        
        // After #, there should be a space or end of line
        if let ch = state.current(), ch != " " && ch != "\n" {
            state.move(to: savedIndex)
            return nil
        }
        
        // Skip the space after #
        if let ch = state.current(), ch == " " {
            state.advance()
        }
        
        // Collect the heading text until end of line
        let headingStart = state.currentIndex
        while let ch = state.current(), ch != "\n" {
            state.advance()
        }
        
        let headingText = state.substring(from: headingStart, to: state.currentIndex)
        
        // Remove optional closing sequence of # and surrounding spaces without regex
        var finalText = headingText
        // Trim right spaces
        while finalText.last == " " { finalText.removeLast() }
        // Remove trailing #s
        var removedHashes = false
        while finalText.last == "#" { finalText.removeLast(); removedHashes = true }
        // If hashes were removed, trim any remaining trailing spaces
        if removedHashes {
            while finalText.last == " " { finalText.removeLast() }
        }
        
        // Generate ID from heading text (fast, non-regex slugifier)
        let headingId = ParsingHelpers.slugifyHeading(finalText)
        
        // Parse inline content
        var tempState = ParserState(text: finalText)
        let inlines = InlineParser.parseInlineElements(&tempState, configuration: configuration)
        
        // Advance past the newline
        if let ch = state.current(), ch == "\n" {
            state.advance()
        }
        
        return .heading(level: level, children: inlines, id: headingId.isEmpty ? nil : headingId)
    }
    
    static func parseFencedCodeBlock(_ state: inout ParserState) -> MarkdownParser.BlockNode? {
        let savedIndex = state.currentIndex
        
        // Check for ``` or ~~~
        guard let fenceChar = state.current(), (fenceChar == "`" || fenceChar == "~") else {
            return nil
        }
        
        // Count fence characters (minimum 3)
        var fenceLength = 0
        while let ch = state.current(), ch == fenceChar {
            state.advance()
            fenceLength += 1
        }
        
        guard fenceLength >= 3 else {
            state.move(to: savedIndex)
            return nil
        }
        
        // Extract language identifier
        var language: String? = nil
        if let ch = state.current(), ch != "\n" {
            let langStart = state.currentIndex
            while let c = state.current(), c != "\n" {
                state.advance()
            }
            language = state.substring(from: langStart, to: state.currentIndex).trimmingCharacters(in: .whitespaces)
            if language?.isEmpty == true {
                language = nil
            }
        }
        
        // Skip the newline after the opening fence
        if let ch = state.current(), ch == "\n" {
            state.advance()
        }
        
        // Collect code content until closing fence
        var codeLines: [String] = []
        var currentLine = ""
        
        while !state.isAtEnd {
            if let ch = state.current(), ch == "\n" {
                // Check if next line starts with closing fence
                let afterNewline = state.text.index(after: state.currentIndex)
                var temp = afterNewline
                var closeFenceLength = 0
                while temp < state.endIndex && state.text[temp] == fenceChar {
                    closeFenceLength += 1
                    temp = state.text.index(after: temp)
                }
                if closeFenceLength >= fenceLength {
                    // Found closing fence
                    if !currentLine.isEmpty {
                        codeLines.append(currentLine)
                    }
                    state.move(to: temp)
                    // Skip to end of line
                    while let c = state.current(), c != "\n" {
                        state.advance()
                    }
                    if let c = state.current(), c == "\n" {
                        state.advance() // Skip the newline
                    }
                    let code = codeLines.joined(separator: "\n")
                    return .codeBlock(language: language, content: code)
                }
                
                codeLines.append(currentLine)
                currentLine = ""
                state.advance()
            } else {
                if let ch2 = state.current() { currentLine.append(ch2) }
                state.advance()
            }
        }
        
        // If we reach here, the code block was not properly closed
        // Return what we have
        if !currentLine.isEmpty {
            codeLines.append(currentLine)
        }
        let code = codeLines.joined(separator: "\n")
        return .codeBlock(language: language, content: code)
    }
    
    static func parseIndentedCodeBlock(_ state: inout ParserState) -> MarkdownParser.BlockNode? {
        var codeLines: [String] = []
        
        while !state.isAtEnd {
            let lineStartIndex = state.currentIndex
            var spaces = 0
            
            // Count leading spaces
            while let ch = state.current(), ch == " ", spaces < 4 {
                spaces += 1
                state.advance()
            }
            
            if spaces < 4 {
                // Not enough indentation, end of code block
                state.move(to: lineStartIndex)
                break
            }
            
            // Collect the rest of the line
            var line = ""
            while let ch = state.current(), ch != "\n" {
                line.append(ch)
                state.advance()
            }
            
            codeLines.append(line)
            
            // Skip the newline
            if let ch = state.current(), ch == "\n" {
                state.advance()
            }
            
            // Check if next line is empty or continues the code block
            let nextLineStartIndex = state.currentIndex
            var nextSpaces = 0
            while let ch = state.current(), ch == " ", nextSpaces < 4 {
                nextSpaces += 1
                state.advance()
            }
            
            if let ch = state.current(), ch == "\n" {
                // Empty line, could be part of code block
                codeLines.append("")
                state.advance()
            } else if nextSpaces < 4 {
                // Not enough indentation, end of code block
                state.move(to: nextLineStartIndex)
                break
            } else {
                // Continue with next line
                state.move(to: nextLineStartIndex)
            }
        }
        
        if codeLines.isEmpty {
            return nil
        }
        
        return .codeBlock(language: nil, content: codeLines.joined(separator: "\n"))
    }
    
    static func parseBlockquote(_ state: inout ParserState, configuration: MarkdownConfiguration) -> MarkdownParser.BlockNode? {
        
        let savedIndex = state.currentIndex
        
        guard let first = state.current(), first == ">" else {
            return nil
        }
        
        var quoteLines: [String] = []
        
        while !state.isAtEnd {
            if let ch = state.current(), ch == ">" {
                state.advance()
                // Skip optional space after >
                if let c = state.current(), c == " " {
                    state.advance()
                }
                
                // Collect the line
                let lineStartIndex = state.currentIndex
                while let c2 = state.current(), c2 != "\n" {
                    state.advance()
                }
                quoteLines.append(state.substring(from: lineStartIndex, to: state.currentIndex))
                
                // Skip newline
                if let c3 = state.current(), c3 == "\n" {
                    state.advance()
                }
            } else if state.isAtEmptyLine() {
                // Empty line might end the blockquote
                break
            } else {
                // Lazy continuation line (part of blockquote without >)
                let lineStart = state.currentIndex
                while let c4 = state.current(), c4 != "\n" {
                    state.advance()
                }
                let line = state.substring(from: lineStart, to: state.currentIndex)
                
                // Check if this line starts a new block element
                if line.trimmingCharacters(in: .whitespaces).starts(with: "-") ||
                   line.trimmingCharacters(in: .whitespaces).starts(with: "*") ||
                   line.trimmingCharacters(in: .whitespaces).starts(with: "#") ||
                   line.contains(where: { $0 == "|" }) {
                    // This line starts a new block element, end blockquote
                    state.move(to: lineStart)
                    break
                }
                
                quoteLines.append(line)
                
                // Skip newline
                if let c5 = state.current(), c5 == "\n" {
                    state.advance()
                }
            }
        }
        
        if quoteLines.isEmpty {
            state.move(to: savedIndex)
            return nil
        }
        
        // Parse the content of the blockquote recursively
        let quoteContent = quoteLines.joined(separator: "\n")
        var quoteState = ParserState(text: quoteContent)
        let blocks = parseBlocks(&quoteState, configuration: configuration)
        
        return .blockquote(children: blocks)
    }
    
    static func parseList(_ state: inout ParserState, configuration: MarkdownConfiguration) -> MarkdownParser.BlockNode? {
        let savedIndex = state.currentIndex
        
        // Skip up to 3 spaces of indentation
        var indent = 0
        while let ch = state.current(), ch == " ", indent < 3 {
            state.advance()
            indent += 1
        }
        
        // Check for list marker
        
        var isOrdered = false
        var marker = ""
        
        if let char = state.current() {
            if char == "-" || char == "*" || char == "+" {
                marker = String(char)
                state.advance()
            } else if char.isNumber {
                // Check for ordered list
                while let d = state.current(), d.isNumber {
                    marker.append(d)
                    state.advance()
                }
                if let sep = state.current(), (sep == "." || sep == ")") {
                    marker.append(sep)
                    state.advance()
                    isOrdered = true
                } else {
                    state.move(to: savedIndex)
                    return nil
                }
            } else {
                state.move(to: savedIndex)
                return nil
            }
        } else {
            state.move(to: savedIndex)
            return nil
        }
        
        // Must be followed by space
        if state.isAtEnd || state.current() != " " {
            state.move(to: savedIndex)
            return nil
        }
        state.advance() // Skip the space
        
        var items: [MarkdownParser.ListItem] = []
        
        // Parse first item
        let firstItemContent = parseListItemContent(&state, indent: indent, marker: marker, configuration: configuration)
        items.append(firstItemContent)
        
        // Parse subsequent items
        while !state.isAtEnd {
            let itemPositionIndex = state.currentIndex
            
            // Skip indent
            var itemIndent = 0
            while let ch = state.current(), ch == " ", itemIndent < indent + 4 {
                state.advance()
                itemIndent += 1
            }
            
            // Check for list marker
            if let char = state.current() {
                var itemMarker = ""
                
                if isOrdered {
                    if char.isNumber {
                        while let d = state.current(), d.isNumber {
                            itemMarker.append(d)
                            state.advance()
                        }
                        if let sep = state.current(), (sep == "." || sep == ")") {
                            itemMarker.append(sep)
                            state.advance()
                        } else {
                            state.move(to: itemPositionIndex)
                            break
                        }
                    } else {
                        state.move(to: itemPositionIndex)
                        break
                    }
                } else {
                    if char == marker.first {
                        itemMarker = String(char)
                        state.advance()
                    } else {
                        state.move(to: itemPositionIndex)
                        break
                    }
                }
                
                // Must be followed by space
                if state.isAtEnd || state.current() != " " {
                    state.move(to: itemPositionIndex)
                    break
                }
                state.advance() // Skip the space
                
                let itemContent = parseListItemContent(&state, indent: itemIndent, marker: itemMarker, configuration: configuration)
                items.append(itemContent)
            } else {
                break
            }
        }
        
        return .list(ordered: isOrdered, tight: true, items: items)
    }
    
    private static func parseListItemContent(_ state: inout ParserState, indent: Int, marker: String, configuration: MarkdownConfiguration) -> MarkdownParser.ListItem {
        // Check for task list marker
        var isTask = false
        var isChecked = false
        
        if let c0 = state.current(), c0 == "[",
           let c1 = state.peek(1), (c1 == " " || c1 == "x" || c1 == "X"),
           let c2 = state.peek(2), c2 == "]",
           let c3 = state.peek(3), c3 == " " {
            isTask = true
            isChecked = (c1 != " ")
            state.advance(by: 4) // Skip [x] and space
        }
        
        // Collect item content
        var contentLines: [String] = []
        
        // First line of item
        let firstLineStart = state.currentIndex
        while let ch = state.current(), ch != "\n" {
            state.advance()
        }
        contentLines.append(state.substring(from: firstLineStart, to: state.currentIndex))
        
        if let ch = state.current(), ch == "\n" {
            state.advance()
        }
        
        // Continuation lines
        while !state.isAtEnd {
            let lineStartIndex = state.currentIndex
            
            // Check indentation
            var spaces = 0
            while let ch = state.current(), ch == " " {
                spaces += 1
                state.advance()
            }
            
            // Need at least marker width + 1 space of indentation for continuation
            let minIndent = marker.count + 1
            if spaces < minIndent {
                state.move(to: lineStartIndex)
                break
            }
            
            // Check if this is a new list item
            if spaces < indent + 4 {
                let char = state.current() ?? "\n"
                if char == "-" || char == "*" || char == "+" || char.isNumber {
                    state.move(to: lineStartIndex)
                    break
                }
            }
            
            // Collect the line
            while let ch = state.current(), ch != "\n" {
                state.advance()
            }
            
            let line = state.substring(from: lineStartIndex, to: state.currentIndex)
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                // Empty line might be part of the item or might end it
                contentLines.append("")
            } else {
                // Remove the indentation from continuation lines
                let trimmedLine = String(line.dropFirst(min(spaces, minIndent)))
                contentLines.append(trimmedLine)
            }
            
            if let ch = state.current(), ch == "\n" {
                state.advance()
            }
        }
        
        // Parse the content as blocks
        let content = contentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If content starts with # and appears to be a heading marker at the start of a list item,
        // treat it as literal text instead of a heading
        if !content.isEmpty && content.first == "#" {
            // Check if this looks like an ATX heading at the very start
            var hashCount = 0
            for char in content {
                if char == "#" {
                    hashCount += 1
                } else {
                    break
                }
            }
            
            // If we have 1-6 # followed by space at the very beginning of list item content,
            // and there's no blank line before it, treat as paragraph not heading
            if hashCount >= 1 && hashCount <= 6 && 
               content.count > hashCount && 
               content[content.index(content.startIndex, offsetBy: hashCount)] == " " &&
               contentLines.count == 1 {  // Single line, no blank line separation
                // Force it to be parsed as a paragraph
                let inlines = InlineParser.parseInlineOptimized(content, configuration: configuration)
                let blocks = [MarkdownParser.BlockNode.paragraph(children: inlines)]
                return MarkdownParser.ListItem(marker: marker, content: blocks, isTask: isTask, isChecked: isChecked)
            }
        }
        
        var contentState = ParserState(text: content)
        let blocks = parseBlocks(&contentState, configuration: configuration)
        
        return MarkdownParser.ListItem(marker: marker, content: blocks, isTask: isTask, isChecked: isChecked)
    }
    
    static func parseTable(_ state: inout ParserState, configuration: MarkdownConfiguration) -> MarkdownParser.BlockNode? {
        
        let savedIndex = state.currentIndex
        var lines: [String] = []

        // A table must start at the current line. Do not scan ahead.
        let headerStart = state.currentIndex
        while let ch = state.current(), ch != "\n" {
            state.advance()
        }
        let headerLine = state.substring(from: headerStart, to: state.currentIndex)
        guard headerLine.contains("|") else {
            state.move(to: savedIndex)
            return nil
        }

        lines.append(headerLine)

        // Require a separator line immediately after the header line.
        guard let ch = state.current(), ch == "\n" else {
            state.move(to: savedIndex)
            return nil
        }
        state.advance()

        let separatorStart = state.currentIndex
        while let ch = state.current(), ch != "\n" {
            state.advance()
        }
        let separatorLine = state.substring(from: separatorStart, to: state.currentIndex)
        guard separatorLine.contains("|") && separatorLine.contains("-") else {
            state.move(to: savedIndex)
            return nil
        }

        lines.append(separatorLine)

        if let ch = state.current(), ch == "\n" {
            state.advance()
        }

        // Collect contiguous table row lines.
        while !state.isAtEnd {
            let rowStart = state.currentIndex
            while let ch = state.current(), ch != "\n" {
                state.advance()
            }
            let rowLine = state.substring(from: rowStart, to: state.currentIndex)

            guard rowLine.contains("|") else {
                state.move(to: rowStart)
                break
            }

            lines.append(rowLine)

            if let ch = state.current(), ch == "\n" {
                state.advance()
            }
        }

        // Delegate validation/parsing to GFMExtensions.
        guard let (headers, rows, _) = GFMExtensions.parseTable(lines: lines, configuration: configuration) else {
            state.move(to: savedIndex)
            return nil
        }
        
        return .table(header: headers, rows: rows)
    }
    
    static func parseHorizontalRule(_ state: inout ParserState) -> MarkdownParser.BlockNode? {
        
        let savedIndex = state.currentIndex
        
        // Skip up to 3 spaces
        var spaces = 0
        while let ch = state.current(), ch == " ", spaces < 3 {
            state.advance()
            spaces += 1
        }
        
        guard !state.isAtEnd else {
            state.move(to: savedIndex)
            return nil
        }
        
        guard let char = state.current() else { state.move(to: savedIndex); return nil }
        guard char == "-" || char == "*" || char == "_" else {
            state.move(to: savedIndex)
            return nil
        }
        
        var count = 0
        let ruleChar = char
        
        while !state.isAtEnd {
            if let c = state.current(), c == ruleChar {
                count += 1
                state.advance()
            } else if state.current() == " " {
                state.advance()
            } else if state.current() == "\n" {
                break
            } else {
                // Other character, not a horizontal rule
                state.move(to: savedIndex)
                return nil
            }
        }
        
        // Need at least 3 characters
        guard count >= 3 else {
            state.move(to: savedIndex)
            return nil
        }
        
        // Skip the newline
        if state.current() == "\n" {
            state.advance()
        }
        
        return .horizontalRule
    }
    
    static func parseSetextHeading(_ state: inout ParserState, configuration: MarkdownConfiguration) -> MarkdownParser.BlockNode? {
        
        let savedIndex = state.currentIndex
        
        // First line is the heading text
        let headingStart = state.currentIndex
        while let ch = state.current(), ch != "\n" {
            state.advance()
        }
        
        let headingText = state.substring(from: headingStart, to: state.currentIndex)
        guard !headingText.trimmingCharacters(in: .whitespaces).isEmpty else {
            state.move(to: savedIndex)
            return nil
        }
        
        // Skip newline
        guard state.current() == "\n" else {
            state.move(to: savedIndex)
            return nil
        }
        state.advance()
        
        // Check for underline
        guard !state.isAtEnd else {
            state.move(to: savedIndex)
            return nil
        }
        
        guard let underlineChar = state.current() else { state.move(to: savedIndex); return nil }
        guard underlineChar == "=" || underlineChar == "-" else {
            state.move(to: savedIndex)
            return nil
        }
        
        // Count underline characters
        var underlineCount = 0
        while let ch = state.current(), ch == underlineChar {
            underlineCount += 1
            state.advance()
        }
        
        // Skip trailing spaces
        while state.current() == " " {
            state.advance()
        }
        
        // Must end with newline or end of text
        if let ch = state.current(), ch != "\n" {
            state.move(to: savedIndex)
            return nil
        }
        
        // Skip the newline
        if state.current() == "\n" {
            state.advance()
        }
        
        let level = underlineChar == "=" ? 1 : 2
        
        // Generate ID from heading text
        let trimmedText = headingText.trimmingCharacters(in: .whitespaces)
        let headingId = trimmedText.lowercased()
            .replacingOccurrences(of: #"[^\w\s-]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        
        // Parse inline content
        var tempState = ParserState(text: trimmedText)
        let inlines = InlineParser.parseInlineElements(&tempState, configuration: configuration)
        
        return .heading(level: level, children: inlines, id: headingId.isEmpty ? nil : headingId)
    }
    
    static func parseParagraph(_ state: inout ParserState, configuration: MarkdownConfiguration) -> MarkdownParser.BlockNode? {
        
        var lines: [String] = []
        
        while !state.isAtEnd {
            // Check if we're at a block boundary
            if isAtParagraphBreak(&state) {
                break
            }
            
            let lineStart = state.currentIndex
            while let ch = state.current(), ch != "\n" {
                state.advance()
            }
            
            let line = state.substring(from: lineStart, to: state.currentIndex)
            
            // For the first line, we've already determined this isn't a valid block start
            // (otherwise we wouldn't be in parseParagraph), so always include it
            if !lines.isEmpty {
                // Check if this line starts a new block element
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if isATXHeadingStart(trimmed) ||
                   trimmed.starts(with: ">") ||
                   trimmed.starts(with: "```") ||
                   trimmed.starts(with: "~~~") ||
                   trimmed.starts(with: "---") ||
                   trimmed.starts(with: "***") ||
                   trimmed.starts(with: "___") ||
                   isListMarker(trimmed) {
                    state.move(to: lineStart)
                    break
                }
            }
            
            lines.append(line)
            
            // Skip newline
            if state.current() == "\n" {
                state.advance()
            }
            
            // Check for empty line (paragraph break)
            if !state.isAtEnd && state.isAtEmptyLine() {
                break
            }
        }
        
        guard !lines.isEmpty else {
            return nil
        }
        
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }
        
        var tempState = ParserState(text: text)
        let inlines = InlineParser.parseInlineElements(&tempState, configuration: configuration)
        
        return .paragraph(children: inlines)
    }
    
    static func parseFootnoteDefinition(_ state: inout ParserState, configuration: MarkdownConfiguration) -> MarkdownParser.BlockNode? {
        
        let savedIndex = state.currentIndex
        
        // Check for [^
        guard let c0 = state.current(), c0 == "[",
              let c1 = state.peek(1), c1 == "^" else {
            return nil
        }
        
        state.advance(by: 2)
        
        // Collect label
        let labelStart = state.currentIndex
        while let ch = state.current(), ch != "]", ch != "\n" {
            state.advance()
        }
        
        guard state.current() == "]" else {
            state.move(to: savedIndex)
            return nil
        }
        
        let label = state.substring(from: labelStart, to: state.currentIndex)
        guard !label.isEmpty else {
            state.move(to: savedIndex)
            return nil
        }
        
        state.advance() // Skip ]
        
        // Must be followed by :
        guard state.current() == ":" else {
            state.move(to: savedIndex)
            return nil
        }
        state.advance() // Skip :
        
        // Skip optional space
        if state.current() == " " {
            state.advance()
        }
        
        // Collect footnote content (can be multiple lines)
        var contentLines: [String] = []
        
        // First line
        let firstLineStart = state.currentIndex
        while let ch = state.current(), ch != "\n" {
            state.advance()
        }
        contentLines.append(state.substring(from: firstLineStart, to: state.currentIndex))
        
        if state.current() == "\n" {
            state.advance()
        }
        
        // Continuation lines (must be indented with 4 spaces or a tab)
        while !state.isAtEnd {
            let lineStart = state.currentIndex
            var spaces = 0
            
            // Check indentation
            while let ch = state.current(), (ch == " " || ch == "\t") {
                if ch == "\t" {
                    spaces = 4 // Tab counts as 4 spaces
                    state.advance()
                    break
                } else {
                    spaces += 1
                    state.advance()
                }
                
                if spaces >= 4 {
                    break
                }
            }
            
            if spaces < 4 {
                // Not a continuation line
                state.move(to: lineStart)
                break
            }
            
            // Collect the line
            let contentStart = state.currentIndex
            while let ch = state.current(), ch != "\n" {
                state.advance()
            }
            
            let line = state.substring(from: contentStart, to: state.currentIndex)
            contentLines.append(line)
            
            if state.current() == "\n" {
                state.advance()
            }
        }
        
        // Parse the content
        let content = contentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        var contentState = ParserState(text: content)
        let blocks = parseBlocks(&contentState, configuration: configuration)
        
        return .footnoteDefinition(label: label, children: blocks)
    }
    
    // MARK: - Helper Methods
    
    private static func isAtParagraphBreak(_ state: inout ParserState) -> Bool {
        
        let mark = state.mark()
        defer { state.restore(mark) }
        
        // Check for empty line
        if state.isAtEmptyLine() {
            return true
        }
        
        // Check for block markers at current position
        // Skip leading spaces (up to 3)
        var spaces = 0
        while let ch = state.current(), ch == " ", spaces < 3 {
            state.advance()
            spaces += 1
        }
        
        guard !state.isAtEnd else {
            return true
        }
        
        guard let char = state.current() else { return true }
        
        // Check for block markers
        if char == ">" {
            return true
        }
        
        // For backticks and tildes, check if it's a code fence (3+ chars)
        if char == "`" || char == "~" {
            let fenceChar = char
            var fenceCount = 0
            var idx = state.currentIndex
            while idx < state.endIndex && state.text[idx] == fenceChar {
                fenceCount += 1
                idx = state.text.index(after: idx)
            }
            // Code fence requires at least 3 backticks/tildes
            return fenceCount >= 3
        }
        
        // For #, check if it's actually a heading
        if char == "#" {
            // Look ahead to see if this is a valid ATX heading
            var hashCount = 1
            var idx = state.text.index(after: state.currentIndex)
            while idx < state.endIndex && state.text[idx] == "#" && hashCount < 6 {
                hashCount += 1
                idx = state.text.index(after: idx)
            }
            // Valid heading must have space after # or be at end of line
            if idx >= state.endIndex || state.text[idx] == " " || state.text[idx] == "\n" {
                return true
            }
            // Not a valid heading, don't break paragraph
            return false
        }
        
        // Check for horizontal rule
        if char == "-" || char == "*" || char == "_" {
            
            var ruleCount = 0
            let ruleChar = char
            
            while !state.isAtEnd {
                if state.current() == ruleChar {
                    ruleCount += 1
                } else if state.current() != " " {
                    break
                }
                state.advance()
            }
            
            if ruleCount >= 3 && (state.isAtEnd || state.current() == "\n") {
                return true
            }
        }
        
        return false
    }
    
    private static func isATXHeadingStart(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        
        // Count leading # characters
        var hashCount = 0
        for char in trimmed {
            if char == "#" {
                hashCount += 1
            } else {
                break
            }
        }
        
        // Must have 1-6 # characters
        guard hashCount >= 1 && hashCount <= 6 else {
            return false
        }
        
        // After the # characters, must have space or be at end of line
        let afterHashIndex = trimmed.index(trimmed.startIndex, offsetBy: hashCount)
        if afterHashIndex < trimmed.endIndex {
            let nextChar = trimmed[afterHashIndex]
            return nextChar == " "
        }
        
        // Just # characters with nothing after is valid heading
        return true
    }
    
    private static func isListMarker(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        
        // Unordered list markers
        if trimmed.starts(with: "-") || trimmed.starts(with: "*") || trimmed.starts(with: "+") {
            return trimmed.count > 1 && trimmed.dropFirst().first == " "
        }
        
        // Ordered list markers
        if let firstChar = trimmed.first, firstChar.isNumber {
            var i = 0
            while i < trimmed.count && trimmed[trimmed.index(trimmed.startIndex, offsetBy: i)].isNumber {
                i += 1
            }
            if i < trimmed.count {
                let nextChar = trimmed[trimmed.index(trimmed.startIndex, offsetBy: i)]
                if nextChar == "." || nextChar == ")" {
                    return i + 1 < trimmed.count && trimmed[trimmed.index(trimmed.startIndex, offsetBy: i + 1)] == " "
                }
            }
        }
        
        return false
    }
}

// MARK: - Array Extension

private extension Array {
    subscript(safe index: Int) -> Element? {
        return index >= 0 && index < count ? self[index] : nil
    }
}

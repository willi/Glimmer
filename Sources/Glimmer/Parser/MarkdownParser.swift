import Foundation

// Type alias preserved for API clarity, refers to the shared parser state
typealias PublicParserState = ParserState

/// Enhanced Markdown Parser entry point
public struct MarkdownParser {
    
    // MARK: - Enhanced Block Parsing
    
    public static func parse(_ markdown: String, configuration: MarkdownConfiguration) -> [BlockNode] {
        // First pass: preprocess to handle inline footnotes
        let (processedMarkdown, inlineFootnoteDefinitions) = preprocessInlineFootnotes(markdown, configuration: configuration)
        
        // Regular preprocessing
        let preprocessedMarkdown = preprocessForParsing(processedMarkdown, configuration: configuration)

        // Parse blocks in a single pass using the shared state
        var state = PublicParserState(text: preprocessedMarkdown)
        var blocks = BlockParser.parseBlocks(&state, configuration: configuration)
        
        // Add inline footnote definitions at the end
        blocks.append(contentsOf: inlineFootnoteDefinitions)
        
        return blocks
    }

    /// Parse and return blocks along with their starting line numbers (1-based).
    public static func parseWithLocations(_ markdown: String, configuration: MarkdownConfiguration) -> [LocatedBlock] {
        // Handle inline footnotes & preprocessing same as parse()
        let (processedMarkdown, inlineFootnoteDefinitions) = preprocessInlineFootnotes(markdown, configuration: configuration)
        let preprocessedMarkdown = preprocessForParsing(processedMarkdown, configuration: configuration)

        var state = PublicParserState(text: preprocessedMarkdown)
        let located = BlockParser.parseBlocksLocated(&state, configuration: configuration)
        // For inline footnote definitions, we don’t have precise source lines; append with best-effort
        let trailing = inlineFootnoteDefinitions.map { LocatedBlock(node: $0, startLine: state.line) }
        return located + trailing
    }
    
    private static func preprocessInlineFootnotes(_ markdown: String, configuration: MarkdownConfiguration) -> (processed: String, definitions: [BlockNode]) {
        guard configuration.enableFootnotes else {
            return (markdown, [])
        }
        
        let matches = inlineFootnoteMatches(in: markdown)
        guard !matches.isEmpty else {
            return (markdown, [])
        }

        var processed = ""
        processed.reserveCapacity(markdown.count)
        var definitions = Array<BlockNode?>(repeating: nil, count: matches.count)
        var currentIndex = markdown.startIndex

        for (index, match) in matches.enumerated() {
            processed.append(contentsOf: markdown[currentIndex..<match.range.lowerBound])
            let label = "inline-\(matches.count - index)"
            processed.append("[^\(label)]")
            currentIndex = match.range.upperBound

            let inlineNodes = InlineParser.parseInlineElements(
                in: markdown,
                from: match.contentRange.lowerBound,
                to: match.contentRange.upperBound,
                configuration: configuration
            )
            definitions[matches.count - index - 1] = .footnoteDefinition(
                label: label,
                children: [.paragraph(children: inlineNodes)]
            )
        }

        processed.append(contentsOf: markdown[currentIndex...])
        return (processed, definitions.compactMap { $0 })
    }

    private struct InlineFootnoteMatch {
        let range: Range<String.Index>
        let contentRange: Range<String.Index>
    }

    private static func inlineFootnoteMatches(in markdown: String) -> [InlineFootnoteMatch] {
        var matches: [InlineFootnoteMatch] = []
        let utf8 = markdown.utf8
        var index = utf8.startIndex

        while let caret = utf8[index...].firstIndex(of: 0x5E) { // ^
            index = caret

            let openBracket = utf8.index(after: index)
            guard openBracket < utf8.endIndex, utf8[openBracket] == 0x5B else { // [
                index = openBracket
                continue
            }

            let contentStart = utf8.index(after: openBracket)
            var closeBracket = contentStart
            while closeBracket < utf8.endIndex, utf8[closeBracket] != 0x5D { // ]
                closeBracket = utf8.index(after: closeBracket)
            }

            guard closeBracket < utf8.endIndex, closeBracket > contentStart,
                  let matchStart = String.Index(index, within: markdown),
                  let contentLower = String.Index(contentStart, within: markdown),
                  let contentUpper = String.Index(closeBracket, within: markdown) else {
                index = contentStart
                continue
            }

            let afterClose = utf8.index(after: closeBracket)
            guard let matchEnd = String.Index(afterClose, within: markdown) else {
                break
            }

            matches.append(InlineFootnoteMatch(
                range: matchStart..<matchEnd,
                contentRange: contentLower..<contentUpper
            ))
            index = afterClose
        }

        return matches
    }

    public static func parse(_ markdown: String) -> [BlockNode] {
        return parse(markdown, configuration: .default)
    }
    
    public static func preprocess(_ markdown: String, configuration: MarkdownConfiguration = .default) -> String {
        var processedMarkdown = preprocessExtensions(markdown, configuration: configuration)

        if configuration.enableEmojiShortcodes {
            processedMarkdown = GitHubEmojis.processEmojiShortcodes(processedMarkdown)
        }

        return processedMarkdown
    }

    private static func preprocessForParsing(
        _ markdown: String,
        configuration: MarkdownConfiguration
    ) -> String {
        preprocessExtensions(markdown, configuration: configuration)
    }

    private static func preprocessExtensions(
        _ markdown: String,
        configuration: MarkdownConfiguration
    ) -> String {
        var processedMarkdown = markdown

        for markdownExtension in configuration.markdownExtensions {
            processedMarkdown = markdownExtension.preprocess(processedMarkdown)
        }
        
        return processedMarkdown
    }
    
    // Removed per-block state conversion; parsing now delegates directly to BlockParser
    
    
    // MARK: - Optimized Inline Parsing
    
    public static func parseInlineOptimized(_ text: String, configuration: MarkdownConfiguration = .default) -> [InlineNode] {
        // Delegate to InlineParser for consistent behavior
        return InlineParser.parseInlineOptimized(text, configuration: configuration)
    }
    
    
}

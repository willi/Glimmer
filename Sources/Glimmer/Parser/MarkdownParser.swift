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
        let preprocessedMarkdown = preprocess(processedMarkdown, configuration: configuration)

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
        let preprocessedMarkdown = preprocess(processedMarkdown, configuration: configuration)

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
        var processed = markdown
        var definitions: [BlockNode] = []
        var counter = 1
        
        // Find all inline footnotes ^[content]
        let regex = inlineFootnoteRegex
        
        let matches = regex.matches(in: markdown, options: [], range: NSRange(location: 0, length: markdown.utf16.count))
        
        // Process matches in reverse order to maintain string indices
        for match in matches.reversed() {
            guard let range = Range(match.range, in: markdown),
                  let contentRange = Range(match.range(at: 1), in: markdown) else {
                continue
            }
            
            let content = String(markdown[contentRange])
            let label = "inline-\(counter)"
            counter += 1
            
            // Replace ^[content] with [^inline-N]
            processed.replaceSubrange(range, with: "[^\(label)]")
            
            // Create footnote definition
            // Convert to public ParserState for InlineParser
            var publicState = PublicParserState(text: content)
            let inlineNodes = InlineParser.parseInlineElements(&publicState, configuration: configuration)
            definitions.append(.footnoteDefinition(label: label, children: [.paragraph(children: inlineNodes)]))
        }
        
        return (processed, definitions)
    }

    // Precompiled regex for inline footnotes to avoid recompilation overhead
    private static let inlineFootnoteRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\^\[([^\]]+)\]"#, options: [])
    }()

    public static func parse(_ markdown: String) -> [BlockNode] {
        return parse(markdown, configuration: .default)
    }
    
    public static func preprocess(_ markdown: String, configuration: MarkdownConfiguration = .default) -> String {
        var processedMarkdown = markdown

        for markdownExtension in configuration.markdownExtensions {
            processedMarkdown = markdownExtension.preprocess(processedMarkdown)
        }
        
        // Process emoji shortcodes if enabled.
        // A pre-scan guard (e.g. contains(":")) is slower than the regex no-match fast path.
        if configuration.enableEmojiShortcodes {
            processedMarkdown = GitHubEmojis.processEmojiShortcodes(processedMarkdown)
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

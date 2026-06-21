import Foundation

// Type alias preserved for API clarity, refers to the shared parser state
typealias PublicParserState = ParserState

/// Enhanced Markdown Parser entry point
public struct MarkdownParser {
    
    // MARK: - Enhanced Block Parsing
    
    public static func parse(_ markdown: String, configuration: MarkdownConfiguration) -> [BlockNode] {
        parse(markdown, configuration: configuration, reuseSourceASCIIFastPathForInlineRanges: true)
    }

    static func parseByScanningInlineRangeASCIIForTesting(
        _ markdown: String,
        configuration: MarkdownConfiguration
    ) -> [BlockNode] {
        parse(markdown, configuration: configuration, reuseSourceASCIIFastPathForInlineRanges: false)
    }

    static func parseByRescanningSourceASCIIAfterInlineFootnotePreprocessForTesting(
        _ markdown: String,
        configuration: MarkdownConfiguration
    ) -> [BlockNode] {
        parse(
            markdown,
            configuration: configuration,
            reuseSourceASCIIFastPathForInlineRanges: true,
            reuseInlineFootnoteSourceASCII: false
        )
    }

    static func parseByUTF8IndexInlineFootnoteScanForTesting(
        _ markdown: String,
        configuration: MarkdownConfiguration
    ) -> [BlockNode] {
        let inlineFootnotePreprocess = preprocessInlineFootnotes(
            markdown,
            configuration: configuration,
            useSinglePassMatcher: true,
            collectSourceASCII: true,
            useContiguousStorage: false
        )
        let preprocessedMarkdown = preprocessForParsing(inlineFootnotePreprocess.processed, configuration: configuration)

        let sourceASCIIFastPath = computedSourceASCIIFastPath(
            for: preprocessedMarkdown,
            configuration: configuration,
            inlineFootnoteSourceIsASCII: inlineFootnotePreprocess.sourceIsASCII
        )
        var state = PublicParserState(text: preprocessedMarkdown, sourceASCIIFastPath: sourceASCIIFastPath)
        var blocks = BlockParser.parseBlocks(&state, configuration: configuration)
        blocks.append(contentsOf: inlineFootnotePreprocess.definitions)

        return blocks
    }

    private static func parse(
        _ markdown: String,
        configuration: MarkdownConfiguration,
        reuseSourceASCIIFastPathForInlineRanges: Bool,
        reuseInlineFootnoteSourceASCII: Bool = true
    ) -> [BlockNode] {
        // First pass: preprocess to handle inline footnotes
        let inlineFootnotePreprocess = preprocessInlineFootnotes(
            markdown,
            configuration: configuration,
            collectSourceASCII: reuseInlineFootnoteSourceASCII && reuseSourceASCIIFastPathForInlineRanges
        )
        
        // Regular preprocessing
        let preprocessedMarkdown = preprocessForParsing(inlineFootnotePreprocess.processed, configuration: configuration)

        // Parse blocks in a single pass using the shared state
        let sourceASCIIFastPath = reuseSourceASCIIFastPathForInlineRanges
            ? computedSourceASCIIFastPath(
                for: preprocessedMarkdown,
                configuration: configuration,
                inlineFootnoteSourceIsASCII: inlineFootnotePreprocess.sourceIsASCII
            )
            : nil
        var state = PublicParserState(text: preprocessedMarkdown, sourceASCIIFastPath: sourceASCIIFastPath)
        var blocks = BlockParser.parseBlocks(&state, configuration: configuration)
        
        // Add inline footnote definitions at the end
        blocks.append(contentsOf: inlineFootnotePreprocess.definitions)
        
        return blocks
    }

    /// Parse and return blocks along with their starting line numbers (1-based).
    public static func parseWithLocations(_ markdown: String, configuration: MarkdownConfiguration) -> [LocatedBlock] {
        // Handle inline footnotes & preprocessing same as parse()
        let inlineFootnotePreprocess = preprocessInlineFootnotes(
            markdown,
            configuration: configuration,
            collectSourceASCII: true
        )
        let preprocessedMarkdown = preprocessForParsing(inlineFootnotePreprocess.processed, configuration: configuration)

        let sourceASCIIFastPath = computedSourceASCIIFastPath(
            for: preprocessedMarkdown,
            configuration: configuration,
            inlineFootnoteSourceIsASCII: inlineFootnotePreprocess.sourceIsASCII
        )
        var state = PublicParserState(text: preprocessedMarkdown, sourceASCIIFastPath: sourceASCIIFastPath)
        let located = BlockParser.parseBlocksLocated(&state, configuration: configuration)
        // For inline footnote definitions, we don’t have precise source lines; append with best-effort
        let trailing = inlineFootnotePreprocess.definitions.map { LocatedBlock(node: $0, startLine: state.line) }
        return located + trailing
    }

    static func parseByCaretSearchInlineFootnotePreprocessForTesting(
        _ markdown: String,
        configuration: MarkdownConfiguration
    ) -> [BlockNode] {
        let inlineFootnotePreprocess = preprocessInlineFootnotes(
            markdown,
            configuration: configuration,
            useSinglePassMatcher: false
        )
        let preprocessedMarkdown = preprocessForParsing(inlineFootnotePreprocess.processed, configuration: configuration)

        var state = PublicParserState(text: preprocessedMarkdown)
        var blocks = BlockParser.parseBlocks(&state, configuration: configuration)
        blocks.append(contentsOf: inlineFootnotePreprocess.definitions)

        return blocks
    }

    static func inlineFootnoteMatchCountForTesting(_ markdown: String, singlePass: Bool) -> Int {
        if singlePass {
            return inlineFootnoteScan(in: markdown, collectSourceASCII: false).matches.count
        }
        return inlineFootnoteMatchesByCaretSearch(in: markdown).matches.count
    }

    static func inlineFootnoteScanSourceASCIIChecksumForTesting(
        _ markdown: String,
        reuseScanASCII: Bool,
        useContiguousStorage: Bool = true
    ) -> Int {
        let scan = useContiguousStorage
            ? inlineFootnoteScan(in: markdown, collectSourceASCII: reuseScanASCII)
            : inlineFootnoteScanByUTF8Index(in: markdown, collectSourceASCII: reuseScanASCII)
        let sourceIsASCII = reuseScanASCII
            ? scan.sourceIsASCII == true
            : ParsingHelpers.isASCII(markdown)
        return scan.matches.count &+ markdown.utf8.count &+ (sourceIsASCII ? 1 : 0)
    }
    
    private static func preprocessInlineFootnotes(
        _ markdown: String,
        configuration: MarkdownConfiguration,
        collectSourceASCII: Bool = false
    ) -> InlineFootnotePreprocessResult {
        preprocessInlineFootnotes(
            markdown,
            configuration: configuration,
            useSinglePassMatcher: true,
            collectSourceASCII: collectSourceASCII
        )
    }

    private static func preprocessInlineFootnotes(
        _ markdown: String,
        configuration: MarkdownConfiguration,
        useSinglePassMatcher: Bool,
        collectSourceASCII: Bool = false,
        useContiguousStorage: Bool = true
    ) -> InlineFootnotePreprocessResult {
        guard configuration.enableFootnotes else {
            return InlineFootnotePreprocessResult(processed: markdown, definitions: [], sourceIsASCII: nil)
        }
        
        let scan: InlineFootnoteScan
        if useSinglePassMatcher {
            scan = useContiguousStorage
                ? inlineFootnoteScan(in: markdown, collectSourceASCII: collectSourceASCII)
                : inlineFootnoteScanByUTF8Index(in: markdown, collectSourceASCII: collectSourceASCII)
        } else {
            scan = inlineFootnoteMatchesByCaretSearch(in: markdown)
        }
        let matches = scan.matches
        guard !matches.isEmpty else {
            return InlineFootnotePreprocessResult(processed: markdown, definitions: [], sourceIsASCII: scan.sourceIsASCII)
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
        return InlineFootnotePreprocessResult(
            processed: processed,
            definitions: definitions.compactMap { $0 },
            sourceIsASCII: scan.sourceIsASCII
        )
    }

    private static func computedSourceASCIIFastPath(
        for preprocessedMarkdown: String,
        configuration: MarkdownConfiguration,
        inlineFootnoteSourceIsASCII: Bool?
    ) -> Bool {
        guard configuration.markdownExtensions.isEmpty,
              let inlineFootnoteSourceIsASCII else {
            return ParsingHelpers.isASCII(preprocessedMarkdown)
        }

        return inlineFootnoteSourceIsASCII
    }

    private struct InlineFootnotePreprocessResult {
        let processed: String
        let definitions: [BlockNode]
        let sourceIsASCII: Bool?
    }

    private struct InlineFootnoteMatch {
        let range: Range<String.Index>
        let contentRange: Range<String.Index>
    }

    private struct InlineFootnoteScan {
        let matches: [InlineFootnoteMatch]
        let sourceIsASCII: Bool?
    }

    private static func inlineFootnoteScan(
        in markdown: String,
        collectSourceASCII: Bool
    ) -> InlineFootnoteScan {
        if let scan = markdown.utf8.withContiguousStorageIfAvailable({ bytes in
            inlineFootnoteScan(in: markdown, bytes: bytes, collectSourceASCII: collectSourceASCII)
        }) {
            return scan
        }

        return inlineFootnoteScanByUTF8Index(in: markdown, collectSourceASCII: collectSourceASCII)
    }

    private static func inlineFootnoteScan(
        in markdown: String,
        bytes: UnsafeBufferPointer<UInt8>,
        collectSourceASCII: Bool
    ) -> InlineFootnoteScan {
        var matches: [InlineFootnoteMatch] = []
        let utf8 = markdown.utf8
        var offset = bytes.startIndex
        let end = bytes.endIndex
        var sourceIsASCII = true

        while offset < end {
            let byte = bytes[offset]
            if collectSourceASCII, byte >= 0x80 {
                sourceIsASCII = false
            }
            guard byte == 0x5E else { // ^
                offset += 1
                continue
            }

            let openBracketOffset = offset + 1
            guard openBracketOffset < end, bytes[openBracketOffset] == 0x5B else { // [
                offset = openBracketOffset
                continue
            }

            let contentStartOffset = openBracketOffset + 1
            var closeBracketOffset = contentStartOffset
            while closeBracketOffset < end, bytes[closeBracketOffset] != 0x5D { // ]
                if collectSourceASCII, bytes[closeBracketOffset] >= 0x80 {
                    sourceIsASCII = false
                }
                closeBracketOffset += 1
            }

            guard closeBracketOffset < end, closeBracketOffset > contentStartOffset else {
                offset = contentStartOffset
                continue
            }

            let afterCloseOffset = closeBracketOffset + 1
            let matchStartUTF8 = utf8.index(utf8.startIndex, offsetBy: offset)
            let contentLowerUTF8 = utf8.index(matchStartUTF8, offsetBy: contentStartOffset - offset)
            let contentUpperUTF8 = utf8.index(contentLowerUTF8, offsetBy: closeBracketOffset - contentStartOffset)
            let matchEndUTF8 = utf8.index(contentUpperUTF8, offsetBy: afterCloseOffset - closeBracketOffset)

            guard let matchStart = String.Index(matchStartUTF8, within: markdown),
                  let contentLower = String.Index(contentLowerUTF8, within: markdown),
                  let contentUpper = String.Index(contentUpperUTF8, within: markdown),
                  let matchEnd = String.Index(matchEndUTF8, within: markdown) else {
                break
            }

            matches.append(InlineFootnoteMatch(
                range: matchStart..<matchEnd,
                contentRange: contentLower..<contentUpper
            ))
            offset = afterCloseOffset
        }

        return InlineFootnoteScan(
            matches: matches,
            sourceIsASCII: collectSourceASCII ? sourceIsASCII : nil
        )
    }

    private static func inlineFootnoteScanByUTF8Index(
        in markdown: String,
        collectSourceASCII: Bool
    ) -> InlineFootnoteScan {
        var matches: [InlineFootnoteMatch] = []
        let utf8 = markdown.utf8
        var index = utf8.startIndex
        var sourceIsASCII = true

        while index < utf8.endIndex {
            let byte = utf8[index]
            if collectSourceASCII, byte >= 0x80 {
                sourceIsASCII = false
            }
            guard byte == 0x5E else { // ^
                index = utf8.index(after: index)
                continue
            }

            let openBracket = utf8.index(after: index)
            guard openBracket < utf8.endIndex, utf8[openBracket] == 0x5B else { // [
                index = openBracket
                continue
            }
            if collectSourceASCII, utf8[openBracket] >= 0x80 {
                sourceIsASCII = false
            }

            let contentStart = utf8.index(after: openBracket)
            var closeBracket = contentStart
            while closeBracket < utf8.endIndex, utf8[closeBracket] != 0x5D { // ]
                if collectSourceASCII, utf8[closeBracket] >= 0x80 {
                    sourceIsASCII = false
                }
                closeBracket = utf8.index(after: closeBracket)
            }

            guard closeBracket < utf8.endIndex, closeBracket > contentStart,
                  let matchStart = String.Index(index, within: markdown),
                  let contentLower = String.Index(contentStart, within: markdown),
                  let contentUpper = String.Index(closeBracket, within: markdown) else {
                index = contentStart
                continue
            }
            if collectSourceASCII, utf8[closeBracket] >= 0x80 {
                sourceIsASCII = false
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

        return InlineFootnoteScan(
            matches: matches,
            sourceIsASCII: collectSourceASCII ? sourceIsASCII : nil
        )
    }

    private static func inlineFootnoteMatchesByCaretSearch(in markdown: String) -> InlineFootnoteScan {
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

        return InlineFootnoteScan(matches: matches, sourceIsASCII: nil)
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

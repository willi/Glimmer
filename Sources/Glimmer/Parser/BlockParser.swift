import Foundation

/// Handles parsing of block-level markdown elements
public struct BlockParser {
    private struct TableStartProbe {
        let headerRange: Range<String.Index>
        let separatorRange: Range<String.Index>
        let afterSeparatorLine: String.Index
        let lineBreaksToAfterSeparatorLine: Int
        let columnAfterSeparatorLine: Int
    }

    private struct SetextHeadingProbe {
        let headingRange: Range<String.Index>
        let level: Int
        let afterUnderlineLine: String.Index
        let lineBreaksToAfterUnderlineLine: Int
        let columnAfterUnderlineLine: Int
    }

    private enum ProbeEligibility: Equatable {
        case attempt
        case skip
        case unknown
    }

    private enum ParagraphStartProbeMode {
        case shared
        case gated
        case always
    }

    private struct ParagraphStartProbeEligibility {
        let table: ProbeEligibility
        let setextHeading: ProbeEligibility

        static let unknown = ParagraphStartProbeEligibility(table: .unknown, setextHeading: .unknown)
    }

    private struct ParagraphStartProbes {
        let tableStart: TableStartProbe?
        let setextHeading: SetextHeadingProbe?

        static let none = ParagraphStartProbes(tableStart: nil, setextHeading: nil)
    }

    private struct ParagraphContinuationLineScan {
        let lineEnd: String.Index
        let columnAdvance: Int
        let startsParagraphBreakingBlock: Bool
    }

    private struct ListMarkerParse {
        let marker: String
        let isOrdered: Bool
    }

    private struct TableRowLineScan {
        let range: Range<String.Index>
        let columnAdvance: Int
        let containsPipe: Bool
    }

    private struct ASCIIListMarkerProbe {
        let marker: String
        let isOrdered: Bool
        let start: String.UTF8View.Index
        let contentStart: String.UTF8View.Index
        let stringContentStart: String.Index
    }

    
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
        parseBlock(&state, configuration: configuration, paragraphStartProbeMode: .shared)
    }

    static func parseBlockByAlwaysProbingParagraphStartForTesting(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.BlockNode? {
        parseBlock(&state, configuration: configuration, paragraphStartProbeMode: .always)
    }

    static func parseBlockBySeparateParagraphStartProbesForTesting(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.BlockNode? {
        parseBlock(&state, configuration: configuration, paragraphStartProbeMode: .gated)
    }

    private static func parseBlock(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration,
        paragraphStartProbeMode: ParagraphStartProbeMode
    ) -> MarkdownParser.BlockNode? {
        
        let savedIndex = state.currentIndex
        guard !state.isAtEmptyLine() else {
            return nil
        }
        
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
        
        let blockStart = state.current()

        // Try parsing different block types
        if blockStart == "#",
           let heading = parseATXHeading(&state, configuration: configuration) {
            return heading
        }

        if (blockStart == "`" || blockStart == "~"),
           let codeBlock = parseFencedCodeBlock(&state) {
            return codeBlock
        }

        if blockStart == ">",
           let blockquote = parseBlockquote(&state, configuration: configuration) {
            return blockquote
        }

        if shouldAttemptListMarker(blockStart),
           let list = parseList(&state, configuration: configuration) {
            return list
        }

        let paragraphStartProbes = paragraphStartProbes(state, mode: paragraphStartProbeMode)

        if let tableStart = paragraphStartProbes.tableStart {
            if let table = parseTable(&state, configuration: configuration, startProbe: tableStart) {
                return table
            }
        }
        
        if shouldAttemptHorizontalRule(blockStart),
           let hr = parseHorizontalRule(&state) {
            return hr
        }

        if let setextProbe = paragraphStartProbes.setextHeading {
            if let setextHeading = parseSetextHeading(&state, configuration: configuration, probe: setextProbe) {
                return setextHeading
            }
        }
        
        if configuration.enableFootnotes {
            if shouldAttemptFootnoteDefinition(state),
               let footnote = parseFootnoteDefinition(&state, configuration: configuration) {
                return footnote
            }
        }
        
        // Default to paragraph
        state.move(to: savedIndex)
        return parseParagraph(&state, configuration: configuration, skipKnownFirstParagraphBreak: true)
    }
    
    // MARK: - Specific Block Parsers
    
    static func parseATXHeading(_ state: inout ParserState, configuration: MarkdownConfiguration) -> MarkdownParser.BlockNode? {
        if let heading = parseATXHeadingByUTF8Scanning(&state, configuration: configuration) {
            return heading
        }

        return parseATXHeadingByCharacterScanning(&state, configuration: configuration)
    }

    static func parseATXHeadingByCharacterScanningForTesting(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.BlockNode? {
        parseATXHeadingByCharacterScanning(&state, configuration: configuration)
    }

    private static func parseATXHeadingByCharacterScanning(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.BlockNode? {
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
        
        // Remove optional closing sequence of # and surrounding spaces without regex
        var finalEnd = state.currentIndex
        while finalEnd > headingStart {
            let previous = state.text.index(before: finalEnd)
            guard state.text[previous] == " " else { break }
            finalEnd = previous
        }

        // Remove trailing #s
        var removedHashes = false
        while finalEnd > headingStart {
            let previous = state.text.index(before: finalEnd)
            guard state.text[previous] == "#" else { break }
            finalEnd = previous
            removedHashes = true
        }

        // If hashes were removed, trim any remaining trailing spaces
        if removedHashes {
            while finalEnd > headingStart {
                let previous = state.text.index(before: finalEnd)
                guard state.text[previous] == " " else { break }
                finalEnd = previous
            }
        }

        let headingRange = headingStart..<finalEnd
        
        // Generate ID from heading text (fast, non-regex slugifier)
        let headingId = ParsingHelpers.slugifyHeading(in: state.text, range: headingRange)
        
        // Parse inline content
        let inlines = InlineParser.parseInlineElements(
            in: state.text,
            from: headingRange.lowerBound,
            to: headingRange.upperBound,
            configuration: configuration
        )
        
        // Advance past the newline
        if let ch = state.current(), ch == "\n" {
            state.advance()
        }
        
        return .heading(level: level, children: inlines, id: headingId.isEmpty ? nil : headingId)
    }

    private static func parseATXHeadingByUTF8Scanning(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.BlockNode? {
        guard let start = state.currentIndex.samePosition(in: state.text.utf8),
              let end = state.endIndex.samePosition(in: state.text.utf8) else {
            return nil
        }

        let utf8 = state.text.utf8
        var index = start
        var level = 0
        while index < end, utf8[index] == 0x23, level < 6 { // #
            level += 1
            index = utf8.index(after: index)
        }

        guard level > 0 else {
            return nil
        }

        if index < end {
            let byte = utf8[index]
            guard byte == 0x20 || byte == 0x0A else { // space, newline
                return nil
            }
        }

        if index < end, utf8[index] == 0x20 { // space
            index = utf8.index(after: index)
        }

        let headingStart = index
        while index < end {
            let byte = utf8[index]
            if byte == 0x0A { // newline
                break
            }
            if byte >= 0x80 {
                return nil
            }
            index = utf8.index(after: index)
        }

        let lineEnd = index
        var finalEnd = lineEnd
        while finalEnd > headingStart {
            let previous = utf8.index(before: finalEnd)
            guard utf8[previous] == 0x20 else { break } // space
            finalEnd = previous
        }

        var removedHashes = false
        while finalEnd > headingStart {
            let previous = utf8.index(before: finalEnd)
            guard utf8[previous] == 0x23 else { break } // #
            finalEnd = previous
            removedHashes = true
        }

        if removedHashes {
            while finalEnd > headingStart {
                let previous = utf8.index(before: finalEnd)
                guard utf8[previous] == 0x20 else { break } // space
                finalEnd = previous
            }
        }

        guard let headingStringStart = String.Index(headingStart, within: state.text),
              let headingStringEnd = String.Index(finalEnd, within: state.text),
              let lineEndStringIndex = String.Index(lineEnd, within: state.text) else {
            return nil
        }

        let headingRange = headingStringStart..<headingStringEnd
        let headingId = ParsingHelpers.slugifyHeading(in: state.text, range: headingRange)
        let inlines = InlineParser.parseInlineElements(
            in: state.text,
            from: headingRange.lowerBound,
            to: headingRange.upperBound,
            configuration: configuration
        )

        if lineEnd < end, utf8[lineEnd] == 0x0A { // newline
            state.currentIndex = utf8.index(after: lineEnd)
            state.line += 1
            state.column = 1
        } else {
            state.currentIndex = lineEndStringIndex
            state.column += utf8.distance(from: start, to: lineEnd)
        }

        return .heading(level: level, children: inlines, id: headingId.isEmpty ? nil : headingId)
    }
    
    static func parseFencedCodeBlock(_ state: inout ParserState) -> MarkdownParser.BlockNode? {
        if let codeBlock = parseFencedCodeBlockByUTF8Scanning(&state) {
            return codeBlock
        }

        return parseFencedCodeBlockByCharacterScanning(&state)
    }

    static func parseFencedCodeBlockByCharacterScanningForTesting(
        _ state: inout ParserState
    ) -> MarkdownParser.BlockNode? {
        parseFencedCodeBlockByCharacterScanning(&state)
    }

    private static func parseFencedCodeBlockByCharacterScanning(
        _ state: inout ParserState
    ) -> MarkdownParser.BlockNode? {
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
            state.advanceToLineEnd()
            language = state.substring(from: langStart, to: state.currentIndex).trimmingCharacters(in: .whitespaces)
            if language?.isEmpty == true {
                language = nil
            }
        }
        
        // Skip the newline after the opening fence
        if let ch = state.current(), ch == "\n" {
            state.advance()
        }
        
        // Collect code content until closing fence.
        let contentStart = state.currentIndex
        var contentEnd = contentStart
        
        while !state.isAtEnd {
            state.advanceToLineEnd()

            contentEnd = state.currentIndex

            if let ch = state.current(), ch == "\n" {
                // Check if next line starts with closing fence.
                let afterNewline = state.text.index(after: state.currentIndex)
                if let closingFenceEnd = closingFenceEnd(
                    in: state.text,
                    from: afterNewline,
                    fenceChar: fenceChar,
                    fenceLength: fenceLength
                ) {
                    // Found closing fence
                    let code = String(state.text[contentStart..<contentEnd])
                    state.move(to: closingFenceEnd)
                    // Skip to end of line
                    state.advanceToLineEnd()
                    if let c = state.current(), c == "\n" {
                        state.advance() // Skip the newline
                    }
                    return .codeBlock(language: language, content: code)
                }
                
                state.advance()
            } else {
                break
            }
        }
        
        // If we reach here, the code block was not properly closed
        // Return what we have
        let code = String(state.text[contentStart..<contentEnd])
        return .codeBlock(language: language, content: code)
    }

    private static func parseFencedCodeBlockByUTF8Scanning(
        _ state: inout ParserState
    ) -> MarkdownParser.BlockNode? {
        guard let start = state.currentIndex.samePosition(in: state.text.utf8),
              let end = state.endIndex.samePosition(in: state.text.utf8) else {
            return nil
        }

        let utf8 = state.text.utf8
        guard start < end else {
            return nil
        }

        let fence = utf8[start]
        guard fence == 0x60 || fence == 0x7E else { // ` ~
            return nil
        }

        var index = start
        var fenceLength = 0
        while index < end, utf8[index] == fence {
            fenceLength += 1
            index = utf8.index(after: index)
        }

        guard fenceLength >= 3 else {
            return nil
        }

        let languageStart = index
        while index < end {
            let byte = utf8[index]
            if byte == 0x0A { // newline
                break
            }
            if byte >= 0x80 {
                return nil
            }
            index = utf8.index(after: index)
        }

        var language: String?
        if languageStart < index {
            guard let stringLanguageStart = String.Index(languageStart, within: state.text),
                  let stringLanguageEnd = String.Index(index, within: state.text) else {
                return nil
            }
            language = String(state.text[stringLanguageStart..<stringLanguageEnd]).trimmingCharacters(in: .whitespaces)
            if language?.isEmpty == true {
                language = nil
            }
        }

        if index < end, utf8[index] == 0x0A { // newline
            index = utf8.index(after: index)
        }

        let contentStart = index
        var contentEnd = contentStart
        var finalIndex = index

        while index < end {
            var lineEnd = index
            while lineEnd < end {
                let byte = utf8[lineEnd]
                if byte == 0x0A { // newline
                    break
                }
                if byte >= 0x80 {
                    return nil
                }
                lineEnd = utf8.index(after: lineEnd)
            }

            contentEnd = lineEnd
            if lineEnd < end, utf8[lineEnd] == 0x0A {
                let nextLineStart = utf8.index(after: lineEnd)
                if let closingFenceEnd = closingFenceEnd(in: utf8, from: nextLineStart, end: end, fence: fence, fenceLength: fenceLength) {
                    var afterClosingLine = closingFenceEnd
                    while afterClosingLine < end {
                        let byte = utf8[afterClosingLine]
                        if byte == 0x0A { // newline
                            break
                        }
                        if byte >= 0x80 {
                            return nil
                        }
                        afterClosingLine = utf8.index(after: afterClosingLine)
                    }

                    finalIndex = afterClosingLine
                    if finalIndex < end, utf8[finalIndex] == 0x0A {
                        finalIndex = utf8.index(after: finalIndex)
                    }
                    return finishFencedCodeBlockUTF8(
                        state: &state,
                        start: start,
                        finalIndex: finalIndex,
                        contentStart: contentStart,
                        contentEnd: contentEnd,
                        language: language
                    )
                }

                index = nextLineStart
                finalIndex = index
            } else {
                finalIndex = lineEnd
                break
            }
        }

        return finishFencedCodeBlockUTF8(
            state: &state,
            start: start,
            finalIndex: finalIndex,
            contentStart: contentStart,
            contentEnd: contentEnd,
            language: language
        )
    }

    private static func finishFencedCodeBlockUTF8(
        state: inout ParserState,
        start: String.UTF8View.Index,
        finalIndex: String.UTF8View.Index,
        contentStart: String.UTF8View.Index,
        contentEnd: String.UTF8View.Index,
        language: String?
    ) -> MarkdownParser.BlockNode? {
        guard let stringContentStart = String.Index(contentStart, within: state.text),
              let stringContentEnd = String.Index(contentEnd, within: state.text),
              let stringFinalIndex = String.Index(finalIndex, within: state.text) else {
            return nil
        }

        let code = String(state.text[stringContentStart..<stringContentEnd])
        moveASCIIState(&state, from: start, to: finalIndex, stringFinalIndex: stringFinalIndex)
        return .codeBlock(language: language, content: code)
    }

    private static func moveASCIIState(
        _ state: inout ParserState,
        from start: String.UTF8View.Index,
        to end: String.UTF8View.Index,
        stringFinalIndex: String.Index
    ) {
        let utf8 = state.text.utf8
        var index = start
        var lineBreaks = 0
        var bytesAfterLastLineBreak = 0
        var consumedBytes = 0

        while index < end {
            let byte = utf8[index]
            consumedBytes += 1
            if byte == 0x0A {
                lineBreaks += 1
                bytesAfterLastLineBreak = 0
            } else {
                bytesAfterLastLineBreak += 1
            }
            index = utf8.index(after: index)
        }

        if lineBreaks == 0 {
            state.column += consumedBytes
        } else {
            state.line += lineBreaks
            state.column = bytesAfterLastLineBreak + 1
        }
        state.currentIndex = stringFinalIndex
    }
    
    static func parseIndentedCodeBlock(_ state: inout ParserState) -> MarkdownParser.BlockNode? {
        if let codeBlock = parseIndentedCodeBlockByUTF8Scanning(&state) {
            return codeBlock
        }

        return parseIndentedCodeBlockByCharacterScanning(&state)
    }

    static func parseIndentedCodeBlockByCharacterScanningForTesting(
        _ state: inout ParserState
    ) -> MarkdownParser.BlockNode? {
        parseIndentedCodeBlockByCharacterScanning(&state)
    }

    private static func parseIndentedCodeBlockByCharacterScanning(
        _ state: inout ParserState
    ) -> MarkdownParser.BlockNode? {
        var code = ""
        code.reserveCapacity(256)
        var appendedLine = false
        
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
            let contentStart = state.currentIndex
            while let ch = state.current(), ch != "\n" {
                state.advance()
            }
            
            appendCodeLine(state.text[contentStart..<state.currentIndex], to: &code, appendedLine: &appendedLine)
            
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
                appendEmptyCodeLine(to: &code, appendedLine: &appendedLine)
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
        
        if !appendedLine {
            return nil
        }
        
        return .codeBlock(language: nil, content: code)
    }

    private static func parseIndentedCodeBlockByUTF8Scanning(
        _ state: inout ParserState
    ) -> MarkdownParser.BlockNode? {
        guard let start = state.currentIndex.samePosition(in: state.text.utf8),
              let end = state.endIndex.samePosition(in: state.text.utf8) else {
            return nil
        }

        let utf8 = state.text.utf8
        var index = start
        var finalIndex = start
        var code = ""
        code.reserveCapacity(256)
        var appendedLine = false

        while index < end {
            let lineStart = index
            var spaces = 0
            while index < end, utf8[index] == 0x20, spaces < 4 { // space
                spaces += 1
                index = utf8.index(after: index)
            }

            if spaces < 4 {
                finalIndex = lineStart
                break
            }

            let contentStart = index
            while index < end {
                let byte = utf8[index]
                if byte == 0x0A { // newline
                    break
                }
                if byte >= 0x80 {
                    return nil
                }
                index = utf8.index(after: index)
            }

            guard let stringContentStart = String.Index(contentStart, within: state.text),
                  let stringContentEnd = String.Index(index, within: state.text) else {
                return nil
            }
            appendCodeLine(state.text[stringContentStart..<stringContentEnd], to: &code, appendedLine: &appendedLine)

            if index < end, utf8[index] == 0x0A { // newline
                index = utf8.index(after: index)
            }
            finalIndex = index

            let nextLineStart = index
            var lookahead = index
            var nextSpaces = 0
            while lookahead < end, utf8[lookahead] == 0x20, nextSpaces < 4 { // space
                nextSpaces += 1
                lookahead = utf8.index(after: lookahead)
            }

            if lookahead < end, utf8[lookahead] == 0x0A { // newline
                appendEmptyCodeLine(to: &code, appendedLine: &appendedLine)
                index = utf8.index(after: lookahead)
                finalIndex = index
            } else if nextSpaces < 4 {
                finalIndex = nextLineStart
                break
            } else {
                index = nextLineStart
                finalIndex = nextLineStart
            }
        }

        guard appendedLine,
              let stringFinalIndex = String.Index(finalIndex, within: state.text) else {
            return nil
        }

        moveASCIIState(&state, from: start, to: finalIndex, stringFinalIndex: stringFinalIndex)
        return .codeBlock(language: nil, content: code)
    }
    
    static func parseBlockquote(_ state: inout ParserState, configuration: MarkdownConfiguration) -> MarkdownParser.BlockNode? {
        parseBlockquote(
            &state,
            configuration: configuration,
            useParagraphFastPath: true,
            useSingleRangeParagraphFastPath: true,
            useSingleRangeRecursiveFastPath: true,
            usePlainTextParagraphFastPath: true
        )
    }

    static func parseBlockquoteByRecursivelyParsingJoinedContentForTesting(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.BlockNode? {
        parseBlockquote(
            &state,
            configuration: configuration,
            useParagraphFastPath: false,
            useSingleRangeParagraphFastPath: false,
            useSingleRangeRecursiveFastPath: false,
            usePlainTextParagraphFastPath: false
        )
    }

    static func parseBlockquoteByJoiningSingleParagraphsForTesting(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.BlockNode? {
        parseBlockquote(
            &state,
            configuration: configuration,
            useParagraphFastPath: true,
            useSingleRangeParagraphFastPath: false,
            useSingleRangeRecursiveFastPath: true,
            usePlainTextParagraphFastPath: false
        )
    }

    private static func parseBlockquote(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration,
        useParagraphFastPath: Bool,
        useSingleRangeParagraphFastPath: Bool,
        useSingleRangeRecursiveFastPath: Bool,
        usePlainTextParagraphFastPath: Bool
    ) -> MarkdownParser.BlockNode? {
        let savedIndex = state.currentIndex
        
        guard let first = state.current(), first == ">" else {
            return nil
        }
        
        var quoteLineRanges: [Range<String.Index>] = []
        var quoteLineUTF8Count = 0
        var canUseParagraphFastPath = true
        var currentParagraphHasContent = false
        
        while !state.isAtEnd {
            if let ch = state.current(), ch == ">" {
                state.advance()
                // Skip optional space after >
                if let c = state.current(), c == " " {
                    state.advance()
                }
                
                // Collect the line
                let lineStartIndex = state.currentIndex
                state.advanceToLineEnd()
                quoteLineRanges.append(lineStartIndex..<state.currentIndex)
                quoteLineUTF8Count += state.text.utf8.distance(from: lineStartIndex, to: state.currentIndex)

                let lineRange = lineStartIndex..<state.currentIndex
                if isBlankLine(in: state.text, range: lineRange) {
                    currentParagraphHasContent = false
                } else {
                    canUseParagraphFastPath = canUseParagraphFastPath &&
                        !lineStartsBlockParserCandidate(
                            in: state.text,
                            range: lineRange,
                            isFirstLine: !currentParagraphHasContent
                        )
                    currentParagraphHasContent = true
                }
                
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
                state.advanceToLineEnd()
                let lineRange = lineStart..<state.currentIndex

                // Check if this line starts a new block element
                if lazyBlockquoteContinuationStartsNewBlock(in: state.text, range: lineRange) {
                    // This line starts a new block element, end blockquote
                    state.move(to: lineStart)
                    break
                }

                quoteLineRanges.append(lineRange)
                quoteLineUTF8Count += state.text.utf8.distance(from: lineRange.lowerBound, to: lineRange.upperBound)
                if isBlankLine(in: state.text, range: lineRange) {
                    currentParagraphHasContent = false
                } else {
                    canUseParagraphFastPath = canUseParagraphFastPath &&
                        !lineStartsBlockParserCandidate(
                            in: state.text,
                            range: lineRange,
                            isFirstLine: !currentParagraphHasContent
                        )
                    currentParagraphHasContent = true
                }

                // Skip newline
                if let c5 = state.current(), c5 == "\n" {
                    state.advance()
                }
            }
        }

        if quoteLineRanges.isEmpty {
            state.move(to: savedIndex)
            return nil
        }

        if useParagraphFastPath, canUseParagraphFastPath {
            let blocks = parseBlockquoteParagraphsFastPath(
                from: quoteLineRanges,
                in: state.text,
                configuration: configuration,
                useSingleRangeParagraphFastPath: useSingleRangeParagraphFastPath,
                usePlainTextParagraphFastPath: usePlainTextParagraphFastPath
            )
            return .blockquote(children: blocks)
        }

        if useSingleRangeRecursiveFastPath,
           let blocks = parseSingleRangeBlockquoteContent(
            from: quoteLineRanges,
            in: state.text,
            configuration: configuration
           ) {
            return .blockquote(children: blocks)
        }

        // Parse the content of the blockquote recursively
        let quoteContent = joinedBlockquoteContent(
            from: quoteLineRanges,
            in: state.text,
            reservedUTF8Count: quoteLineUTF8Count
        )
        var quoteState = ParserState(text: quoteContent)
        let blocks = parseBlocks(&quoteState, configuration: configuration)

        return .blockquote(children: blocks)
    }

    private static func parseSingleRangeBlockquoteContent(
        from ranges: [Range<String.Index>],
        in source: String,
        configuration: MarkdownConfiguration
    ) -> [MarkdownParser.BlockNode]? {
        guard ranges.count == 1 else {
            return nil
        }

        let range = whitespaceTrimmedRange(in: source, range: ranges[0])
        guard range.lowerBound < range.upperBound else {
            return []
        }

        return parseBlocksInSingleSourceRange(range, in: source, configuration: configuration)
    }

    private static func parseBlocksInSingleSourceRange(
        _ range: Range<String.Index>,
        in source: String,
        configuration: MarkdownConfiguration
    ) -> [MarkdownParser.BlockNode] {
        var state = ParserState(
            text: source,
            currentIndex: range.lowerBound,
            endIndex: range.upperBound,
            asciiFastPath: false
        )
        return parseBlocks(&state, configuration: configuration)
    }

    static func parseBlockquoteByCopyingLinesForTesting(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.BlockNode? {
        let savedIndex = state.currentIndex

        guard let first = state.current(), first == ">" else {
            return nil
        }

        var quoteLines: [String] = []

        while !state.isAtEnd {
            if let ch = state.current(), ch == ">" {
                state.advance()
                if let c = state.current(), c == " " {
                    state.advance()
                }

                let lineStartIndex = state.currentIndex
                while let c2 = state.current(), c2 != "\n" {
                    state.advance()
                }
                quoteLines.append(state.substring(from: lineStartIndex, to: state.currentIndex))

                if let c3 = state.current(), c3 == "\n" {
                    state.advance()
                }
            } else if state.isAtEmptyLine() {
                break
            } else {
                let lineStart = state.currentIndex
                while let c4 = state.current(), c4 != "\n" {
                    state.advance()
                }
                let line = state.substring(from: lineStart, to: state.currentIndex)

                if line.trimmingCharacters(in: .whitespaces).starts(with: "-") ||
                   line.trimmingCharacters(in: .whitespaces).starts(with: "*") ||
                   line.trimmingCharacters(in: .whitespaces).starts(with: "#") ||
                   line.contains(where: { $0 == "|" }) {
                    state.move(to: lineStart)
                    break
                }

                quoteLines.append(line)

                if let c5 = state.current(), c5 == "\n" {
                    state.advance()
                }
            }
        }

        if quoteLines.isEmpty {
            state.move(to: savedIndex)
            return nil
        }

        let quoteContent = quoteLines.joined(separator: "\n")
        var quoteState = ParserState(text: quoteContent)
        let blocks = parseBlocks(&quoteState, configuration: configuration)

        return .blockquote(children: blocks)
    }

    private static func lazyBlockquoteContinuationStartsNewBlock(
        in text: String,
        range: Range<String.Index>
    ) -> Bool {
        if lineContains("|", in: text, range: range) {
            return true
        }

        let trimmedRange = whitespaceTrimmedRange(in: text, range: range)
        guard trimmedRange.lowerBound < trimmedRange.upperBound else {
            return false
        }

        let first = text[trimmedRange.lowerBound]
        return first == "-" || first == "*" || first == "#"
    }

    private static func joinedBlockquoteContent(
        from ranges: [Range<String.Index>],
        in source: String,
        reservedUTF8Count: Int
    ) -> String {
        var content = ""
        content.reserveCapacity(reservedUTF8Count + max(0, ranges.count - 1))

        for (index, range) in ranges.enumerated() {
            if index > 0 {
                content.append("\n")
            }
            content.append(contentsOf: source[range])
        }

        return content
    }

    private static func parseBlockquoteParagraphsFastPath(
        from ranges: [Range<String.Index>],
        in source: String,
        configuration: MarkdownConfiguration,
        useSingleRangeParagraphFastPath: Bool,
        usePlainTextParagraphFastPath: Bool
    ) -> [MarkdownParser.BlockNode] {
        var blocks: [MarkdownParser.BlockNode] = []
        var paragraphRanges: [Range<String.Index>] = []
        paragraphRanges.reserveCapacity(ranges.count)
        var paragraphUTF8Count = 0

        func flushParagraph() {
            guard !paragraphRanges.isEmpty else {
                return
            }

            if usePlainTextParagraphFastPath,
               let inlines = plainTextParagraphInlinesFromNonBlankSourceRanges(
                from: paragraphRanges,
                in: source,
                reservedUTF8Count: paragraphUTF8Count,
                configuration: configuration
               ) {
                if !inlines.isEmpty {
                    blocks.append(.paragraph(children: inlines))
                }
                paragraphRanges.removeAll(keepingCapacity: true)
                paragraphUTF8Count = 0
                return
            }

            if useSingleRangeParagraphFastPath,
               let singleRange = singleTrimmedContentRange(from: paragraphRanges, in: source) {
                let inlines = InlineParser.parseInlineElements(
                    in: source,
                    from: singleRange.lowerBound,
                    to: singleRange.upperBound,
                    configuration: configuration
                )
                blocks.append(.paragraph(children: inlines))
                paragraphRanges.removeAll(keepingCapacity: true)
                paragraphUTF8Count = 0
                return
            }

            let content = joinedTrimmedContent(
                from: paragraphRanges,
                in: source,
                reservedUTF8Count: paragraphUTF8Count
            )
            if !content.isEmpty {
                let inlines = InlineParser.parseInlineOptimized(content, configuration: configuration)
                blocks.append(.paragraph(children: inlines))
            }

            paragraphRanges.removeAll(keepingCapacity: true)
            paragraphUTF8Count = 0
        }

        blocks.reserveCapacity(1)
        for range in ranges {
            if isBlankLine(in: source, range: range) {
                flushParagraph()
                continue
            }

            paragraphRanges.append(range)
            paragraphUTF8Count += source.utf8.distance(from: range.lowerBound, to: range.upperBound)
        }

        flushParagraph()
        return blocks
    }
    
    static func parseList(_ state: inout ParserState, configuration: MarkdownConfiguration) -> MarkdownParser.BlockNode? {
        parseList(&state, configuration: configuration, useASCIIListMarkerFastPath: true)
    }

    static func parseListByCharacterMarkerParsingForTesting(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.BlockNode? {
        parseList(&state, configuration: configuration, useASCIIListMarkerFastPath: false)
    }

    private static func parseList(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration,
        useASCIIListMarkerFastPath: Bool
    ) -> MarkdownParser.BlockNode? {
        let savedIndex = state.currentIndex
        
        // Skip up to 3 spaces of indentation
        var indent = 0
        while let ch = state.current(), ch == " ", indent < 3 {
            state.advance()
            indent += 1
        }
        
        guard let parsedMarker = parseListMarker(
            &state,
            useASCIIListMarkerFastPath: useASCIIListMarkerFastPath
        ) else {
            state.move(to: savedIndex)
            return nil
        }

        let isOrdered = parsedMarker.isOrdered
        let marker = parsedMarker.marker

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

            guard let itemMarker = parseListMarker(
                &state,
                useASCIIListMarkerFastPath: useASCIIListMarkerFastPath
            ) else {
                state.move(to: itemPositionIndex)
                break
            }

            guard itemMarker.isOrdered == isOrdered,
                  isOrdered || itemMarker.marker == marker else {
                state.move(to: itemPositionIndex)
                break
            }

            let itemContent = parseListItemContent(
                &state,
                indent: itemIndent,
                marker: itemMarker.marker,
                configuration: configuration
            )
            items.append(itemContent)
        }
        
        return .list(ordered: isOrdered, tight: true, items: items)
    }

    private static func parseListMarker(
        _ state: inout ParserState,
        useASCIIListMarkerFastPath: Bool
    ) -> ListMarkerParse? {
        if useASCIIListMarkerFastPath,
           let probe = parseASCIIListMarker(in: state) {
            moveASCIIState(
                &state,
                from: probe.start,
                to: probe.contentStart,
                stringFinalIndex: probe.stringContentStart
            )
            return ListMarkerParse(marker: probe.marker, isOrdered: probe.isOrdered)
        }

        return parseListMarkerByCharacterScanning(&state)
    }

    private static func parseASCIIListMarker(in state: ParserState) -> ASCIIListMarkerProbe? {
        guard let start = state.currentIndex.samePosition(in: state.text.utf8),
              let end = state.endIndex.samePosition(in: state.text.utf8),
              start < end else {
            return nil
        }

        let utf8 = state.text.utf8
        let first = utf8[start]
        if first == 0x2D || first == 0x2A || first == 0x2B { // - * +
            let markerEnd = utf8.index(after: start)
            guard markerEnd < end, utf8[markerEnd] == 0x20 else { // space
                return nil
            }

            let contentStart = utf8.index(after: markerEnd)
            guard let stringContentStart = String.Index(contentStart, within: state.text) else {
                return nil
            }

            let marker: String
            switch first {
            case 0x2D: marker = "-"
            case 0x2A: marker = "*"
            default: marker = "+"
            }

            return ASCIIListMarkerProbe(
                marker: marker,
                isOrdered: false,
                start: start,
                contentStart: contentStart,
                stringContentStart: stringContentStart
            )
        }

        guard first >= 0x30, first <= 0x39 else {
            return nil
        }

        var markerEnd = start
        while markerEnd < end, utf8[markerEnd] >= 0x30, utf8[markerEnd] <= 0x39 {
            markerEnd = utf8.index(after: markerEnd)
        }

        guard markerEnd < end else {
            return nil
        }

        let delimiter = utf8[markerEnd]
        guard delimiter == 0x2E || delimiter == 0x29 else { // . )
            return nil
        }

        let afterDelimiter = utf8.index(after: markerEnd)
        guard afterDelimiter < end, utf8[afterDelimiter] == 0x20 else { // space
            return nil
        }

        let contentStart = utf8.index(after: afterDelimiter)
        guard let stringMarkerStart = String.Index(start, within: state.text),
              let stringMarkerEnd = String.Index(afterDelimiter, within: state.text),
              let stringContentStart = String.Index(contentStart, within: state.text) else {
            return nil
        }

        return ASCIIListMarkerProbe(
            marker: String(state.text[stringMarkerStart..<stringMarkerEnd]),
            isOrdered: true,
            start: start,
            contentStart: contentStart,
            stringContentStart: stringContentStart
        )
    }

    private static func parseListMarkerByCharacterScanning(_ state: inout ParserState) -> ListMarkerParse? {
        let savedIndex = state.currentIndex
        var isOrdered = false
        var marker = ""

        if let char = state.current() {
            if char == "-" || char == "*" || char == "+" {
                marker = String(char)
                state.advance()
            } else if char.isNumber {
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

        if state.isAtEnd || state.current() != " " {
            state.move(to: savedIndex)
            return nil
        }
        state.advance()

        return ListMarkerParse(marker: marker, isOrdered: isOrdered)
    }

    static func parseListMarkerSignatureForTesting(
        _ state: inout ParserState,
        useASCIIListMarkerFastPath: Bool
    ) -> String? {
        guard let marker = parseListMarker(
            &state,
            useASCIIListMarkerFastPath: useASCIIListMarkerFastPath
        ) else {
            return nil
        }

        let offset = state.text.utf8.distance(from: state.text.utf8.startIndex, to: state.currentIndex)
        return "\(marker.isOrdered ? "ordered" : "unordered")|\(marker.marker)|\(offset)|\(state.line)|\(state.column)"
    }
    
    static func parseListItemContent(_ state: inout ParserState, indent: Int, marker: String, configuration: MarkdownConfiguration) -> MarkdownParser.ListItem {
        parseListItemContent(
            &state,
            indent: indent,
            marker: marker,
            configuration: configuration,
            useSingleRangeParagraphFastPath: true,
            usePlainTextParagraphFastPath: true
        )
    }

    static func parseListItemContentByJoiningSingleParagraphForTesting(
        _ state: inout ParserState,
        indent: Int,
        marker: String,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.ListItem {
        parseListItemContent(
            &state,
            indent: indent,
            marker: marker,
            configuration: configuration,
            useSingleRangeParagraphFastPath: false,
            usePlainTextParagraphFastPath: false
        )
    }

    private static func parseListItemContent(
        _ state: inout ParserState,
        indent: Int,
        marker: String,
        configuration: MarkdownConfiguration,
        useSingleRangeParagraphFastPath: Bool,
        usePlainTextParagraphFastPath: Bool
    ) -> MarkdownParser.ListItem {
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
        
        // Collect item content ranges after marker/continuation indentation.
        var contentLineRanges: [Range<String.Index>] = []
        var contentLineUTF8Count = 0
        var canUseParagraphFastPath = true
        
        // First line of item
        let firstLineStart = state.currentIndex
        while let ch = state.current(), ch != "\n" {
            state.advance()
        }
        let firstLineRange = firstLineStart..<state.currentIndex
        contentLineRanges.append(firstLineRange)
        contentLineUTF8Count += state.text.utf8.distance(from: firstLineStart, to: state.currentIndex)
        canUseParagraphFastPath = canUseParagraphFastPath &&
            contentLineCanUseParagraphFastPath(in: state.text, range: firstLineRange, isFirstLine: true)
        
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
            
            let lineEnd = state.currentIndex
            if isBlankLine(in: state.text, range: lineStartIndex..<lineEnd) {
                // Empty line might be part of the item or might end it
                let emptyRange = lineEnd..<lineEnd
                contentLineRanges.append(emptyRange)
                canUseParagraphFastPath = false
            } else {
                // Remove the indentation from continuation lines
                let contentStart = state.text.index(
                    lineStartIndex,
                    offsetBy: min(spaces, minIndent),
                    limitedBy: lineEnd
                ) ?? lineEnd
                let lineRange = contentStart..<lineEnd
                contentLineRanges.append(lineRange)
                contentLineUTF8Count += state.text.utf8.distance(from: contentStart, to: lineEnd)
                canUseParagraphFastPath = canUseParagraphFastPath &&
                    contentLineCanUseParagraphFastPath(in: state.text, range: lineRange, isFirstLine: false)
            }
            
            if let ch = state.current(), ch == "\n" {
                state.advance()
            }
        }
        
        if useSingleRangeParagraphFastPath,
           let singleRange = singleTrimmedContentRange(from: contentLineRanges, in: state.text),
           canUseParagraphFastPath || isSingleLineListHeadingLiteral(in: state.text, range: singleRange) {
            let inlines = InlineParser.parseInlineElements(
                in: state.text,
                from: singleRange.lowerBound,
                to: singleRange.upperBound,
                configuration: configuration
            )
            let blocks = [MarkdownParser.BlockNode.paragraph(children: inlines)]
            return MarkdownParser.ListItem(marker: marker, content: blocks, isTask: isTask, isChecked: isChecked)
        }

        if useSingleRangeParagraphFastPath,
           let singleRange = singleTrimmedContentRange(from: contentLineRanges, in: state.text) {
            let blocks = parseBlocksInSingleSourceRange(
                singleRange,
                in: state.text,
                configuration: configuration
            )
            return MarkdownParser.ListItem(marker: marker, content: blocks, isTask: isTask, isChecked: isChecked)
        }

        if usePlainTextParagraphFastPath,
           canUseParagraphFastPath,
           let inlines = plainTextParagraphInlinesFromNonBlankSourceRanges(
            from: contentLineRanges,
            in: state.text,
            reservedUTF8Count: contentLineUTF8Count,
            configuration: configuration
           ) {
            let blocks = [MarkdownParser.BlockNode.paragraph(children: inlines)]
            return MarkdownParser.ListItem(marker: marker, content: blocks, isTask: isTask, isChecked: isChecked)
        }

        // Parse the content as blocks
        let content = joinedTrimmedContent(
            from: contentLineRanges,
            in: state.text,
            reservedUTF8Count: contentLineUTF8Count
        )
        
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
               contentLineRanges.count == 1 {  // Single line, no blank line separation
                // Force it to be parsed as a paragraph
                let inlines = InlineParser.parseInlineOptimized(content, configuration: configuration)
                let blocks = [MarkdownParser.BlockNode.paragraph(children: inlines)]
                return MarkdownParser.ListItem(marker: marker, content: blocks, isTask: isTask, isChecked: isChecked)
            }
        }

        if canUseParagraphFastPath {
            let inlines = InlineParser.parseInlineOptimized(content, configuration: configuration)
            let blocks = [MarkdownParser.BlockNode.paragraph(children: inlines)]
            return MarkdownParser.ListItem(marker: marker, content: blocks, isTask: isTask, isChecked: isChecked)
        }
        
        var contentState = ParserState(text: content)
        let blocks = parseBlocks(&contentState, configuration: configuration)
        
        return MarkdownParser.ListItem(marker: marker, content: blocks, isTask: isTask, isChecked: isChecked)
    }

    static func parseListItemContentByCopyingLinesForTesting(
        _ state: inout ParserState,
        indent: Int,
        marker: String,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.ListItem {
        var isTask = false
        var isChecked = false

        if let c0 = state.current(), c0 == "[",
           let c1 = state.peek(1), (c1 == " " || c1 == "x" || c1 == "X"),
           let c2 = state.peek(2), c2 == "]",
           let c3 = state.peek(3), c3 == " " {
            isTask = true
            isChecked = (c1 != " ")
            state.advance(by: 4)
        }

        var contentLines: [String] = []

        let firstLineStart = state.currentIndex
        while let ch = state.current(), ch != "\n" {
            state.advance()
        }
        contentLines.append(state.substring(from: firstLineStart, to: state.currentIndex))

        if let ch = state.current(), ch == "\n" {
            state.advance()
        }

        while !state.isAtEnd {
            let lineStartIndex = state.currentIndex

            var spaces = 0
            while let ch = state.current(), ch == " " {
                spaces += 1
                state.advance()
            }

            let minIndent = marker.count + 1
            if spaces < minIndent {
                state.move(to: lineStartIndex)
                break
            }

            if spaces < indent + 4 {
                let char = state.current() ?? "\n"
                if char == "-" || char == "*" || char == "+" || char.isNumber {
                    state.move(to: lineStartIndex)
                    break
                }
            }

            while let ch = state.current(), ch != "\n" {
                state.advance()
            }

            let line = state.substring(from: lineStartIndex, to: state.currentIndex)
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                contentLines.append("")
            } else {
                let trimmedLine = String(line.dropFirst(min(spaces, minIndent)))
                contentLines.append(trimmedLine)
            }

            if let ch = state.current(), ch == "\n" {
                state.advance()
            }
        }

        let content = contentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        if !content.isEmpty && content.first == "#" {
            var hashCount = 0
            for char in content {
                if char == "#" {
                    hashCount += 1
                } else {
                    break
                }
            }

            if hashCount >= 1 && hashCount <= 6 &&
               content.count > hashCount &&
               content[content.index(content.startIndex, offsetBy: hashCount)] == " " &&
               contentLines.count == 1 {
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
        parseTable(&state, configuration: configuration, startProbe: nil)
    }

    static func parseTableUsingStartProbeForTesting(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.BlockNode? {
        guard let startProbe = tableStartProbe(state) else {
            return nil
        }
        return parseTable(&state, configuration: configuration, startProbe: startProbe)
    }

    static func parseTableByRescanningStartLinesForTesting(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.BlockNode? {
        parseTable(&state, configuration: configuration, startProbe: nil)
    }

    static func parseTableByCheckingRowsWithSubstringContainsForTesting(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.BlockNode? {
        guard let startProbe = tableStartProbe(state) else {
            return nil
        }
        return parseTable(
            &state,
            configuration: configuration,
            startProbe: startProbe,
            useSharedRowLineScan: false,
            useUTF8RowPipeScan: false
        )
    }

    static func parseTableBySeparateRowLineAndPipeScansForTesting(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.BlockNode? {
        guard let startProbe = tableStartProbe(state) else {
            return nil
        }
        return parseTable(
            &state,
            configuration: configuration,
            startProbe: startProbe,
            useSharedRowLineScan: false
        )
    }

    private static func parseTable(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration,
        startProbe: TableStartProbe?,
        useSharedRowLineScan: Bool = true,
        useUTF8RowPipeScan: Bool = true
    ) -> MarkdownParser.BlockNode? {
        let savedIndex = state.currentIndex
        var lineRanges: [Range<String.Index>] = []

        if let startProbe {
            lineRanges.append(startProbe.headerRange)
            lineRanges.append(startProbe.separatorRange)
            moveStateAfterTableStartProbe(&state, startProbe)
        } else {
            // A table must start at the current line. Do not scan ahead.
            let headerStart = state.currentIndex
            state.advanceToLineEnd()
            let headerEnd = state.currentIndex
            guard state.text[headerStart..<headerEnd].contains("|") else {
                state.move(to: savedIndex)
                return nil
            }

            lineRanges.append(headerStart..<headerEnd)

            // Require a separator line immediately after the header line.
            guard let ch = state.current(), ch == "\n" else {
                state.move(to: savedIndex)
                return nil
            }
            state.advance()

            let separatorStart = state.currentIndex
            state.advanceToLineEnd()
            let separatorEnd = state.currentIndex
            let separatorLine = state.text[separatorStart..<separatorEnd]
            guard separatorLine.contains("|") && separatorLine.contains("-") else {
                state.move(to: savedIndex)
                return nil
            }

            lineRanges.append(separatorStart..<separatorEnd)

            if let ch = state.current(), ch == "\n" {
                state.advance()
            }
        }

        // Collect contiguous table row lines.
        while !state.isAtEnd {
            let rowStart = state.currentIndex
            let rowRange: Range<String.Index>
            let rowContainsPipe: Bool

            if useSharedRowLineScan,
               let rowScan = scanTableRowLine(state) {
                rowRange = rowScan.range
                rowContainsPipe = rowScan.containsPipe
                state.currentIndex = rowRange.upperBound
                state.column += rowScan.columnAdvance
            } else {
                state.advanceToLineEnd()
                let rowEnd = state.currentIndex
                rowRange = rowStart..<rowEnd
                rowContainsPipe = tableRowContainsPipe(in: state.text, range: rowRange, useUTF8Scan: useUTF8RowPipeScan)
            }

            guard rowContainsPipe else {
                state.move(to: rowStart)
                break
            }

            lineRanges.append(rowRange)

            if let ch = state.current(), ch == "\n" {
                state.advance()
            }
        }

        // Delegate validation/parsing to GFMExtensions.
        guard let (headers, rows, _) = GFMExtensions.parseTable(
            source: state.text,
            lineRanges: lineRanges,
            configuration: configuration
        ) else {
            state.move(to: savedIndex)
            return nil
        }
        
        return .table(header: headers, rows: rows)
    }

    private static func scanTableRowLine(_ state: ParserState) -> TableRowLineScan? {
        guard let start = state.currentIndex.samePosition(in: state.text.utf8),
              let end = state.endIndex.samePosition(in: state.text.utf8) else {
            return nil
        }

        let utf8 = state.text.utf8
        var index = start
        var containsPipe = false
        var columnAdvance = 0

        while index < end {
            let byte = utf8[index]
            if byte == 0x0A { // newline
                break
            }
            if byte >= 0x80 {
                guard var stringIndex = index.samePosition(in: state.text) else {
                    return nil
                }

                while stringIndex < state.endIndex {
                    let character = state.text[stringIndex]
                    if character == "\n" {
                        break
                    }
                    if character == "|" {
                        containsPipe = true
                    }
                    stringIndex = state.text.index(after: stringIndex)
                    columnAdvance += 1
                }

                return TableRowLineScan(
                    range: state.currentIndex..<stringIndex,
                    columnAdvance: columnAdvance,
                    containsPipe: containsPipe
                )
            }
            if byte == 0x7C { // |
                containsPipe = true
            }
            index = utf8.index(after: index)
            columnAdvance += 1
        }

        return TableRowLineScan(
            range: state.currentIndex..<index,
            columnAdvance: columnAdvance,
            containsPipe: containsPipe
        )
    }

    static func tableRowContainsPipeForTesting(in text: String, range: Range<String.Index>) -> Bool {
        tableRowContainsPipe(in: text, range: range, useUTF8Scan: true)
    }

    static func tableRowContainsPipeBySubstringContainsForTesting(
        in text: String,
        range: Range<String.Index>
    ) -> Bool {
        tableRowContainsPipe(in: text, range: range, useUTF8Scan: false)
    }

    private static func tableRowContainsPipe(
        in text: String,
        range: Range<String.Index>,
        useUTF8Scan: Bool
    ) -> Bool {
        if useUTF8Scan {
            return lineContains("|", in: text, range: range)
        }
        return text[range].contains("|")
    }
    
    static func parseHorizontalRule(_ state: inout ParserState) -> MarkdownParser.BlockNode? {
        if let horizontalRule = parseHorizontalRuleByUTF8Scanning(&state) {
            return horizontalRule
        }

        return parseHorizontalRuleByCharacterScanning(&state)
    }

    static func parseHorizontalRuleByCharacterScanningForTesting(
        _ state: inout ParserState
    ) -> MarkdownParser.BlockNode? {
        parseHorizontalRuleByCharacterScanning(&state)
    }

    private static func parseHorizontalRuleByCharacterScanning(
        _ state: inout ParserState
    ) -> MarkdownParser.BlockNode? {
        
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

    private static func parseHorizontalRuleByUTF8Scanning(
        _ state: inout ParserState
    ) -> MarkdownParser.BlockNode? {
        guard let start = state.currentIndex.samePosition(in: state.text.utf8),
              let end = state.endIndex.samePosition(in: state.text.utf8) else {
            return nil
        }

        let utf8 = state.text.utf8
        var index = start
        var spaces = 0
        while index < end, utf8[index] == 0x20, spaces < 3 { // space
            spaces += 1
            index = utf8.index(after: index)
        }

        guard index < end else {
            return nil
        }

        let rule = utf8[index]
        guard rule == 0x2D || rule == 0x2A || rule == 0x5F else { // - * _
            return nil
        }

        var count = 0
        while index < end {
            let byte = utf8[index]
            if byte == rule {
                count += 1
                index = utf8.index(after: index)
            } else if byte == 0x20 { // space
                index = utf8.index(after: index)
            } else if byte == 0x0A { // newline
                break
            } else {
                return nil
            }
        }

        guard count >= 3 else {
            return nil
        }

        if index < end, utf8[index] == 0x0A { // newline
            index = utf8.index(after: index)
        }

        guard let stringFinalIndex = String.Index(index, within: state.text) else {
            return nil
        }
        moveASCIIState(&state, from: start, to: index, stringFinalIndex: stringFinalIndex)
        return .horizontalRule
    }
    
    static func parseSetextHeading(_ state: inout ParserState, configuration: MarkdownConfiguration) -> MarkdownParser.BlockNode? {
        parseSetextHeading(&state, configuration: configuration, probe: nil)
    }

    static func parseSetextHeadingUsingProbeForTesting(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.BlockNode? {
        guard let probe = setextHeadingProbe(state) else {
            return nil
        }
        return parseSetextHeading(&state, configuration: configuration, probe: probe)
    }

    static func parseSetextHeadingUsingProbeWithTrimRescanForTesting(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.BlockNode? {
        guard let probe = setextHeadingProbe(state, useScannedHeadingRange: false) else {
            return nil
        }
        return parseSetextHeading(&state, configuration: configuration, probe: probe)
    }

    static func parseSetextHeadingByRescanningLinesForTesting(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.BlockNode? {
        parseSetextHeading(&state, configuration: configuration, probe: nil)
    }

    private static func parseSetextHeading(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration,
        probe: SetextHeadingProbe?
    ) -> MarkdownParser.BlockNode? {
        let savedIndex = state.currentIndex
        let headingRange: Range<String.Index>
        let level: Int

        if let probe {
            headingRange = probe.headingRange
            level = probe.level
            moveStateAfterSetextHeadingProbe(&state, probe)
        } else {
            // First line is the heading text
            let headingStart = state.currentIndex
            while let ch = state.current(), ch != "\n" {
                state.advance()
            }

            let headingLineEnd = state.currentIndex
            headingRange = whitespaceTrimmedRange(in: state.text, range: headingStart..<headingLineEnd)
            guard headingRange.lowerBound < headingRange.upperBound else {
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
            while let ch = state.current(), ch == underlineChar {
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

            level = underlineChar == "=" ? 1 : 2
        }

        // Generate ID from heading text
        let headingId = ParsingHelpers.slugifyHeading(in: state.text, range: headingRange)
        
        // Parse inline content
        let inlines = InlineParser.parseInlineElements(
            in: state.text,
            from: headingRange.lowerBound,
            to: headingRange.upperBound,
            configuration: configuration
        )
        
        return .heading(level: level, children: inlines, id: headingId.isEmpty ? nil : headingId)
    }
    
    static func parseParagraph(_ state: inout ParserState, configuration: MarkdownConfiguration) -> MarkdownParser.BlockNode? {
        parseParagraph(
            &state,
            configuration: configuration,
            skipKnownFirstParagraphBreak: false,
            useRangeBackedInlineParsing: true,
            useSharedContinuationLineScan: true
        )
    }

    static func parseParagraphByCopyingTextForTesting(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.BlockNode? {
        parseParagraph(
            &state,
            configuration: configuration,
            skipKnownFirstParagraphBreak: false,
            useRangeBackedInlineParsing: false,
            useSharedContinuationLineScan: true
        )
    }

    static func parseParagraphSkippingKnownFirstBreakForTesting(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.BlockNode? {
        parseParagraph(
            &state,
            configuration: configuration,
            skipKnownFirstParagraphBreak: true,
            useRangeBackedInlineParsing: true,
            useSharedContinuationLineScan: true
        )
    }

    static func parseParagraphByRescanningContinuationLinesForTesting(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.BlockNode? {
        parseParagraph(
            &state,
            configuration: configuration,
            skipKnownFirstParagraphBreak: false,
            useRangeBackedInlineParsing: true,
            useSharedContinuationLineScan: false
        )
    }

    private static func parseParagraph(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration,
        skipKnownFirstParagraphBreak: Bool
    ) -> MarkdownParser.BlockNode? {
        parseParagraph(
            &state,
            configuration: configuration,
            skipKnownFirstParagraphBreak: skipKnownFirstParagraphBreak,
            useRangeBackedInlineParsing: true,
            useSharedContinuationLineScan: true
        )
    }

    private static func parseParagraph(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration,
        skipKnownFirstParagraphBreak: Bool,
        useRangeBackedInlineParsing: Bool,
        useSharedContinuationLineScan: Bool
    ) -> MarkdownParser.BlockNode? {
        var paragraphStart: String.Index?
        var paragraphEnd = state.currentIndex
        var acceptedLineCount = 0
        
        while !state.isAtEnd {
            // Check if we're at a block boundary
            if !(skipKnownFirstParagraphBreak && acceptedLineCount == 0),
               isAtParagraphBreak(&state) {
                break
            }
            
            let lineStart = state.currentIndex
            let lineScan = useSharedContinuationLineScan && acceptedLineCount > 0
                ? scanParagraphContinuationLine(state)
                : nil

            if let lineScan {
                state.currentIndex = lineScan.lineEnd
                state.column += lineScan.columnAdvance
            } else {
                state.advanceToLineEnd()
            }
            
            // For the first line, we've already determined this isn't a valid block start
            // (otherwise we wouldn't be in parseParagraph), so always include it
            if acceptedLineCount > 0 {
                // Check if this line starts a new block element
                let startsParagraphBreakingBlock = lineScan?.startsParagraphBreakingBlock ??
                    lineStartsParagraphBreakingBlock(in: state.text, range: lineStart..<state.currentIndex)
                if startsParagraphBreakingBlock {
                    state.move(to: lineStart)
                    break
                }
            }
            
            if paragraphStart == nil {
                paragraphStart = lineStart
            }
            paragraphEnd = state.currentIndex
            acceptedLineCount += 1
            
            // Skip newline
            if state.current() == "\n" {
                state.advance()
            }
            
            // Check for empty line (paragraph break)
            if !state.isAtEnd && state.isAtEmptyLine() {
                break
            }
        }
        
        guard let textStart = paragraphStart else {
            return nil
        }

        var textRange = textStart..<paragraphEnd
        textRange = leadingWhitespaceTrimmedRange(in: state.text, range: textRange)
        textRange = trailingWhitespaceTrimmedRange(in: state.text, range: textRange)
        guard textRange.lowerBound < textRange.upperBound else {
            return nil
        }

        let inlines: [MarkdownParser.InlineNode]
        if useRangeBackedInlineParsing {
            inlines = InlineParser.parseInlineElements(
                in: state.text,
                from: textRange.lowerBound,
                to: textRange.upperBound,
                configuration: configuration
            )
        } else {
            let text = String(state.text[textRange])
            var tempState = ParserState(text: text)
            inlines = InlineParser.parseInlineElements(&tempState, configuration: configuration)
        }
        
        return .paragraph(children: inlines)
    }
    
    static func parseFootnoteDefinition(_ state: inout ParserState, configuration: MarkdownConfiguration) -> MarkdownParser.BlockNode? {
        parseFootnoteDefinition(
            &state,
            configuration: configuration,
            useSingleRangeParagraphFastPath: true,
            usePlainTextParagraphFastPath: true
        )
    }

    static func parseFootnoteDefinitionByJoiningSingleParagraphForTesting(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.BlockNode? {
        parseFootnoteDefinition(
            &state,
            configuration: configuration,
            useSingleRangeParagraphFastPath: false,
            usePlainTextParagraphFastPath: false
        )
    }

    private static func parseFootnoteDefinition(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration,
        useSingleRangeParagraphFastPath: Bool,
        usePlainTextParagraphFastPath: Bool
    ) -> MarkdownParser.BlockNode? {
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
        
        // Collect footnote content ranges after marker/continuation indentation.
        var contentLineRanges: [Range<String.Index>] = []
        var contentLineUTF8Count = 0
        var canUseParagraphFastPath = true
        
        // First line
        let firstLineStart = state.currentIndex
        while let ch = state.current(), ch != "\n" {
            state.advance()
        }
        let firstLineRange = firstLineStart..<state.currentIndex
        contentLineRanges.append(firstLineRange)
        contentLineUTF8Count += state.text.utf8.distance(from: firstLineStart, to: state.currentIndex)
        canUseParagraphFastPath = canUseParagraphFastPath &&
            contentLineCanUseParagraphFastPath(in: state.text, range: firstLineRange, isFirstLine: true)
        
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
            
            let lineRange = contentStart..<state.currentIndex
            contentLineRanges.append(lineRange)
            contentLineUTF8Count += state.text.utf8.distance(from: contentStart, to: state.currentIndex)
            canUseParagraphFastPath = canUseParagraphFastPath &&
                contentLineCanUseParagraphFastPath(in: state.text, range: lineRange, isFirstLine: false)
            
            if state.current() == "\n" {
                state.advance()
            }
        }
        
        if useSingleRangeParagraphFastPath,
           canUseParagraphFastPath,
           let singleRange = singleTrimmedContentRange(from: contentLineRanges, in: state.text) {
            let inlines = InlineParser.parseInlineElements(
                in: state.text,
                from: singleRange.lowerBound,
                to: singleRange.upperBound,
                configuration: configuration
            )
            return .footnoteDefinition(label: label, children: [.paragraph(children: inlines)])
        }

        if usePlainTextParagraphFastPath,
           canUseParagraphFastPath,
           let inlines = plainTextParagraphInlinesFromNonBlankSourceRanges(
            from: contentLineRanges,
            in: state.text,
            reservedUTF8Count: contentLineUTF8Count,
            configuration: configuration
           ) {
            return .footnoteDefinition(label: label, children: [.paragraph(children: inlines)])
        }

        // Parse the content
        let content = joinedTrimmedContent(
            from: contentLineRanges,
            in: state.text,
            reservedUTF8Count: contentLineUTF8Count
        )
        if canUseParagraphFastPath {
            let inlines = InlineParser.parseInlineOptimized(content, configuration: configuration)
            return .footnoteDefinition(label: label, children: [.paragraph(children: inlines)])
        }

        var contentState = ParserState(text: content)
        let blocks = parseBlocks(&contentState, configuration: configuration)
        
        return .footnoteDefinition(label: label, children: blocks)
    }

    static func parseFootnoteDefinitionByCopyingLinesForTesting(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration
    ) -> MarkdownParser.BlockNode? {
        let savedIndex = state.currentIndex

        guard let c0 = state.current(), c0 == "[",
              let c1 = state.peek(1), c1 == "^" else {
            return nil
        }

        state.advance(by: 2)

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

        state.advance()

        guard state.current() == ":" else {
            state.move(to: savedIndex)
            return nil
        }
        state.advance()

        if state.current() == " " {
            state.advance()
        }

        var contentLines: [String] = []

        let firstLineStart = state.currentIndex
        while let ch = state.current(), ch != "\n" {
            state.advance()
        }
        contentLines.append(state.substring(from: firstLineStart, to: state.currentIndex))

        if state.current() == "\n" {
            state.advance()
        }

        while !state.isAtEnd {
            let lineStart = state.currentIndex
            var spaces = 0

            while let ch = state.current(), (ch == " " || ch == "\t") {
                if ch == "\t" {
                    spaces = 4
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
                state.move(to: lineStart)
                break
            }

            let contentStart = state.currentIndex
            while let ch = state.current(), ch != "\n" {
                state.advance()
            }

            contentLines.append(state.substring(from: contentStart, to: state.currentIndex))

            if state.current() == "\n" {
                state.advance()
            }
        }

        let content = contentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        var contentState = ParserState(text: content)
        let blocks = parseBlocks(&contentState, configuration: configuration)

        return .footnoteDefinition(label: label, children: blocks)
    }
    
    // MARK: - Helper Methods

    private static func contentLineCanUseParagraphFastPath(
        in text: String,
        range: Range<String.Index>,
        isFirstLine: Bool
    ) -> Bool {
        guard let start = range.lowerBound.samePosition(in: text.utf8),
              let end = range.upperBound.samePosition(in: text.utf8) else {
            return contentLineCanUseParagraphFastPathBySeparateScans(
                in: text,
                range: range,
                isFirstLine: isFirstLine
            )
        }

        let utf8 = text.utf8
        var index = start
        var leadingSpaces = 0

        while index < end, utf8[index] == 0x20, leadingSpaces < 4 {
            index = utf8.index(after: index)
            leadingSpaces += 1
        }

        if leadingSpaces >= 4 {
            return false
        }

        guard index < end else {
            return false
        }

        switch utf8[index] {
        case 0x09, 0x0A, 0x0D:
            return lineHasNonWhitespaceAfterASCIIBlankPrefix(in: text, range: range, from: index, to: end)
        case 0x23, // #
             0x3E, // >
             0x60, // `
             0x7E, // ~
             0x7C, // |
             0x2D, // -
             0x2A, // *
             0x2B: // +
            return false
        case 0x30...0x39:
            var probe = index
            while probe < end, utf8[probe] >= 0x30, utf8[probe] <= 0x39 {
                probe = utf8.index(after: probe)
            }
            return !(probe < end && (utf8[probe] == 0x2E || utf8[probe] == 0x29)) // . )
        case 0x3D where !isFirstLine: // =
            return false
        case 0x00..<0x80:
            return true
        default:
            return contentLineCanUseParagraphFastPathBySeparateScans(
                in: text,
                range: range,
                isFirstLine: isFirstLine
            )
        }
    }

    static func contentLineCanUseParagraphFastPathForTesting(
        in text: String,
        range: Range<String.Index>,
        isFirstLine: Bool
    ) -> Bool {
        contentLineCanUseParagraphFastPath(in: text, range: range, isFirstLine: isFirstLine)
    }

    static func contentLineCanUseParagraphFastPathBySeparateScansForTesting(
        in text: String,
        range: Range<String.Index>,
        isFirstLine: Bool
    ) -> Bool {
        contentLineCanUseParagraphFastPathBySeparateScans(in: text, range: range, isFirstLine: isFirstLine)
    }

    private static func contentLineCanUseParagraphFastPathBySeparateScans(
        in text: String,
        range: Range<String.Index>,
        isFirstLine: Bool
    ) -> Bool {
        !isBlankLine(in: text, range: range) &&
            !lineStartsBlockParserCandidate(in: text, range: range, isFirstLine: isFirstLine)
    }

    private static func lineHasNonWhitespaceAfterASCIIBlankPrefix(
        in text: String,
        range: Range<String.Index>,
        from start: String.UTF8View.Index,
        to end: String.UTF8View.Index
    ) -> Bool {
        var index = start
        while index < end {
            switch text.utf8[index] {
            case 0x09, 0x0A, 0x0D, 0x20:
                index = text.utf8.index(after: index)
            case 0x00..<0x80:
                return true
            default:
                return !isBlankLineByCharacterScanning(in: text, range: range)
            }
        }
        return false
    }

    private static func lineStartsBlockParserCandidate(
        in text: String,
        range: Range<String.Index>,
        isFirstLine: Bool
    ) -> Bool {
        guard let start = range.lowerBound.samePosition(in: text.utf8),
              let end = range.upperBound.samePosition(in: text.utf8) else {
            return lineStartsBlockParserCandidateByCharacterScanning(
                in: text,
                range: range,
                isFirstLine: isFirstLine
            )
        }

        let utf8 = text.utf8
        var index = start
        var leadingSpaces = 0
        while index < end, utf8[index] == 0x20, leadingSpaces < 4 {
            index = utf8.index(after: index)
            leadingSpaces += 1
        }

        if leadingSpaces >= 4 {
            return true
        }

        guard index < end else {
            return true
        }

        switch utf8[index] {
        case 0x23, // #
             0x3E, // >
             0x60, // `
             0x7E, // ~
             0x7C, // |
             0x2D, // -
             0x2A, // *
             0x2B: // +
            return true
        case 0x30...0x39:
            var probe = index
            while probe < end, utf8[probe] >= 0x30, utf8[probe] <= 0x39 {
                probe = utf8.index(after: probe)
            }
            return probe < end && (utf8[probe] == 0x2E || utf8[probe] == 0x29) // . )
        case 0x3D where !isFirstLine: // =
            return true
        case 0x00..<0x80:
            return false
        default:
            return lineStartsBlockParserCandidateByCharacterScanning(
                in: text,
                range: range,
                isFirstLine: isFirstLine
            )
        }
    }

    static func lineStartsBlockParserCandidateForTesting(
        in text: String,
        range: Range<String.Index>,
        isFirstLine: Bool
    ) -> Bool {
        lineStartsBlockParserCandidate(in: text, range: range, isFirstLine: isFirstLine)
    }

    static func lineStartsBlockParserCandidateByCharacterScanningForTesting(
        in text: String,
        range: Range<String.Index>,
        isFirstLine: Bool
    ) -> Bool {
        lineStartsBlockParserCandidateByCharacterScanning(in: text, range: range, isFirstLine: isFirstLine)
    }

    private static func lineStartsBlockParserCandidateByCharacterScanning(
        in text: String,
        range: Range<String.Index>,
        isFirstLine: Bool
    ) -> Bool {
        var index = range.lowerBound
        var leadingSpaces = 0
        while index < range.upperBound, text[index] == " ", leadingSpaces < 4 {
            index = text.index(after: index)
            leadingSpaces += 1
        }

        if leadingSpaces >= 4 {
            return true
        }

        guard index < range.upperBound else {
            return true
        }

        let first = text[index]
        if first == "#" || first == ">" || first == "`" || first == "~" || first == "|" {
            return true
        }

        if first == "-" || first == "*" || first == "+" {
            return true
        }

        if first.isNumber {
            var probe = index
            while probe < range.upperBound, text[probe].isNumber {
                probe = text.index(after: probe)
            }
            if probe < range.upperBound, text[probe] == "." || text[probe] == ")" {
                return true
            }
        }

        if !isFirstLine, first == "=" {
            return true
        }

        return false
    }

    private static func isBlankLine(in text: String, range: Range<String.Index>) -> Bool {
        let utf8 = text.utf8
        var utf8Index = range.lowerBound
        while utf8Index < range.upperBound {
            switch utf8[utf8Index] {
            case 0x09, 0x0A, 0x0D, 0x20:
                utf8Index = utf8.index(after: utf8Index)
                continue
            case 0x00..<0x80:
                return false
            default:
                return isBlankLineByCharacterScanning(in: text, range: range)
            }
        }
        return true
    }

    static func isBlankLineForTesting(in text: String, range: Range<String.Index>) -> Bool {
        isBlankLine(in: text, range: range)
    }

    static func isBlankLineByCharacterScanningForTesting(
        in text: String,
        range: Range<String.Index>
    ) -> Bool {
        isBlankLineByCharacterScanning(in: text, range: range)
    }

    private static func isBlankLineByCharacterScanning(
        in text: String,
        range: Range<String.Index>
    ) -> Bool {
        var index = range.lowerBound
        while index < range.upperBound {
            if !text[index].isWhitespace {
                return false
            }
            index = text.index(after: index)
        }
        return true
    }

    private static func joinedTrimmedContent(
        from ranges: [Range<String.Index>],
        in source: String,
        reservedUTF8Count: Int
    ) -> String {
        let trimmedRanges = trimmedContentRanges(from: ranges, in: source)
        guard !trimmedRanges.isEmpty else {
            return ""
        }

        return joinedContent(from: trimmedRanges, in: source, reservedUTF8Count: reservedUTF8Count)
    }

    private static func plainTextParagraphInlinesFromSourceRanges(
        from ranges: [Range<String.Index>],
        in source: String,
        reservedUTF8Count: Int,
        configuration: MarkdownConfiguration
    ) -> [MarkdownParser.InlineNode]? {
        guard configuration.markdownExtensions.isEmpty,
              !configuration.enableRepositoryReferences,
              !configuration.enableAutolinks,
              !configuration.enableCommitSHAs else {
            return nil
        }

        let trimmedRanges = trimmedContentRanges(from: ranges, in: source)
        guard !trimmedRanges.isEmpty else {
            return []
        }

        guard !trimmedRanges.contains(where: {
            rangeContainsActivePlainTextInlineMarker(in: source, range: $0, configuration: configuration)
        }) else {
            return nil
        }

        let content = joinedContent(from: trimmedRanges, in: source, reservedUTF8Count: reservedUTF8Count)
        return content.isEmpty ? [] : [.text(content)]
    }

    private static func plainTextParagraphInlinesFromNonBlankSourceRanges(
        from ranges: [Range<String.Index>],
        in source: String,
        reservedUTF8Count: Int,
        configuration: MarkdownConfiguration
    ) -> [MarkdownParser.InlineNode]? {
        guard configuration.markdownExtensions.isEmpty,
              !configuration.enableRepositoryReferences,
              !configuration.enableAutolinks,
              !configuration.enableCommitSHAs else {
            return nil
        }

        guard !ranges.isEmpty else {
            return []
        }

        guard !ranges.contains(where: {
            rangeContainsActivePlainTextInlineMarker(in: source, range: $0, configuration: configuration)
        }) else {
            return nil
        }

        let content = joinedNonBlankTrimmedContent(from: ranges, in: source, reservedUTF8Count: reservedUTF8Count)
        return content.isEmpty ? [] : [.text(content)]
    }

    static func plainTextParagraphInlinesFromSourceRangesForTesting(
        from ranges: [Range<String.Index>],
        in source: String,
        reservedUTF8Count: Int,
        configuration: MarkdownConfiguration
    ) -> [MarkdownParser.InlineNode]? {
        plainTextParagraphInlinesFromSourceRanges(
            from: ranges,
            in: source,
            reservedUTF8Count: reservedUTF8Count,
            configuration: configuration
        )
    }

    static func plainTextParagraphInlinesFromNonBlankSourceRangesForTesting(
        from ranges: [Range<String.Index>],
        in source: String,
        reservedUTF8Count: Int,
        configuration: MarkdownConfiguration
    ) -> [MarkdownParser.InlineNode]? {
        plainTextParagraphInlinesFromNonBlankSourceRanges(
            from: ranges,
            in: source,
            reservedUTF8Count: reservedUTF8Count,
            configuration: configuration
        )
    }

    private static func trimmedContentRanges(
        from ranges: [Range<String.Index>],
        in source: String
    ) -> [Range<String.Index>] {
        guard let firstContentIndex = ranges.firstIndex(where: { rangeContainsNonWhitespace(in: source, range: $0) }),
              let lastContentIndex = ranges.lastIndex(where: { rangeContainsNonWhitespace(in: source, range: $0) }) else {
            return []
        }

        var trimmedRanges: [Range<String.Index>] = []
        trimmedRanges.reserveCapacity(lastContentIndex - firstContentIndex + 1)

        for index in firstContentIndex...lastContentIndex {
            var range = ranges[index]
            if index == firstContentIndex {
                range = leadingWhitespaceTrimmedRange(in: source, range: range)
            }
            if index == lastContentIndex {
                range = trailingWhitespaceTrimmedRange(in: source, range: range)
            }
            trimmedRanges.append(range)
        }

        return trimmedRanges
    }

    private static func joinedContent(
        from ranges: [Range<String.Index>],
        in source: String,
        reservedUTF8Count: Int
    ) -> String {
        var content = ""
        content.reserveCapacity(reservedUTF8Count + max(0, ranges.count - 1))
        for (index, range) in ranges.enumerated() {
            if index > 0 {
                content.append("\n")
            }
            content.append(contentsOf: source[range])
        }
        return content
    }

    private static func joinedNonBlankTrimmedContent(
        from ranges: [Range<String.Index>],
        in source: String,
        reservedUTF8Count: Int
    ) -> String {
        var content = ""
        content.reserveCapacity(reservedUTF8Count + max(0, ranges.count - 1))

        let lastIndex = ranges.count - 1
        for (index, originalRange) in ranges.enumerated() {
            var range = originalRange
            if index == 0 {
                range = leadingWhitespaceTrimmedRange(in: source, range: range)
            }
            if index == lastIndex {
                range = trailingWhitespaceTrimmedRange(in: source, range: range)
            }

            if index > 0 {
                content.append("\n")
            }
            if range.lowerBound < range.upperBound {
                content.append(contentsOf: source[range])
            }
        }

        return content
    }

    private static func rangeContainsActivePlainTextInlineMarker(
        in source: String,
        range: Range<String.Index>,
        configuration: MarkdownConfiguration
    ) -> Bool {
        guard let lower = range.lowerBound.samePosition(in: source.utf8),
              let upper = range.upperBound.samePosition(in: source.utf8) else {
            return true
        }

        let utf8 = source.utf8
        var index = lower
        while index < upper {
            switch utf8[index] {
            case 0x5C, // \
                 0x60, // `
                 0x2A, // *
                 0x5F, // _
                 0x7E, // ~
                 0x5B, // [
                 0x21, // !
                 0x3C: // <
                return true
            case 0x40 where configuration.enableMentions, // @
                 0x23 where configuration.enableIssueReferences, // #
                 0x3A where configuration.enableEmojiShortcodes: // :
                return true
            default:
                break
            }
            index = utf8.index(after: index)
        }

        return false
    }

    private static func singleTrimmedContentRange(
        from ranges: [Range<String.Index>],
        in source: String
    ) -> Range<String.Index>? {
        guard ranges.count == 1,
              let range = ranges.first,
              rangeContainsNonWhitespace(in: source, range: range) else {
            return nil
        }

        let leadingTrimmed = leadingWhitespaceTrimmedRange(in: source, range: range)
        let trimmed = trailingWhitespaceTrimmedRange(in: source, range: leadingTrimmed)
        return trimmed.lowerBound < trimmed.upperBound ? trimmed : nil
    }

    private static func isSingleLineListHeadingLiteral(in text: String, range: Range<String.Index>) -> Bool {
        guard range.lowerBound < range.upperBound,
              text[range.lowerBound] == "#" else {
            return false
        }

        var index = range.lowerBound
        var hashCount = 0
        while index < range.upperBound, text[index] == "#", hashCount < 6 {
            hashCount += 1
            index = text.index(after: index)
        }

        return hashCount >= 1 &&
            hashCount <= 6 &&
            index < range.upperBound &&
            text[index] == " "
    }

    private static func rangeContainsNonWhitespace(in text: String, range: Range<String.Index>) -> Bool {
        guard let start = range.lowerBound.samePosition(in: text.utf8),
              let end = range.upperBound.samePosition(in: text.utf8) else {
            return rangeContainsNonWhitespaceByCharacterScanning(in: text, range: range)
        }

        var index = start
        while index < end {
            switch text.utf8[index] {
            case 0x09...0x0D, 0x20:
                index = text.utf8.index(after: index)
            case 0x00..<0x80:
                return true
            default:
                return rangeContainsNonWhitespaceByCharacterScanning(in: text, range: range)
            }
        }

        return false
    }

    static func rangeContainsNonWhitespaceForTesting(in text: String, range: Range<String.Index>) -> Bool {
        rangeContainsNonWhitespace(in: text, range: range)
    }

    static func rangeContainsNonWhitespaceByCharacterScanningForTesting(
        in text: String,
        range: Range<String.Index>
    ) -> Bool {
        rangeContainsNonWhitespaceByCharacterScanning(in: text, range: range)
    }

    private static func rangeContainsNonWhitespaceByCharacterScanning(
        in text: String,
        range: Range<String.Index>
    ) -> Bool {
        var index = range.lowerBound
        while index < range.upperBound {
            if !text[index].isWhitespace {
                return true
            }
            index = text.index(after: index)
        }
        return false
    }

    private static func leadingWhitespaceTrimmedRange(
        in text: String,
        range: Range<String.Index>
    ) -> Range<String.Index> {
        guard let start = range.lowerBound.samePosition(in: text.utf8),
              let end = range.upperBound.samePosition(in: text.utf8) else {
            return leadingWhitespaceTrimmedRangeByCharacterScanning(in: text, range: range)
        }

        var lowerBound = start
        while lowerBound < end {
            switch text.utf8[lowerBound] {
            case 0x09...0x0D, 0x20:
                lowerBound = text.utf8.index(after: lowerBound)
            case 0x00..<0x80:
                guard let stringLowerBound = String.Index(lowerBound, within: text) else {
                    return leadingWhitespaceTrimmedRangeByCharacterScanning(in: text, range: range)
                }
                return stringLowerBound..<range.upperBound
            default:
                return leadingWhitespaceTrimmedRangeByCharacterScanning(in: text, range: range)
            }
        }

        return range.upperBound..<range.upperBound
    }

    static func leadingWhitespaceTrimmedRangeForTesting(
        in text: String,
        range: Range<String.Index>
    ) -> Range<String.Index> {
        leadingWhitespaceTrimmedRange(in: text, range: range)
    }

    static func leadingWhitespaceTrimmedRangeByCharacterScanningForTesting(
        in text: String,
        range: Range<String.Index>
    ) -> Range<String.Index> {
        leadingWhitespaceTrimmedRangeByCharacterScanning(in: text, range: range)
    }

    private static func leadingWhitespaceTrimmedRangeByCharacterScanning(
        in text: String,
        range: Range<String.Index>
    ) -> Range<String.Index> {
        var lowerBound = range.lowerBound
        while lowerBound < range.upperBound, text[lowerBound].isWhitespace {
            lowerBound = text.index(after: lowerBound)
        }
        return lowerBound..<range.upperBound
    }

    private static func trailingWhitespaceTrimmedRange(
        in text: String,
        range: Range<String.Index>
    ) -> Range<String.Index> {
        guard let start = range.lowerBound.samePosition(in: text.utf8),
              let end = range.upperBound.samePosition(in: text.utf8) else {
            return trailingWhitespaceTrimmedRangeByCharacterScanning(in: text, range: range)
        }

        var upperBound = end
        while upperBound > start {
            let previous = text.utf8.index(before: upperBound)
            switch text.utf8[previous] {
            case 0x09...0x0D, 0x20:
                upperBound = previous
            case 0x00..<0x80:
                guard let stringUpperBound = String.Index(upperBound, within: text) else {
                    return trailingWhitespaceTrimmedRangeByCharacterScanning(in: text, range: range)
                }
                return range.lowerBound..<stringUpperBound
            default:
                return trailingWhitespaceTrimmedRangeByCharacterScanning(in: text, range: range)
            }
        }

        return range.lowerBound..<range.lowerBound
    }

    static func trailingWhitespaceTrimmedRangeForTesting(
        in text: String,
        range: Range<String.Index>
    ) -> Range<String.Index> {
        trailingWhitespaceTrimmedRange(in: text, range: range)
    }

    static func trailingWhitespaceTrimmedRangeByCharacterScanningForTesting(
        in text: String,
        range: Range<String.Index>
    ) -> Range<String.Index> {
        trailingWhitespaceTrimmedRangeByCharacterScanning(in: text, range: range)
    }

    private static func trailingWhitespaceTrimmedRangeByCharacterScanning(
        in text: String,
        range: Range<String.Index>
    ) -> Range<String.Index> {
        var upperBound = range.upperBound
        while upperBound > range.lowerBound {
            let previous = text.index(before: upperBound)
            guard text[previous].isWhitespace else { break }
            upperBound = previous
        }
        return range.lowerBound..<upperBound
    }

    private static func closingFenceEnd(
        in text: String,
        from start: String.Index,
        fenceChar: Character,
        fenceLength: Int
    ) -> String.Index? {
        var index = start
        var closeFenceLength = 0
        while index < text.endIndex && text[index] == fenceChar {
            closeFenceLength += 1
            index = text.index(after: index)
        }

        return closeFenceLength >= fenceLength ? index : nil
    }

    private static func closingFenceEnd(
        in utf8: String.UTF8View,
        from start: String.UTF8View.Index,
        end: String.UTF8View.Index,
        fence: UInt8,
        fenceLength: Int
    ) -> String.UTF8View.Index? {
        var index = start
        var closeFenceLength = 0
        while index < end, utf8[index] == fence {
            closeFenceLength += 1
            index = utf8.index(after: index)
        }

        return closeFenceLength >= fenceLength ? index : nil
    }

    private static func appendCodeLine(
        _ line: Substring,
        to code: inout String,
        appendedLine: inout Bool
    ) {
        if appendedLine {
            code.append("\n")
        }
        code.append(contentsOf: line)
        appendedLine = true
    }

    private static func appendEmptyCodeLine(to code: inout String, appendedLine: inout Bool) {
        if appendedLine {
            code.append("\n")
        }
        appendedLine = true
    }
    
    private static func isAtParagraphBreak(_ state: inout ParserState) -> Bool {
        if let result = isAtParagraphBreakByUTF8Scanning(state) {
            return result
        }

        return isAtParagraphBreakByCharacterScanning(&state)
    }

    static func isAtParagraphBreakForTesting(_ state: inout ParserState) -> Bool {
        isAtParagraphBreak(&state)
    }

    static func isAtParagraphBreakByCharacterScanningForTesting(_ state: inout ParserState) -> Bool {
        isAtParagraphBreakByCharacterScanning(&state)
    }

    private static func isAtParagraphBreakByUTF8Scanning(_ state: ParserState) -> Bool? {
        if state.isAtEmptyLine() {
            return true
        }

        let utf8 = state.text.utf8
        var index = state.currentIndex
        var spaces = 0
        while index < state.endIndex, utf8[index] == 0x20, spaces < 3 {
            index = utf8.index(after: index)
            spaces += 1
        }

        guard index < state.endIndex else {
            return true
        }

        switch utf8[index] {
        case 0x3E: // >
            return true
        case 0x60, 0x7E: // ` ~
            let fence = utf8[index]
            var fenceCount = 0
            var scan = index
            while scan < state.endIndex, utf8[scan] == fence {
                fenceCount += 1
                scan = utf8.index(after: scan)
            }
            return fenceCount >= 3
        case 0x23: // #
            var hashCount = 1
            var scan = utf8.index(after: index)
            while scan < state.endIndex, utf8[scan] == 0x23, hashCount < 6 {
                hashCount += 1
                scan = utf8.index(after: scan)
            }
            return scan >= state.endIndex || utf8[scan] == 0x20 || utf8[scan] == 0x0A // space, newline
        case 0x2D, 0x2A, 0x5F: // - * _
            let rule = utf8[index]
            var ruleCount = 0
            var scan = index
            while scan < state.endIndex {
                let byte = utf8[scan]
                if byte == rule {
                    ruleCount += 1
                } else if byte != 0x20 { // space
                    break
                }
                scan = utf8.index(after: scan)
            }

            return ruleCount >= 3 && (scan >= state.endIndex || utf8[scan] == 0x0A) // newline
        case 0x00..<0x80:
            return false
        default:
            return nil
        }
    }

    private static func isAtParagraphBreakByCharacterScanning(_ state: inout ParserState) -> Bool {
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

    private static func shouldAttemptTable(_ state: ParserState) -> Bool {
        tableStartProbe(state) != nil
    }

    static func shouldAttemptTableForTesting(_ state: ParserState) -> Bool {
        shouldAttemptTable(state)
    }

    static func shouldAttemptTableByLineRangesForTesting(_ state: ParserState) -> Bool {
        shouldAttemptTableByLineRanges(state)
    }

    private static func paragraphStartProbes(
        _ state: ParserState,
        mode: ParagraphStartProbeMode
    ) -> ParagraphStartProbes {
        switch mode {
        case .shared:
            if let probes = paragraphStartProbesBySharedUTF8Scanning(state) {
                return probes
            }
            return paragraphStartProbesBySeparateScanning(state, useEligibility: true)
        case .gated:
            return paragraphStartProbesBySeparateScanning(state, useEligibility: true)
        case .always:
            return paragraphStartProbesBySeparateScanning(state, useEligibility: false)
        }
    }

    private static func paragraphStartProbesBySeparateScanning(
        _ state: ParserState,
        useEligibility: Bool
    ) -> ParagraphStartProbes {
        let eligibility = useEligibility ? paragraphStartProbeEligibility(state) : .unknown
        let tableStart = eligibility.table == .skip ? nil : tableStartProbe(state)
        let setextHeading = eligibility.setextHeading == .skip ? nil : setextHeadingProbe(state)
        return ParagraphStartProbes(tableStart: tableStart, setextHeading: setextHeading)
    }

    private static func paragraphStartProbeEligibility(_ state: ParserState) -> ParagraphStartProbeEligibility {
        guard let start = state.currentIndex.samePosition(in: state.text.utf8),
              let end = state.endIndex.samePosition(in: state.text.utf8) else {
            return .unknown
        }

        let utf8 = state.text.utf8
        var index = start
        var firstLineHasPipe = false
        var firstLineHasNonWhitespace = false
        while index < end {
            let byte = utf8[index]
            if byte == 0x0A { // newline
                break
            }
            if byte < 0x20, byte != 0x09 { // preserve line-range fallback for controls like CR
                return .unknown
            }
            if byte == 0x7C { // |
                firstLineHasPipe = true
            }
            if byte != 0x20 && byte != 0x09 { // space, tab
                firstLineHasNonWhitespace = true
            }
            index = utf8.index(after: index)
        }

        let hasNextLine = index < end && utf8[index] == 0x0A
        let tableEligibility: ProbeEligibility = firstLineHasPipe && hasNextLine ? .attempt : .skip
        guard firstLineHasNonWhitespace, hasNextLine else {
            return ParagraphStartProbeEligibility(table: tableEligibility, setextHeading: .skip)
        }

        let underlineStart = utf8.index(after: index)
        guard underlineStart < end else {
            return ParagraphStartProbeEligibility(table: tableEligibility, setextHeading: .skip)
        }

        let underlineFirstByte = utf8[underlineStart]
        let setextEligibility: ProbeEligibility = (underlineFirstByte == 0x3D || underlineFirstByte == 0x2D)
            ? .attempt
            : .skip

        return ParagraphStartProbeEligibility(table: tableEligibility, setextHeading: setextEligibility)
    }

    private static func paragraphStartProbesBySharedUTF8Scanning(_ state: ParserState) -> ParagraphStartProbes? {
        guard let start = state.currentIndex.samePosition(in: state.text.utf8),
              let end = state.endIndex.samePosition(in: state.text.utf8) else {
            return nil
        }

        let utf8 = state.text.utf8
        var firstLineEnd = start
        var firstLineHasPipe = false
        var firstLineHasNonWhitespace = false
        var firstLineIsASCII = true
        var firstContentIndex: String.Index?
        var afterLastContentIndex = start

        while firstLineEnd < end {
            let byte = utf8[firstLineEnd]
            if byte == 0x0A { // newline
                break
            }
            if byte < 0x20, byte != 0x09 { // preserve fallback behavior for controls like CR
                return nil
            }
            if byte == 0x7C { // |
                firstLineHasPipe = true
            }
            if byte >= 0x80 {
                firstLineIsASCII = false
            }
            if byte != 0x20 && byte != 0x09 { // space, tab
                firstLineHasNonWhitespace = true
                if byte < 0x80 {
                    firstContentIndex = firstContentIndex ?? firstLineEnd
                    afterLastContentIndex = utf8.index(after: firstLineEnd)
                }
            }
            firstLineEnd = utf8.index(after: firstLineEnd)
        }

        guard firstLineEnd < end, utf8[firstLineEnd] == 0x0A else {
            return ParagraphStartProbes.none
        }

        let secondLineStart = utf8.index(after: firstLineEnd)
        guard secondLineStart < end else {
            return ParagraphStartProbes.none
        }

        let secondFirstByte = utf8[secondLineStart]
        guard secondFirstByte != 0x0A else {
            return ParagraphStartProbes.none
        }
        if secondFirstByte < 0x20, secondFirstByte != 0x09 {
            return nil
        }

        let setextCandidate = firstLineHasNonWhitespace &&
            (secondFirstByte == 0x3D || secondFirstByte == 0x2D) // = -
        guard firstLineHasPipe || setextCandidate else {
            return ParagraphStartProbes.none
        }

        var secondLineEnd = secondLineStart
        var secondLineHasPipe = false
        var secondLineHasDash = false
        var setextLineIsValid = setextCandidate
        var setextTrailingSpaces = false

        while secondLineEnd < end {
            let byte = utf8[secondLineEnd]
            if byte == 0x0A { // newline
                break
            }
            if byte < 0x20 { // preserve fallback behavior for controls, including tabs, on underline lines
                return nil
            }
            if byte == 0x7C { // |
                secondLineHasPipe = true
            } else if byte == 0x2D { // -
                secondLineHasDash = true
            }

            if setextLineIsValid {
                if byte == secondFirstByte, !setextTrailingSpaces {
                    // Still in the underline marker run.
                } else if byte == 0x20 {
                    setextTrailingSpaces = true
                } else {
                    setextLineIsValid = false
                }
            }

            secondLineEnd = utf8.index(after: secondLineEnd)
        }

        let afterSecondLine: String.Index
        let lineBreaksToAfterSecondLine: Int
        let columnAfterSecondLine: Int
        if secondLineEnd < end, utf8[secondLineEnd] == 0x0A {
            afterSecondLine = utf8.index(after: secondLineEnd)
            lineBreaksToAfterSecondLine = 2
            columnAfterSecondLine = 1
        } else {
            afterSecondLine = secondLineEnd
            lineBreaksToAfterSecondLine = 1
            columnAfterSecondLine = utf8.distance(from: secondLineStart, to: secondLineEnd) + 1
        }

        let tableStart: TableStartProbe?
        if firstLineHasPipe && secondLineHasPipe && secondLineHasDash {
            tableStart = TableStartProbe(
                headerRange: state.currentIndex..<firstLineEnd,
                separatorRange: secondLineStart..<secondLineEnd,
                afterSeparatorLine: afterSecondLine,
                lineBreaksToAfterSeparatorLine: lineBreaksToAfterSecondLine,
                columnAfterSeparatorLine: columnAfterSecondLine
            )
        } else {
            tableStart = nil
        }

        let setextHeading: SetextHeadingProbe?
        if setextLineIsValid {
            let headingRange: Range<String.Index>
            if firstLineIsASCII, let firstContentIndex {
                headingRange = firstContentIndex..<afterLastContentIndex
            } else {
                let headingLineRange = state.currentIndex..<firstLineEnd
                headingRange = whitespaceTrimmedRange(in: state.text, range: headingLineRange)
            }
            if headingRange.lowerBound < headingRange.upperBound {
                setextHeading = SetextHeadingProbe(
                    headingRange: headingRange,
                    level: secondFirstByte == 0x3D ? 1 : 2,
                    afterUnderlineLine: afterSecondLine,
                    lineBreaksToAfterUnderlineLine: lineBreaksToAfterSecondLine,
                    columnAfterUnderlineLine: columnAfterSecondLine
                )
            } else {
                setextHeading = nil
            }
        } else {
            setextHeading = nil
        }

        return ParagraphStartProbes(tableStart: tableStart, setextHeading: setextHeading)
    }

    private static func tableStartProbe(_ state: ParserState) -> TableStartProbe? {
        tableStartProbeByUTF8Scanning(state)
    }

    private static func tableStartProbeByUTF8Scanning(_ state: ParserState) -> TableStartProbe? {
        guard let start = state.currentIndex.samePosition(in: state.text.utf8),
              let end = state.endIndex.samePosition(in: state.text.utf8) else {
            return tableStartProbeByLineRanges(state)
        }

        let utf8 = state.text.utf8
        var index = start
        var headerHasPipe = false
        while index < end {
            let byte = utf8[index]
            if byte == 0x0A { // newline
                break
            }
            if byte < 0x20, byte != 0x09 { // preserve line-range semantics for controls like CR
                return tableStartProbeByLineRanges(state)
            }
            if byte == 0x7C { // |
                headerHasPipe = true
            }
            index = utf8.index(after: index)
        }

        let headerEnd = index
        guard headerHasPipe,
              index < end,
              utf8[index] == 0x0A else {
            return nil
        }

        index = utf8.index(after: index)
        let separatorStart = index
        var separatorHasPipe = false
        var separatorHasDash = false
        while index < end {
            let byte = utf8[index]
            if byte == 0x0A { // newline
                break
            }
            if byte < 0x20, byte != 0x09 { // preserve line-range semantics for controls like CR
                return tableStartProbeByLineRanges(state)
            }
            if byte == 0x7C { // |
                separatorHasPipe = true
            } else if byte == 0x2D { // -
                separatorHasDash = true
            }
            index = utf8.index(after: index)
        }

        guard separatorHasPipe && separatorHasDash else {
            return nil
        }

        let separatorEnd = index
        let afterSeparator: String.Index
        let lineBreaks: Int
        let column: Int
        if index < end, utf8[index] == 0x0A {
            afterSeparator = utf8.index(after: index)
            lineBreaks = 2
            column = 1
        } else {
            afterSeparator = separatorEnd
            lineBreaks = 1
            column = utf8.distance(from: separatorStart, to: separatorEnd) + 1
        }

        return TableStartProbe(
            headerRange: state.currentIndex..<headerEnd,
            separatorRange: separatorStart..<separatorEnd,
            afterSeparatorLine: afterSeparator,
            lineBreaksToAfterSeparatorLine: lineBreaks,
            columnAfterSeparatorLine: column
        )
    }

    private static func shouldAttemptTableByLineRanges(_ state: ParserState) -> Bool {
        tableStartProbeByLineRanges(state) != nil
    }

    private static func tableStartProbeByLineRanges(_ state: ParserState) -> TableStartProbe? {
        let headerRange = currentLineRange(in: state, from: state.currentIndex)
        guard lineContains("|", in: state.text, range: headerRange),
              let separatorRange = nextLineRange(in: state, after: headerRange) else {
            return nil
        }

        guard lineContains("|", in: state.text, range: separatorRange),
              lineContains("-", in: state.text, range: separatorRange) else {
            return nil
        }

        let afterSeparator: String.Index
        let lineBreaks: Int
        let column: Int
        if separatorRange.upperBound < state.endIndex,
           state.text[separatorRange.upperBound] == "\n" {
            afterSeparator = state.text.index(after: separatorRange.upperBound)
            lineBreaks = 2
            column = 1
        } else {
            afterSeparator = separatorRange.upperBound
            lineBreaks = 1
            column = state.text.distance(from: separatorRange.lowerBound, to: separatorRange.upperBound) + 1
        }

        return TableStartProbe(
            headerRange: headerRange,
            separatorRange: separatorRange,
            afterSeparatorLine: afterSeparator,
            lineBreaksToAfterSeparatorLine: lineBreaks,
            columnAfterSeparatorLine: column
        )
    }

    private static func moveStateAfterTableStartProbe(_ state: inout ParserState, _ probe: TableStartProbe) {
        guard probe.afterSeparatorLine >= state.currentIndex else {
            state.move(to: probe.afterSeparatorLine)
            return
        }

        state.currentIndex = probe.afterSeparatorLine
        state.line += probe.lineBreaksToAfterSeparatorLine
        state.column = probe.columnAfterSeparatorLine
    }

    private static func shouldAttemptSetextHeading(_ state: ParserState) -> Bool {
        if let result = shouldAttemptSetextHeadingByUTF8Scanning(state) {
            return result
        }

        return shouldAttemptSetextHeadingByLineRanges(state)
    }

    static func shouldAttemptSetextHeadingForTesting(_ state: ParserState) -> Bool {
        shouldAttemptSetextHeading(state)
    }

    static func shouldAttemptSetextHeadingByLineRangesForTesting(_ state: ParserState) -> Bool {
        shouldAttemptSetextHeadingByLineRanges(state)
    }

    private static func setextHeadingProbe(
        _ state: ParserState,
        useScannedHeadingRange: Bool = true
    ) -> SetextHeadingProbe? {
        setextHeadingProbeByUTF8Scanning(state, useScannedHeadingRange: useScannedHeadingRange)
    }

    private static func shouldAttemptSetextHeadingByUTF8Scanning(_ state: ParserState) -> Bool? {
        guard let start = state.currentIndex.samePosition(in: state.text.utf8),
              let end = state.endIndex.samePosition(in: state.text.utf8) else {
            return nil
        }

        let utf8 = state.text.utf8
        var headingIndex = start
        var headingHasNonWhitespace = false
        while headingIndex < end {
            let byte = utf8[headingIndex]
            if byte == 0x0A { // newline
                break
            }
            if byte < 0x20, byte != 0x09 { // preserve line-range semantics for controls like CR
                return nil
            }
            if byte != 0x20 && byte != 0x09 { // space, tab
                headingHasNonWhitespace = true
            }
            headingIndex = utf8.index(after: headingIndex)
        }

        guard headingHasNonWhitespace,
              headingIndex < end,
              utf8[headingIndex] == 0x0A else {
            return false
        }

        var underlineIndex = utf8.index(after: headingIndex)
        guard underlineIndex < end else {
            return false
        }

        let underline = utf8[underlineIndex]
        guard underline == 0x3D || underline == 0x2D else { // = -
            return false
        }

        while underlineIndex < end {
            let byte = utf8[underlineIndex]
            if byte == 0x0A { // newline
                break
            }
            if byte < 0x20 { // preserve line-range semantics for controls like CR
                return nil
            }
            if byte != underline && byte != 0x20 { // space
                return false
            }
            underlineIndex = utf8.index(after: underlineIndex)
        }

        return true
    }

    private static func setextHeadingProbeByUTF8Scanning(
        _ state: ParserState,
        useScannedHeadingRange: Bool
    ) -> SetextHeadingProbe? {
        guard let start = state.currentIndex.samePosition(in: state.text.utf8),
              let end = state.endIndex.samePosition(in: state.text.utf8) else {
            return nil
        }

        let utf8 = state.text.utf8
        var headingIndex = start
        var headingHasNonWhitespace = false
        var headingIsASCII = true
        var firstContentIndex: String.Index?
        var afterLastContentIndex = start
        while headingIndex < end {
            let byte = utf8[headingIndex]
            if byte == 0x0A { // newline
                break
            }
            if byte < 0x20, byte != 0x09 { // preserve line-range semantics for controls like CR
                return nil
            }
            if byte >= 0x80 {
                headingIsASCII = false
            }
            if byte != 0x20 && byte != 0x09 { // space, tab
                headingHasNonWhitespace = true
                if byte < 0x80 {
                    firstContentIndex = firstContentIndex ?? headingIndex
                    afterLastContentIndex = utf8.index(after: headingIndex)
                }
            }
            headingIndex = utf8.index(after: headingIndex)
        }

        guard headingHasNonWhitespace,
              headingIndex < end,
              utf8[headingIndex] == 0x0A else {
            return nil
        }

        var underlineIndex = utf8.index(after: headingIndex)
        guard underlineIndex < end else {
            return nil
        }

        let underline = utf8[underlineIndex]
        guard underline == 0x3D || underline == 0x2D else { // = -
            return nil
        }

        let underlineStart = underlineIndex
        while underlineIndex < end {
            let byte = utf8[underlineIndex]
            guard byte == underline else { break }
            underlineIndex = utf8.index(after: underlineIndex)
        }

        while underlineIndex < end, utf8[underlineIndex] == 0x20 { // space
            underlineIndex = utf8.index(after: underlineIndex)
        }

        if underlineIndex < end, utf8[underlineIndex] != 0x0A {
            return nil
        }

        let headingRange: Range<String.Index>
        if useScannedHeadingRange, headingIsASCII, let firstContentIndex {
            headingRange = firstContentIndex..<afterLastContentIndex
        } else {
            let headingLineRange = state.currentIndex..<headingIndex
            headingRange = whitespaceTrimmedRange(in: state.text, range: headingLineRange)
        }
        guard headingRange.lowerBound < headingRange.upperBound else {
            return nil
        }

        let afterUnderline: String.Index
        let lineBreaks: Int
        let column: Int
        if underlineIndex < end, utf8[underlineIndex] == 0x0A {
            afterUnderline = utf8.index(after: underlineIndex)
            lineBreaks = 2
            column = 1
        } else {
            afterUnderline = underlineIndex
            lineBreaks = 1
            column = utf8.distance(from: underlineStart, to: underlineIndex) + 1
        }

        return SetextHeadingProbe(
            headingRange: headingRange,
            level: underline == 0x3D ? 1 : 2,
            afterUnderlineLine: afterUnderline,
            lineBreaksToAfterUnderlineLine: lineBreaks,
            columnAfterUnderlineLine: column
        )
    }

    private static func shouldAttemptSetextHeadingByLineRanges(_ state: ParserState) -> Bool {
        let headingRange = currentLineRange(in: state, from: state.currentIndex)
        guard lineHasNonWhitespace(in: state.text, range: headingRange),
              let underlineRange = nextLineRange(in: state, after: headingRange),
              let underline = firstUTF8Byte(in: state.text, range: underlineRange),
              underline == 0x3D || underline == 0x2D else { // = -
            return false
        }

        return lineContainsOnlySetextUnderline(underline, in: state.text, range: underlineRange)
    }

    private static func moveStateAfterSetextHeadingProbe(_ state: inout ParserState, _ probe: SetextHeadingProbe) {
        guard probe.afterUnderlineLine >= state.currentIndex else {
            state.move(to: probe.afterUnderlineLine)
            return
        }

        state.currentIndex = probe.afterUnderlineLine
        state.line += probe.lineBreaksToAfterUnderlineLine
        state.column = probe.columnAfterUnderlineLine
    }

    private static func scanParagraphContinuationLine(_ state: ParserState) -> ParagraphContinuationLineScan? {
        guard let start = state.currentIndex.samePosition(in: state.text.utf8),
              let end = state.endIndex.samePosition(in: state.text.utf8) else {
            return nil
        }

        let utf8 = state.text.utf8
        var index = start
        while index < end {
            let byte = utf8[index]
            if byte == 0x0A { // newline
                break
            }
            switch byte {
            case 0x09, 0x20: // tab, space
                index = utf8.index(after: index)
            case 0x00...0x1F, 0x80...0xFF:
                return nil
            default:
                guard isParagraphBreakingBlockStartByte(byte) else {
                    return scanPlainParagraphContinuationLine(
                        in: utf8,
                        start: start,
                        from: utf8.index(after: index),
                        end: end
                    )
                }
                return scanParagraphBreakingContinuationLine(
                    in: utf8,
                    start: start,
                    firstNonWhitespace: index,
                    firstNonWhitespaceByte: byte,
                    end: end
                )
            }
        }

        return ParagraphContinuationLineScan(
            lineEnd: index,
            columnAdvance: utf8.distance(from: start, to: index),
            startsParagraphBreakingBlock: false
        )
    }

    private static func scanPlainParagraphContinuationLine(
        in utf8: String.UTF8View,
        start: String.UTF8View.Index,
        from index: String.UTF8View.Index,
        end: String.UTF8View.Index
    ) -> ParagraphContinuationLineScan? {
        var index = index
        while index < end {
            let byte = utf8[index]
            if byte == 0x0A { // newline
                break
            }
            if byte >= 0x80 {
                return nil
            }
            index = utf8.index(after: index)
        }

        return ParagraphContinuationLineScan(
            lineEnd: index,
            columnAdvance: utf8.distance(from: start, to: index),
            startsParagraphBreakingBlock: false
        )
    }

    private static func scanParagraphBreakingContinuationLine(
        in utf8: String.UTF8View,
        start: String.UTF8View.Index,
        firstNonWhitespace: String.UTF8View.Index,
        firstNonWhitespaceByte: UInt8,
        end: String.UTF8View.Index
    ) -> ParagraphContinuationLineScan? {
        var index = firstNonWhitespace
        var effectiveEnd = firstNonWhitespace

        while index < end {
            let byte = utf8[index]
            if byte == 0x0A { // newline
                break
            }
            switch byte {
            case 0x09, 0x20: // tab, space
                break
            case 0x00...0x1F, 0x80...0xFF:
                return nil
            default:
                effectiveEnd = utf8.index(after: index)
            }
            index = utf8.index(after: index)
        }

        return ParagraphContinuationLineScan(
            lineEnd: index,
            columnAdvance: utf8.distance(from: start, to: index),
            startsParagraphBreakingBlock: lineStartsParagraphBreakingBlockASCII(
                startByte: firstNonWhitespaceByte,
                in: utf8,
                start: firstNonWhitespace,
                end: effectiveEnd
            )
        )
    }

    private static func lineStartsParagraphBreakingBlock(in text: String, range: Range<String.Index>) -> Bool {
        guard let start = range.lowerBound.samePosition(in: text.utf8),
              let end = range.upperBound.samePosition(in: text.utf8) else {
            return lineStartsParagraphBreakingBlockByCharacterScanning(in: text, range: range)
        }

        let utf8 = text.utf8
        var first = start
        while first < end {
            switch utf8[first] {
            case 0x09, 0x20: // tab, space
                first = utf8.index(after: first)
            case 0x00...0x1F:
                return lineStartsParagraphBreakingBlockByCharacterScanning(in: text, range: range)
            case 0x00..<0x80:
                guard isParagraphBreakingBlockStartByte(utf8[first]) else {
                    return false
                }
                return lineStartsParagraphBreakingBlockFromASCIIStart(
                    in: text,
                    utf8: utf8,
                    start: first,
                    end: end,
                    originalRange: range
                )
            default:
                return lineStartsParagraphBreakingBlockByCharacterScanning(in: text, range: range)
            }
        }

        return false
    }

    private static func lineStartsParagraphBreakingBlockFromASCIIStart(
        in text: String,
        utf8: String.UTF8View,
        start: String.UTF8View.Index,
        end: String.UTF8View.Index,
        originalRange: Range<String.Index>
    ) -> Bool {
        var effectiveEnd = end
        while effectiveEnd > start {
            let previous = utf8.index(before: effectiveEnd)
            switch utf8[previous] {
            case 0x09, 0x20: // tab, space
                effectiveEnd = previous
            case 0x00...0x1F:
                return lineStartsParagraphBreakingBlockByCharacterScanning(in: text, range: originalRange)
            case 0x00..<0x80:
                return lineStartsParagraphBreakingBlockASCII(startByte: utf8[start], in: utf8, start: start, end: effectiveEnd)
            default:
                return lineStartsParagraphBreakingBlockByCharacterScanning(in: text, range: originalRange)
            }
        }

        return lineStartsParagraphBreakingBlockASCII(startByte: utf8[start], in: utf8, start: start, end: effectiveEnd)
    }

    private static func lineStartsParagraphBreakingBlockASCII(
        startByte: UInt8,
        in utf8: String.UTF8View,
        start: String.UTF8View.Index,
        end: String.UTF8View.Index
    ) -> Bool {
        switch startByte {
        case 0x23: // #
            return isATXHeadingStartASCII(in: utf8, start: start, end: end)
        case 0x3E: // >
            return true
        case 0x60: // `
            return hasASCIITriple(0x60, in: utf8, start: start, end: end)
        case 0x7E: // ~
            return hasASCIITriple(0x7E, in: utf8, start: start, end: end)
        case 0x2D: // -
            return hasASCIITriple(0x2D, in: utf8, start: start, end: end) ||
                isListMarkerASCII(in: utf8, start: start, end: end)
        case 0x2A: // *
            return hasASCIITriple(0x2A, in: utf8, start: start, end: end) ||
                isListMarkerASCII(in: utf8, start: start, end: end)
        case 0x5F: // _
            return hasASCIITriple(0x5F, in: utf8, start: start, end: end)
        case 0x2B, // +
             0x30...0x39: // 0...9
            return isListMarkerASCII(in: utf8, start: start, end: end)
        default:
            return false
        }
    }

    private static func lineStartsParagraphBreakingBlockByFullTrim(
        in text: String,
        range: Range<String.Index>
    ) -> Bool {
        let trimmedRange = whitespaceTrimmedRange(in: text, range: range)
        guard trimmedRange.lowerBound < trimmedRange.upperBound else {
            return false
        }

        guard let start = trimmedRange.lowerBound.samePosition(in: text.utf8),
              let end = trimmedRange.upperBound.samePosition(in: text.utf8) else {
            return lineStartsParagraphBreakingBlockByCharacterScanning(in: text, range: range)
        }

        let utf8 = text.utf8
        switch utf8[start] {
        case 0x23: // #
            return isATXHeadingStartASCII(in: utf8, start: start, end: end)
        case 0x3E: // >
            return true
        case 0x60: // `
            return hasASCIITriple(0x60, in: utf8, start: start, end: end)
        case 0x7E: // ~
            return hasASCIITriple(0x7E, in: utf8, start: start, end: end)
        case 0x2D: // -
            return hasASCIITriple(0x2D, in: utf8, start: start, end: end) ||
                isListMarkerASCII(in: utf8, start: start, end: end)
        case 0x2A: // *
            return hasASCIITriple(0x2A, in: utf8, start: start, end: end) ||
                isListMarkerASCII(in: utf8, start: start, end: end)
        case 0x5F: // _
            return hasASCIITriple(0x5F, in: utf8, start: start, end: end)
        case 0x2B, // +
             0x30...0x39: // 0...9
            return isListMarkerASCII(in: utf8, start: start, end: end)
        case 0x00..<0x80:
            return false
        default:
            return lineStartsParagraphBreakingBlockByCharacterScanning(in: text, range: range)
        }
    }

    private static func isParagraphBreakingBlockStartByte(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x23, // #
             0x2A, // *
             0x2B, // +
             0x2D, // -
             0x30...0x39, // 0...9
             0x3E, // >
             0x5F, // _
             0x60, // `
             0x7E: // ~
            return true
        default:
            return false
        }
    }

    static func lineStartsParagraphBreakingBlockForTesting(
        in text: String,
        range: Range<String.Index>
    ) -> Bool {
        lineStartsParagraphBreakingBlock(in: text, range: range)
    }

    static func lineStartsParagraphBreakingBlockByFullTrimForTesting(
        in text: String,
        range: Range<String.Index>
    ) -> Bool {
        lineStartsParagraphBreakingBlockByFullTrim(in: text, range: range)
    }

    static func lineStartsParagraphBreakingBlockByCharacterScanningForTesting(
        in text: String,
        range: Range<String.Index>
    ) -> Bool {
        lineStartsParagraphBreakingBlockByCharacterScanning(in: text, range: range)
    }

    private static func lineStartsParagraphBreakingBlockByCharacterScanning(
        in text: String,
        range: Range<String.Index>
    ) -> Bool {
        let trimmedRange = whitespaceTrimmedRangeByCharacterScanning(in: text, range: range)
        guard trimmedRange.lowerBound < trimmedRange.upperBound else {
            return false
        }

        let first = text[trimmedRange.lowerBound]
        if first == "#" {
            return isATXHeadingStart(in: text, range: trimmedRange)
        }
        if first == ">" {
            return true
        }
        if hasPrefix("```", in: text, range: trimmedRange) ||
           hasPrefix("~~~", in: text, range: trimmedRange) ||
           hasPrefix("---", in: text, range: trimmedRange) ||
           hasPrefix("***", in: text, range: trimmedRange) ||
           hasPrefix("___", in: text, range: trimmedRange) {
            return true
        }

        return isListMarker(in: text, range: trimmedRange)
    }

    private static func hasASCIITriple(
        _ byte: UInt8,
        in utf8: String.UTF8View,
        start: String.UTF8View.Index,
        end: String.UTF8View.Index
    ) -> Bool {
        var index = start
        for _ in 0..<3 {
            guard index < end, utf8[index] == byte else {
                return false
            }
            index = utf8.index(after: index)
        }
        return true
    }

    private static func isATXHeadingStartASCII(
        in utf8: String.UTF8View,
        start: String.UTF8View.Index,
        end: String.UTF8View.Index
    ) -> Bool {
        var index = start
        var hashCount = 0
        while index < end, utf8[index] == 0x23, hashCount < 6 {
            hashCount += 1
            index = utf8.index(after: index)
        }

        guard hashCount > 0 else {
            return false
        }
        if index < end {
            return utf8[index] == 0x20 // space
        }
        return true
    }

    private static func isListMarkerASCII(
        in utf8: String.UTF8View,
        start: String.UTF8View.Index,
        end: String.UTF8View.Index
    ) -> Bool {
        let first = utf8[start]
        if first == 0x2D || first == 0x2A || first == 0x2B { // - * +
            let next = utf8.index(after: start)
            return next < end && utf8[next] == 0x20 // space
        }

        guard first >= 0x30, first <= 0x39 else {
            return false
        }

        var index = start
        while index < end, utf8[index] >= 0x30, utf8[index] <= 0x39 {
            index = utf8.index(after: index)
        }

        guard index < end else {
            return false
        }

        let delimiter = utf8[index]
        guard delimiter == 0x2E || delimiter == 0x29 else { // . )
            return false
        }

        let afterDelimiter = utf8.index(after: index)
        return afterDelimiter < end && utf8[afterDelimiter] == 0x20 // space
    }

    private static func whitespaceTrimmedRange(in text: String, range: Range<String.Index>) -> Range<String.Index> {
        guard let start = range.lowerBound.samePosition(in: text.utf8),
              let end = range.upperBound.samePosition(in: text.utf8) else {
            return whitespaceTrimmedRangeByCharacterScanning(in: text, range: range)
        }

        let utf8 = text.utf8
        var lower = start
        var upper = end

        trimLeading: while lower < upper {
            switch utf8[lower] {
            case 0x09, 0x20: // tab, space
                lower = utf8.index(after: lower)
            case 0x00...0x1F: // ambiguous ASCII controls; preserve CharacterSet semantics
                return whitespaceTrimmedRangeByCharacterScanning(in: text, range: range)
            case 0x00..<0x80:
                break trimLeading
            default:
                return whitespaceTrimmedRangeByCharacterScanning(in: text, range: range)
            }
        }

        trimTrailing: while upper > lower {
            let previous = utf8.index(before: upper)
            switch utf8[previous] {
            case 0x09, 0x20: // tab, space
                upper = previous
            case 0x00...0x1F: // ambiguous ASCII controls; preserve CharacterSet semantics
                return whitespaceTrimmedRangeByCharacterScanning(in: text, range: range)
            case 0x00..<0x80:
                break trimTrailing
            default:
                return whitespaceTrimmedRangeByCharacterScanning(in: text, range: range)
            }
        }

        guard let stringLower = String.Index(lower, within: text),
              let stringUpper = String.Index(upper, within: text) else {
            return whitespaceTrimmedRangeByCharacterScanning(in: text, range: range)
        }

        return stringLower..<stringUpper
    }

    static func whitespaceTrimmedRangeForTesting(
        in text: String,
        range: Range<String.Index>
    ) -> Range<String.Index> {
        whitespaceTrimmedRange(in: text, range: range)
    }

    static func whitespaceTrimmedRangeByCharacterScanningForTesting(
        in text: String,
        range: Range<String.Index>
    ) -> Range<String.Index> {
        whitespaceTrimmedRangeByCharacterScanning(in: text, range: range)
    }

    private static func whitespaceTrimmedRangeByCharacterScanning(
        in text: String,
        range: Range<String.Index>
    ) -> Range<String.Index> {
        var lower = range.lowerBound
        var upper = range.upperBound

        while lower < upper, isTrimmableWhitespace(text[lower]) {
            lower = text.index(after: lower)
        }

        while upper > lower {
            let previous = text.index(before: upper)
            if !isTrimmableWhitespace(text[previous]) {
                break
            }
            upper = previous
        }

        return lower..<upper
    }

    private static func isTrimmableWhitespace(_ character: Character) -> Bool {
        for scalar in character.unicodeScalars {
            if !CharacterSet.whitespaces.contains(scalar) {
                return false
            }
        }
        return true
    }

    private static func hasPrefix(
        _ prefix: String,
        in text: String,
        range: Range<String.Index>
    ) -> Bool {
        var index = range.lowerBound
        for expected in prefix {
            guard index < range.upperBound, text[index] == expected else {
                return false
            }
            index = text.index(after: index)
        }
        return true
    }

    private static func isATXHeadingStart(in text: String, range: Range<String.Index>) -> Bool {
        var index = range.lowerBound
        var hashCount = 0
        while index < range.upperBound, text[index] == "#", hashCount < 6 {
            hashCount += 1
            index = text.index(after: index)
        }

        guard hashCount > 0 else {
            return false
        }
        if index < range.upperBound {
            return text[index] == " "
        }
        return true
    }

    private static func isListMarker(in text: String, range: Range<String.Index>) -> Bool {
        let first = text[range.lowerBound]
        if first == "-" || first == "*" || first == "+" {
            let next = text.index(after: range.lowerBound)
            return next < range.upperBound && text[next] == " "
        }

        guard first.isNumber else {
            return false
        }

        var index = range.lowerBound
        while index < range.upperBound, text[index].isNumber {
            index = text.index(after: index)
        }

        guard index < range.upperBound else {
            return false
        }

        let delimiter = text[index]
        guard delimiter == "." || delimiter == ")" else {
            return false
        }

        let afterDelimiter = text.index(after: index)
        return afterDelimiter < range.upperBound && text[afterDelimiter] == " "
    }

    private static func shouldAttemptListMarker(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character == "-" || character == "*" || character == "+" || character.isNumber
    }

    private static func shouldAttemptHorizontalRule(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character == "-" || character == "*" || character == "_"
    }

    private static func shouldAttemptFootnoteDefinition(_ state: ParserState) -> Bool {
        guard state.currentIndex < state.endIndex,
              state.text[state.currentIndex] == "[" else {
            return false
        }

        let next = state.text.index(after: state.currentIndex)
        return next < state.endIndex && state.text[next] == "^"
    }

    private static func currentLineRange(in state: ParserState, from start: String.Index) -> Range<String.Index> {
        guard let uStart = start.samePosition(in: state.text.utf8),
              let uEnd = state.endIndex.samePosition(in: state.text.utf8) else {
            var end = start
            while end < state.endIndex && state.text[end] != "\n" {
                end = state.text.index(after: end)
            }
            return start..<end
        }

        var uIndex = uStart
        while uIndex < uEnd && state.text.utf8[uIndex] != 0x0A {
            uIndex = state.text.utf8.index(after: uIndex)
        }

        guard let end = String.Index(uIndex, within: state.text) else {
            return start..<start
        }
        return start..<end
    }

    private static func nextLineRange(
        in state: ParserState,
        after lineRange: Range<String.Index>
    ) -> Range<String.Index>? {
        guard lineRange.upperBound < state.endIndex,
              state.text[lineRange.upperBound] == "\n" else {
            return nil
        }

        let start = state.text.index(after: lineRange.upperBound)
        return currentLineRange(in: state, from: start)
    }

    private static func lineContains(
        _ target: Character,
        in text: String,
        range: Range<String.Index>
    ) -> Bool {
        guard let targetByte = target.asciiValue,
              let start = range.lowerBound.samePosition(in: text.utf8),
              let end = range.upperBound.samePosition(in: text.utf8) else {
            var index = range.lowerBound
            while index < range.upperBound {
                if text[index] == target {
                    return true
                }
                index = text.index(after: index)
            }
            return false
        }

        var index = start
        while index < end {
            if text.utf8[index] == targetByte {
                return true
            }
            index = text.utf8.index(after: index)
        }
        return false
    }

    private static func firstUTF8Byte(in text: String, range: Range<String.Index>) -> UInt8? {
        guard range.lowerBound < range.upperBound,
              let start = range.lowerBound.samePosition(in: text.utf8),
              start < text.utf8.endIndex else {
            return nil
        }
        return text.utf8[start]
    }

    private static func lineHasNonWhitespace(in text: String, range: Range<String.Index>) -> Bool {
        guard let start = range.lowerBound.samePosition(in: text.utf8),
              let end = range.upperBound.samePosition(in: text.utf8) else {
            var index = range.lowerBound
            while index < range.upperBound {
                let ch = text[index]
                if ch != " " && ch != "\t" {
                    return true
                }
                index = text.index(after: index)
            }
            return false
        }

        var index = start
        while index < end {
            let byte = text.utf8[index]
            if byte != 0x20 && byte != 0x09 { // space, tab
                return true
            }
            index = text.utf8.index(after: index)
        }
        return false
    }

    private static func lineContainsOnlySetextUnderline(
        _ underline: UInt8,
        in text: String,
        range: Range<String.Index>
    ) -> Bool {
        guard let start = range.lowerBound.samePosition(in: text.utf8),
              let end = range.upperBound.samePosition(in: text.utf8) else {
            let underlineCharacter: Character = underline == 0x3D ? "=" : "-"
            var index = range.lowerBound
            while index < range.upperBound {
                let ch = text[index]
                if ch != underlineCharacter && ch != " " {
                    return false
                }
                index = text.index(after: index)
            }
            return true
        }

        var index = start
        while index < end {
            let byte = text.utf8[index]
            if byte != underline && byte != 0x20 { // space
                return false
            }
            index = text.utf8.index(after: index)
        }
        return true
    }
    
}

// MARK: - Array Extension

private extension Array {
    subscript(safe index: Int) -> Element? {
        return index >= 0 && index < count ? self[index] : nil
    }
}

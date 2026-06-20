import Foundation
import os
import QuartzCore

enum ParallelChunkSplitter {
    struct RangeChunk: Sendable {
        let index: Int
        let range: Range<String.Index>
        let startOffset: Int
    }

    struct CopiedChunk: Sendable {
        let index: Int
        let text: String
        let startOffset: Int
    }

    static func splitRanges(markdown: String, chunkSize: Int) -> [RangeChunk] {
        splitRangesClassified(markdown: markdown, chunkSize: chunkSize)
    }

    static func splitRangesByRepeatedLineScanningForTesting(markdown: String, chunkSize: Int) -> [RangeChunk] {
        guard !markdown.isEmpty else { return [] }

        var chunks: [RangeChunk] = []
        var chunkStart = markdown.startIndex
        var chunkStartOffset = 0
        var chunkIndex = 0
        var chunkUTF8Count = 0
        var inCodeBlock = false
        var inTable = false
        var prevLineHadPipes = false
        var inBlockquote = false
        var inList = false
        var lastLineNonEmpty = false

        var lineStart = markdown.startIndex
        while lineStart < markdown.endIndex {
            let lineEnd = lineEndIndex(in: markdown, from: lineStart)
            let nextLineStart = lineEnd < markdown.endIndex ? markdown.index(after: lineEnd) : lineEnd
            let lineRange = lineStart..<lineEnd

            if lineHasPrefix("```", in: markdown, range: lineRange) ||
                lineHasPrefix("~~~", in: markdown, range: lineRange) {
                inCodeBlock.toggle()
            }

            if !inCodeBlock {
                if !inTable {
                    if prevLineHadPipes && isTableSeparator(in: markdown, range: lineRange) {
                        inTable = true
                    }
                    prevLineHadPipes = lineContains("|", in: markdown, range: lineRange)
                } else if !lineContains("|", in: markdown, range: lineRange) {
                    inTable = false
                    prevLineHadPipes = false
                }
            }

            if !inCodeBlock {
                if lineHasPrefix(">", in: markdown, range: lineRange) {
                    inBlockquote = true
                } else if lineRange.isEmpty {
                    inBlockquote = false
                }
            }

            if !inCodeBlock {
                let trimmedRange = whitespaceTrimmedRange(in: markdown, range: lineRange)
                if trimmedLineStartsUnorderedList(in: markdown, range: trimmedRange) ||
                    trimmedLineStartsOrderedList(in: markdown, range: trimmedRange) {
                    inList = true
                } else if trimmedRange.isEmpty {
                    inList = false
                }
            }

            chunkUTF8Count += markdown.utf8.distance(from: lineStart, to: nextLineStart)

            let trimmedRange = whitespaceTrimmedRange(in: markdown, range: lineRange)
            let isSetextUnderline = isSetextUnderline(in: markdown, range: trimmedRange)
            let avoidSetextSplit = lastLineNonEmpty && isSetextUnderline
            let isLastLine = nextLineStart >= markdown.endIndex
            let shouldSplit = chunkUTF8Count >= chunkSize &&
                !inCodeBlock && !inTable && !inBlockquote && !inList &&
                !avoidSetextSplit &&
                (lineRange.isEmpty || isLastLine)

            if shouldSplit || isLastLine {
                chunks.append(RangeChunk(
                    index: chunkIndex,
                    range: chunkStart..<nextLineStart,
                    startOffset: chunkStartOffset
                ))
                chunkStartOffset += chunkUTF8Count
                chunkStart = nextLineStart
                chunkUTF8Count = 0
                chunkIndex += 1
            }

            lastLineNonEmpty = !lineRange.isEmpty
            lineStart = nextLineStart
        }

        if chunkStart < markdown.endIndex {
            chunks.append(RangeChunk(
                index: chunkIndex,
                range: chunkStart..<markdown.endIndex,
                startOffset: chunkStartOffset
            ))
        }

        return chunks
    }

    private static func splitRangesClassified(
        markdown: String,
        chunkSize: Int
    ) -> [RangeChunk] {
        guard !markdown.isEmpty else { return [] }

        var chunks: [RangeChunk] = []
        var chunkStart = markdown.startIndex
        var chunkStartOffset = 0
        var chunkIndex = 0
        var chunkUTF8Count = 0
        var inCodeBlock = false
        var inTable = false
        var prevLineHadPipes = false
        var inBlockquote = false
        var inList = false
        var lastLineNonEmpty = false

        var lineStart = markdown.startIndex
        while lineStart < markdown.endIndex {
            let line = classifyLineUTF8(in: markdown, from: lineStart)

            if line.hasFencePrefix {
                inCodeBlock.toggle()
            }

            if !inCodeBlock {
                if !inTable {
                    if prevLineHadPipes && line.isTableSeparator {
                        inTable = true
                    }
                    prevLineHadPipes = line.hasPipe
                } else if !line.hasPipe {
                    inTable = false
                    prevLineHadPipes = false
                }
            }

            if !inCodeBlock {
                if line.startsBlockquote {
                    inBlockquote = true
                } else if line.isEmpty {
                    inBlockquote = false
                }
            }

            if !inCodeBlock {
                if line.startsList {
                    inList = true
                } else if line.trimmedIsEmpty {
                    inList = false
                }
            }

            chunkUTF8Count += line.utf8CountIncludingLineBreak

            let avoidSetextSplit = lastLineNonEmpty && line.isSetextUnderline
            let isLastLine = line.nextLineStart >= markdown.endIndex
            let shouldSplit = chunkUTF8Count >= chunkSize &&
                !inCodeBlock && !inTable && !inBlockquote && !inList &&
                !avoidSetextSplit &&
                (line.isEmpty || isLastLine)

            if shouldSplit || isLastLine {
                chunks.append(RangeChunk(
                    index: chunkIndex,
                    range: chunkStart..<line.nextLineStart,
                    startOffset: chunkStartOffset
                ))
                chunkStartOffset += chunkUTF8Count
                chunkStart = line.nextLineStart
                chunkUTF8Count = 0
                chunkIndex += 1
            }

            lastLineNonEmpty = !line.isEmpty
            lineStart = line.nextLineStart
        }

        if chunkStart < markdown.endIndex {
            chunks.append(RangeChunk(
                index: chunkIndex,
                range: chunkStart..<markdown.endIndex,
                startOffset: chunkStartOffset
            ))
        }

        return chunks
    }

    private struct ClassifiedLine {
        let nextLineStart: String.Index
        let utf8CountIncludingLineBreak: Int
        let isEmpty: Bool
        let hasFencePrefix: Bool
        let hasPipe: Bool
        let isTableSeparator: Bool
        let startsBlockquote: Bool
        let startsList: Bool
        let trimmedIsEmpty: Bool
        let isSetextUnderline: Bool
    }

    private static func classifyLineUTF8(in text: String, from lineStart: String.Index) -> ClassifiedLine {
        let utf8 = text.utf8
        var index = lineStart
        var utf8CountIncludingLineBreak = 0
        var hasPipe = false
        var hasNonASCII = false
        var trimmedStart: String.Index?
        var trimmedEnd = lineStart
        var previousByteWasCarriageReturn = false

        while index < text.endIndex {
            let byte = utf8[index]
            if byte == 10 && !previousByteWasCarriageReturn {
                break
            }

            let next = utf8.index(after: index)
            utf8CountIncludingLineBreak += 1

            if byte == 124 {
                hasPipe = true
            } else if byte >= 128 {
                hasNonASCII = true
            }

            if !isHorizontalWhitespace(byte) {
                if trimmedStart == nil {
                    trimmedStart = index
                }
                trimmedEnd = next
            }

            previousByteWasCarriageReturn = byte == 13
            index = next
        }

        let lineEnd = index
        let nextLineStart: String.Index
        if lineEnd < text.endIndex {
            nextLineStart = utf8.index(after: lineEnd)
            utf8CountIncludingLineBreak += 1
        } else {
            nextLineStart = lineEnd
        }

        let isEmpty = lineStart == lineEnd
        let trimmedLowerBound = trimmedStart ?? lineEnd
        let trimmedUpperBound = trimmedStart == nil ? lineEnd : trimmedEnd
        let trimmedIsEmpty = trimmedStart == nil
        let startsOrderedList = trimmedLineStartsOrderedListUTF8(
            in: text,
            trimmedLowerBound: trimmedLowerBound,
            trimmedUpperBound: trimmedUpperBound
        )

        return ClassifiedLine(
            nextLineStart: nextLineStart,
            utf8CountIncludingLineBreak: utf8CountIncludingLineBreak,
            isEmpty: isEmpty,
            hasFencePrefix: lineHasASCIITriple(96, 96, 96, in: utf8, from: lineStart, to: lineEnd) ||
                lineHasASCIITriple(126, 126, 126, in: utf8, from: lineStart, to: lineEnd),
            hasPipe: hasPipe,
            isTableSeparator: isTableSeparatorUTF8(
                in: utf8,
                trimmedLowerBound: trimmedLowerBound,
                trimmedUpperBound: trimmedUpperBound,
                hasPipe: hasPipe,
                hasNonASCII: hasNonASCII
            ),
            startsBlockquote: lineStart < lineEnd && utf8[lineStart] == 62,
            startsList: trimmedLineStartsUnorderedListUTF8(
                in: utf8,
                trimmedLowerBound: trimmedLowerBound,
                trimmedUpperBound: trimmedUpperBound
            ) || startsOrderedList,
            trimmedIsEmpty: trimmedIsEmpty,
            isSetextUnderline: isSetextUnderlineUTF8(
                in: utf8,
                trimmedLowerBound: trimmedLowerBound,
                trimmedUpperBound: trimmedUpperBound,
                hasNonASCII: hasNonASCII
            )
        )
    }

    private static func isHorizontalWhitespace(_ byte: UInt8) -> Bool {
        byte == 32 || byte == 9
    }

    private static func lineHasASCIITriple(
        _ first: UInt8,
        _ second: UInt8,
        _ third: UInt8,
        in utf8: String.UTF8View,
        from start: String.Index,
        to end: String.Index
    ) -> Bool {
        guard start < end, utf8[start] == first else { return false }
        let secondIndex = utf8.index(after: start)
        guard secondIndex < end, utf8[secondIndex] == second else { return false }
        let thirdIndex = utf8.index(after: secondIndex)
        return thirdIndex < end && utf8[thirdIndex] == third
    }

    private static func trimmedLineStartsUnorderedListUTF8(
        in utf8: String.UTF8View,
        trimmedLowerBound: String.Index,
        trimmedUpperBound: String.Index
    ) -> Bool {
        guard trimmedLowerBound < trimmedUpperBound else { return false }
        let first = utf8[trimmedLowerBound]
        guard first == 45 || first == 42 || first == 43 else { return false }
        let next = utf8.index(after: trimmedLowerBound)
        return next < trimmedUpperBound && utf8[next] == 32
    }

    private static func trimmedLineStartsOrderedListUTF8(
        in text: String,
        trimmedLowerBound: String.Index,
        trimmedUpperBound: String.Index
    ) -> Bool {
        let utf8 = text.utf8
        guard trimmedLowerBound < trimmedUpperBound else { return false }
        let first = utf8[trimmedLowerBound]

        if first >= 128 {
            return trimmedLineStartsOrderedList(in: text, range: trimmedLowerBound..<trimmedUpperBound)
        }

        guard first >= 48 && first <= 57 else { return false }

        var index = trimmedLowerBound
        while index < trimmedUpperBound {
            let byte = utf8[index]
            if byte >= 48 && byte <= 57 {
                index = utf8.index(after: index)
            } else if byte >= 128 {
                return trimmedLineStartsOrderedList(in: text, range: trimmedLowerBound..<trimmedUpperBound)
            } else {
                break
            }
        }

        return index < trimmedUpperBound && utf8[index] == 46
    }

    private static func isSetextUnderlineUTF8(
        in utf8: String.UTF8View,
        trimmedLowerBound: String.Index,
        trimmedUpperBound: String.Index,
        hasNonASCII: Bool
    ) -> Bool {
        guard trimmedLowerBound < trimmedUpperBound, !hasNonASCII else { return false }

        var index = trimmedLowerBound
        while index < trimmedUpperBound {
            let byte = utf8[index]
            guard byte == 45 || byte == 61 else {
                return false
            }
            index = utf8.index(after: index)
        }

        return true
    }

    private static func isTableSeparatorUTF8(
        in utf8: String.UTF8View,
        trimmedLowerBound: String.Index,
        trimmedUpperBound: String.Index,
        hasPipe: Bool,
        hasNonASCII: Bool
    ) -> Bool {
        guard hasPipe, trimmedLowerBound < trimmedUpperBound, !hasNonASCII else { return false }

        var cellStart = trimmedLowerBound
        var index = trimmedLowerBound
        var hasValid = false

        while true {
            if index == trimmedUpperBound || utf8[index] == 124 {
                let cellRange = whitespaceTrimmedRangeUTF8(in: utf8, range: cellStart..<index)
                if cellRange.lowerBound < cellRange.upperBound {
                    var dashCount = 0
                    var cellIndex = cellRange.lowerBound

                    while cellIndex < cellRange.upperBound {
                        let byte = utf8[cellIndex]
                        if byte == 58 {
                            cellIndex = utf8.index(after: cellIndex)
                            continue
                        }

                        guard byte == 45 else {
                            return false
                        }

                        dashCount += 1
                        cellIndex = utf8.index(after: cellIndex)
                    }

                    if dashCount >= 3 {
                        hasValid = true
                    } else {
                        return false
                    }
                }

                if index == trimmedUpperBound {
                    break
                }
                cellStart = utf8.index(after: index)
            }

            index = utf8.index(after: index)
        }

        return hasValid
    }

    private static func whitespaceTrimmedRangeUTF8(
        in utf8: String.UTF8View,
        range: Range<String.Index>
    ) -> Range<String.Index> {
        var lowerBound = range.lowerBound
        var upperBound = range.upperBound

        while lowerBound < upperBound, isHorizontalWhitespace(utf8[lowerBound]) {
            lowerBound = utf8.index(after: lowerBound)
        }

        while upperBound > lowerBound {
            let previous = utf8.index(before: upperBound)
            guard isHorizontalWhitespace(utf8[previous]) else { break }
            upperBound = previous
        }

        return lowerBound..<upperBound
    }

    static func splitCopiedForTesting(markdown: String, chunkSize: Int) -> [CopiedChunk] {
        var chunks: [CopiedChunk] = []
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)

        var currentChunk = ""
        var currentStartOffset = 0
        var chunkIndex = 0
        var inCodeBlock = false
        var inTable = false
        var prevLineHadPipes = false
        var inBlockquote = false
        var inList = false
        var lastLineNonEmpty = false

        for (lineIndex, line) in lines.enumerated() {
            let lineStr = String(line)

            if lineStr.hasPrefix("```") || lineStr.hasPrefix("~~~") {
                inCodeBlock = !inCodeBlock
            }

            if !inCodeBlock {
                if !inTable {
                    if prevLineHadPipes && isTableSeparator(lineStr) {
                        inTable = true
                    }
                    prevLineHadPipes = lineStr.contains("|")
                } else {
                    if lineStr.contains("|") {
                        // stay in table
                    } else {
                        inTable = false
                        prevLineHadPipes = false
                    }
                }
            }

            if !inCodeBlock {
                if lineStr.hasPrefix(">") { inBlockquote = true }
                else if lineStr.isEmpty { inBlockquote = false }
            }

            if !inCodeBlock {
                let trimmedList = lineStr.trimmingCharacters(in: .whitespaces)
                if trimmedList.hasPrefix("- ") || trimmedList.hasPrefix("* ") || trimmedList.hasPrefix("+ ") {
                    inList = true
                } else if let first = trimmedList.first,
                          first.isNumber,
                          trimmedList.drop(while: { $0.isNumber }).first == "." {
                    inList = true
                } else if trimmedList.isEmpty {
                    inList = false
                }
            }

            currentChunk += lineStr + "\n"

            let trimmed = lineStr.trimmingCharacters(in: .whitespaces)
            let isSetextUnderline = !trimmed.isEmpty && trimmed.allSatisfy { $0 == "-" || $0 == "=" }
            let avoidSetextSplit = lastLineNonEmpty && isSetextUnderline
            let shouldSplit = currentChunk.count >= chunkSize &&
                !inCodeBlock && !inTable && !inBlockquote && !inList &&
                !avoidSetextSplit &&
                (lineStr.isEmpty || lineIndex == lines.count - 1)

            if shouldSplit || lineIndex == lines.count - 1 {
                chunks.append(CopiedChunk(index: chunkIndex, text: currentChunk, startOffset: currentStartOffset))
                currentStartOffset += currentChunk.count
                currentChunk = ""
                chunkIndex += 1
            }

            lastLineNonEmpty = !lineStr.isEmpty
        }

        if !currentChunk.isEmpty {
            chunks.append(CopiedChunk(index: chunkIndex, text: currentChunk, startOffset: currentStartOffset))
        }

        return chunks
    }

    private static func lineEndIndex(in text: String, from start: String.Index) -> String.Index {
        var index = start
        while index < text.endIndex, text[index] != "\n" {
            index = text.index(after: index)
        }
        return index
    }

    private static func lineHasPrefix(_ prefix: String, in text: String, range: Range<String.Index>) -> Bool {
        var index = range.lowerBound
        for character in prefix {
            guard index < range.upperBound, text[index] == character else {
                return false
            }
            index = text.index(after: index)
        }
        return true
    }

    private static func lineContains(_ character: Character, in text: String, range: Range<String.Index>) -> Bool {
        var index = range.lowerBound
        while index < range.upperBound {
            if text[index] == character {
                return true
            }
            index = text.index(after: index)
        }
        return false
    }

    private static func whitespaceTrimmedRange(
        in text: String,
        range: Range<String.Index>
    ) -> Range<String.Index> {
        var lowerBound = range.lowerBound
        var upperBound = range.upperBound

        while lowerBound < upperBound, isHorizontalWhitespace(text[lowerBound]) {
            lowerBound = text.index(after: lowerBound)
        }

        while upperBound > lowerBound {
            let previous = text.index(before: upperBound)
            guard isHorizontalWhitespace(text[previous]) else { break }
            upperBound = previous
        }

        return lowerBound..<upperBound
    }

    private static func isHorizontalWhitespace(_ character: Character) -> Bool {
        character == " " || character == "\t"
    }

    private static func trimmedLineStartsUnorderedList(in text: String, range: Range<String.Index>) -> Bool {
        guard range.lowerBound < range.upperBound else { return false }
        let first = text[range.lowerBound]
        guard first == "-" || first == "*" || first == "+" else { return false }
        let next = text.index(after: range.lowerBound)
        return next < range.upperBound && text[next] == " "
    }

    private static func trimmedLineStartsOrderedList(in text: String, range: Range<String.Index>) -> Bool {
        guard range.lowerBound < range.upperBound, text[range.lowerBound].isNumber else {
            return false
        }

        var index = range.lowerBound
        while index < range.upperBound, text[index].isNumber {
            index = text.index(after: index)
        }

        return index < range.upperBound && text[index] == "."
    }

    private static func isSetextUnderline(in text: String, range: Range<String.Index>) -> Bool {
        guard range.lowerBound < range.upperBound else { return false }
        var index = range.lowerBound
        while index < range.upperBound {
            let character = text[index]
            guard character == "-" || character == "=" else {
                return false
            }
            index = text.index(after: index)
        }
        return true
    }

    private static func isTableSeparator(in text: String, range: Range<String.Index>) -> Bool {
        let trimmed = whitespaceTrimmedRange(in: text, range: range)
        guard lineContains("|", in: text, range: trimmed) else { return false }

        var cellStart = trimmed.lowerBound
        var index = trimmed.lowerBound
        var hasValid = false

        while index <= trimmed.upperBound {
            if index == trimmed.upperBound || text[index] == "|" {
                let cellRange = whitespaceTrimmedRange(in: text, range: cellStart..<index)
                if cellRange.lowerBound < cellRange.upperBound {
                    var dashCount = 0
                    var cellIndex = cellRange.lowerBound
                    while cellIndex < cellRange.upperBound {
                        let character = text[cellIndex]
                        if character == ":" {
                            cellIndex = text.index(after: cellIndex)
                            continue
                        }
                        guard character == "-" else {
                            return false
                        }
                        dashCount += 1
                        cellIndex = text.index(after: cellIndex)
                    }
                    if dashCount >= 3 {
                        hasValid = true
                    } else {
                        return false
                    }
                }

                if index == trimmed.upperBound {
                    break
                }
                cellStart = text.index(after: index)
            }
            index = text.index(after: index)
        }

        return hasValid
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return false }
        let parts = trimmed.split(separator: "|", omittingEmptySubsequences: false)
        var hasValid = false
        for raw in parts {
            let cell = raw.trimmingCharacters(in: .whitespaces)
            if cell.isEmpty { continue }
            let stripped = cell.replacingOccurrences(of: ":", with: "")
            if stripped.count >= 3 && stripped.allSatisfy({ $0 == "-" }) {
                hasValid = true
            } else {
                return false
            }
        }
        return hasValid
    }
}

/// Parallel markdown parser for very large documents
public final class ParallelMarkdownParser: @unchecked Sendable {
    
    // MARK: - Types
    
    public struct ParallelConfiguration: Sendable {
        /// Number of concurrent parsing tasks
        public let concurrency: Int
        
        /// Minimum document size (in characters) to trigger parallel parsing
        public let minimumSizeThreshold: Int
        
        /// Chunk size for parallel processing
        public let chunkSize: Int
        
        /// Whether to preserve order of blocks
        public let preserveOrder: Bool
        
        public init(
            concurrency: Int = ProcessInfo.processInfo.processorCount,
            minimumSizeThreshold: Int = 10000,
            chunkSize: Int = 5000,
            preserveOrder: Bool = true
        ) {
            self.concurrency = max(1, concurrency)
            self.minimumSizeThreshold = minimumSizeThreshold
            self.chunkSize = chunkSize
            self.preserveOrder = preserveOrder
        }
    }
    
    private struct ParseChunk: Sendable {
        let index: Int
        let range: Range<String.Index>
        let startOffset: Int
    }
    
    private struct ParseResult: Sendable {
        let index: Int
        let blocks: [MarkdownParser.BlockNode]
        let parseTime: TimeInterval
    }

    private enum ChunkParseMode: Sendable {
        case rangeBacked
        case copied
    }
    
    // MARK: - Properties
    
    private let parallelConfig: ParallelConfiguration
    private let markdownConfig: MarkdownConfiguration
    private let queue = DispatchQueue(label: "com.glimmer.parallel", attributes: .concurrent)
    private let parseGroup = DispatchGroup()
    private struct ActiveOps: Sendable { var ops: [CancellableParallelOperation] = [] }
    private let activeOpsLock = OSAllocatedUnfairLock(initialState: ActiveOps())
    
    // MARK: - Initialization
    
    public init(
        parallelConfig: ParallelConfiguration = ParallelConfiguration(),
        markdownConfig: MarkdownConfiguration = .default
    ) {
        self.parallelConfig = parallelConfig
        self.markdownConfig = markdownConfig
    }
    
    // MARK: - Public Methods
    
    /// Parse markdown using parallel processing
    public func parse(_ markdown: String) -> [MarkdownParser.BlockNode] {
        // Check if document is large enough for parallel processing
        if markdown.count < parallelConfig.minimumSizeThreshold {
            // Use regular parser for small documents
            return MarkdownParser.parse(markdown, configuration: markdownConfig)
        }
        
        // Split into chunks
        let chunks = splitIntoChunks(markdown)
        
        // If only one chunk, use regular parser
        if chunks.count <= 1 {
            return MarkdownParser.parse(markdown, configuration: markdownConfig)
        }
        
        // Parse chunks in parallel
        let results = parseChunksInParallel(chunks, in: markdown, mode: .rangeBacked)
        
        // Combine results
        return combineResults(results)
    }
    
    /// Parse markdown asynchronously with progress reporting
    public func parseAsync(
        _ markdown: String,
        progress: @escaping @Sendable (Double) -> Void,
        completion: @escaping @Sendable ([MarkdownParser.BlockNode]) -> Void
    ) {
        let op = CancellableParallelOperation(
            markdown: markdown,
            parallelConfig: parallelConfig,
            markdownConfig: markdownConfig,
            autoStart: false
        )
        activeOpsLock.withLock { $0.ops.append(op) }
        op
            .onProgress { value in
                progress(value)
            }
            .onComplete { [weak self, weak op] blocks in
                // remove op from active list
                if let self = self, let op = op {
                    self.activeOpsLock.withLock { state in
                        if let idx = state.ops.firstIndex(where: { $0 === op }) {
                            state.ops.remove(at: idx)
                        }
                    }
                }
                completion(blocks)
            }
        op.start()
    }
    
    /// Parse with cancellation support
    public func parseCancellable(
        _ markdown: String
    ) -> CancellableParallelOperation {
        CancellableParallelOperation(
            markdown: markdown,
            parallelConfig: parallelConfig,
            markdownConfig: markdownConfig
        )
    }
    
    // MARK: - Private Methods
    
    private func splitIntoChunks(_ markdown: String) -> [ParseChunk] {
        ParallelChunkSplitter
            .splitRanges(markdown: markdown, chunkSize: parallelConfig.chunkSize)
            .map { ParseChunk(index: $0.index, range: $0.range, startOffset: $0.startOffset) }
    }

    func parseByCopyingChunksForTesting(_ markdown: String) -> [MarkdownParser.BlockNode] {
        if markdown.count < parallelConfig.minimumSizeThreshold {
            return MarkdownParser.parse(markdown, configuration: markdownConfig)
        }

        let chunks = splitIntoChunks(markdown)
        if chunks.count <= 1 {
            return MarkdownParser.parse(markdown, configuration: markdownConfig)
        }

        let results = parseChunksInParallel(chunks, in: markdown, mode: .copied)
        return combineResults(results)
    }

    private func parseChunksInParallel(
        _ chunks: [ParseChunk],
        in markdown: String,
        mode: ChunkParseMode
    ) -> [ParseResult] {
        struct ResultsState: Sendable {
            var orderedResults: [ParseResult?]
            var unorderedResults: [ParseResult]
        }
        let preserveOrder = parallelConfig.preserveOrder
        let resultsLock = OSAllocatedUnfairLock(initialState: ResultsState(
            orderedResults: preserveOrder ? Array(repeating: nil, count: chunks.count) : [],
            unorderedResults: []
        ))
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: parallelConfig.concurrency)
        for chunk in chunks {
            group.enter()
            queue.async {
                semaphore.wait()
                defer {
                    semaphore.signal()
                    group.leave()
                }
                let startTime = CFAbsoluteTimeGetCurrent()
                var state: ParserState
                switch mode {
                case .rangeBacked:
                    state = ParserState(
                        text: markdown,
                        currentIndex: chunk.range.lowerBound,
                        endIndex: chunk.range.upperBound
                    )
                case .copied:
                    state = ParserState(text: String(markdown[chunk.range]))
                }
                let blocks = BlockParser.parseBlocks(&state, configuration: self.markdownConfig)
                let parseTime = CFAbsoluteTimeGetCurrent() - startTime
                let result = ParseResult(index: chunk.index, blocks: blocks, parseTime: parseTime)
                resultsLock.withLock { state in
                    if preserveOrder, chunk.index < state.orderedResults.count {
                        state.orderedResults[chunk.index] = result
                    } else {
                        state.unorderedResults.append(result)
                    }
                }
            }
        }
        group.wait()
        return resultsLock.withLock { state in
            if preserveOrder {
                return state.orderedResults.compactMap { $0 }
            }
            return state.unorderedResults
        }
    }
    
    private func combineResults(_ results: [ParseResult]) -> [MarkdownParser.BlockNode] {
        if parallelConfig.preserveOrder {
            return results.flatMap { $0.blocks }
        } else {
            return results.flatMap { $0.blocks }
        }
    }
}

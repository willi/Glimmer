import Foundation
import os
import QuartzCore

/// Parallel markdown parser for very large documents
public final class ParallelMarkdownParser {
    
    // MARK: - Types
    
    public struct ParallelConfiguration {
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
    
    private struct ParseChunk {
        let index: Int
        let text: String
        let startOffset: Int
    }
    
    private struct ParseResult {
        let index: Int
        let blocks: [MarkdownParser.BlockNode]
        let parseTime: TimeInterval
    }
    
    // MARK: - Properties
    
    private let parallelConfig: ParallelConfiguration
    private let markdownConfig: MarkdownConfiguration
    private let queue = DispatchQueue(label: "com.glimmer.parallel", attributes: .concurrent)
    private let parseGroup = DispatchGroup()
    private struct ActiveOps { var ops: [CancellableParallelOperation] = [] }
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
        let results = parseChunksInParallel(chunks)
        
        // Combine results
        return combineResults(results)
    }
    
    /// Parse markdown asynchronously with progress reporting
    public func parseAsync(
        _ markdown: String,
        progress: @escaping (Double) -> Void,
        completion: @escaping ([MarkdownParser.BlockNode]) -> Void
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
        var chunks: [ParseChunk] = []
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
            
            // Track code blocks to avoid splitting them
            if lineStr.hasPrefix("```") || lineStr.hasPrefix("~~~") {
                inCodeBlock = !inCodeBlock
            }
            
            // Track tables more robustly: detect header+separator, then rows with pipes
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
            // Track blockquotes
            if !inCodeBlock {
                if lineStr.hasPrefix(">") { inBlockquote = true }
                else if lineStr.isEmpty { inBlockquote = false }
            }
            // Track lists (simple detection)
            if !inCodeBlock {
                let trimmedList = lineStr.trimmingCharacters(in: .whitespaces)
                if trimmedList.hasPrefix("- ") || trimmedList.hasPrefix("* ") || trimmedList.hasPrefix("+ ") {
                    inList = true
                } else if let first = trimmedList.first, first.isNumber, trimmedList.drop(while: { $0.isNumber }).first == "." {
                    inList = true
                } else if trimmedList.isEmpty {
                    inList = false
                }
            }

            currentChunk += lineStr + "\n"

            // Avoid splitting across Setext underline lines (==== or ----)
            let trimmed = lineStr.trimmingCharacters(in: .whitespaces)
            let isSetextUnderline = !trimmed.isEmpty && trimmed.allSatisfy { $0 == "-" || $0 == "=" }
            let avoidSetextSplit = lastLineNonEmpty && isSetextUnderline
            let shouldSplit = currentChunk.count >= parallelConfig.chunkSize &&
                              !inCodeBlock && !inTable && !inBlockquote && !inList &&
                              !avoidSetextSplit &&
                              (lineStr.isEmpty || lineIndex == lines.count - 1)
            
            if shouldSplit || lineIndex == lines.count - 1 {
                chunks.append(ParseChunk(
                    index: chunkIndex,
                    text: currentChunk,
                    startOffset: currentStartOffset
                ))
                
                currentStartOffset += currentChunk.count
                currentChunk = ""
                chunkIndex += 1
            }
            lastLineNonEmpty = !lineStr.isEmpty
        }
        
        // Add any remaining content
        if !currentChunk.isEmpty {
            chunks.append(ParseChunk(
                index: chunkIndex,
                text: currentChunk,
                startOffset: currentStartOffset
            ))
        }
        
        return chunks
    }

    private func parseChunksInParallel(_ chunks: [ParseChunk]) -> [ParseResult] {
        var results: [ParseResult] = []
        let resultsLock = NSLock()
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
                var state = ParserState(text: chunk.text)
                let blocks = BlockParser.parseBlocks(&state, configuration: self.markdownConfig)
                let parseTime = CFAbsoluteTimeGetCurrent() - startTime
                resultsLock.lock()
                results.append(ParseResult(index: chunk.index, blocks: blocks, parseTime: parseTime))
                resultsLock.unlock()
            }
        }
        group.wait()
        return results
    }
    
    private func combineResults(_ results: [ParseResult]) -> [MarkdownParser.BlockNode] {
        if parallelConfig.preserveOrder {
            return results.sorted { $0.index < $1.index }.flatMap { $0.blocks }
        } else {
            return results.flatMap { $0.blocks }
        }
    }

    // MARK: - Helpers
    private func isTableSeparator(_ line: String) -> Bool {
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

import Foundation
import os

/// A cancellable parallel parsing operation that mirrors `ParallelMarkdownParser` behavior
/// but allows callers to cancel in-flight work and observe progress.
public final class CancellableParallelOperation {
    public typealias ProgressHandler = (Double) -> Void
    public typealias CompletionHandler = ([MarkdownParser.BlockNode]) -> Void

    private let markdown: String
    private let parallelConfig: ParallelMarkdownParser.ParallelConfiguration
    private let markdownConfig: MarkdownConfiguration

    private let queue = DispatchQueue(label: "com.glimmer.parallel.cancellable", attributes: .concurrent)
    private let group = DispatchGroup()
    private struct State { var isCancelled = false; var progress: ProgressHandler? = nil; var complete: CompletionHandler? = nil }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private struct ProgressState { var lastEmitted: Double = 0 }
    private let progressState = OSAllocatedUnfairLock(initialState: ProgressState())
    public var isCancelled: Bool { state.withLock { $0.isCancelled } }

    /// Create a cancellable parallel parse operation.
    /// By default, the operation starts immediately. Pass autoStart = false to
    /// register handlers before beginning work, then call start().
    public init(
        markdown: String,
        parallelConfig: ParallelMarkdownParser.ParallelConfiguration,
        markdownConfig: MarkdownConfiguration,
        autoStart: Bool = true
    ) {
        self.markdown = markdown
        self.parallelConfig = parallelConfig
        self.markdownConfig = markdownConfig
        if autoStart { start() }
    }

    /// Provide a progress callback. Returns self for chaining.
    @discardableResult
    public func onProgress(_ handler: @escaping ProgressHandler) -> Self {
        state.withLock { $0.progress = handler }
        return self
    }

    /// Provide a completion callback. Returns self for chaining.
    @discardableResult
    public func onComplete(_ handler: @escaping CompletionHandler) -> Self {
        state.withLock { $0.complete = handler }
        return self
    }

    /// Cancel the operation. In-flight chunk parses may still complete, but
    /// no further progress or completion will be delivered.
    public func cancel() {
        state.withLock { $0.isCancelled = true }
    }

    deinit { cancel() }

    // MARK: - Internal Execution

    private struct LocalParseChunk { let index: Int; let text: String; let startOffset: Int }
    private struct LocalParseResult { let index: Int; let blocks: [MarkdownParser.BlockNode] }

    public func start() {
        progressState.withLock { $0.lastEmitted = 0 }

        // Fall back to single-threaded parse when under threshold
        if markdown.count < parallelConfig.minimumSizeThreshold {
            if isCancelled { finish(with: []) } else {
                let blocks = MarkdownParser.parse(markdown, configuration: markdownConfig)
                // preserve old parseAsync behavior: report full progress for small docs
                let handler = self.state.withLock { $0.progress }
                progressState.withLock { $0.lastEmitted = 1.0 }
                DispatchQueue.main.async { handler?(1.0) }
                finish(with: blocks)
            }
            return
        }

        let chunks = splitIntoChunks(markdown)
        if chunks.count <= 1 {
            if isCancelled { finish(with: []) } else {
                let blocks = MarkdownParser.parse(markdown, configuration: markdownConfig)
                let handler = self.state.withLock { $0.progress }
                progressState.withLock { $0.lastEmitted = 1.0 }
                DispatchQueue.main.async { handler?(1.0) }
                finish(with: blocks)
            }
            return
        }

        let totalChunks = chunks.count
        struct ResultsState { var completed: Int = 0; var results: [LocalParseResult] = [] }
        let resultsLock = OSAllocatedUnfairLock(initialState: ResultsState())

        for chunk in chunks {
            if isCancelled { break }
            group.enter()
            queue.async { [weak self] in
                guard let self = self else { return }
                if self.isCancelled { self.group.leave(); return }

                var state = ParserState(text: chunk.text)
                let blocks = BlockParser.parseBlocks(&state, configuration: self.markdownConfig)

                let progressValue: Double = resultsLock.withLock { state in
                    state.results.append(LocalParseResult(index: chunk.index, blocks: blocks))
                    state.completed += 1
                    return Double(state.completed) / Double(totalChunks)
                }
                let cancelled = self.isCancelled

                if !cancelled {
                    let handler = self.state.withLock { $0.progress }
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self, !self.isCancelled else { return }
                        let monotonicProgress = self.progressState.withLock { state in
                            state.lastEmitted = max(state.lastEmitted, progressValue)
                            return state.lastEmitted
                        }
                        handler?(monotonicProgress)
                    }
                }

                self.group.leave()
            }
        }

        group.notify(queue: .global(qos: .userInitiated)) { [weak self] in
            guard let self = self else { return }
            if self.isCancelled { self.finish(with: []) }
            else {
                let combined = resultsLock.withLock { self.combineResults($0.results) }
                self.finish(with: combined)
            }
        }
    }

    private func finish(with blocks: [MarkdownParser.BlockNode]) {
        if isCancelled { return }
        let handler = state.withLock { $0.complete }
        DispatchQueue.main.async { handler?(blocks) }
    }

    // MARK: - Helpers (duplicated from ParallelMarkdownParser to avoid tighter coupling)

    private func splitIntoChunks(_ markdown: String) -> [LocalParseChunk] {
        var chunks: [LocalParseChunk] = []
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)

        var currentChunk = ""
        var currentStartOffset = 0
        var chunkIndex = 0
        var inCodeBlock = false
        var inTable = false
        var inBlockquote = false
        var inList = false
        var lastLineNonEmpty = false

        for (lineIndex, line) in lines.enumerated() {
            let lineStr = String(line)

            if lineStr.hasPrefix("```") || lineStr.hasPrefix("~~~") { inCodeBlock.toggle() }

            if !inCodeBlock && lineStr.contains("|") { inTable = true }
            else if !inCodeBlock && lineStr.isEmpty { inTable = false }

            if !inCodeBlock {
                if lineStr.hasPrefix(">") { inBlockquote = true }
                else if lineStr.isEmpty { inBlockquote = false }
            }

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

            let trimmed = lineStr.trimmingCharacters(in: .whitespaces)
            let isSetextUnderline = !trimmed.isEmpty && trimmed.allSatisfy { $0 == "-" || $0 == "=" }
            let avoidSetextSplit = lastLineNonEmpty && isSetextUnderline
            let shouldSplit = currentChunk.count >= parallelConfig.chunkSize &&
                              !inCodeBlock && !inTable && !inBlockquote && !inList &&
                              !avoidSetextSplit &&
                              (lineStr.isEmpty || lineIndex == lines.count - 1)

            if shouldSplit || lineIndex == lines.count - 1 {
                chunks.append(LocalParseChunk(index: chunkIndex, text: currentChunk, startOffset: currentStartOffset))
                currentStartOffset += currentChunk.count
                currentChunk = ""
                chunkIndex += 1
            }
            lastLineNonEmpty = !lineStr.isEmpty
        }

        if !currentChunk.isEmpty {
            chunks.append(LocalParseChunk(index: chunkIndex, text: currentChunk, startOffset: currentStartOffset))
        }

        return chunks
    }

    private func combineResults(_ results: [LocalParseResult]) -> [MarkdownParser.BlockNode] {
        if parallelConfig.preserveOrder {
            return results.sorted { $0.index < $1.index }.flatMap { $0.blocks }
        } else {
            return results.flatMap { $0.blocks }
        }
    }
}

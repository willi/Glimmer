import Foundation
import os

/// A cancellable parallel parsing operation that mirrors `ParallelMarkdownParser` behavior
/// but allows callers to cancel in-flight work and observe progress.
public final class CancellableParallelOperation: @unchecked Sendable {
    public typealias ProgressHandler = @Sendable (Double) -> Void
    public typealias CompletionHandler = @Sendable ([MarkdownParser.BlockNode]) -> Void

    private let markdown: String
    private let parallelConfig: ParallelMarkdownParser.ParallelConfiguration
    private let markdownConfig: MarkdownConfiguration

    private let queue = DispatchQueue(label: "com.glimmer.parallel.cancellable", attributes: .concurrent)
    private let group = DispatchGroup()
    private struct State: Sendable { var isCancelled = false; var progress: ProgressHandler? = nil; var complete: CompletionHandler? = nil }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private struct ProgressState: Sendable { var lastEmitted: Double = 0 }
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

    private struct LocalParseChunk: Sendable {
        let index: Int
        let range: Range<String.Index>
        let startOffset: Int
    }
    private struct LocalParseResult: Sendable { let index: Int; let blocks: [MarkdownParser.BlockNode] }

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
        let semaphore = DispatchSemaphore(value: parallelConfig.concurrency)
        let dispatchGroup = group
        let preserveOrder = parallelConfig.preserveOrder
        struct ResultsState: Sendable {
            var completed: Int = 0
            var orderedResults: [LocalParseResult?]
            var unorderedResults: [LocalParseResult] = []
        }
        let resultsLock = OSAllocatedUnfairLock(initialState: ResultsState(
            orderedResults: preserveOrder ? Array(repeating: nil, count: totalChunks) : []
        ))

        for chunk in chunks {
            if isCancelled { break }
            dispatchGroup.enter()
            queue.async { [weak self] in
                guard let self = self else {
                    dispatchGroup.leave()
                    return
                }
                semaphore.wait()
                defer {
                    semaphore.signal()
                    dispatchGroup.leave()
                }

                if self.isCancelled { return }

                let chunkText = String(self.markdown[chunk.range])
                var state = ParserState(text: chunkText)
                let blocks = BlockParser.parseBlocks(&state, configuration: self.markdownConfig)

                let progressValue: Double = resultsLock.withLock { state in
                    let result = LocalParseResult(index: chunk.index, blocks: blocks)
                    if preserveOrder, chunk.index < state.orderedResults.count {
                        state.orderedResults[chunk.index] = result
                    } else {
                        state.unorderedResults.append(result)
                    }
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
            }
        }

        dispatchGroup.notify(queue: .global(qos: .userInitiated)) { [weak self] in
            guard let self = self else { return }
            if self.isCancelled { self.finish(with: []) }
            else {
                let combined = resultsLock.withLock { state in
                    if preserveOrder {
                        return state.orderedResults.compactMap { $0 }.flatMap { $0.blocks }
                    }
                    return self.combineResults(state.unorderedResults)
                }
                self.finish(with: combined)
            }
        }
    }

    private func finish(with blocks: [MarkdownParser.BlockNode]) {
        if isCancelled { return }
        let handler = state.withLock { $0.complete }
        DispatchQueue.main.async { handler?(blocks) }
    }

    // MARK: - Helpers

    private func splitIntoChunks(_ markdown: String) -> [LocalParseChunk] {
        ParallelChunkSplitter
            .splitRanges(markdown: markdown, chunkSize: parallelConfig.chunkSize)
            .map { LocalParseChunk(index: $0.index, range: $0.range, startOffset: $0.startOffset) }
    }

    private func combineResults(_ results: [LocalParseResult]) -> [MarkdownParser.BlockNode] {
        if parallelConfig.preserveOrder {
            return results.sorted { $0.index < $1.index }.flatMap { $0.blocks }
        } else {
            return results.flatMap { $0.blocks }
        }
    }
}

import XCTest
import os
@testable import Glimmer

final class ParallelParserAsyncTests: XCTestCase {

    func testParseAsyncReportsProgressAndCompletes() {
        // Force parallel by setting low threshold and small chunk size
        let cfg = ParallelMarkdownParser.ParallelConfiguration(
            concurrency: 2,
            minimumSizeThreshold: 0,
            chunkSize: 16,
            preserveOrder: true
        )
        let parser = ParallelMarkdownParser(parallelConfig: cfg, markdownConfig: .default)

        // Build markdown long enough to create multiple chunks
        let repeated = Array(repeating: "- item\n- item\n- item\n\n", count: 20).joined()

        let done = expectation(description: "completion called")

        struct ProgressState: Sendable {
            var lastProgress: Double = 0
            var progressNeverDecreased = true
            var progressNeverExceededOne = true
        }
        let progressState = OSAllocatedUnfairLock(initialState: ProgressState())

        parser.parseAsync(repeated, progress: { p in
            progressState.withLock { state in
                if p < state.lastProgress { state.progressNeverDecreased = false }
                if p > 1.0 { state.progressNeverExceededOne = false }
                state.lastProgress = p
            }
        }, completion: { blocks in
            XCTAssertFalse(blocks.isEmpty, "Expected parsed blocks")
            let state = progressState.withLock { $0 }
            XCTAssertEqual(state.lastProgress, 1.0, accuracy: 0.0001)
            XCTAssertTrue(state.progressNeverDecreased, "Progress should be monotonic non-decreasing")
            XCTAssertTrue(state.progressNeverExceededOne, "Progress should not exceed 1.0")
            done.fulfill()
        })

        wait(for: [done], timeout: 3.0)
    }

    func testParseAsyncSmallInputReportsOneAndCompletes() {
        // Use default threshold so small input goes through fallback path
        let parser = ParallelMarkdownParser(parallelConfig: .init(), markdownConfig: .default)
        let md = "# Title\n\nBody\n"

        let done = expectation(description: "completion called")
        let sawProgressOne = expectation(description: "progress reached 1.0")

        parser.parseAsync(md, progress: { p in
            if p >= 1.0 { sawProgressOne.fulfill() }
        }, completion: { blocks in
            XCTAssertFalse(blocks.isEmpty)
            done.fulfill()
        })

        wait(for: [sawProgressOne, done], timeout: 2.0)
    }

    func testParseCancellableCancelSkipsCompletion() {
        let cfg = ParallelMarkdownParser.ParallelConfiguration(
            concurrency: 4,
            minimumSizeThreshold: 0,
            chunkSize: 32,
            preserveOrder: true
        )
        let parser = ParallelMarkdownParser(parallelConfig: cfg, markdownConfig: .default)
        let repeated = Array(repeating: "Paragraph line that is quite long to ensure chunking.\n\n", count: 200).joined()

        // Completion should NOT be called after cancellation
        let notCompleted = expectation(description: "completion should not be called")
        notCompleted.isInverted = true

        let op = parser.parseCancellable(repeated)
            .onComplete { _ in
                notCompleted.fulfill()
            }
            .onProgress { _ in /* ignore */ }

        // Cancel quickly; allow some time for in-flight work to settle
        op.cancel()

        wait(for: [notCompleted], timeout: 1.0)
    }
}

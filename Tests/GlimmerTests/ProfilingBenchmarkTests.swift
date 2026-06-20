import XCTest
import SwiftUI
@testable import Glimmer

/// Phase-level benchmark over a large, complex document. Not a regression
/// gate — prints timings for profiling sessions. The long-running variant
/// (`testProfilingLoop`) exists so Instruments can attach and sample.
final class ProfilingBenchmarkTests: XCTestCase {

    // MARK: - Corpus

    /// ~1MB of markdown exercising every feature: headings, emphasis, links,
    /// autolinks, mentions, issues, emoji, inline code, nested lists, task
    /// lists, tables, fenced code with highlighting, blockquotes, footnotes.
    static func makeCorpus(sections: Int) -> String {
        var out = "# Profiling Corpus\n\n"
        for i in 0..<sections {
            out += """
            ## Section \(i): The *quick* **brown** fox :rocket:

            Paragraph \(i) with **bold**, *italic*, ~~struck~~, `inline code`, a [link](https://example.com/page/\(i)), \
            an autolink https://github.com/glimmer/issue\(i), a mention @octocat\(i % 7), issue #\(100 + i), \
            repo facebook/react and PR apple/swift#\(i). Emoji :tada: :sparkles: and more **nested *emphasis* here**.

            - Level one item \(i) with **bold** text
              - Level two with `code` and [link](https://example.com/\(i))
                - Level three with *italics* and :rocket:
              - Level two again @user\(i % 5)
            - Another level one #\(i)

            - [x] Completed task \(i) with **bold**
            - [ ] Pending task with [link](https://example.com/t\(i))

            | Column A | Column *B* | **C** | `D` |
            |----------|-----------|-------|-----|
            | cell \(i) | *styled* | [t](https://x.y/\(i)) | `code` |
            | @mention | #\(i) | :tada: | ~~gone~~ |
            | row3 \(i) | **bb** | plain | text |

            ```swift
            struct Section\(i): View {
                let value = \(i)
                var body: some View {
                    // a comment about \(i)
                    Text("hello \\(value)")
                        .font(.body)
                        .padding(\(i % 16))
                }
            }
            ```

            > Quoted wisdom \(i) with **bold** and a [link](https://example.com/q\(i)).
            > Second line of the quote with `code`.

            Footnote reference here.[^\(i)]

            [^\(i)]: The footnote *content* for section \(i).

            ---

            """
        }
        return out
    }

    private func ms(_ duration: TimeInterval) -> String {
        String(format: "%8.2f ms", duration * 1000)
    }

    @discardableResult
    private func time<T>(_ label: String, _ block: () -> T) -> T {
        let start = Date()
        let result = block()
        print("[BENCH] \(label): \(ms(Date().timeIntervalSince(start)))")
        return result
    }

    // MARK: - Phase timings

    func testPhaseTimings() {
        var config = MarkdownConfiguration.default
        config.enableCaching = false
        config.enableRenderCaching = false

        let corpus = Self.makeCorpus(sections: 400)
        print("[BENCH] corpus size: \(corpus.utf8.count / 1024) KB")

        // Warm-up (JIT-ish effects, lazy statics like emoji maps)
        _ = MarkdownParser.parse(String(corpus.prefix(20_000)), configuration: config)

        let blocks = time("parse (cold, no cache)") {
            MarkdownParser.parse(corpus, configuration: config)
        }
        print("[BENCH] block count: \(blocks.count)")

        time("parse again (no cache)") {
            _ = MarkdownParser.parse(corpus, configuration: config)
        }

        time("render (no cache)") {
            var renderer = MarkdownRenderer()
            _ = renderer.render(blocks: blocks, configuration: config)
        }

        var cachingConfig = config
        cachingConfig.enableRenderCaching = true
        MarkdownRenderer.clearRenderCache()
        time("render (cache cold)") {
            var renderer = MarkdownRenderer()
            _ = renderer.render(blocks: blocks, configuration: cachingConfig)
        }
        time("render (cache warm)") {
            var renderer = MarkdownRenderer()
            _ = renderer.render(blocks: blocks, configuration: cachingConfig)
        }
        let stats = MarkdownRenderer.getRenderCacheStats()
        print("[BENCH] render cache default capacity: hits=\(stats.hits) misses=\(stats.misses)")

        var bigCacheConfig = cachingConfig
        bigCacheConfig.maxRenderCacheEntries = 8192
        MarkdownRenderer.clearRenderCache()
        time("render (cache cold, capacity 8192)") {
            var renderer = MarkdownRenderer()
            _ = renderer.render(blocks: blocks, configuration: bigCacheConfig)
        }
        time("render (cache warm, capacity 8192)") {
            var renderer = MarkdownRenderer()
            _ = renderer.render(blocks: blocks, configuration: bigCacheConfig)
        }
        let bigStats = MarkdownRenderer.getRenderCacheStats()
        print("[BENCH] render cache 8192 capacity: hits=\(bigStats.hits) misses=\(bigStats.misses)")

        time("flatten word granularity") {
            _ = RevealFlattener.flatten(blocks, granularity: .word, configuration: config)
        }
        time("flatten char granularity") {
            _ = RevealFlattener.flatten(blocks, granularity: .character, configuration: config)
        }

        // Streaming-shaped growth: re-parse a growing prefix like a chat turn.
        let chat = String(corpus.prefix(8_000))
        time("chat-sized growth x100 (parse+flatten, cached parser)") {
            var growingConfig = MarkdownConfiguration.default
            growingConfig.enableRenderCaching = true
            var idx = chat.startIndex
            for _ in 0..<100 {
                idx = chat.index(idx, offsetBy: chat.count / 100, limitedBy: chat.endIndex) ?? chat.endIndex
                let buffer = String(chat[..<idx])
                let b = Glimmer.parse(buffer, configuration: growingConfig)
                _ = RevealFlattener.flatten(b, granularity: .word, configuration: growingConfig)
            }
        }

        time("chat-sized growth x100 (incremental reveal session)") {
            var growingConfig = MarkdownConfiguration.default
            growingConfig.enableRenderCaching = true
            let session = RevealSession(granularity: .word, configuration: growingConfig)
            var idx = chat.startIndex
            for _ in 0..<100 {
                idx = chat.index(idx, offsetBy: chat.count / 100, limitedBy: chat.endIndex) ?? chat.endIndex
                let buffer = String(chat[..<idx])
                _ = session.update(buffer)
            }
            let stats = session.stats
            print("[BENCH] incremental reveal session: full=\(stats.fullRebuilds) incremental=\(stats.incrementalUpdates)")
        }
    }

    /// Long-running loop for attaching Instruments (Time Profiler).
    /// Skipped unless GLIMMER_PROFILING=1 to keep CI/test runs fast.
    func testProfilingLoop() throws {
        guard ProcessInfo.processInfo.environment["GLIMMER_PROFILING"] == "1" else {
            throw XCTSkip("set GLIMMER_PROFILING=1 to run the profiling loop")
        }
        var config = MarkdownConfiguration.default
        config.enableCaching = false
        config.enableRenderCaching = false

        let corpus = Self.makeCorpus(sections: 200)
        let deadline = Date().addingTimeInterval(45)
        var iterations = 0
        while Date() < deadline {
            let blocks = MarkdownParser.parse(corpus, configuration: config)
            var renderer = MarkdownRenderer()
            _ = renderer.render(blocks: blocks, configuration: config)
            _ = RevealFlattener.flatten(blocks, granularity: .word, configuration: config)
            iterations += 1
        }
        print("[BENCH] profiling loop iterations: \(iterations)")
    }
}

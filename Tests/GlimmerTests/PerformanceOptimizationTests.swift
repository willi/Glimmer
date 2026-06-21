import XCTest
import SwiftUI
@testable import Glimmer

final class PerformanceOptimizationTests: XCTestCase {
    func testOptimization1_StreamingChunkConsumptionBeatsBaselineRemoveFirstLoop() {
        let chunk = String(repeating: "\n", count: 120_000)

        let baseline = median((0..<3).map { _ in
            timed {
                _ = consumeLinesBaselineRemoveFirst(chunk)
            }
        })

        let optimized = median((0..<3).map { _ in
            timed {
                let parser = StreamingMarkdownParser(configuration: .default)
                _ = parser.parseChunk(chunk)
            }
        })

        XCTAssertLessThan(
            optimized,
            baseline,
            "Streaming parser line consumption should outperform repeated removeFirst baseline."
        )
    }

    func testOptimization2_RenderLRUTouchOutperformsArrayTouchModel() {
        let keys = (0..<8_000).map { "k\($0)" }
        let touches = 80_000

        let baseline = median((0..<3).map { _ in
            timed {
                _ = simulateArrayLRUTouches(keys: keys, touches: touches)
            }
        })

        let optimized = median((0..<3).map { _ in
            timed {
                _ = simulateLinkedLRUTouches(keys: keys, touches: touches)
            }
        })

        XCTAssertLessThan(
            optimized,
            baseline,
            "Linked-list LRU touch model should beat array firstIndex/remove/append model."
        )
    }

    func testOptimization3_DictCacheEvictionOutperformsMinScanModel() {
        let capacity = 2_500
        let operations = 30_000

        let baseline = median((0..<3).map { _ in
            timed {
                _ = simulateMinScanLRUEvictions(capacity: capacity, operations: operations)
            }
        })

        let optimized = median((0..<3).map { _ in
            timed {
                _ = simulateLinkedLRUEvictions(capacity: capacity, operations: operations)
            }
        })

        XCTAssertLessThan(
            optimized,
            baseline,
            "Linked-list O(1) eviction model should beat dictionary min-scan LRU eviction model."
        )
    }

    func testOptimization4_HigherConfiguredConcurrencyImprovesParallelParseThroughput() throws {
        let cpuCount = ProcessInfo.processInfo.processorCount
        guard cpuCount >= 2 else {
            throw XCTSkip("Requires at least 2 CPU cores to compare concurrency throughput.")
        }

        let markdown = String(
            repeating: """
            ## Heading

            Paragraph text with **bold** and [link](https://example.com).

            - item
            - item

            """,
            count: 3_000
        )

        let serialConfig = ParallelMarkdownParser.ParallelConfiguration(
            concurrency: 1,
            minimumSizeThreshold: 0,
            chunkSize: 2_048,
            preserveOrder: true
        )
        let parallelConfig = ParallelMarkdownParser.ParallelConfiguration(
            concurrency: min(4, cpuCount),
            minimumSizeThreshold: 0,
            chunkSize: 2_048,
            preserveOrder: true
        )

        let serialParser = ParallelMarkdownParser(parallelConfig: serialConfig, markdownConfig: .default)
        let parallelParser = ParallelMarkdownParser(parallelConfig: parallelConfig, markdownConfig: .default)

        let serialTime = median((0..<3).map { _ in
            timed {
                _ = serialParser.parse(markdown)
            }
        })
        let parallelTime = median((0..<3).map { _ in
            timed {
                _ = parallelParser.parse(markdown)
            }
        })

        XCTAssertLessThan(
            parallelTime,
            serialTime,
            "Configured higher concurrency should improve parse throughput on multi-core systems."
        )
    }

    func testOptimization24_RangeParallelChunkSplitterAvoidsChunkStringCopies() {
        let markdown = makeParallelChunkSplitterBenchmarkMarkdown(sectionCount: 2_000)
        let chunkSize = 1_024

        let copiedChunks = ParallelChunkSplitter.splitCopiedForTesting(markdown: markdown, chunkSize: chunkSize)
        let rangeChunks = ParallelChunkSplitter.splitRanges(markdown: markdown, chunkSize: chunkSize)
        XCTAssertGreaterThan(copiedChunks.count, 1)
        XCTAssertEqual(rangeChunks.first?.range.lowerBound, markdown.startIndex)
        XCTAssertEqual(rangeChunks.last?.range.upperBound, markdown.endIndex)

        let copied = median((0..<5).map { _ in
            timed {
                let chunks = ParallelChunkSplitter.splitCopiedForTesting(markdown: markdown, chunkSize: chunkSize)
                XCTAssertGreaterThan(copiedChunkChecksum(chunks), 0)
            }
        })

        let rangeBacked = median((0..<5).map { _ in
            timed {
                let chunks = ParallelChunkSplitter.splitRanges(markdown: markdown, chunkSize: chunkSize)
                XCTAssertGreaterThan(rangeChunkChecksum(chunks, in: markdown), 0)
            }
        })

        print(
            "[BENCH] parallel chunk split copied strings: \(formatMilliseconds(copied)) ms " +
            "range-backed: \(formatMilliseconds(rangeBacked)) ms " +
            "speedup: \(formatRatio(copied / max(rangeBacked, 0.0001)))x"
        )

        XCTAssertLessThan(
            rangeBacked,
            copied,
            "Range-backed parallel chunk splitting should avoid line/chunk String copies."
        )
    }

    func testOptimization70_ParallelChunkSplitterClassifiesLinesOnce() throws {
        func assertSameRangeChunks(_ markdown: String, chunkSize: Int, file: StaticString = #filePath, line: UInt = #line) {
            let repeated = ParallelChunkSplitter.splitRangesByRepeatedLineScanningForTesting(
                markdown: markdown,
                chunkSize: chunkSize
            )
            let classified = ParallelChunkSplitter.splitRanges(markdown: markdown, chunkSize: chunkSize)

            XCTAssertEqual(classified.count, repeated.count, file: file, line: line)
            XCTAssertEqual(classified.first?.range.lowerBound, repeated.first?.range.lowerBound, file: file, line: line)
            XCTAssertEqual(classified.last?.range.upperBound, repeated.last?.range.upperBound, file: file, line: line)
            XCTAssertEqual(
                rangeChunkChecksum(classified, in: markdown),
                rangeChunkChecksum(repeated, in: markdown),
                file: file,
                line: line
            )

            for (lhs, rhs) in zip(classified, repeated) {
                XCTAssertEqual(lhs.index, rhs.index, file: file, line: line)
                XCTAssertEqual(lhs.startOffset, rhs.startOffset, file: file, line: line)
                XCTAssertEqual(lhs.range.lowerBound, rhs.range.lowerBound, file: file, line: line)
                XCTAssertEqual(lhs.range.upperBound, rhs.range.upperBound, file: file, line: line)
                XCTAssertEqual(markdown[lhs.range], markdown[rhs.range], file: file, line: line)
            }
        }

        let representativeDocuments = [
            makeParallelChunkSplitterBenchmarkMarkdown(sectionCount: 80),
            ParserBoundaryCorpus.parallelChunkBoundary(repetitions: 12),
            ProfilingBenchmarkTests.makeCorpus(sections: 4),
            "```\n" +
                "| not a table |\n" +
                "---\n" +
                "```\n\n" +
                "A | B\n" +
                "--- | ---\n" +
                "x | y\n\n" +
                "> quote\n" +
                "> next\n\n" +
                "- item\n" +
                "- second\n\n" +
                "\u{0661}. unicode\n" +
                "\u{0662}. second\n\n" +
                "Heading\n" +
                "=====\n\n" +
                "   \n" +
                "after whitespace\n",
            "Title\r\n---\r\n\n| A |\r\n|---|\r\n\n+ item\n\n"
        ]

        for markdown in representativeDocuments {
            for chunkSize in [8, 16, 48, 257, 1_024] {
                assertSameRangeChunks(markdown, chunkSize: chunkSize)
            }
        }

        let boundaryCorpus = ParserBoundaryCorpus.parallelChunkBoundary(repetitions: 8)
        let serial = MarkdownParser.parse(boundaryCorpus, configuration: .github)

        for chunkSize in [8, 16, 48] {
            let config = ParallelMarkdownParser.ParallelConfiguration(
                concurrency: 3,
                minimumSizeThreshold: 0,
                chunkSize: chunkSize,
                preserveOrder: true
            )
            let parallel = ParallelMarkdownParser(parallelConfig: config, markdownConfig: .github).parse(boundaryCorpus)
            ParserCanonicalSnapshot.assertSemanticallyEqual(
                parallel,
                serial,
                "UTF-8 splitter line classification must preserve parallel parser semantics for chunkSize \(chunkSize)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let markdown = makeParallelChunkSplitterBenchmarkMarkdown(sectionCount: 4_000) +
            ParserBoundaryCorpus.parallelChunkBoundary(repetitions: 300)
        let chunkSize = 1_024

        let repeated = median((0..<5).map { _ in
            timed {
                let chunks = ParallelChunkSplitter.splitRangesByRepeatedLineScanningForTesting(
                    markdown: markdown,
                    chunkSize: chunkSize
                )
                XCTAssertGreaterThan(rangeChunkChecksum(chunks, in: markdown), 0)
            }
        })

        let classified = median((0..<5).map { _ in
            timed {
                let chunks = ParallelChunkSplitter.splitRanges(markdown: markdown, chunkSize: chunkSize)
                XCTAssertGreaterThan(rangeChunkChecksum(chunks, in: markdown), 0)
            }
        })

        print(
            "[BENCH] parallel splitter repeated line scans: \(formatMilliseconds(repeated)) ms " +
            "classified: \(formatMilliseconds(classified)) ms " +
            "speedup: \(formatRatio(repeated / max(classified, 0.0001)))x"
        )

        XCTAssertLessThan(
            classified,
            repeated,
            "Parallel chunk splitting should classify each line once instead of repeatedly scanning it."
        )
        #endif
    }

    func testOptimization71_ASCIIParserStateAdvanceUsesUTF8Bytes() throws {
        let representativeInputs = [
            "",
            "plain ascii",
            "line one\nline two\n",
            "line one\r\nline two\r\n",
            "carriage\rreturn\nnext",
            "tabs\tand spaces",
            "café\nnext",
            "emoji \u{1F680}\nnext"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parserStateAdvanceSignature(input, optimized: true),
                parserStateAdvanceSignature(input, optimized: false),
                "ParserState.advance must preserve cursor semantics for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let input = makeParserStateAdvanceBenchmark(lineCount: 80_000)

        let character = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(parserStateAdvanceChecksum(input, optimized: false), 0)
            }
        })

        let utf8 = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(parserStateAdvanceChecksum(input, optimized: true), 0)
            }
        })

        print(
            "[BENCH] parser state advance character: \(formatMilliseconds(character)) ms " +
            "utf8: \(formatMilliseconds(utf8)) ms " +
            "speedup: \(formatRatio(character / max(utf8, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8,
            character,
            "ParserState.advance should move through ASCII text with UTF-8 bytes instead of Character reads."
        )
        #endif
    }

    func testOptimization72_RangeBackedParallelChunkParsingAvoidsChunkStringCopies() throws {
        let correctnessInputs = [
            ("splitter", makeParallelChunkSplitterBenchmarkMarkdown(sectionCount: 40), MarkdownConfiguration.default),
            ("boundary", ParserBoundaryCorpus.parallelChunkBoundary(repetitions: 10), MarkdownConfiguration.github),
            ("profiling", ProfilingBenchmarkTests.makeCorpus(sections: 4), MarkdownConfiguration.github),
            ("unicodeCRLF", "## Cafe\u{0301}\r\n\r\nParagraph with emoji \u{1F680}.\r\n\r\n- item\r\n- item\r\n", MarkdownConfiguration.default)
        ]

        for (name, markdown, configuration) in correctnessInputs {
            let serial = MarkdownParser.parse(markdown, configuration: configuration)
            for chunkSize in [16, 48, 257, 1_024] {
                let config = ParallelMarkdownParser.ParallelConfiguration(
                    concurrency: 3,
                    minimumSizeThreshold: 0,
                    chunkSize: chunkSize,
                    preserveOrder: true
                )
                let parser = ParallelMarkdownParser(parallelConfig: config, markdownConfig: configuration)
                let copied = parser.parseByCopyingChunksForTesting(markdown)
                let rangeBacked = parser.parse(markdown)

                ParserCanonicalSnapshot.assertSemanticallyEqual(
                    rangeBacked,
                    copied,
                    "\(name), chunkSize \(chunkSize): range-backed parallel parse changed copied-chunk semantics"
                )
                ParserCanonicalSnapshot.assertSemanticallyEqual(
                    rangeBacked,
                    serial,
                    "\(name), chunkSize \(chunkSize): range-backed parallel parse changed serial semantics"
                )
            }
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let markdown = makeParallelChunkSplitterBenchmarkMarkdown(sectionCount: 10_000) +
            ParserBoundaryCorpus.parallelChunkBoundary(repetitions: 500)
        let config = ParallelMarkdownParser.ParallelConfiguration(
            concurrency: 1,
            minimumSizeThreshold: 0,
            chunkSize: 1_024,
            preserveOrder: true
        )
        let parser = ParallelMarkdownParser(parallelConfig: config, markdownConfig: .github)

        let copied = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(parallelParseChecksum(parser.parseByCopyingChunksForTesting(markdown)), 0)
            }
        })

        let rangeBacked = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(parallelParseChecksum(parser.parse(markdown)), 0)
            }
        })

        print(
            "[BENCH] parallel chunk parse copied strings: \(formatMilliseconds(copied)) ms " +
            "range-backed: \(formatMilliseconds(rangeBacked)) ms " +
            "speedup: \(formatRatio(copied / max(rangeBacked, 0.0001)))x"
        )

        XCTAssertLessThan(
            rangeBacked,
            copied,
            "Range-backed parallel chunk parsing should avoid per-chunk String copies."
        )
        #endif
    }

    func testOptimization52_PreallocatedParallelResultSlotsAvoidSorting() {
        let results = makeParallelResultOrderingBenchmark(count: 80_000)
        XCTAssertGreaterThan(results.count, 1)

        let appendAndSort = median((0..<5).map { _ in
            timed {
                var completed: [IndexedParallelBlocks] = []
                completed.reserveCapacity(results.count)
                for result in results.reversed() {
                    completed.append(result)
                }

                let checksum = completed
                    .sorted { $0.index < $1.index }
                    .reduce(0) { $0 + indexedParallelBlocksChecksum($1) }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let preallocatedSlots = median((0..<5).map { _ in
            timed {
                var slots = Array<IndexedParallelBlocks?>(repeating: nil, count: results.count)
                for result in results.reversed() {
                    slots[result.index] = result
                }

                let checksum = slots.reduce(0) { partial, result in
                    guard let result else { return partial }
                    return partial + indexedParallelBlocksChecksum(result)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] parallel result append+sort: \(formatMilliseconds(appendAndSort)) ms " +
            "preallocated slots: \(formatMilliseconds(preallocatedSlots)) ms " +
            "speedup: \(formatRatio(appendAndSort / max(preallocatedSlots, 0.0001)))x"
        )

        XCTAssertLessThan(
            preallocatedSlots,
            appendAndSort,
            "Ordered parallel result collection should fill indexed slots instead of sorting completed chunks."
        )
    }

    func testOptimization5_RemovingRedundantPrescanGuardsImprovesNoMarkerPath() {
        let markdown = String(
            repeating: "Plain markdown line with no special marker tokens\n",
            count: 24_000
        )
        let inlineFootnoteRegex = try! NSRegularExpression(pattern: #"\^\[([^\]]+)\]"#, options: [])

        let unguardedFootnote = median((0..<3).map { _ in
            timed {
                var checksum = 0
                for _ in 0..<24 {
                    checksum += unguardedInlineFootnoteScanCount(markdown, regex: inlineFootnoteRegex)
                }
                XCTAssertGreaterThanOrEqual(checksum, 0)
            }
        })
        let guardedFootnote = median((0..<3).map { _ in
            timed {
                var checksum = 0
                for _ in 0..<24 {
                    checksum += guardedInlineFootnoteScanCount(markdown, regex: inlineFootnoteRegex)
                }
                XCTAssertGreaterThanOrEqual(checksum, 0)
            }
        })

        let unguardedEmoji = median((0..<3).map { _ in
            timed {
                var checksum = 0
                for _ in 0..<12 {
                    checksum += unguardedEmojiPreprocess(markdown).count
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })
        let guardedEmoji = median((0..<3).map { _ in
            timed {
                var checksum = 0
                for _ in 0..<12 {
                    checksum += guardedEmojiPreprocess(markdown).count
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        XCTAssertLessThan(
            unguardedFootnote,
            guardedFootnote,
            "Inline-footnote regex no-match path should beat redundant contains+regex prescan."
        )
        XCTAssertLessThan(
            unguardedEmoji,
            guardedEmoji,
            "Emoji regex no-match path should beat redundant contains+regex prescan."
        )
    }

    func testOptimization6_TableWidthCacheSpeedsRepeatedMeasurements() {
        let (header, rows) = makeLargeTableForWidthMeasurement()
        TextMeasurement.clearColumnWidthCacheForTesting()

        let uncached = median((0..<3).map { _ in
            timed {
                for _ in 0..<6 {
                    _ = TextMeasurement.calculateColumnWidthsUncachedForTesting(
                        header: header,
                        rows: rows,
                        baseFont: .body
                    )
                }
            }
        })

        TextMeasurement.clearColumnWidthCacheForTesting()
        let cached = median((0..<3).map { _ in
            timed {
                for _ in 0..<6 {
                    _ = TextMeasurement.calculateColumnWidths(
                        header: header,
                        rows: rows,
                        baseFont: .body
                    )
                }
            }
        })

        let stats = TextMeasurement.columnWidthCacheStatsForTesting()
        XCTAssertGreaterThan(stats.hits, 0, "Expected cache hits for repeated table width calculations.")
        XCTAssertGreaterThanOrEqual(stats.entries, 1, "Expected at least one cached table width entry.")
        XCTAssertLessThan(cached, uncached, "Cached table width calculations should outperform uncached calculations.")
    }

    func testOptimization7_StatefulStreamingUpdatesBeatFullReparsePerUpdate() {
        let updates = makeAppendOnlyStreamingUpdates(updateCount: 180)
        let finalMarkdown = updates.joined()

        let baseline = median((0..<3).map { _ in
            timed {
                var markdown = ""
                var checksum = 0
                for update in updates {
                    markdown += update
                    checksum ^= MarkdownParser.parse(markdown, configuration: .default).count
                }
                XCTAssertGreaterThanOrEqual(checksum, 0)
            }
        })

        let optimized = median((0..<3).map { _ in
            timed {
                let parser = StreamingMarkdownParser(configuration: .default)
                var checksum = 0
                for update in updates {
                    _ = parser.parseChunk(update)
                    checksum ^= parser.snapshotBlocks().count
                }
                checksum ^= parser.finish().count
                XCTAssertGreaterThanOrEqual(checksum, 0)
            }
        })

        let fullBlocks = MarkdownParser.parse(finalMarkdown, configuration: .default)
        let parser = StreamingMarkdownParser(configuration: .default)
        for update in updates {
            _ = parser.parseChunk(update)
        }
        let streamingBlocks = parser.snapshotBlocks()

        XCTAssertEqual(
            streamingBlocks.count,
            fullBlocks.count,
            "Stateful streaming snapshot should preserve final block count for append-only updates."
        )
        XCTAssertLessThan(
            optimized,
            baseline,
            "Stateful streaming updates should outperform reparsing the full document on each update."
        )
    }

    func testOptimization8_InlineBuilderCompositionBeatsRecursiveConcatModel() {
        let nodes = makeDeepNestedInlineNodes(depth: 8, fanout: 5)

        let baselineOutput = renderInlineBaselineRecursive(nodes, baseFont: .body)
        let optimizedOutput = renderInlineOptimizedBuilder(nodes, baseFont: .body)
        XCTAssertEqual(
            baselineOutput.characters.count,
            optimizedOutput.characters.count,
            "Inline builder and recursive models should produce equivalent output length."
        )

        let baselineIntermediates = countBaselineIntermediateAttributedNodes(nodes)
        let optimizedIntermediates = countOptimizedIntermediateAttributedNodes(nodes)
        XCTAssertLessThan(
            optimizedIntermediates,
            baselineIntermediates,
            "Inline builder should create fewer intermediate AttributedString fragments than recursive concatenation."
        )

        let baseline = median((0..<3).map { _ in
            timed {
                var checksum = 0
                for _ in 0..<20 {
                    checksum ^= renderInlineBaselineRecursive(nodes, baseFont: .body).characters.count
                }
                XCTAssertGreaterThanOrEqual(checksum, 0)
            }
        })

        let optimized = median((0..<3).map { _ in
            timed {
                var checksum = 0
                for _ in 0..<20 {
                    checksum ^= renderInlineOptimizedBuilder(nodes, baseFont: .body).characters.count
                }
                XCTAssertGreaterThanOrEqual(checksum, 0)
            }
        })

        XCTAssertLessThanOrEqual(
            optimized / max(baseline, 0.0001),
            1.25,
            "In-place inline composition should stay within acceptable overhead while reducing fragment churn."
        )
    }

    func testOptimization9_FastEmojiLookupMatchesPublicMapsForRepresentativeShortcodes() {
        let shortcodes = ["+1", "rocket", "tada", "sparkles", "accessibility", "octocat", "zzz"]

        for shortcode in shortcodes {
            XCTAssertEqual(
                GitHubEmojis.unicodeEmoji(for: shortcode),
                GitHubEmojis.emojiMap[shortcode],
                "Fast Unicode lookup must match the public map for \(shortcode)."
            )
            XCTAssertEqual(
                GitHubEmojis.bundledEmojiURL(for: shortcode),
                GitHubEmojis.emojiUrls[shortcode],
                "Fast URL lookup must match the public map for \(shortcode)."
            )
        }

        let blocks = MarkdownParser.parse("Ship :rocket: :octocat: :not_real:", configuration: .github)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected a paragraph")
        }

        XCTAssertTrue(inlines.contains { node in
            if case .text(let text) = node {
                return text.contains("🚀")
            }
            return false
        })
        XCTAssertTrue(inlines.contains { node in
            if case .image(_, let alt, _) = node {
                return alt == ":octocat:"
            }
            return false
        })
        XCTAssertTrue(inlines.contains { node in
            if case .text(let text) = node {
                return text.contains(":not_real:")
            }
            return false
        })
    }

    func testOptimization10_RenderCacheAdmissionSkipsHorizontalRulesAndCachesRenderedContent() {
        var config = MarkdownConfiguration.default
        config.enableRenderCaching = true

        MarkdownRenderer.clearRenderCache()
        var ruleRenderer = MarkdownRenderer()
        let ruleBlocks: [MarkdownParser.BlockNode] = [.horizontalRule]
        _ = ruleRenderer.render(blocks: ruleBlocks, configuration: config)
        _ = ruleRenderer.render(blocks: ruleBlocks, configuration: config)
        var stats = MarkdownRenderer.getRenderCacheStats()
        XCTAssertEqual(stats.hits, 0)
        XCTAssertEqual(stats.misses, 0)

        MarkdownRenderer.clearRenderCache()
        var paragraphRenderer = MarkdownRenderer()
        let paragraphBlocks: [MarkdownParser.BlockNode] = [.paragraph(children: [.text("tiny")])]
        _ = paragraphRenderer.render(blocks: paragraphBlocks, configuration: config)
        _ = paragraphRenderer.render(blocks: paragraphBlocks, configuration: config)
        stats = MarkdownRenderer.getRenderCacheStats()
        XCTAssertEqual(stats.misses, 1)
        XCTAssertEqual(stats.hits, 1)
    }

    func testOptimization11_InlineAttributedCacheKeysAndStats() {
        MarkdownInlineAttributedCache.clearForTesting()
        let nodes: [MarkdownParser.InlineNode] = [
            .text("Cached "),
            .strong(children: [.text("inline")]),
            .text(" content")
        ]
        let key = MarkdownInlineAttributedCache.key(
            nodes: nodes,
            configuration: .github,
            baseFont: .body,
            mode: .plain
        )

        XCTAssertNil(MarkdownInlineAttributedCache.value(for: key))
        MarkdownInlineAttributedCache.insert(AttributedString("Cached inline content"), for: key)
        XCTAssertNotNil(MarkdownInlineAttributedCache.value(for: key))

        let interactiveKey = MarkdownInlineAttributedCache.key(
            nodes: nodes,
            configuration: .github,
            baseFont: .body,
            mode: .interactive
        )
        XCTAssertNotEqual(key, interactiveKey)

        let stats = MarkdownInlineAttributedCache.statsForTesting()
        XCTAssertEqual(stats.misses, 1)
        XCTAssertEqual(stats.hits, 1)
        XCTAssertEqual(stats.entries, 1)
    }

    func testOptimization14_RendererInlineCacheRequiresSessionAndReusesRenderedInlines() {
        MarkdownInlineAttributedCache.clearForTesting()

        var config = MarkdownConfiguration.default
        config.enableRenderCaching = true
        let nodes: [MarkdownParser.InlineNode] = [
            .text("Cached "),
            .strong(children: [.text("inline")]),
            .text(" content")
        ]

        let standalone = MarkdownRenderer().renderInlines(nodes, configuration: config)
        XCTAssertEqual(String(standalone.characters), "Cached inline content")
        var stats = MarkdownInlineAttributedCache.statsForTesting()
        XCTAssertEqual(stats.misses, 0)
        XCTAssertEqual(stats.hits, 0)
        XCTAssertEqual(stats.entries, 0)

        var renderer = MarkdownRenderer()
        renderer.beginSession(configuration: config)
        let first = renderer.renderInlines(nodes, configuration: config)
        let second = renderer.renderInlines(nodes, configuration: config)

        XCTAssertEqual(first, second)
        stats = MarkdownInlineAttributedCache.statsForTesting()
        XCTAssertEqual(stats.misses, 1)
        XCTAssertEqual(stats.hits, 1)
        XCTAssertEqual(stats.entries, 1)
    }

    func testOptimization12_IncrementalRevealSessionBeatsFullParseFlattenGrowth() {
        let updates = makeAppendOnlyStreamingUpdates(updateCount: 160)

        let baseline = median((0..<3).map { _ in
            timed {
                var markdown = ""
                var checksum = 0
                for update in updates {
                    markdown += update
                    let blocks = Glimmer.parse(markdown, configuration: .default)
                    checksum ^= RevealFlattener
                        .flatten(blocks, granularity: .word, configuration: .default)
                        .countableCount
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let optimized = median((0..<3).map { _ in
            timed {
                let session = RevealSession(granularity: .word, configuration: .default)
                var markdown = ""
                var checksum = 0
                for update in updates {
                    markdown += update
                    checksum ^= session.update(markdown).countableCount
                }
                XCTAssertEqual(session.stats.fullRebuilds, 1)
                XCTAssertEqual(session.stats.incrementalUpdates, updates.count - 1)
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        XCTAssertLessThan(
            optimized,
            baseline * 0.35,
            "Incremental reveal session should avoid repeated full parse+flatten growth work."
        )
    }

    func testOptimization20_RevealFlattenOffsetsAvoidPostWalk() {
        let blocks = Glimmer.parse(makeRevealOffsetBenchmarkMarkdown(sectionCount: 260), configuration: .default)
        let atomOffset = 12_000
        let blockOffset = 700
        let countableOffset = 8_000
        let cases: [(label: String, granularity: RevealGranularity)] = [
            ("word", .word),
            ("character", .character)
        ]

        for benchmarkCase in cases {
            let baselineModel = flattenRevealWithPostWalkOffset(
                blocks,
                granularity: benchmarkCase.granularity,
                atomOffset: atomOffset,
                blockOffset: blockOffset,
                countableOffset: countableOffset
            )
            let offsetAwareModel = flattenRevealWithOffsetAwarePath(
                blocks,
                granularity: benchmarkCase.granularity,
                atomOffset: atomOffset,
                blockOffset: blockOffset,
                countableOffset: countableOffset
            )
            assertRevealModelsHaveSameBlocksAndAtoms(offsetAwareModel, baselineModel)

            let postWalk = median((0..<5).map { _ in
                timed {
                    var checksum = 0
                    for _ in 0..<10 {
                        let model = flattenRevealWithPostWalkOffset(
                            blocks,
                            granularity: benchmarkCase.granularity,
                            atomOffset: atomOffset,
                            blockOffset: blockOffset,
                            countableOffset: countableOffset
                        )
                        checksum += revealModelLightChecksum(model)
                    }
                    XCTAssertGreaterThan(checksum, 0)
                }
            })

            let offsetAware = median((0..<5).map { _ in
                timed {
                    var checksum = 0
                    for _ in 0..<10 {
                        let model = flattenRevealWithOffsetAwarePath(
                            blocks,
                            granularity: benchmarkCase.granularity,
                            atomOffset: atomOffset,
                            blockOffset: blockOffset,
                            countableOffset: countableOffset
                        )
                        checksum += revealModelLightChecksum(model)
                    }
                    XCTAssertGreaterThan(checksum, 0)
                }
            })

            print(
                "[BENCH] reveal flatten \(benchmarkCase.label) post-walk offsets: " +
                "\(formatMilliseconds(postWalk)) ms offset-aware: \(formatMilliseconds(offsetAware)) ms " +
                "speedup: \(formatRatio(postWalk / max(offsetAware, 0.0001)))x"
            )

            XCTAssertLessThan(
                offsetAware,
                postWalk,
                "Offset-aware reveal flattening should avoid the post-flatten ID rewrite for \(benchmarkCase.label)."
            )
        }
    }

    func testOptimization13_CoreTextWidthMeasurementBeatsTextKitMeasurement() throws {
        let samples = try makeRepresentativeInlineMeasurementSamples()

        for sample in samples {
            let textKitWidth = TextMeasurement.measureInlineNodesWithTextKitForTesting(sample, baseFont: .body)
            let coreTextWidth = TextMeasurement.measureInlineNodesWithCoreTextForTesting(sample, baseFont: .body)
            XCTAssertEqual(coreTextWidth, textKitWidth, accuracy: 2)
        }

        let iterations = 400
        _ = TextMeasurement.measureInlineNodesWithTextKitForTesting(samples[0], baseFont: .body)
        _ = TextMeasurement.measureInlineNodesWithCoreTextForTesting(samples[0], baseFont: .body)

        let textKit = median((0..<3).map { _ in
            timed {
                var checksum = 0
                for _ in 0..<iterations {
                    for sample in samples {
                        checksum += Int(TextMeasurement
                            .measureInlineNodesWithTextKitForTesting(sample, baseFont: .body)
                            .rounded())
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let coreText = median((0..<3).map { _ in
            timed {
                var checksum = 0
                for _ in 0..<iterations {
                    for sample in samples {
                        checksum += Int(TextMeasurement
                            .measureInlineNodesWithCoreTextForTesting(sample, baseFont: .body)
                            .rounded())
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] width measurement textkit: \(formatMilliseconds(textKit)) ms " +
            "coretext: \(formatMilliseconds(coreText)) ms speedup: \(formatRatio(textKit / max(coreText, 0.0001)))x"
        )

        XCTAssertLessThan(
            coreText,
            textKit,
            "CoreText width measurement should outperform TextKit for representative inline markdown."
        )
    }

    func testOptimization15_RangeBackedASCIITableRowsAvoidCellStringCopies() throws {
        let rows = makeASCIITableRowsForParsingBenchmark(rowCount: 2_400)
        let alignments: [MarkdownParser.TableAlignment] = [.left, .center, .right, .left, .right]

        for row in rows.prefix(12) {
            let copying = try XCTUnwrap(
                GFMExtensions.parseASCIITableRowByCopyingCellsForTesting(
                    row,
                    alignments: alignments,
                    configuration: .github
                )
            )
            let rangeBacked = GFMExtensions.parseTableRow(row, alignments: alignments, configuration: .github)
            XCTAssertEqual(rangeBacked, copying)
        }

        let copying = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for row in rows {
                    let cells = GFMExtensions.parseASCIITableRowByCopyingCellsForTesting(
                        row,
                        alignments: alignments,
                        configuration: .github
                    ) ?? []
                    checksum += cells.count
                    checksum += cells.first?.content.count ?? 0
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let rangeBacked = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for row in rows {
                    let cells = GFMExtensions.parseTableRow(row, alignments: alignments, configuration: .github)
                    checksum += cells.count
                    checksum += cells.first?.content.count ?? 0
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] ascii table row parse copying: \(formatMilliseconds(copying)) ms " +
            "range-backed: \(formatMilliseconds(rangeBacked)) ms " +
            "speedup: \(formatRatio(copying / max(rangeBacked, 0.0001)))x"
        )

        XCTAssertLessThan(
            rangeBacked,
            copying,
            "Range-backed ASCII table row parsing should avoid per-cell String copies and outperform the old model."
        )
    }

    func testOptimization108_ASCIITableRowsBuildCellsInSinglePass() throws {
        let representativeRows = [
            "| a | b | c |",
            "a|b|c",
            "| | middle | |",
            "| **bold** | [link](https://example.com) | `code` |",
            "| leading | trailing   |",
            "",
            "|"
        ]
        let alignments: [MarkdownParser.TableAlignment] = [.left, .center, .right]

        for row in representativeRows {
            let materialized = try XCTUnwrap(
                GFMExtensions.parseASCIITableRowByMaterializingRangesForTesting(
                    row,
                    alignments: alignments,
                    configuration: .github
                ),
                row
            )
            let singlePass = GFMExtensions.parseTableRow(row, alignments: alignments, configuration: .github)
            XCTAssertEqual(singlePass, materialized, "Single-pass ASCII table rows must preserve semantics for \(row)")
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let rows = makeASCIITableRowsForSinglePassBenchmark(rowCount: 90_000)

        let materialized = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for row in rows {
                    let cells = GFMExtensions.parseASCIITableRowByMaterializingRangesForTesting(
                        row,
                        alignments: alignments,
                        configuration: .github
                    ) ?? []
                    checksum &+= cells.reduce(0) { $0 + tableCellBenchmarkChecksum($1) }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let singlePass = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for row in rows {
                    let cells = GFMExtensions.parseTableRow(row, alignments: alignments, configuration: .github)
                    checksum &+= cells.reduce(0) { $0 + tableCellBenchmarkChecksum($1) }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] ascii table row materialized ranges: \(formatMilliseconds(materialized)) ms " +
            "single pass: \(formatMilliseconds(singlePass)) ms " +
            "speedup: \(formatRatio(materialized / max(singlePass, 0.0001)))x"
        )

        XCTAssertLessThan(
            singlePass,
            materialized,
            "ASCII table row parsing should build cells while scanning instead of materializing cell ranges first."
        )
        #endif
    }

    func testOptimization132_ASCIITableRowsBypassInlineParserForPlainCells() throws {
        let representativeRows = [
            "| alpha | beta 123 | gamma |",
            "| **bold** | [link](https://example.com) | `code` |",
            "| @octo | #42 | :rocket: |",
            "| owner/repo | apple/swift#123 | deadbeefdeadbeefdeadbeefdeadbeefdeadbeef |",
            "| https://example.com | www.example.com | mailto:octo@example.com |",
            "| escaped \\*literal\\* | ![alt](image.png) | <span>html</span> |",
            "| café | plain | ✅ |"
        ]
        let alignments: [MarkdownParser.TableAlignment] = [.left, .center, .right]

        for row in representativeRows {
            let fullInline = GFMExtensions.parseASCIITableRowByParsingPlainCellsForTesting(
                row,
                alignments: alignments,
                configuration: .github
            ) ?? GFMExtensions.parseTableRow(row, alignments: alignments, configuration: .github)
            let fastPlainCells = GFMExtensions.parseTableRow(row, alignments: alignments, configuration: .github)
            XCTAssertEqual(fastPlainCells, fullInline, "Plain table-cell fast path must preserve semantics for \(row)")
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let rows = makeASCIITableRowsForSinglePassBenchmark(rowCount: 90_000)

        let fullInline = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for row in rows {
                    let cells = GFMExtensions.parseASCIITableRowByParsingPlainCellsForTesting(
                        row,
                        alignments: alignments,
                        configuration: .github
                    ) ?? []
                    checksum &+= cells.reduce(0) { $0 + tableCellBenchmarkChecksum($1) }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let fastPlainCells = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for row in rows {
                    let cells = GFMExtensions.parseTableRow(row, alignments: alignments, configuration: .github)
                    checksum &+= cells.reduce(0) { $0 + tableCellBenchmarkChecksum($1) }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] ascii table plain cells full inline: \(formatMilliseconds(fullInline)) ms " +
            "direct text: \(formatMilliseconds(fastPlainCells)) ms " +
            "speedup: \(formatRatio(fullInline / max(fastPlainCells, 0.0001)))x"
        )

        XCTAssertLessThan(
            fastPlainCells,
            fullInline,
            "ASCII table row parsing should bypass the inline parser for cells that are proven plain text."
        )
        #endif
    }

    func testOptimization51_ASCIITableAlignmentsScanBytes() throws {
        let representativeLines = [
            "| --- | :---: | ---: |",
            "--- | :--- | ---:",
            "| - | :-: | -: |",
            "| x | --- |",
            "|   |   |",
            "",
            "| café | --- |"
        ]

        for line in representativeLines {
            let characterScan = GFMExtensions.parseASCIITableAlignmentsByCharacterScanningForTesting(line) ??
                GFMExtensions.parseTableAlignments(line)
            XCTAssertEqual(
                GFMExtensions.parseTableAlignments(line),
                characterScan,
                "ASCII table alignment byte scan must preserve Character-scan semantics for \(line)"
            )
        }

        let lines = makeASCIITableAlignmentBenchmark(count: 260_000)

        let characterScan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for line in lines {
                    let alignments = GFMExtensions.parseASCIITableAlignmentsByCharacterScanningForTesting(line) ?? []
                    checksum += tableAlignmentChecksum(alignments)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let byteScan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for line in lines {
                    let alignments = GFMExtensions.parseTableAlignments(line)
                    checksum += tableAlignmentChecksum(alignments)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] ascii table alignment character scan: \(formatMilliseconds(characterScan)) ms " +
            "byte scan: \(formatMilliseconds(byteScan)) ms " +
            "speedup: \(formatRatio(characterScan / max(byteScan, 0.0001)))x"
        )

        XCTAssertLessThan(
            byteScan,
            characterScan,
            "ASCII table alignment parsing should check dashes and colons with UTF-8 bytes."
        )
    }

    func testOptimization115_ASCIITableAlignmentsAvoidMaterializedRanges() throws {
        let representativeLines = [
            "| --- | :---: | ---: |",
            "--- | :--- | ---:",
            "| - | :-: | -: |",
            "| x | --- |",
            "|   |   |",
            "",
            "| café | --- |",
            "|   ---   |   :---:   |   ---:   |"
        ]

        for line in representativeLines {
            let materialized = GFMExtensions.parseASCIITableAlignmentsByMaterializingRangesForTesting(line) ??
                GFMExtensions.parseTableAlignments(line)
            XCTAssertEqual(
                GFMExtensions.parseTableAlignments(line),
                materialized,
                "Single-pass ASCII table alignment scan must preserve materialized-range semantics for \(line)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let lines = makeASCIITableAlignmentBenchmark(count: 260_000)

        let materialized = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for line in lines {
                    let alignments = GFMExtensions.parseASCIITableAlignmentsByMaterializingRangesForTesting(line) ?? []
                    checksum += tableAlignmentChecksum(alignments)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let singlePass = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for line in lines {
                    let alignments = GFMExtensions.parseTableAlignments(line)
                    checksum += tableAlignmentChecksum(alignments)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] ascii table alignment materialized ranges: \(formatMilliseconds(materialized)) ms " +
            "single pass: \(formatMilliseconds(singlePass)) ms " +
            "speedup: \(formatRatio(materialized / max(singlePass, 0.0001)))x"
        )

        XCTAssertLessThan(
            singlePass,
            materialized,
            "ASCII table alignment parsing should classify cells while scanning instead of materializing ranges first."
        )
        #endif
    }

    func testOptimization18_RangeBackedTableBlocksAvoidLineStringCopies() throws {
        let table = makeASCIITableBlockForParsingBenchmark(rowCount: 1_600)
        let lines = table.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let lineRanges = lineRangesExcludingTrailingNewlines(in: table)

        let copying = try XCTUnwrap(GFMExtensions.parseTable(lines: lines, configuration: .github))
        let rangeBacked = try XCTUnwrap(
            GFMExtensions.parseTable(source: table, lineRanges: lineRanges, configuration: .github)
        )

        XCTAssertEqual(rangeBacked.headers, copying.headers)
        XCTAssertEqual(rangeBacked.rows, copying.rows)
        XCTAssertEqual(rangeBacked.alignments, copying.alignments)

        let copyingTime = median((0..<5).map { _ in
            timed {
                let lines = table.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                let parsed = GFMExtensions.parseTable(lines: lines, configuration: .github)
                let checksum = (parsed?.headers.count ?? 0) + (parsed?.rows.count ?? 0)
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let rangeBackedTime = median((0..<5).map { _ in
            timed {
                let parsed = GFMExtensions.parseTable(source: table, lineRanges: lineRanges, configuration: .github)
                let checksum = (parsed?.headers.count ?? 0) + (parsed?.rows.count ?? 0)
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] table block parse copying lines: \(formatMilliseconds(copyingTime)) ms " +
            "range-backed lines: \(formatMilliseconds(rangeBackedTime)) ms " +
            "speedup: \(formatRatio(copyingTime / max(rangeBackedTime, 0.0001)))x"
        )

        XCTAssertLessThan(
            rangeBackedTime,
            copyingTime,
            "Range-backed table block parsing should avoid table line String copies and outperform copied-line parsing."
        )
    }

    func testOptimization21_RangeBackedBlockquotesAvoidLineStringCopies() throws {
        let markdown = makeASCIIBlockquoteForParsingBenchmark(lineCount: 4_000)

        let copying = try XCTUnwrap(parseBlockquoteForBenchmark(markdown, copying: true))
        let rangeBacked = try XCTUnwrap(parseBlockquoteForBenchmark(markdown, copying: false))
        XCTAssertEqual(blockBenchmarkChecksum(rangeBacked), blockBenchmarkChecksum(copying))

        let copyingTime = median((0..<5).map { _ in
            timed {
                let parsed = parseBlockquoteForBenchmark(markdown, copying: true)
                XCTAssertGreaterThan(blockBenchmarkChecksum(parsed), 0)
            }
        })

        let rangeBackedTime = median((0..<5).map { _ in
            timed {
                let parsed = parseBlockquoteForBenchmark(markdown, copying: false)
                XCTAssertGreaterThan(blockBenchmarkChecksum(parsed), 0)
            }
        })

        print(
            "[BENCH] blockquote parse copying lines: \(formatMilliseconds(copyingTime)) ms " +
            "range-backed lines: \(formatMilliseconds(rangeBackedTime)) ms " +
            "speedup: \(formatRatio(copyingTime / max(rangeBackedTime, 0.0001)))x"
        )

        XCTAssertLessThan(
            rangeBackedTime,
            copyingTime,
            "Range-backed blockquote parsing should avoid per-line String copies and outperform copied-line parsing."
        )
    }

    func testOptimization22_FootnoteParagraphFastPathAvoidsLineCopiesAndBlockReparse() throws {
        let markdown = makeASCIIFootnoteForParsingBenchmark(lineCount: 5_000)

        let copying = try XCTUnwrap(parseFootnoteForBenchmark(markdown, copying: true))
        let rangeBacked = try XCTUnwrap(parseFootnoteForBenchmark(markdown, copying: false))
        XCTAssertEqual(blockBenchmarkChecksum(rangeBacked), blockBenchmarkChecksum(copying))

        let copyingTime = median((0..<5).map { _ in
            timed {
                let parsed = parseFootnoteForBenchmark(markdown, copying: true)
                XCTAssertGreaterThan(blockBenchmarkChecksum(parsed), 0)
            }
        })

        let rangeBackedTime = median((0..<5).map { _ in
            timed {
                let parsed = parseFootnoteForBenchmark(markdown, copying: false)
                XCTAssertGreaterThan(blockBenchmarkChecksum(parsed), 0)
            }
        })

        print(
            "[BENCH] footnote parse copying lines: \(formatMilliseconds(copyingTime)) ms " +
            "range-backed paragraph fast path: \(formatMilliseconds(rangeBackedTime)) ms " +
            "speedup: \(formatRatio(copyingTime / max(rangeBackedTime, 0.0001)))x"
        )

        XCTAssertLessThan(
            rangeBackedTime,
            copyingTime,
            "Footnote paragraph fast path should avoid per-line String copies and block reparse overhead."
        )
    }

    func testOptimization43_SingleLineFootnoteParsesInlineFromSourceRange() throws {
        let representativeInputs = [
            "[^one]: plain footnote content",
            "[^two]:  leading and trailing **bold** text   ",
            "[^three]: [link](https://example.com) and `code`",
            "[^four]: Unicode café and emoji :tada:",
            "[^five]: # heading fallback",
            "[^six]: first line\n    continuation line"
        ]

        for input in representativeInputs {
            let joined = try XCTUnwrap(parseSingleLineFootnoteForBenchmark(input, optimized: false), input)
            let rangeBacked = try XCTUnwrap(parseSingleLineFootnoteForBenchmark(input, optimized: true), input)
            ParserCanonicalSnapshot.assertSemanticallyEqual(
                [rangeBacked],
                [joined],
                "Single-line footnote source parsing must preserve semantics for \(input)"
            )
        }

        let inputs = makeSingleLineFootnoteBenchmark(count: 120_000)

        let joined = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += blockBenchmarkChecksum(parseSingleLineFootnoteForBenchmark(input, optimized: false))
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let rangeBacked = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += blockBenchmarkChecksum(parseSingleLineFootnoteForBenchmark(input, optimized: true))
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] single-line footnote joined parse: \(formatMilliseconds(joined)) ms " +
            "source-range parse: \(formatMilliseconds(rangeBacked)) ms " +
            "speedup: \(formatRatio(joined / max(rangeBacked, 0.0001)))x"
        )

        XCTAssertLessThan(
            rangeBacked,
            joined,
            "Single-line footnote paragraphs should parse inlines directly from the source range."
        )
    }

    func testOptimization23_ListItemParagraphFastPathAvoidsLineCopiesAndBlockReparse() {
        let markdown = makeASCIIListItemContentForParsingBenchmark(lineCount: 5_000)

        let copying = parseListItemContentForBenchmark(markdown, copying: true)
        let rangeBacked = parseListItemContentForBenchmark(markdown, copying: false)
        XCTAssertEqual(listItemBenchmarkChecksum(rangeBacked), listItemBenchmarkChecksum(copying))

        let copyingTime = median((0..<5).map { _ in
            timed {
                let item = parseListItemContentForBenchmark(markdown, copying: true)
                XCTAssertGreaterThan(listItemBenchmarkChecksum(item), 0)
            }
        })

        let rangeBackedTime = median((0..<5).map { _ in
            timed {
                let item = parseListItemContentForBenchmark(markdown, copying: false)
                XCTAssertGreaterThan(listItemBenchmarkChecksum(item), 0)
            }
        })

        print(
            "[BENCH] list item parse copying lines: \(formatMilliseconds(copyingTime)) ms " +
            "range-backed paragraph fast path: \(formatMilliseconds(rangeBackedTime)) ms " +
            "speedup: \(formatRatio(copyingTime / max(rangeBackedTime, 0.0001)))x"
        )

        XCTAssertLessThan(
            rangeBackedTime,
            copyingTime,
            "List item paragraph fast path should avoid per-line String copies and block reparse overhead."
        )
    }

    func testOptimization42_SingleLineListItemParsesInlineFromSourceRange() {
        let representativeInputs = [
            "plain list item content",
            "  leading and trailing **bold** text   ",
            "# literal heading in list item",
            "[x] completed task with `code`",
            "[ ] pending task with [link](https://example.com)",
            "Unicode café and emoji :tada:",
            "first line\n  continuation line"
        ]

        for input in representativeInputs {
            let joined = parseSingleLineListItemForBenchmark(input, optimized: false)
            let rangeBacked = parseSingleLineListItemForBenchmark(input, optimized: true)
            XCTAssertEqual(rangeBacked.marker, joined.marker, input)
            XCTAssertEqual(rangeBacked.isTask, joined.isTask, input)
            XCTAssertEqual(rangeBacked.isChecked, joined.isChecked, input)
            ParserCanonicalSnapshot.assertSemanticallyEqual(rangeBacked.content, joined.content, input)
        }

        let inputs = makeSingleLineListItemContentBenchmark(count: 180_000)

        let joined = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let item = parseSingleLineListItemForBenchmark(input, optimized: false)
                    checksum += listItemBenchmarkChecksum(item)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let rangeBacked = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let item = parseSingleLineListItemForBenchmark(input, optimized: true)
                    checksum += listItemBenchmarkChecksum(item)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] single-line list item joined parse: \(formatMilliseconds(joined)) ms " +
            "source-range parse: \(formatMilliseconds(rangeBacked)) ms " +
            "speedup: \(formatRatio(joined / max(rangeBacked, 0.0001)))x"
        )

        XCTAssertLessThan(
            rangeBacked,
            joined,
            "Single-line list item paragraphs should parse inlines directly from the source range."
        )
    }

    func testOptimization54_SingleLineNestedListItemParsesBlockFromSourceRange() {
        let representativeInputs = [
            "- nested list item",
            "1. ordered nested item",
            "> nested quote",
            "---",
            "```swift",
            "# literal heading in list item",
            "Unicode café paragraph"
        ]

        for input in representativeInputs {
            let joined = parseSingleLineListItemForBenchmark(input, optimized: false)
            let rangeBacked = parseSingleLineListItemForBenchmark(input, optimized: true)
            XCTAssertEqual(rangeBacked.marker, joined.marker, input)
            XCTAssertEqual(rangeBacked.isTask, joined.isTask, input)
            XCTAssertEqual(rangeBacked.isChecked, joined.isChecked, input)
            ParserCanonicalSnapshot.assertSemanticallyEqual(
                rangeBacked.content,
                joined.content,
                "Single-line nested list item source parsing must preserve semantics for \(input)"
            )
        }

        let inputs = makeSingleLineNestedListItemContentBenchmark(count: 120_000)

        let joined = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let item = parseSingleLineListItemForBenchmark(input, optimized: false)
                    checksum += listItemBenchmarkChecksum(item)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let rangeBacked = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let item = parseSingleLineListItemForBenchmark(input, optimized: true)
                    checksum += listItemBenchmarkChecksum(item)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] single-line nested list item joined parse: \(formatMilliseconds(joined)) ms " +
            "source-range parse: \(formatMilliseconds(rangeBacked)) ms " +
            "speedup: \(formatRatio(joined / max(rangeBacked, 0.0001)))x"
        )

        XCTAssertLessThan(
            rangeBacked,
            joined,
            "Single-line nested list items should parse nested blocks directly from the source range."
        )
    }

    func testOptimization92_ListItemSingleRangeReuseAvoidsDuplicateTrim() throws {
        let representativeInputs = [
            "- nested list item",
            "1. ordered nested item",
            "> nested quote",
            "---",
            "```swift",
            "# literal heading in list item",
            "Unicode café paragraph"
        ]

        for input in representativeInputs {
            let recomputed = parseSingleLineListItemRangeReuseForBenchmark(input, reuseSingleTrimmedRange: false)
            let reused = parseSingleLineListItemRangeReuseForBenchmark(input, reuseSingleTrimmedRange: true)
            XCTAssertEqual(reused.marker, recomputed.marker, input)
            XCTAssertEqual(reused.isTask, recomputed.isTask, input)
            XCTAssertEqual(reused.isChecked, recomputed.isChecked, input)
            ParserCanonicalSnapshot.assertSemanticallyEqual(
                reused.content,
                recomputed.content,
                "Reused single list-item trim range must preserve semantics for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeSingleLineNestedListItemContentBenchmark(count: 160_000)

        let recomputed = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let item = parseSingleLineListItemRangeReuseForBenchmark(
                        input,
                        reuseSingleTrimmedRange: false
                    )
                    checksum += listItemBenchmarkChecksum(item)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let reused = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let item = parseSingleLineListItemRangeReuseForBenchmark(
                        input,
                        reuseSingleTrimmedRange: true
                    )
                    checksum += listItemBenchmarkChecksum(item)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] single-line list item trim recomputed: \(formatMilliseconds(recomputed)) ms " +
            "reused: \(formatMilliseconds(reused)) ms " +
            "speedup: \(formatRatio(recomputed / max(reused, 0.0001)))x"
        )

        XCTAssertLessThan(
            reused,
            recomputed,
            "Single-line nested list items should reuse the trimmed source range between parse branches."
        )
        #endif
    }

    func testOptimization106_TaskMarkersUseUTF8BytePeek() throws {
        let representativeInputs = [
            "[x] completed task with `code`",
            "[X] uppercase task",
            "[ ] pending task with [link](https://example.com)",
            "[o] malformed task marker",
            "[x]missing trailing space",
            "[ ] café after marker",
            "plain [x] marker later",
            "[ ] "
        ]

        for input in representativeInputs {
            let peeking = parseTaskMarkerListItemForBenchmark(input, utf8TaskMarker: false)
            let bytePeek = parseTaskMarkerListItemForBenchmark(input, utf8TaskMarker: true)
            XCTAssertEqual(bytePeek.item.marker, peeking.item.marker, input)
            XCTAssertEqual(bytePeek.item.isTask, peeking.item.isTask, input)
            XCTAssertEqual(bytePeek.item.isChecked, peeking.item.isChecked, input)
            XCTAssertEqual(bytePeek.offset, peeking.offset, input)
            XCTAssertEqual(bytePeek.line, peeking.line, input)
            XCTAssertEqual(bytePeek.column, peeking.column, input)
            ParserCanonicalSnapshot.assertSemanticallyEqual(
                bytePeek.item.content,
                peeking.item.content,
                "Task marker byte peek must preserve list item content semantics for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeTaskMarkerBytePeekBenchmark(count: 220_000)

        let peeking = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let parsed = parseTaskMarkerListItemForBenchmark(input, utf8TaskMarker: false)
                    checksum &+= listItemBenchmarkChecksum(parsed.item)
                    checksum &+= parsed.offset &+ parsed.line &+ parsed.column
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let bytePeek = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let parsed = parseTaskMarkerListItemForBenchmark(input, utf8TaskMarker: true)
                    checksum &+= listItemBenchmarkChecksum(parsed.item)
                    checksum &+= parsed.offset &+ parsed.line &+ parsed.column
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] task marker character peeks: \(formatMilliseconds(peeking)) ms " +
            "UTF-8 byte peek: \(formatMilliseconds(bytePeek)) ms " +
            "speedup: \(formatRatio(peeking / max(bytePeek, 0.0001)))x"
        )

        XCTAssertLessThan(
            bytePeek,
            peeking,
            "Task marker parsing should avoid repeated Character peeks."
        )
        #endif
    }

    func testOptimization116_ListItemContinuationPrefixesUseUTF8Scan() throws {
        let representativeInputs = [
            "first line\n  continuation line",
            "[x] completed task\n  continuation with `code`",
            "first line\n- sibling list item",
            "first line\n  - nested list item",
            "first line\n  1. ordered nested item",
            "first line\n    over-indented continuation",
            "first line\r\n  continuation after CRLF",
            "first line\n  ١. unicode digit marker"
        ]

        for input in representativeInputs {
            let character = parseListItemContinuationPrefixForBenchmark(input, utf8Prefix: false)
            let utf8 = parseListItemContinuationPrefixForBenchmark(input, utf8Prefix: true)
            XCTAssertEqual(utf8.item.marker, character.item.marker, input)
            XCTAssertEqual(utf8.item.isTask, character.item.isTask, input)
            XCTAssertEqual(utf8.item.isChecked, character.item.isChecked, input)
            XCTAssertEqual(utf8.offset, character.offset, input)
            XCTAssertEqual(utf8.line, character.line, input)
            XCTAssertEqual(utf8.column, character.column, input)
            ParserCanonicalSnapshot.assertSemanticallyEqual(
                utf8.item.content,
                character.item.content,
                "UTF-8 list continuation prefix scan must preserve semantics for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeListItemContinuationPrefixBenchmark(count: 95_000)

        let character = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let parsed = parseListItemContinuationPrefixForBenchmark(input, utf8Prefix: false)
                    checksum &+= listItemBenchmarkChecksum(parsed.item)
                    checksum &+= parsed.offset &+ parsed.line &+ parsed.column
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let utf8 = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let parsed = parseListItemContinuationPrefixForBenchmark(input, utf8Prefix: true)
                    checksum &+= listItemBenchmarkChecksum(parsed.item)
                    checksum &+= parsed.offset &+ parsed.line &+ parsed.column
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] list continuation prefix character scan: \(formatMilliseconds(character)) ms " +
            "UTF-8 scan: \(formatMilliseconds(utf8)) ms " +
            "speedup: \(formatRatio(character / max(utf8, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8,
            character,
            "List item continuation prefixes should avoid repeated Character scans and offset recomputation."
        )
        #endif
    }

    func testOptimization133_FootnoteContinuationPrefixesUseUTF8Scan() throws {
        let representativeInputs = [
            "[^note]: first line\n    continuation line",
            "[^tab]: first line\n\tcontinuation with `code`",
            "[^mixed-tab]: first line\n   \tcontinuation after spaces and tab",
            "[^short]: first line\n   not a continuation\nnext paragraph",
            "[^blank]: first line\n    \n    - nested item",
            "[^unicode]: café\n    continuation with こんにちは",
            "[^crlf]: first line\r\n    continuation after CRLF\r\n"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseFootnoteContinuationPrefixSignatureForBenchmark(input, utf8Prefix: true),
                parseFootnoteContinuationPrefixSignatureForBenchmark(input, utf8Prefix: false),
                "UTF-8 footnote continuation prefix scan must preserve semantics for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeFootnoteContinuationPrefixBenchmark(count: 95_000)

        let character = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(
                    footnoteContinuationPrefixChecksum(inputs, utf8Prefix: false),
                    0
                )
            }
        })

        let utf8 = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(
                    footnoteContinuationPrefixChecksum(inputs, utf8Prefix: true),
                    0
                )
            }
        })

        print(
            "[BENCH] footnote continuation prefix character scan: \(formatMilliseconds(character)) ms " +
            "UTF-8 scan: \(formatMilliseconds(utf8)) ms " +
            "speedup: \(formatRatio(character / max(utf8, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8,
            character,
            "Footnote continuation prefixes should avoid Character scans for ASCII indentation."
        )
        #endif
    }

    func testOptimization117_InvalidInlineURLsValidateBeforeLabelMaterialization() throws {
        let representativeInputs: [(markdown: String, image: Bool)] = [
            ("[**bold** and [nested] text](http://[)", false),
            ("[`code label` and escaped \\[ bracket](http://%)", false),
            ("[valid **bold** link](https://example.com/docs)", false),
            ("![alt **text** and [nested] text](http://exa<mple.com)", true),
            ("![escaped \\[ alt text](http://{)", true),
            ("![valid alt text](https://example.com/image.png)", true)
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseInlineURLValidationCanonicalForBenchmark(
                    input.markdown,
                    image: input.image,
                    earlyValidation: true
                ),
                parseInlineURLValidationCanonicalForBenchmark(
                    input.markdown,
                    image: input.image,
                    earlyValidation: false
                ),
                "Early URL validation must preserve parsed output and parser position for \(input.markdown)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeInvalidInlineURLValidationBenchmark(count: 45_000)

        let labelFirst = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum &+= parseInlineURLValidationChecksumForBenchmark(
                        input.link,
                        image: false,
                        earlyValidation: false
                    )
                    checksum &+= parseInlineURLValidationChecksumForBenchmark(
                        input.image,
                        image: true,
                        earlyValidation: false
                    )
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let urlFirst = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum &+= parseInlineURLValidationChecksumForBenchmark(
                        input.link,
                        image: false,
                        earlyValidation: true
                    )
                    checksum &+= parseInlineURLValidationChecksumForBenchmark(
                        input.image,
                        image: true,
                        earlyValidation: true
                    )
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] invalid inline URL label-first validation: \(formatMilliseconds(labelFirst)) ms " +
            "URL-first validation: \(formatMilliseconds(urlFirst)) ms " +
            "speedup: \(formatRatio(labelFirst / max(urlFirst, 0.0001)))x"
        )

        XCTAssertLessThan(
            urlFirst,
            labelFirst,
            "Invalid inline links and images should reject bad URLs before materializing label or alt text."
        )
        #endif
    }

    func testOptimization118_InlineFootnoteScanUsesContiguousUTF8Storage() throws {
        let representativeInputs: [(markdown: String, configuration: MarkdownConfiguration)] = [
            ("Plain ASCII paragraph with **bold** and [link](https://example.com).", .default),
            ("Plain carets ^ and ^^ without bracket markers.", .default),
            ("Inline note ^[footnote **bold** text] after paragraph.", .default),
            ("Two notes ^[first] and ^[second] with #123 in GitHub mode.", .github),
            ("Unicode outside footnote cafe\u{301} and ^[ascii note].", .default),
            ("Unicode only inside footnote ^[cafe\u{301} note] after ASCII text.", .default),
            ("Empty inline note ^[] stays literal.", .default),
            ("Malformed inline ^[unclosed note with cafe\u{301}", .default),
            ("Broken then valid ^[unclosed and ^[valid] end", .default)
        ]

        for input in representativeInputs {
            ParserCanonicalSnapshot.assertSemanticallyEqual(
                MarkdownParser.parse(input.markdown, configuration: input.configuration),
                MarkdownParser.parseByUTF8IndexInlineFootnoteScanForTesting(
                    input.markdown,
                    configuration: input.configuration
                ),
                "Contiguous UTF-8 inline-footnote scanning must preserve parser semantics."
            )

            XCTAssertEqual(
                MarkdownParser.inlineFootnoteScanSourceASCIIChecksumForTesting(
                    input.markdown,
                    reuseScanASCII: true,
                    useContiguousStorage: true
                ),
                MarkdownParser.inlineFootnoteScanSourceASCIIChecksumForTesting(
                    input.markdown,
                    reuseScanASCII: true,
                    useContiguousStorage: false
                ),
                "Contiguous UTF-8 scanning must preserve match and source-ASCII results."
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeInlineFootnoteContiguousStorageBenchmark()

        let utf8IndexLoop = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    for _ in 0..<80 {
                        checksum &+= MarkdownParser.inlineFootnoteScanSourceASCIIChecksumForTesting(
                            input,
                            reuseScanASCII: true,
                            useContiguousStorage: false
                        )
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let contiguous = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    for _ in 0..<80 {
                        checksum &+= MarkdownParser.inlineFootnoteScanSourceASCIIChecksumForTesting(
                            input,
                            reuseScanASCII: true,
                            useContiguousStorage: true
                        )
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] inline footnote UTF-8 index scan: \(formatMilliseconds(utf8IndexLoop)) ms " +
            "contiguous storage scan: \(formatMilliseconds(contiguous)) ms " +
            "speedup: \(formatRatio(utf8IndexLoop / max(contiguous, 0.0001)))x"
        )

        let parseInputs = Array(inputs.prefix(3))
        let utf8IndexParse = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in parseInputs {
                    for _ in 0..<3 {
                        checksum &+= blockArrayBenchmarkChecksum(
                            MarkdownParser.parseByUTF8IndexInlineFootnoteScanForTesting(
                                input,
                                configuration: .github
                            )
                        )
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let contiguousParse = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in parseInputs {
                    for _ in 0..<3 {
                        checksum &+= blockArrayBenchmarkChecksum(MarkdownParser.parse(input, configuration: .github))
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] inline footnote parse with UTF-8 index scan: \(formatMilliseconds(utf8IndexParse)) ms " +
            "contiguous storage scan: \(formatMilliseconds(contiguousParse)) ms " +
            "speedup: \(formatRatio(utf8IndexParse / max(contiguousParse, 0.0001)))x"
        )

        XCTAssertLessThan(
            contiguousParse,
            utf8IndexParse,
            "Full parsing should benefit from the contiguous inline-footnote scan on footnote-heavy documents."
        )
        #endif
    }

    func testOptimization16_RangeBackedLinksAvoidLabelAndDestinationCopies() throws {
        let links = makeASCIILinksForParsingBenchmark(linkCount: 3_600)

        for link in links.prefix(20) {
            let copying = try XCTUnwrap(parseLinkForBenchmark(link, copying: true))
            let rangeBacked = try XCTUnwrap(parseLinkForBenchmark(link, copying: false))
            XCTAssertEqual(rangeBacked, copying)
        }

        let copying = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for link in links {
                    if let node = parseLinkForBenchmark(link, copying: true) {
                        checksum += linkBenchmarkChecksum(node)
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let rangeBacked = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for link in links {
                    if let node = parseLinkForBenchmark(link, copying: false) {
                        checksum += linkBenchmarkChecksum(node)
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] ascii link parse copying: \(formatMilliseconds(copying)) ms " +
            "range-backed: \(formatMilliseconds(rangeBacked)) ms " +
            "speedup: \(formatRatio(copying / max(rangeBacked, 0.0001)))x"
        )

        XCTAssertLessThan(
            rangeBacked,
            copying,
            "Range-backed link parsing should avoid label/resource String copies and outperform the old model."
        )
    }

    func testOptimization19_SimpleLinkResourceFastPathAvoidsBalancedScan() throws {
        let simpleResources = makeSimpleLinkResourcesForParsingBenchmark(resourceCount: 12_000)
        for resource in simpleResources.prefix(20) {
            let balanced = try XCTUnwrap(parseInlineLinkResourceForBenchmark(resource, fastPath: false))
            let fast = try XCTUnwrap(parseInlineLinkResourceForBenchmark(resource, fastPath: true))
            assertEqualInlineLinkResource(fast, balanced, source: resource)
        }

        let fallbackResources = [
            #"https://example.com/a(b)c)"#,
            #"https://example.com/a\)b)"#,
            #"https://example.com/a "Title")"#,
            #"https://example.com/a 'Title')"#,
            #"https://example.com/a (Title))"#,
            #"https://example.com/café)"#
        ]

        for resource in fallbackResources {
            let balanced = try XCTUnwrap(parseInlineLinkResourceForBenchmark(resource, fastPath: false))
            let fast = try XCTUnwrap(parseInlineLinkResourceForBenchmark(resource, fastPath: true))
            assertEqualInlineLinkResource(fast, balanced, source: resource)
        }

        let balanced = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for resource in simpleResources {
                    if let parsed = parseInlineLinkResourceForBenchmark(resource, fastPath: false) {
                        checksum += inlineLinkResourceBenchmarkChecksum(parsed, in: resource)
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let fast = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for resource in simpleResources {
                    if let parsed = parseInlineLinkResourceForBenchmark(resource, fastPath: true) {
                        checksum += inlineLinkResourceBenchmarkChecksum(parsed, in: resource)
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] simple link resource balanced scan: \(formatMilliseconds(balanced)) ms " +
            "fast path: \(formatMilliseconds(fast)) ms " +
            "speedup: \(formatRatio(balanced / max(fast, 0.0001)))x"
        )

        XCTAssertLessThan(
            fast,
            balanced,
            "Simple ASCII link resources should avoid balanced scanning and outperform the old parser path."
        )
    }

    func testOptimization29_SimpleLinkResourceUsesASCIICursorMove() throws {
        let representativeInputs = [
            "[label](https://example.com/path)",
            "[**Guide**](https://example.com/docs \"Title\")",
            #"[fallback](https://example.com/a\)b)"#,
            "[unicode](https://example.com/café)"
        ]

        for input in representativeInputs {
            let characterMove = try XCTUnwrap(parseLinkResourceMoveForBenchmark(input, asciiMove: false))
            let asciiMove = try XCTUnwrap(parseLinkResourceMoveForBenchmark(input, asciiMove: true))
            XCTAssertEqual(asciiMove, characterMove, "ASCII resource move must preserve semantics for \(input)")
        }

        let links = makeASCIILinksForParsingBenchmark(linkCount: 5_000)

        let characterMove = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for link in links {
                    if let node = parseLinkResourceMoveForBenchmark(link, asciiMove: false) {
                        checksum += linkBenchmarkChecksum(node)
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let asciiMove = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for link in links {
                    if let node = parseLinkResourceMoveForBenchmark(link, asciiMove: true) {
                        checksum += linkBenchmarkChecksum(node)
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] simple link resource character move: \(formatMilliseconds(characterMove)) ms " +
            "ascii move: \(formatMilliseconds(asciiMove)) ms " +
            "speedup: \(formatRatio(characterMove / max(asciiMove, 0.0001)))x"
        )

        XCTAssertLessThan(
            asciiMove,
            characterMove,
            "Simple ASCII link resources should advance with cached byte counts instead of character walking."
        )
    }

    func testOptimization95_SimpleLinkResourceCarriesScannedByteCount() throws {
        let representativeInputs = [
            "[label](https://example.com/path)",
            "[spaced](   https://example.com/path)",
            "[title](https://example.com/docs \"Title\")",
            "[single](https://example.com/docs 'Title')",
            "[empty title gap](https://example.com/docs    )",
            #"[fallback](https://example.com/a\)b)"#,
            "[unicode](https://example.com/café)"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseLinkResourceByteCountCanonicalForBenchmark(input, countedByteCount: true),
                parseLinkResourceByteCountCanonicalForBenchmark(input, countedByteCount: false),
                "Counted simple link resource bytes must preserve semantics and parser position for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let links = makeASCIILinksForParsingBenchmark(linkCount: 8_000)

        let recounting = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for link in links {
                    checksum &+= parseLinkResourceByteCountChecksumForBenchmark(link, countedByteCount: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let counted = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for link in links {
                    checksum &+= parseLinkResourceByteCountChecksumForBenchmark(link, countedByteCount: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] simple link resource byte count recounting: \(formatMilliseconds(recounting)) ms " +
            "counted: \(formatMilliseconds(counted)) ms " +
            "speedup: \(formatRatio(recounting / max(counted, 0.0001)))x"
        )

        XCTAssertLessThan(
            counted,
            recounting,
            "Simple link resource parsing should reuse the scanned byte count instead of recounting UTF-8 distance."
        )
        #endif
    }

    func testOptimization112_UnicodeSimpleLinkResourcesStayOnUTF8FastPath() throws {
        let representativeResources = [
            "https://example.com/café)",
            "https://example.com/こんにちは)",
            "https://example.com/docs \"Café title\")",
            "https://example.com/docs 'Résumé title')",
            "https://example.com/docs \"こんにちは ✅\")",
            "   https://example.com/café   )"
        ]

        for resource in representativeResources {
            let balanced = try XCTUnwrap(parseInlineLinkResourceForBenchmark(resource, fastPath: false))
            let fast = try XCTUnwrap(parseInlineLinkResourceForBenchmark(resource, fastPath: true))
            assertEqualInlineLinkResource(fast, balanced, source: resource)
            XCTAssertNil(fast.asciiByteCount, "Unicode resources must not expose ASCII cursor counts for \(resource)")
        }

        let fallbackResources = [
            #"https://example.com/a(b)café)"#,
            #"https://example.com/a\)café)"#
        ]

        for resource in fallbackResources {
            let balanced = try XCTUnwrap(parseInlineLinkResourceForBenchmark(resource, fastPath: false))
            let fast = try XCTUnwrap(parseInlineLinkResourceForBenchmark(resource, fastPath: true))
            assertEqualInlineLinkResource(fast, balanced, source: resource)
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let resources = makeUnicodeSimpleLinkResourcesForParsingBenchmark(resourceCount: 36_000)

        let balanced = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for resource in resources {
                    if let parsed = parseInlineLinkResourceForBenchmark(resource, fastPath: false) {
                        checksum += inlineLinkResourceBenchmarkChecksum(parsed, in: resource)
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let fast = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for resource in resources {
                    if let parsed = parseInlineLinkResourceForBenchmark(resource, fastPath: true) {
                        checksum += inlineLinkResourceBenchmarkChecksum(parsed, in: resource)
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] unicode simple link resource balanced scan: \(formatMilliseconds(balanced)) ms " +
            "utf8 fast path: \(formatMilliseconds(fast)) ms " +
            "speedup: \(formatRatio(balanced / max(fast, 0.0001)))x"
        )

        XCTAssertLessThan(
            fast,
            balanced,
            "Unicode simple link resources should stay on the UTF-8 fast path instead of balanced scanning."
        )
        #endif
    }

    func testOptimization93_SimpleBracketedLinkTextUsesCountedASCIIMove() throws {
        let representativeInputs = [
            "[plain label](https://example.com/path)",
            "[**Guide** and *topic*](https://example.com/docs \"Title\")",
            "[a \\[b\\]](http://example.com)",
            "[outer [inner]](http://example.com)",
            "[multi\nline](https://example.com)",
            "[unicode café](https://example.com/cafe)"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseLinkBracketedTextMoveCanonicalForBenchmark(input, countedMove: true),
                parseLinkBracketedTextMoveCanonicalForBenchmark(input, countedMove: false),
                "Counted bracketed link-text move must preserve parse result and parser position for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let links = makeASCIILinksForBracketedTextMoveBenchmark(linkCount: 120_000)

        let recounting = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for link in links {
                    checksum &+= parseLinkBracketedTextMoveChecksumForBenchmark(link, countedMove: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let counted = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for link in links {
                    checksum &+= parseLinkBracketedTextMoveChecksumForBenchmark(link, countedMove: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] simple bracketed link text move recounting: \(formatMilliseconds(recounting)) ms " +
            "counted: \(formatMilliseconds(counted)) ms " +
            "speedup: \(formatRatio(recounting / max(counted, 0.0001)))x"
        )

        XCTAssertLessThan(
            counted,
            recounting,
            "Simple ASCII bracketed link text should move with the byte count already discovered by scanning."
        )
        #endif
    }

    func testOptimization46_ASCIIAutolinksUseASCIICursorMove() {
        let representativeInputs = [
            "https://example.com/path",
            "https://example.com/path,",
            "http://example.com/a(b))",
            "www.example.com/path",
            "mailto:octocat@example.com",
            "ftp://example.com/file.txt",
            "<https://example.com/a(b)>",
            "<octocat@example.com>"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseAutolinkMoveCanonicalForBenchmark(input, asciiMove: true),
                parseAutolinkMoveCanonicalForBenchmark(input, asciiMove: false),
                "ASCII autolink cursor move must preserve parse result and parser position for \(input)"
            )
        }

        let inputs = makeASCIIAutolinksForMoveBenchmark(count: 80_000)

        let characterMove = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += parseAutolinkMoveChecksumForBenchmark(input, asciiMove: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let asciiMove = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += parseAutolinkMoveChecksumForBenchmark(input, asciiMove: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] ascii autolink character move: \(formatMilliseconds(characterMove)) ms " +
            "ascii move: \(formatMilliseconds(asciiMove)) ms " +
            "speedup: \(formatRatio(characterMove / max(asciiMove, 0.0001)))x"
        )

        XCTAssertLessThan(
            asciiMove,
            characterMove,
            "ASCII autolink parsing should advance with byte offsets instead of character walking."
        )
    }

    func testOptimization102_ASCIIAutolinksUseCountedCursorMove() throws {
        let representativeInputs = [
            "https://example.com/path",
            "https://example.com/path,",
            "https://example.com/path...",
            "http://example.com/a(b))",
            "https://example.com/path]]",
            "www.example.com/path",
            "mailto:octocat@example.com",
            "ftp://example.com/file.txt",
            "<https://example.com/a(b)>",
            "<octocat@example.com>"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseAutolinkCountedMoveCanonicalForBenchmark(input, countedMove: true),
                parseAutolinkCountedMoveCanonicalForBenchmark(input, countedMove: false),
                "Counted ASCII autolink cursor move must preserve parse result and parser position for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeASCIIAutolinksForMoveBenchmark(count: 100_000)

        let recounting = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += parseAutolinkCountedMoveChecksumForBenchmark(input, countedMove: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let counted = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += parseAutolinkCountedMoveChecksumForBenchmark(input, countedMove: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] ascii autolink recounting move: \(formatMilliseconds(recounting)) ms " +
            "counted move: \(formatMilliseconds(counted)) ms " +
            "speedup: \(formatRatio(recounting / max(counted, 0.0001)))x"
        )

        XCTAssertLessThan(
            counted,
            recounting,
            "ASCII autolink parsing should move with the byte count already discovered by scanning."
        )
        #endif
    }

    func testOptimization107_ASCIIAutolinksTrimTailWithBytes() throws {
        let representativeInputs = [
            "https://example.com/path",
            "https://example.com/path.",
            "https://example.com/path.,;:?!",
            "https://example.com/path...",
            "http://example.com/a(b))",
            "www.example.com/a[b]]",
            "(https://example.com/a(b))",
            "mailto:octocat@example.com;",
            "<https://example.com/path.>",
            "https://example.com/café."
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseAutolinkTailTrimCanonicalForBenchmark(input, byteTrim: true),
                parseAutolinkTailTrimCanonicalForBenchmark(input, byteTrim: false),
                "ASCII autolink byte tail trim must preserve parse result and parser position for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeASCIIAutolinksForTailTrimBenchmark(count: 120_000)

        let characterTrim = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum &+= parseAutolinkTailTrimChecksumForBenchmark(input, byteTrim: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let byteTrim = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum &+= parseAutolinkTailTrimChecksumForBenchmark(input, byteTrim: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] ascii autolink character tail trim: \(formatMilliseconds(characterTrim)) ms " +
            "byte tail trim: \(formatMilliseconds(byteTrim)) ms " +
            "speedup: \(formatRatio(characterTrim / max(byteTrim, 0.0001)))x"
        )

        XCTAssertLessThan(
            byteTrim,
            characterTrim,
            "ASCII autolink tail validation should inspect trailing punctuation with UTF-8 bytes."
        )
        #endif
    }

    func testOptimization134_AngleAutolinksRejectHTMLWithoutCopying() throws {
        let representativeInputs = [
            "<span>",
            "</span>",
            "<br>",
            "<custom-tag>",
            "<h1>",
            "<em>",
            "<img/>",
            "<https://example.com/path>",
            "<octocat@example.com>",
            "<mailto:octocat@example.com>",
            "<1invalid:example>",
            "<invalid scheme>"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseAngleAutolinkCopyCanonicalForBenchmark(input, deferRejectedCopy: true),
                parseAngleAutolinkCopyCanonicalForBenchmark(input, deferRejectedCopy: false),
                "Deferred rejected angle autolink copy must preserve parse result and parser position for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeRejectedAngleAutolinksForCopyBenchmark(count: 160_000)

        let copyBeforeReject = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum &+= parseAngleAutolinkCopyChecksumForBenchmark(input, deferRejectedCopy: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let copyAfterReject = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum &+= parseAngleAutolinkCopyChecksumForBenchmark(input, deferRejectedCopy: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] angle autolink copy-before-reject: \(formatMilliseconds(copyBeforeReject)) ms " +
            "copy-after-reject: \(formatMilliseconds(copyAfterReject)) ms " +
            "speedup: \(formatRatio(copyBeforeReject / max(copyAfterReject, 0.0001)))x"
        )

        XCTAssertLessThan(
            copyAfterReject,
            copyBeforeReject,
            "HTML-looking angle text should reject before materializing autolink content."
        )
        #endif
    }

    func testOptimization103_InlineFootnoteReferencesUseCountedASCIIMove() throws {
        let representativeInputs = [
            "[^1]",
            "[^long-ascii-label-123]",
            "[^label_with_underscore]",
            "[^]",
            "[^unclosed",
            "[^line\n]",
            "[^unicode-café]"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseFootnoteReferenceMoveCanonicalForBenchmark(input, countedMove: true),
                parseFootnoteReferenceMoveCanonicalForBenchmark(input, countedMove: false),
                "Counted ASCII footnote reference move must preserve parse result and parser position for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeInlineFootnoteReferenceMoveBenchmark(count: 140_000)

        let recounting = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += parseFootnoteReferenceMoveChecksumForBenchmark(input, countedMove: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let counted = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += parseFootnoteReferenceMoveChecksumForBenchmark(input, countedMove: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] inline footnote reference recounting move: \(formatMilliseconds(recounting)) ms " +
            "counted move: \(formatMilliseconds(counted)) ms " +
            "speedup: \(formatRatio(recounting / max(counted, 0.0001)))x"
        )

        XCTAssertLessThan(
            counted,
            recounting,
            "Inline footnote references should move with the byte count already discovered by scanning."
        )
        #endif
    }

    func testOptimization104_MentionUsernamesCopyAfterDomainRejection() throws {
        let representativeInputs = [
            "@octocat opened #42",
            "Contact user@example.com please",
            "Contact @example.com please",
            "Multiple @example.com and @valid mentions",
            "prefix@skip then (@alice)",
            "@",
            "Unicode café @example.com and @valid"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseInlineForMentionUsernameCopyCanonicalForBenchmark(input, deferredCopy: true),
                parseInlineForMentionUsernameCopyCanonicalForBenchmark(input, deferredCopy: false),
                "Deferred mention username copy must preserve inline semantics and parser position for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeMentionUsernameCopyBenchmark(count: 40_000)

        let copyBeforeReject = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let inlines = parseInlineForMentionUsernameCopyBenchmark(input, deferredCopy: false)
                    checksum &+= inlineNodesBenchmarkChecksum(inlines)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let copyAfterReject = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let inlines = parseInlineForMentionUsernameCopyBenchmark(input, deferredCopy: true)
                    checksum &+= inlineNodesBenchmarkChecksum(inlines)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] mention username copy-before-reject: \(formatMilliseconds(copyBeforeReject)) ms " +
            "copy-after-reject: \(formatMilliseconds(copyAfterReject)) ms " +
            "speedup: \(formatRatio(copyBeforeReject / max(copyAfterReject, 0.0001)))x"
        )

        XCTAssertLessThan(
            copyAfterReject,
            copyBeforeReject,
            "Domain-like mention rejects should avoid materializing usernames before restoring parser state."
        )
        #endif
    }

    func testOptimization47_ASCIIAutolinksDetectSchemeWithBytes() {
        let representativeInputs = [
            "",
            "h",
            "http:/",
            "https://example.com/path",
            "http://example.com/a(b))",
            "www.example.com/path",
            "mailto:octocat@example.com",
            "ftp://example.com/file.txt",
            "plain text",
            "<https://example.com/path>",
            "<octocat@example.com>"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseAutolinkSchemeCanonicalForBenchmark(input, asciiScheme: true),
                parseAutolinkSchemeCanonicalForBenchmark(input, asciiScheme: false),
                "ASCII autolink scheme detection must preserve parse result and parser position for \(input)"
            )
        }

        let inputs = makeBareASCIIAutolinksForSchemeBenchmark(count: 100_000)

        let characterScheme = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += parseAutolinkSchemeChecksumForBenchmark(input, asciiScheme: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let asciiScheme = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += parseAutolinkSchemeChecksumForBenchmark(input, asciiScheme: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] ascii autolink character scheme: \(formatMilliseconds(characterScheme)) ms " +
            "byte scheme: \(formatMilliseconds(asciiScheme)) ms " +
            "speedup: \(formatRatio(characterScheme / max(asciiScheme, 0.0001)))x"
        )

        XCTAssertLessThan(
            asciiScheme,
            characterScheme,
            "ASCII autolink parsing should detect URL schemes with byte prefix checks."
        )
    }

    func testOptimization50_ASCIIInlineCodeTrimsRangeBeforeCopying() {
        let representativeInputs = [
            "`code`",
            "` code `",
            "`\tcode\t`",
            "`  `",
            "` code\n`",
            "`\ncode `",
            "``code ` nested``",
            "`` code ``",
            "`unclosed"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseInlineCodeTrimCanonicalForBenchmark(input, optimized: true),
                parseInlineCodeTrimCanonicalForBenchmark(input, optimized: false),
                "ASCII inline code range trimming must preserve parse result and parser position for \(input)"
            )
        }

        let inputs = makeASCIIInlineCodeTrimBenchmark(count: 140_000)

        let copiedTrim = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += parseInlineCodeTrimChecksumForBenchmark(input, optimized: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let rangeTrim = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += parseInlineCodeTrimChecksumForBenchmark(input, optimized: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] ascii inline code copied trim: \(formatMilliseconds(copiedTrim)) ms " +
            "range trim: \(formatMilliseconds(rangeTrim)) ms " +
            "speedup: \(formatRatio(copiedTrim / max(rangeTrim, 0.0001)))x"
        )

        XCTAssertLessThan(
            rangeTrim,
            copiedTrim,
            "ASCII inline code parsing should trim code span ranges before copying content."
        )
    }

    func testOptimization119_FailedASCIIInlineCodeSpansReuseBacktickScans() throws {
        let representativeInputs: [(markdown: String, configuration: MarkdownConfiguration)] = [
            ("`unclosed", .default),
            ("``unclosed", .default),
            ("` ``", .default),
            ("` `` ``", .default),
            ("`closed` then `unclosed", .default),
            ("``code ` nested`` and ```tail", .default),
            ("before `unclosed\nnext `line`", .default),
            ("@octocat saw `unclosed and #42", .github),
            ("repo/name has ``unclosed and https://example.com", .github)
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseInlineForFailedCodeSpanCanonicalForBenchmark(
                    input.markdown,
                    configuration: input.configuration,
                    cachedFailures: true
                ),
                parseInlineForFailedCodeSpanCanonicalForBenchmark(
                    input.markdown,
                    configuration: input.configuration,
                    cachedFailures: false
                ),
                "Failed inline-code scan caching must preserve parsed output and parser position for \(input.markdown)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeFailedASCIIInlineCodeSpanBenchmark(documentCount: 120, runCount: 90)

        let reprobing = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum &+= parseInlineFailedCodeSpanChecksumForBenchmark(input, cachedFailures: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let cached = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum &+= parseInlineFailedCodeSpanChecksumForBenchmark(input, cachedFailures: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] failed ascii inline code reprobing: \(formatMilliseconds(reprobing)) ms " +
            "cached scan: \(formatMilliseconds(cached)) ms " +
            "speedup: \(formatRatio(reprobing / max(cached, 0.0001)))x"
        )

        XCTAssertLessThan(
            cached,
            reprobing,
            "Failed ASCII inline-code spans should reuse suffix scan facts instead of rescanning each opener."
        )
        #endif
    }

    func testOptimization17_OnePassASCIIEmphasisAvoidsDelimiterRetryScans() throws {
        let representativeInputs = [
            "*italic*",
            "**bold**",
            "***bold***",
            "***foo**",
            "**foo***",
            "**unclosed payload",
            "***unclosed payload",
            "*foo **bar** baz*"
        ]

        for input in representativeInputs {
            let retrying = try XCTUnwrap(parseEmphasisForBenchmark(input, onePass: false))
            let onePass = try XCTUnwrap(parseEmphasisForBenchmark(input, onePass: true))
            XCTAssertEqual(onePass, retrying, "One-pass emphasis must preserve retry parser semantics for \(input)")
        }

        let inputs = makeUnmatchedASCIIEmphasisForParsingBenchmark(count: 4_800)

        let retrying = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    if let node = parseEmphasisForBenchmark(input, onePass: false) {
                        checksum += inlineNodeBenchmarkChecksum(node)
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let onePass = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    if let node = parseEmphasisForBenchmark(input, onePass: true) {
                        checksum += inlineNodeBenchmarkChecksum(node)
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] ascii emphasis retrying: \(formatMilliseconds(retrying)) ms " +
            "one-pass: \(formatMilliseconds(onePass)) ms " +
            "speedup: \(formatRatio(retrying / max(onePass, 0.0001)))x"
        )

        XCTAssertLessThan(
            onePass,
            retrying,
            "One-pass ASCII emphasis delimiter scanning should avoid retry rescans and outperform the old model."
        )
    }

    func testOptimization25_ASCIIStrikethroughFastPathAvoidsCharacterPeekScan() throws {
        let representativeInputs = [
            "~~gone~~",
            "~~gone **bold** and `code`~~",
            "~~line one\nline two~~",
            "~~unclosed payload"
        ]

        for input in representativeInputs {
            let characterScan = parseStrikethroughForBenchmark(input, fastPath: false)
            let asciiScan = parseStrikethroughForBenchmark(input, fastPath: true)
            XCTAssertEqual(asciiScan, characterScan, "ASCII strikethrough fast path must preserve semantics for \(input)")
        }

        let inputs = makeASCIIStrikethroughForParsingBenchmark(count: 5_200)

        let characterScan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    if let node = parseStrikethroughForBenchmark(input, fastPath: false) {
                        checksum += inlineNodeBenchmarkChecksum(node)
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let asciiScan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    if let node = parseStrikethroughForBenchmark(input, fastPath: true) {
                        checksum += inlineNodeBenchmarkChecksum(node)
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] ascii strikethrough character-scan: \(formatMilliseconds(characterScan)) ms " +
            "byte-scan: \(formatMilliseconds(asciiScan)) ms " +
            "speedup: \(formatRatio(characterScan / max(asciiScan, 0.0001)))x"
        )

        XCTAssertLessThan(
            asciiScan,
            characterScan,
            "ASCII strikethrough parsing should avoid Character/peek scanning and outperform the old model."
        )
    }

    func testOptimization26_SimpleASCIITextRunsSkipGitHubCandidateValidation() {
        let representativeInputs = [
            "Plain words before **bold**",
            "Hello @alice and more text",
            "Fix #42 after a long prefix",
            ":rocket: starts with emoji marker",
            "No markers in this text run"
        ]

        for input in representativeInputs {
            let candidateValidated = consumeASCIITextRunForBenchmark(input, simple: false)
            let simple = consumeASCIITextRunForBenchmark(input, simple: true)
            XCTAssertEqual(simple.consumed, candidateValidated.consumed)
            XCTAssertEqual(simple.offset, candidateValidated.offset)
        }

        let inputs = makeASCIITextRunDispatchBenchmark(count: 16_000)

        let candidateValidated = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let result = consumeASCIITextRunForBenchmark(input, simple: false)
                    checksum += result.offset
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let simple = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let result = consumeASCIITextRunForBenchmark(input, simple: true)
                    checksum += result.offset
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] ascii text run candidate validation: \(formatMilliseconds(candidateValidated)) ms " +
            "simple dispatch: \(formatMilliseconds(simple)) ms " +
            "speedup: \(formatRatio(candidateValidated / max(simple, 0.0001)))x"
        )

        XCTAssertLessThan(
            simple,
            candidateValidated,
            "Simple ASCII text runs should skip GitHub candidate validation when those features are disabled."
        )
    }

    func testOptimization27_ASCIIInlineParsingAvoidsRedundantPlainTextPrescan() {
        let representativeInputs = [
            "Plain words with no markers at all",
            "Long prefix before **bold** and trailing words",
            "Text before [link](https://example.com) after",
            "Escaped \\*marker\\* and `code`",
            "Unicode café keeps the conservative path"
        ]

        for input in representativeInputs {
            let prescanned = parseInlineForPlainTextPrescanBenchmark(input, prescan: true)
            let direct = parseInlineForPlainTextPrescanBenchmark(input, prescan: false)
            XCTAssertEqual(direct, prescanned, "Direct ASCII inline parsing must preserve semantics for \(input)")
        }

        let inputs = makeASCIIInlinePlainTextPrescanBenchmark(count: 12_000)

        let prescanned = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let inlines = parseInlineForPlainTextPrescanBenchmark(input, prescan: true)
                    checksum += inlineNodesBenchmarkChecksum(inlines)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let direct = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let inlines = parseInlineForPlainTextPrescanBenchmark(input, prescan: false)
                    checksum += inlineNodesBenchmarkChecksum(inlines)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] ascii inline plain-text prescan: \(formatMilliseconds(prescanned)) ms " +
            "direct scan: \(formatMilliseconds(direct)) ms " +
            "speedup: \(formatRatio(prescanned / max(direct, 0.0001)))x"
        )

        XCTAssertLessThan(
            direct,
            prescanned,
            "ASCII inline parsing should avoid pre-scanning text that the text-run scanner will scan again."
        )
    }

    func testOptimization66_GFMCandidateDispatchAvoidsDuplicateCandidateProbes() throws {
        let representativeInputs = [
            "See https://example.com and hello/world",
            "Fix owner/repo#42 after deadbeef",
            "Hex-like repo owner abcdef1/repo should stay a repo",
            "Visit http://github.com/owner/repo without splitting a repo",
            "ffffftp://example.com remains text while owner/repo parses"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseInlineForGFMCandidateDispatchBenchmark(input, cachedDispatch: true),
                parseInlineForGFMCandidateDispatchBenchmark(input, cachedDispatch: false),
                "Cached GFM candidate dispatch must preserve inline semantics for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeGFMCandidateDispatchBenchmark(count: 12_000)

        let reprobing = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let inlines = parseInlineForGFMCandidateDispatchBenchmark(input, cachedDispatch: false)
                    checksum += inlineNodesBenchmarkChecksum(inlines)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let cachedDispatch = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let inlines = parseInlineForGFMCandidateDispatchBenchmark(input, cachedDispatch: true)
                    checksum += inlineNodesBenchmarkChecksum(inlines)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] gfm candidate dispatch reprobing: \(formatMilliseconds(reprobing)) ms " +
            "cached kind: \(formatMilliseconds(cachedDispatch)) ms " +
            "speedup: \(formatRatio(reprobing / max(cachedDispatch, 0.0001)))x"
        )

        XCTAssertLessThan(
            cachedDispatch,
            reprobing,
            "GFM candidate dispatch should reuse the candidate type found by ASCII text-run scanning."
        )
        #endif
    }

    func testOptimization96_GFMCandidateValidationSkipsImpossibleStartBytes() throws {
        let representativeInputs = [
            "Zyzz qrst uvxy before https://example.com/path and owner/repo",
            "Plain qrst uvxyz before deadbeefcafebabe and swiftlang/swift-markdown#42",
            "No candidate here, only qrst yz uvxy punctuation.",
            "ffffftp://example.com remains text while owner/repo parses",
            "abcdef1/repo stays a repository reference instead of a SHA prefix"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseInlineForGFMCandidateValidationGateCanonicalForBenchmark(input, gated: true),
                parseInlineForGFMCandidateValidationGateCanonicalForBenchmark(input, gated: false),
                "Gated GFM candidate validation must preserve inline semantics and parser position for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeGFMCandidateValidationGateBenchmark(count: 14_000)

        let ungated = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let inlines = parseInlineForGFMCandidateValidationGateBenchmark(input, gated: false)
                    checksum &+= inlineNodesBenchmarkChecksum(inlines)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let gated = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let inlines = parseInlineForGFMCandidateValidationGateBenchmark(input, gated: true)
                    checksum &+= inlineNodesBenchmarkChecksum(inlines)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] gfm candidate validation ungated: \(formatMilliseconds(ungated)) ms " +
            "gated: \(formatMilliseconds(gated)) ms " +
            "speedup: \(formatRatio(ungated / max(gated, 0.0001)))x"
        )

        XCTAssertLessThan(
            gated,
            ungated,
            "GFM candidate validation should skip bytes that cannot start any enabled candidate."
        )
        #endif
    }

    func testOptimization94_GFMLeafParsersUseCountedASCIIMove() throws {
        let representativeInputs = [
            "@octocat fixed #42 with :rocket: in owner/repo",
            "swiftlang/swift-markdown#512 references deadbeefcafebabe",
            "Email test@example.com and :unknown_shortcode: should preserve fallback text",
            "#999999999999999999999999999999999999999999 overflows back to text",
            "prefixdeadbeefcafebabe is not a commit SHA",
            "deadbeefcafebabeX is not a commit SHA"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseInlineForGFMLeafMoveCanonicalForBenchmark(input, countedMove: true),
                parseInlineForGFMLeafMoveCanonicalForBenchmark(input, countedMove: false),
                "Counted GFM leaf moves must preserve inline semantics and parser position for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeGFMLeafMoveBenchmark(count: 16_000)

        let recounting = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let inlines = parseInlineForGFMLeafMoveBenchmark(input, countedMove: false)
                    checksum &+= inlineNodesBenchmarkChecksum(inlines)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let counted = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let inlines = parseInlineForGFMLeafMoveBenchmark(input, countedMove: true)
                    checksum &+= inlineNodesBenchmarkChecksum(inlines)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] gfm leaf parser moves recounting: \(formatMilliseconds(recounting)) ms " +
            "counted: \(formatMilliseconds(counted)) ms " +
            "speedup: \(formatRatio(recounting / max(counted, 0.0001)))x"
        )

        XCTAssertLessThan(
            counted,
            recounting,
            "GFM leaf parsers should move with byte counts already discovered by their UTF-8 scanners."
        )
        #endif
    }

    func testOptimization97_GFMLeafBoundaryChecksUseASCIIBytes() throws {
        let representativeInputs = [
            "@octocat fixed #42 with :rocket: in owner/repo and deadbeefcafebabe",
            "Email test@example.com keeps text while @valid remains a mention",
            "prefix@no abc#42 xdeadbeefcafebabe deadbeefcafebabeX",
            "owner/repo#123 and owner/repo#not and @owner/repo",
            "/owner/repo :owner/repo https://github.com/owner/repo",
            "Upper ABCDEF1234567890 then swiftlang/swift-markdown#512"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseInlineForGFMLeafBoundaryCanonicalForBenchmark(input, asciiBytes: true),
                parseInlineForGFMLeafBoundaryCanonicalForBenchmark(input, asciiBytes: false),
                "ASCII-byte GFM leaf boundary checks must preserve inline semantics and parser position for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeGFMLeafBoundaryBenchmark(count: 20_000)

        let characterBoundaries = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let inlines = parseInlineForGFMLeafBoundaryBenchmark(input, asciiBytes: false)
                    checksum &+= inlineNodesBenchmarkChecksum(inlines)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let asciiByteBoundaries = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let inlines = parseInlineForGFMLeafBoundaryBenchmark(input, asciiBytes: true)
                    checksum &+= inlineNodesBenchmarkChecksum(inlines)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] gfm leaf boundary checks character: \(formatMilliseconds(characterBoundaries)) ms " +
            "ascii bytes: \(formatMilliseconds(asciiByteBoundaries)) ms " +
            "speedup: \(formatRatio(characterBoundaries / max(asciiByteBoundaries, 0.0001)))x"
        )

        XCTAssertLessThan(
            asciiByteBoundaries,
            characterBoundaries,
            "GFM leaf parsers should reuse ASCII-byte boundary checks when the inline parser has proved ASCII input."
        )
        #endif
    }

    func testOptimization98_ASCIIInlineDispatchUsesByteSwitch() throws {
        let representativeInputs: [(markdown: String, configuration: MarkdownConfiguration)] = [
            ("Prefix before **bold** and _italic_ then `code`.", .default),
            ("[link](https://example.com) and ![alt](https://example.com/image.png)", .default),
            ("~~gone~~ <https://example.com> <span class=\"x\">html</span>", .github),
            ("@octocat closed #42 with :rocket: in owner/repo#123.", .github),
            ("https://example.com/path and www.example.com then deadbeefcafebabe.", .github),
            ("Failed *marker and [link plus ! image and <not closed", .github),
            ("Backslash \\*escape\\* and newline\nnext line stays conservative.", .github)
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseInlineForASCIIByteDispatchCanonicalForBenchmark(
                    input.markdown,
                    configuration: input.configuration,
                    byteDispatch: true
                ),
                parseInlineForASCIIByteDispatchCanonicalForBenchmark(
                    input.markdown,
                    configuration: input.configuration,
                    byteDispatch: false
                ),
                "ASCII byte inline dispatch must preserve inline semantics and parser position for \(input.markdown)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeASCIIInlineByteDispatchBenchmark(count: 18_000)

        let characterDispatch = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let inlines = parseInlineForASCIIByteDispatchBenchmark(input, byteDispatch: false)
                    checksum &+= inlineNodesBenchmarkChecksum(inlines)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let byteDispatch = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let inlines = parseInlineForASCIIByteDispatchBenchmark(input, byteDispatch: true)
                    checksum &+= inlineNodesBenchmarkChecksum(inlines)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] ascii inline character dispatch: \(formatMilliseconds(characterDispatch)) ms " +
            "byte dispatch: \(formatMilliseconds(byteDispatch)) ms " +
            "speedup: \(formatRatio(characterDispatch / max(byteDispatch, 0.0001)))x"
        )

        XCTAssertLessThan(
            byteDispatch,
            characterDispatch,
            "ASCII inline dispatch should switch on the current byte instead of materializing a Character."
        )
        #endif
    }

    func testOptimization99_ASCIIBackslashEscapesUseByteDispatch() throws {
        let representativeInputs: [(markdown: String, configuration: MarkdownConfiguration)] = [
            ("Escaped \\*marker\\* and \\[bracket\\] stay text.", .default),
            ("Escaped \\#42 \\@octocat \\:rocket: with github features.", .github),
            ("Escaped \\! image and \\<tag> before owner/repo.", .github),
            ("Escaped \\é should stay on the character path.", .default),
            ("Trailing backslash at end \\", .default),
            ("Backslash before newline \\\nnext line uses conservative path.", .github)
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseInlineForASCIIEscapeDispatchCanonicalForBenchmark(
                    input.markdown,
                    configuration: input.configuration,
                    byteEscapes: true
                ),
                parseInlineForASCIIEscapeDispatchCanonicalForBenchmark(
                    input.markdown,
                    configuration: input.configuration,
                    byteEscapes: false
                ),
                "ASCII byte backslash dispatch must preserve inline semantics and parser position for \(input.markdown)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeASCIIBackslashEscapeDispatchBenchmark(count: 28_000)

        let characterEscapes = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let inlines = parseInlineForASCIIEscapeDispatchBenchmark(input, byteEscapes: false)
                    checksum &+= inlineNodesBenchmarkChecksum(inlines)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let byteEscapes = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let inlines = parseInlineForASCIIEscapeDispatchBenchmark(input, byteEscapes: true)
                    checksum &+= inlineNodesBenchmarkChecksum(inlines)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] ascii backslash escapes character: \(formatMilliseconds(characterEscapes)) ms " +
            "byte dispatch: \(formatMilliseconds(byteEscapes)) ms " +
            "speedup: \(formatRatio(characterEscapes / max(byteEscapes, 0.0001)))x"
        )

        XCTAssertLessThan(
            byteEscapes,
            characterEscapes,
            "ASCII backslash escapes should avoid Character dispatch after the inline byte scanner stops on a backslash."
        )
        #endif
    }

    func testOptimization100_SourceASCIIEligibilityIsReusedForInlineRanges() throws {
        let representativeInputs: [(markdown: String, configuration: MarkdownConfiguration)] = [
            (makeSourceASCIIInlineRangeBenchmark(sectionCount: 8), .github),
            ("# Cafe\u{0301}\n\nParagraph with emoji \u{1F680} and **bold**.", .default),
            ("## Heading\r\n\r\nParagraph with [link](https://example.com) and `code`.\r\n", .github),
            ("> quoted **bold** line\n> [link](https://example.com)\n", .default),
            ("- item with **bold**\n  continuation with [link](https://example.com)\n", .github)
        ]

        for input in representativeInputs {
            ParserCanonicalSnapshot.assertSemanticallyEqual(
                MarkdownParser.parse(input.markdown, configuration: input.configuration),
                MarkdownParser.parseByScanningInlineRangeASCIIForTesting(
                    input.markdown,
                    configuration: input.configuration
                ),
                "Source ASCII inline-range reuse must preserve parser semantics."
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let markdown = makeSourceASCIIInlineRangeBenchmark(sectionCount: 900)

        let perRangeScan = median((0..<5).map { _ in
            timed {
                let blocks = MarkdownParser.parseByScanningInlineRangeASCIIForTesting(
                    markdown,
                    configuration: .github
                )
                XCTAssertGreaterThan(blockArrayBenchmarkChecksum(blocks), 0)
            }
        })

        let sourceASCIIReuse = median((0..<5).map { _ in
            timed {
                let blocks = MarkdownParser.parse(markdown, configuration: .github)
                XCTAssertGreaterThan(blockArrayBenchmarkChecksum(blocks), 0)
            }
        })

        print(
            "[BENCH] source ascii inline ranges per-range scan: \(formatMilliseconds(perRangeScan)) ms " +
            "source reuse: \(formatMilliseconds(sourceASCIIReuse)) ms " +
            "speedup: \(formatRatio(perRangeScan / max(sourceASCIIReuse, 0.0001)))x"
        )

        XCTAssertLessThan(
            sourceASCIIReuse,
            perRangeScan,
            "ASCII source parsing should reuse full-source eligibility for range-backed inline parses."
        )
        #endif
    }

    func testOptimization110_InlineFootnoteScanReusesSourceASCIIEligibility() throws {
        let unicodePreprocess = MarkdownExtension(
            id: "test.unicode-preprocess",
            version: 1,
            preprocess: { source in source.replacingOccurrences(of: "ASCII_EXTENSION_TOKEN", with: "cafe\u{301}") }
        )
        let extensionConfiguration = MarkdownConfiguration.default.addingExtension(unicodePreprocess)

        let representativeInputs: [(markdown: String, configuration: MarkdownConfiguration)] = [
            ("Plain ASCII paragraph with **bold** and [link](https://example.com).", .default),
            ("Inline note ^[footnote **bold** text] after paragraph.", .default),
            ("Two notes ^[first] and ^[second] with #123 in GitHub mode.", .github),
            ("Unicode outside footnote cafe\u{301} and ^[ascii note].", .default),
            ("Unicode only inside footnote ^[cafe\u{301} note] after ASCII text.", .default),
            ("Malformed inline ^[unclosed note with cafe\u{301}", .default),
            ("ASCII_EXTENSION_TOKEN in extension-controlled preprocessing.", extensionConfiguration)
        ]

        for input in representativeInputs {
            ParserCanonicalSnapshot.assertSemanticallyEqual(
                MarkdownParser.parse(input.markdown, configuration: input.configuration),
                MarkdownParser.parseByRescanningSourceASCIIAfterInlineFootnotePreprocessForTesting(
                    input.markdown,
                    configuration: input.configuration
                ),
                "Reusing source ASCII from inline-footnote scanning must preserve parser semantics."
            )

            XCTAssertEqual(
                MarkdownParser.inlineFootnoteScanSourceASCIIChecksumForTesting(
                    input.markdown,
                    reuseScanASCII: true
                ),
                MarkdownParser.inlineFootnoteScanSourceASCIIChecksumForTesting(
                    input.markdown,
                    reuseScanASCII: false
                ),
                "Inline-footnote source ASCII collection must match the separate source ASCII scan."
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeInlineFootnoteSourceASCIIBenchmark(count: 180_000)

        let rescanned = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += MarkdownParser.inlineFootnoteScanSourceASCIIChecksumForTesting(
                        input,
                        reuseScanASCII: false
                    )
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let reused = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += MarkdownParser.inlineFootnoteScanSourceASCIIChecksumForTesting(
                        input,
                        reuseScanASCII: true
                    )
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] inline footnote scan plus source ascii rescan: \(formatMilliseconds(rescanned)) ms " +
            "scan-carried ascii: \(formatMilliseconds(reused)) ms " +
            "speedup: \(formatRatio(rescanned / max(reused, 0.0001)))x"
        )

        XCTAssertLessThan(
            reused,
            rescanned,
            "Inline-footnote scanning should carry source ASCII eligibility instead of rescanning the source."
        )
        #endif
    }

    func testOptimization113_UnicodeSimpleBracketedLinkTextUsesUTF8Scan() throws {
        let representativeInputs = [
            "[café label](https://example.com/path)",
            "[こんにちは ✅](https://example.com/path \"Title\")",
            "[Résumé parser guide](https://example.com/docs)",
            "[plain ASCII](https://example.com/path)",
            "[outer [inner]](https://example.com/path)",
            #"[escaped \] label](https://example.com/path)"#,
            "[multi\nline](https://example.com/path)"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseLinkBracketedTextScanCanonicalForBenchmark(input, optimized: true),
                parseLinkBracketedTextScanCanonicalForBenchmark(input, optimized: false),
                "UTF-8 simple bracketed link-text scan must preserve parse result and parser position for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let links = makeUnicodeSimpleBracketedLinksForParsingBenchmark(linkCount: 48_000)

        let character = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for link in links {
                    checksum &+= parseLinkBracketedTextScanChecksumForBenchmark(link, optimized: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let utf8 = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for link in links {
                    checksum &+= parseLinkBracketedTextScanChecksumForBenchmark(link, optimized: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] unicode simple bracketed link text character scan: \(formatMilliseconds(character)) ms " +
            "utf8 scan: \(formatMilliseconds(utf8)) ms " +
            "speedup: \(formatRatio(character / max(utf8, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8,
            character,
            "Unicode simple bracketed link text should scan ASCII delimiters with UTF-8 indices."
        )
        #endif
    }

    func testOptimization114_UnresolvedReferenceLinksSkipReferenceLabelScan() throws {
        let representativeInputs = [
            "[label][reference]",
            "[label][]",
            "[label][reference with spaces]",
            "[outer [inner]][reference]",
            "[label][unterminated",
            "[label][reference] trailing",
            "[label](https://example.com/path)",
            "[café](https://example.com/path)"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseLinkReferenceLabelScanCanonicalForBenchmark(input, optimized: true),
                parseLinkReferenceLabelScanCanonicalForBenchmark(input, optimized: false),
                "Skipping unresolved reference-style link label scan must preserve parse result and parser position for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let links = makeUnresolvedReferenceLinksForParsingBenchmark(linkCount: 120_000)

        let scanned = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for link in links {
                    checksum &+= parseLinkReferenceLabelScanChecksumForBenchmark(link, optimized: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let skipped = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for link in links {
                    checksum &+= parseLinkReferenceLabelScanChecksumForBenchmark(link, optimized: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] unresolved reference link label scan: \(formatMilliseconds(scanned)) ms " +
            "immediate restore: \(formatMilliseconds(skipped)) ms " +
            "speedup: \(formatRatio(scanned / max(skipped, 0.0001)))x"
        )

        XCTAssertLessThan(
            skipped,
            scanned,
            "Unsupported reference-style links should restore immediately instead of scanning an unused reference label."
        )
        #endif
    }

    func testOptimization67_ASCIIListMarkerParsingAvoidsCharacterCursorLoop() throws {
        let representativeDocuments = [
            "- item\n- second\n",
            "+ item\n+ second\n",
            "1. first\n2) second\n",
            "   - indented\n   - next\n",
            "١. unicode fallback\n٢. second\n",
            "-not a list\n",
            "1.not ordered\n",
            "- item\n* separate\n"
        ]

        for input in representativeDocuments {
            let character = parseListForBenchmark(input, optimized: false)
            let ascii = parseListForBenchmark(input, optimized: true)
            let characterDescription = character.map { ParserCanonicalSnapshot.canonicalDescription(for: [$0]) } ?? "nil"
            let asciiDescription = ascii.map { ParserCanonicalSnapshot.canonicalDescription(for: [$0]) } ?? "nil"
            XCTAssertEqual(
                asciiDescription,
                characterDescription,
                "ASCII list marker parsing must preserve list semantics for \(input)"
            )
        }

        let representativeMarkers = [
            "- item",
            "* item",
            "+ item",
            "123. ordered",
            "123) ordered",
            "١. unicode fallback",
            "-not a list",
            "1.not ordered"
        ]

        for input in representativeMarkers {
            XCTAssertEqual(
                parseListMarkerSignatureForBenchmark(input, optimized: true),
                parseListMarkerSignatureForBenchmark(input, optimized: false),
                "ASCII list marker parsing must preserve marker semantics for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeASCIIListMarkerBenchmark(count: 240_000)

        let character = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += parseListMarkerSignatureForBenchmark(input, optimized: false)?.utf8.count ?? 1
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let ascii = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += parseListMarkerSignatureForBenchmark(input, optimized: true)?.utf8.count ?? 1
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] list marker character scan: \(formatMilliseconds(character)) ms " +
            "ascii probe: \(formatMilliseconds(ascii)) ms " +
            "speedup: \(formatRatio(character / max(ascii, 0.0001)))x"
        )

        XCTAssertLessThan(
            ascii,
            character,
            "ASCII list marker parsing should avoid Character cursor scans for common list markers."
        )
        #endif
    }

    func testOptimization126_ASCIIListIndentScanAvoidsCharacterCursorLoop() throws {
        let representativeDocuments = [
            "- item\n- second\n",
            " - item\n - second\n",
            "  - item\n  - second\n",
            "   - item\n   - second\n",
            "    - four spaces is not a list marker here\n",
            "  1. first\n  2) second\n",
            "  ١. unicode fallback\n  ٢. second\n",
            "\t- tab is not leading list indentation\n"
        ]

        for input in representativeDocuments {
            let character = parseListIndentForBenchmark(input, utf8Indent: false)
            let ascii = parseListIndentForBenchmark(input, utf8Indent: true)
            let characterDescription = character.map { ParserCanonicalSnapshot.canonicalDescription(for: [$0]) } ?? "nil"
            let asciiDescription = ascii.map { ParserCanonicalSnapshot.canonicalDescription(for: [$0]) } ?? "nil"
            XCTAssertEqual(
                asciiDescription,
                characterDescription,
                "ASCII list indentation scan must preserve list semantics for \(input)"
            )
        }

        let representativeMarkers = [
            "- item",
            " - item",
            "  * item",
            "   + item",
            "    - too deep",
            "  123. ordered",
            "\t- tab is not leading list indentation"
        ]

        for input in representativeMarkers {
            XCTAssertEqual(
                parseIndentedListMarkerSignatureForBenchmark(input, utf8Indent: true),
                parseIndentedListMarkerSignatureForBenchmark(input, utf8Indent: false),
                "ASCII list indentation scan must preserve marker semantics for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeASCIIListMarkerIndentBenchmark(count: 320_000)

        let character = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += parseIndentedListMarkerSignatureForBenchmark(
                        input,
                        utf8Indent: false
                    )?.utf8.count ?? 1
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let ascii = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += parseIndentedListMarkerSignatureForBenchmark(
                        input,
                        utf8Indent: true
                    )?.utf8.count ?? 1
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] list marker indent character scan: \(formatMilliseconds(character)) ms " +
            "utf8 scan: \(formatMilliseconds(ascii)) ms " +
            "speedup: \(formatRatio(character / max(ascii, 0.0001)))x"
        )

        XCTAssertLessThan(
            ascii,
            character,
            "ASCII list indentation scan should avoid Character cursor scans before common list markers."
        )
        #endif
    }

    func testOptimization127_ASCIIListMarkerMoveReusesScannedByteCount() throws {
        let representativeDocuments = [
            "- item\n- second\n",
            "+ item\n+ second\n",
            "1. first\n2) second\n",
            "123456789. wide ordered marker\n123456790. next\n",
            "   - indented\n   - next\n",
            "١. unicode fallback\n٢. second\n",
            "-not a list\n",
            "1.not ordered\n"
        ]

        for input in representativeDocuments {
            XCTAssertEqual(
                parseListMarkerMoveCanonicalForBenchmark(input, countedMove: true),
                parseListMarkerMoveCanonicalForBenchmark(input, countedMove: false),
                "Counted ASCII list marker moves must preserve full list semantics and parser position for \(input)"
            )
        }

        let representativeMarkers = [
            "- item",
            "* item",
            "+ item",
            "1. ordered",
            "123456789. ordered",
            "123456789) ordered",
            "١. unicode fallback",
            "-not a list",
            "1.not ordered"
        ]

        for input in representativeMarkers {
            XCTAssertEqual(
                parseListMarkerMoveSignatureForBenchmark(input, countedMove: true),
                parseListMarkerMoveSignatureForBenchmark(input, countedMove: false),
                "Counted ASCII list marker moves must preserve marker semantics for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeASCIIListMarkerMoveBenchmark(count: 420_000)

        let rescanned = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += parseListMarkerMoveSignatureForBenchmark(
                        input,
                        countedMove: false
                    )?.utf8.count ?? 1
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let counted = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += parseListMarkerMoveSignatureForBenchmark(
                        input,
                        countedMove: true
                    )?.utf8.count ?? 1
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] ascii list marker move rescanned: \(formatMilliseconds(rescanned)) ms " +
            "counted: \(formatMilliseconds(counted)) ms " +
            "speedup: \(formatRatio(rescanned / max(counted, 0.0001)))x"
        )

        XCTAssertLessThan(
            counted,
            rescanned,
            "ASCII list marker parsing should reuse the scanned byte count instead of rescanning marker bytes."
        )
        #endif
    }

    func testOptimization68_BlockFallbackParagraphSkipsKnownFirstBreakProbe() throws {
        let representativeInputs = [
            "plain paragraph\n",
            "  leading plain paragraph\n",
            "first line\nsecond line\n",
            "###not heading\n",
            "####### too many hashes\n",
            "-- not rule\n",
            "__ not rule\n",
            "é paragraph with unicode\n"
        ]

        for input in representativeInputs {
            let checked = try XCTUnwrap(parseKnownParagraphForBenchmark(input, skipKnownFirstBreak: false))
            let skipped = try XCTUnwrap(parseKnownParagraphForBenchmark(input, skipKnownFirstBreak: true))
            ParserCanonicalSnapshot.assertSemanticallyEqual(
                [skipped],
                [checked],
                "Known-first-line paragraph skip must preserve paragraph semantics for \(input)"
            )
        }

        let blockBoundaryInputs = [
            "---\n",
            "# Heading\n",
            "> Quote\n",
            "```swift\nlet value = 1\n```\n",
            "- item\n",
            "    code\n",
            "A | B\n--- | ---\n",
            "Heading\n---\n",
            "١. unicode digit\n",
            "[^bench]: footnote text\n"
        ]

        for input in blockBoundaryInputs {
            let blocks = MarkdownParser.parse(input)
            XCTAssertFalse(
                blocks.contains { block in
                    if case .paragraph = block { return true }
                    return false
                },
                "Block parser must still route block starts before the paragraph fallback for \(input)"
            )
        }

        let paragraphFallbackInputs = [
            "A | B\nnot sep\n",
            "Heading\n---x\n",
            "Heading\r\n---\n",
            "+   \ncontinued\n"
        ]

        for input in paragraphFallbackInputs {
            let blocks = MarkdownParser.parse(input)
            XCTAssertTrue(
                blocks.contains { block in
                    if case .paragraph = block { return true }
                    return false
                },
                "Non-block starts should still reach the paragraph fallback for \(input)"
            )
        }

        for input in ["\nnext", "   \nnext", "\t\nnext"] {
            let result = parseBlockForBenchmark(input)
            XCTAssertNil(result.block, "Direct parseBlock calls should reject blank lines for \(input)")
            XCTAssertTrue(result.preservedPosition, "Direct parseBlock blank-line rejection must not consume input")
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeKnownParagraphFirstLineBreakBenchmark(count: 180_000)

        let checked = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += blockBenchmarkChecksum(parseKnownParagraphForBenchmark(input, skipKnownFirstBreak: false))
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let skipped = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += blockBenchmarkChecksum(parseKnownParagraphForBenchmark(input, skipKnownFirstBreak: true))
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] known paragraph first-break checked: \(formatMilliseconds(checked)) ms " +
            "skipped: \(formatMilliseconds(skipped)) ms " +
            "speedup: \(formatRatio(checked / max(skipped, 0.0001)))x"
        )

        XCTAssertLessThan(
            skipped,
            checked,
            "Block parser paragraph fallback should skip the first paragraph-break probe already ruled out by block dispatch."
        )
        #endif
    }

    func testOptimization69_BlockDispatchSkipsImpossibleTableAndSetextProbes() throws {
        let representativeInputs = [
            "plain paragraph\n",
            "first line\nsecond line\n",
            "  leading plain paragraph\n",
            "\tleading tab text\n",
            "###not heading\n",
            "A | B\n--- | ---\nrow | cell\n",
            "A | B\nnot sep\n",
            "Heading\n---\n",
            "Heading\n---x\n",
            "Heading\r\n---\n",
            "| A |\r\n| - |\n",
            "١. unicode digit\n",
            "[^bench]: footnote text\n",
            "   # Heading\n",
            "   ```swift\nlet value = 1\n```\n",
            "    code\n",
            "\nnext"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseBlockSignatureForBenchmark(input, gated: true),
                parseBlockSignatureForBenchmark(input, gated: false),
                "Block dispatch probe gating must preserve parseBlock semantics for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeBlockDispatchProbeEligibilityBenchmark(count: 140_000)

        let alwaysProbe = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += parseBlockDispatchChecksumForBenchmark(input, gated: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let gated = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += parseBlockDispatchChecksumForBenchmark(input, gated: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] block dispatch table/setext always: \(formatMilliseconds(alwaysProbe)) ms " +
            "gated: \(formatMilliseconds(gated)) ms " +
            "speedup: \(formatRatio(alwaysProbe / max(gated, 0.0001)))x"
        )

        XCTAssertLessThan(
            gated,
            alwaysProbe,
            "Block dispatch should skip impossible table and setext probes before paragraph fallback."
        )
        #endif
    }

    func testOptimization73_BlockDispatchReusesSharedLineClassificationForTableAndSetext() throws {
        let representativeInputs = [
            "plain paragraph\n",
            "first line\nsecond line\n",
            "A | B\n--- | ---\nrow | cell\n",
            "A | B\nnot sep\n",
            "Heading\n---\n",
            "Heading\n---x\n",
            "Heading\r\n---\n",
            "| A |\r\n| - |\n",
            "  Heading\n===\n",
            "   # Heading\n",
            "---\nnext\n",
            "Unicode café | value\n| - | - |\n",
            "Unicode café\n---\n"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseBlockSignatureForBenchmark(input, sharedParagraphStartProbes: true),
                parseBlockSignatureForBenchmark(input, sharedParagraphStartProbes: false),
                "Shared block dispatch line classification must preserve parseBlock semantics for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeBlockDispatchSharedLineClassificationBenchmark(count: 140_000)

        let separate = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += parseBlockDispatchChecksumForBenchmark(input, sharedParagraphStartProbes: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let shared = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += parseBlockDispatchChecksumForBenchmark(input, sharedParagraphStartProbes: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] block dispatch separate table/setext probes: \(formatMilliseconds(separate)) ms " +
            "shared line classification: \(formatMilliseconds(shared)) ms " +
            "speedup: \(formatRatio(separate / max(shared, 0.0001)))x"
        )

        XCTAssertLessThan(
            shared,
            separate,
            "Block dispatch should reuse one line classification for table and setext start probes."
        )
        #endif
    }

    func testOptimization74_ParagraphContinuationLineClassificationAvoidsRescan() throws {
        let representativeInputs = [
            "first line with **bold**\nsecond line with [link](https://example.com)\nthird line\n",
            "intro line\ncontinued text\n# Heading\nparagraph after\n",
            "intro\n###not heading stays text\nstill paragraph\n",
            "intro line\nnot a setext underline\n---\nafter rule\n",
            "intro\ncontinued\n```swift\nlet value = 1\n```\n",
            "intro\n> quoted\nback after quote\n",
            "intro\n- list item\n- second item\n",
            "intro\n1. ordered item\nnext\n",
            "intro\n= not a paragraph break\n| table-ish | line |\n| --- | --- |\n",
            "intro\n_ _ _\nafter spaced rule\n",
            "intro\n-- not a rule\ncontinued\n",
            "intro\n__ not a rule\ncontinued\n",
            "intro\n\u{00A0}# unicode whitespace heading\ncontinued\n",
            "intro\n\u{0661}. unicode digit list\ncontinued\n",
            "intro\n# café\ncontinued\n",
            "intro\n---\u{00A0}\ncontinued\n",
            "intro\r\n- list item\r\n",
            "Unicode café\ncontinued 世界\n- list\n"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseParagraphSignatureForBenchmark(input, sharedContinuationLineScan: true),
                parseParagraphSignatureForBenchmark(input, sharedContinuationLineScan: false),
                "Shared paragraph continuation line scan must preserve parse result and parser position for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeParagraphContinuationLineScanBenchmark(count: 90_000)

        let rescanned = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += parseParagraphContinuationChecksumForBenchmark(
                        input,
                        sharedContinuationLineScan: false
                    )
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let shared = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += parseParagraphContinuationChecksumForBenchmark(
                        input,
                        sharedContinuationLineScan: true
                    )
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] paragraph continuation rescan parse: \(formatMilliseconds(rescanned)) ms " +
            "shared line scan parse: \(formatMilliseconds(shared)) ms " +
            "speedup: \(formatRatio(rescanned / max(shared, 0.0001)))x"
        )

        XCTAssertLessThan(
            shared,
            rescanned,
            "Paragraph parsing should classify ASCII continuation lines while advancing to the line end."
        )
        #endif
    }

    func testOptimization75_DeferredInlineLiteralRunsAvoidFragmentCopy() throws {
        let representativeInputs: [(String, MarkdownConfiguration)] = [
            (
                "Intro text before **bold** then [link](https://example.com) and `code` after",
                .default
            ),
            (
                "Intro * not emphasis and [not a link] plus escaped \\*marker\\* tail",
                .default
            ),
            (
                "Before @octocat fixed #42 in owner/repo with deadbeef and https://example.com/path after",
                .github
            ),
            (
                "Before café **bold** and 世界 [link](https://example.com/café) after",
                .default
            )
        ]

        for (input, configuration) in representativeInputs {
            XCTAssertEqual(
                parseInlineForLiteralRunBufferBenchmark(
                    input,
                    deferredLiteralRuns: true,
                    configuration: configuration
                ),
                parseInlineForLiteralRunBufferBenchmark(
                    input,
                    deferredLiteralRuns: false,
                    configuration: configuration
                ),
                "Deferred literal runs must preserve inline semantics for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeMixedInlineLiteralRunBenchmark(count: 3_000)

        let copying = median((0..<3).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let inlines = parseInlineForLiteralRunBufferBenchmark(
                        input,
                        deferredLiteralRuns: false,
                        configuration: .default
                    )
                    checksum += inlineNodesBenchmarkChecksum(inlines)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let deferred = median((0..<3).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let inlines = parseInlineForLiteralRunBufferBenchmark(
                        input,
                        deferredLiteralRuns: true,
                        configuration: .default
                    )
                    checksum += inlineNodesBenchmarkChecksum(inlines)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] inline literal run eager copy: \(formatMilliseconds(copying)) ms " +
            "deferred range: \(formatMilliseconds(deferred)) ms " +
            "speedup: \(formatRatio(copying / max(deferred, 0.0001)))x"
        )

        XCTAssertLessThan(
            deferred,
            copying,
            "Inline parsing should defer literal text materialization until the text node is emitted."
        )
        #endif
    }

    func testOptimization76_PlainContainerParagraphsBypassInlineReparse() throws {
        let representativeBlockquote = """
        > first plain blockquote line
        > second plain blockquote line
        > third plain blockquote line
        """
        let joinedBlockquote = try XCTUnwrap(
            parseBlockquoteForBenchmark(representativeBlockquote, mode: .paragraphFastPathJoiningSingleRanges)
        )
        let optimizedBlockquote = try XCTUnwrap(
            parseBlockquoteForBenchmark(representativeBlockquote, mode: .paragraphFastPath)
        )
        ParserCanonicalSnapshot.assertSemanticallyEqual([optimizedBlockquote], [joinedBlockquote])

        let representativeListItem = """
        first plain item line
          second plain item line
          third plain item line
        """
        let joinedListItem = parsePlainListItemParagraphForBenchmark(representativeListItem, optimized: false)
        let optimizedListItem = parsePlainListItemParagraphForBenchmark(representativeListItem, optimized: true)
        ParserCanonicalSnapshot.assertSemanticallyEqual(optimizedListItem.content, joinedListItem.content)

        let representativeFootnote = """
        [^plain]: first plain footnote line
            second plain footnote line
            third plain footnote line
        """
        let joinedFootnote = try XCTUnwrap(parsePlainFootnoteParagraphForBenchmark(representativeFootnote, optimized: false))
        let optimizedFootnote = try XCTUnwrap(
            parsePlainFootnoteParagraphForBenchmark(representativeFootnote, optimized: true)
        )
        ParserCanonicalSnapshot.assertSemanticallyEqual([optimizedFootnote], [joinedFootnote])

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let blockquote = makeASCIIBlockquoteForParsingBenchmark(lineCount: 4_000)
        let listItem = makeASCIIListItemContentForParsingBenchmark(lineCount: 5_000)
        let footnote = makeASCIIFootnoteForParsingBenchmark(lineCount: 5_000)

        let joinedChecksum = plainContainerParagraphChecksum(
            blockquote: blockquote,
            listItem: listItem,
            footnote: footnote,
            optimized: false
        )
        let optimizedChecksum = plainContainerParagraphChecksum(
            blockquote: blockquote,
            listItem: listItem,
            footnote: footnote,
            optimized: true
        )
        XCTAssertEqual(optimizedChecksum, joinedChecksum)

        let joined = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(
                    plainContainerParagraphChecksum(
                        blockquote: blockquote,
                        listItem: listItem,
                        footnote: footnote,
                        optimized: false
                    ),
                    0
                )
            }
        })

        let optimized = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(
                    plainContainerParagraphChecksum(
                        blockquote: blockquote,
                        listItem: listItem,
                        footnote: footnote,
                        optimized: true
                    ),
                    0
                )
            }
        })

        print(
            "[BENCH] plain container joined inline reparse: \(formatMilliseconds(joined)) ms " +
            "direct text paragraph: \(formatMilliseconds(optimized)) ms " +
            "speedup: \(formatRatio(joined / max(optimized, 0.0001)))x"
        )

        XCTAssertLessThan(
            optimized,
            joined,
            "Plain container paragraphs should bypass inline parser reparse after source-range collection."
        )
        #endif
    }

    func testOptimization77_NonBlankPlainParagraphSkipsTrimRangeDiscovery() throws {
        let (source, ranges, reservedUTF8Count) = makeNonBlankPlainParagraphRangeBenchmark(lineCount: 6_000)

        let generic = try XCTUnwrap(
            BlockParser.plainTextParagraphInlinesFromSourceRangesForTesting(
                from: ranges,
                in: source,
                reservedUTF8Count: reservedUTF8Count,
                configuration: .default
            )
        )
        let nonBlank = try XCTUnwrap(
            BlockParser.plainTextParagraphInlinesFromNonBlankSourceRangesForTesting(
                from: ranges,
                in: source,
                reservedUTF8Count: reservedUTF8Count,
                configuration: .default
            )
        )
        XCTAssertEqual(nonBlank, generic)

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let genericTime = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for _ in 0..<40 {
                    checksum += plainTextParagraphHelperChecksum(
                        source: source,
                        ranges: ranges,
                        reservedUTF8Count: reservedUTF8Count,
                        optimized: false
                    )
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let nonBlankTime = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for _ in 0..<40 {
                    checksum += plainTextParagraphHelperChecksum(
                        source: source,
                        ranges: ranges,
                        reservedUTF8Count: reservedUTF8Count,
                        optimized: true
                    )
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] plain paragraph generic trim discovery: \(formatMilliseconds(genericTime)) ms " +
            "nonblank trim: \(formatMilliseconds(nonBlankTime)) ms " +
            "speedup: \(formatRatio(genericTime / max(nonBlankTime, 0.0001)))x"
        )

        XCTAssertLessThan(
            nonBlankTime,
            genericTime,
            "Known-nonblank container paragraphs should not rediscover nonblank content ranges before joining."
        )
        #endif
    }

    func testOptimization105_JoinedTrimmedContentAvoidsMaterializedRangeArray() throws {
        let representativeInputs = [
            "   \n  first line\nmiddle line\nlast line   \n   ",
            "single line",
            "   ",
            "\n\n  first\n\nsecond  \n\n",
            "  **bold** text\n  [link](https://example.com)\n  trailing   "
        ]

        for source in representativeInputs {
            let ranges = lineRangesExcludingTrailingNewlines(in: source)
            let reservedUTF8Count = reservedUTF8CountForRanges(ranges, in: source)
            XCTAssertEqual(
                joinedTrimmedContentForBenchmark(
                    source: source,
                    ranges: ranges,
                    reservedUTF8Count: reservedUTF8Count,
                    materializeRanges: false
                ),
                joinedTrimmedContentForBenchmark(
                    source: source,
                    ranges: ranges,
                    reservedUTF8Count: reservedUTF8Count,
                    materializeRanges: true
                ),
                "Single-pass trimmed content join must preserve materialized-range semantics for \(source)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let (source, ranges, reservedUTF8Count) = makeJoinedTrimmedContentBenchmark(lineCount: 6_000)

        let materialized = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for _ in 0..<60 {
                    checksum &+= joinedTrimmedContentChecksumForBenchmark(
                        source: source,
                        ranges: ranges,
                        reservedUTF8Count: reservedUTF8Count,
                        materializeRanges: true
                    )
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let singlePass = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for _ in 0..<60 {
                    checksum &+= joinedTrimmedContentChecksumForBenchmark(
                        source: source,
                        ranges: ranges,
                        reservedUTF8Count: reservedUTF8Count,
                        materializeRanges: false
                    )
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] joined trimmed content materialized ranges: \(formatMilliseconds(materialized)) ms " +
            "single pass: \(formatMilliseconds(singlePass)) ms " +
            "speedup: \(formatRatio(materialized / max(singlePass, 0.0001)))x"
        )

        XCTAssertLessThan(
            singlePass,
            materialized,
            "Trimmed content joining should avoid building a temporary range array."
        )
        #endif
    }

    func testOptimization78_ContentLineFastPathCombinesBlankAndCandidateScans() {
        let representativeInputs = [
            "",
            "   ",
            "    indented code",
            "plain paragraph",
            "   plain paragraph after spaces",
            "# heading",
            "> quote",
            "```swift",
            "~~~",
            "| table |",
            "- list",
            "* list",
            "+ list",
            "123. ordered",
            "123) ordered",
            "= setext continuation",
            "\t- tab is not a leading-space list marker here",
            "  \t# tab after spaces stays paragraph content",
            "\u{000B}",
            "\u{000B}plain after vertical tab",
            "\u{00A0}",
            "\u{00A0}# unicode whitespace heading",
            "\u{0661}. unicode digit"
        ]

        for input in representativeInputs {
            let range = input.startIndex..<input.endIndex
            for isFirstLine in [true, false] {
                XCTAssertEqual(
                    BlockParser.contentLineCanUseParagraphFastPathForTesting(
                        in: input,
                        range: range,
                        isFirstLine: isFirstLine
                    ),
                    BlockParser.contentLineCanUseParagraphFastPathBySeparateScansForTesting(
                        in: input,
                        range: range,
                        isFirstLine: isFirstLine
                    ),
                    "\(input), firstLine=\(isFirstLine)"
                )
            }
        }

        let inputs = makeContentLineFastPathBenchmark(count: 160_000)

        let separate = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for (index, input) in inputs.enumerated() {
                    let range = input.startIndex..<input.endIndex
                    if BlockParser.contentLineCanUseParagraphFastPathBySeparateScansForTesting(
                        in: input,
                        range: range,
                        isFirstLine: index.isMultiple(of: 2)
                    ) {
                        checksum += 1
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let combined = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for (index, input) in inputs.enumerated() {
                    let range = input.startIndex..<input.endIndex
                    if BlockParser.contentLineCanUseParagraphFastPathForTesting(
                        in: input,
                        range: range,
                        isFirstLine: index.isMultiple(of: 2)
                    ) {
                        checksum += 1
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] content-line separate scans: \(formatMilliseconds(separate)) ms " +
            "combined scan: \(formatMilliseconds(combined)) ms " +
            "speedup: \(formatRatio(separate / max(combined, 0.0001)))x"
        )

        XCTAssertLessThan(
            combined,
            separate,
            "Content-line fast path classification should avoid separate blank-line and block-candidate scans."
        )
    }

    func testOptimization28_BlockquoteParagraphFastPathAvoidsRecursiveBlockParse() throws {
        let representativeInputs = [
            "> Quote line 1\n> Quote line 2\n",
            "> first paragraph\n>\n> second paragraph\n",
            "> café quoted\ncontinued 世界\n",
            "> ## Nested heading\n>\n> - nested item\n"
        ]

        for input in representativeInputs {
            let recursive = try XCTUnwrap(parseBlockquoteForBenchmark(input, mode: .recursiveRangeBacked))
            let fastPath = try XCTUnwrap(parseBlockquoteForBenchmark(input, mode: .paragraphFastPath))
            ParserCanonicalSnapshot.assertSemanticallyEqual(
                [fastPath],
                [recursive],
                "Blockquote paragraph fast path must preserve semantics for \(input)"
            )
        }

        let markdown = makeASCIIBlockquoteForParsingBenchmark(lineCount: 4_000)

        let recursive = median((0..<5).map { _ in
            timed {
                let parsed = parseBlockquoteForBenchmark(markdown, mode: .recursiveRangeBacked)
                XCTAssertGreaterThan(blockBenchmarkChecksum(parsed), 0)
            }
        })

        let fastPath = median((0..<5).map { _ in
            timed {
                let parsed = parseBlockquoteForBenchmark(markdown, mode: .paragraphFastPath)
                XCTAssertGreaterThan(blockBenchmarkChecksum(parsed), 0)
            }
        })

        print(
            "[BENCH] blockquote recursive range parse: \(formatMilliseconds(recursive)) ms " +
            "paragraph fast path: \(formatMilliseconds(fastPath)) ms " +
            "speedup: \(formatRatio(recursive / max(fastPath, 0.0001)))x"
        )

        XCTAssertLessThan(
            fastPath,
            recursive,
            "Paragraph-only blockquotes should avoid recursive block parsing and outperform the range-backed recursive path."
        )
    }

    func testOptimization91_BlockquoteLineScanCombinesClassification() throws {
        let representativeInputs = [
            "> Quote line 1\n> Quote line 2\n",
            "> first paragraph\nlazy continuation line\n",
            "> first paragraph\n>\n> second paragraph\n",
            "> tabbed quote\n\t# lazy text after tab stays in quote\n",
            "> first paragraph\n\u{0B}\n= lazy paragraph after ASCII whitespace\n",
            "> quoted paragraph\noutside | table candidate\n",
            "> quoted paragraph\n- outside list candidate\n",
            "> café quoted\ncontinued 世界\n"
        ]

        for input in representativeInputs {
            let separate = try XCTUnwrap(
                parseBlockquoteForBenchmark(input, mode: .paragraphFastPathSeparateLineClassification),
                input
            )
            let combined = try XCTUnwrap(parseBlockquoteForBenchmark(input, mode: .paragraphFastPath), input)
            ParserCanonicalSnapshot.assertSemanticallyEqual(
                [combined],
                [separate],
                "Combined blockquote line scan must preserve semantics for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let markdown = makeLazyASCIIBlockquoteLineScanBenchmark(lineCount: 8_000)

        let separate = median((0..<5).map { _ in
            timed {
                let parsed = parseBlockquoteForBenchmark(
                    markdown,
                    mode: .paragraphFastPathSeparateLineClassification
                )
                XCTAssertGreaterThan(blockBenchmarkChecksum(parsed), 0)
            }
        })

        let combined = median((0..<5).map { _ in
            timed {
                let parsed = parseBlockquoteForBenchmark(markdown, mode: .paragraphFastPath)
                XCTAssertGreaterThan(blockBenchmarkChecksum(parsed), 0)
            }
        })

        print(
            "[BENCH] blockquote separate line scans: \(formatMilliseconds(separate)) ms " +
            "combined line scan: \(formatMilliseconds(combined)) ms " +
            "speedup: \(formatRatio(separate / max(combined, 0.0001)))x"
        )

        XCTAssertLessThan(
            combined,
            separate,
            "Blockquote parsing should classify ASCII content lines while scanning to line end."
        )
        #endif
    }

    func testOptimization44_SingleLineBlockquoteParsesInlineFromSourceRange() throws {
        let representativeInputs = [
            "> quoted paragraph with **bold** text\n",
            ">  leading and trailing `code`   \n",
            "> Unicode café and emoji :tada:\n",
            "> first paragraph\n>\n> second paragraph\n",
            "> first line\nlazy continuation line\n"
        ]

        for input in representativeInputs {
            let joined = try XCTUnwrap(parseBlockquoteForBenchmark(input, mode: .paragraphFastPathJoiningSingleRanges))
            let rangeBacked = try XCTUnwrap(parseBlockquoteForBenchmark(input, mode: .paragraphFastPath))
            ParserCanonicalSnapshot.assertSemanticallyEqual(
                [rangeBacked],
                [joined],
                "Single-range blockquote source parsing must preserve semantics for \(input)"
            )
        }

        let inputs = makeSingleLineBlockquoteBenchmark(count: 120_000)

        let joined = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += blockBenchmarkChecksum(
                        parseBlockquoteForBenchmark(input, mode: .paragraphFastPathJoiningSingleRanges)
                    )
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let rangeBacked = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += blockBenchmarkChecksum(parseBlockquoteForBenchmark(input, mode: .paragraphFastPath))
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] single-line blockquote joined parse: \(formatMilliseconds(joined)) ms " +
            "source-range parse: \(formatMilliseconds(rangeBacked)) ms " +
            "speedup: \(formatRatio(joined / max(rangeBacked, 0.0001)))x"
        )

        XCTAssertLessThan(
            rangeBacked,
            joined,
            "Single-line blockquote paragraphs should parse inlines directly from the source range."
        )
    }

    func testOptimization53_SingleLineNestedBlockquoteParsesBlockFromSourceRange() throws {
        let representativeInputs = [
            "> # Nested heading\n",
            "> ## Nested heading with **literal** markers\n",
            "> - nested list item\n",
            "> 1. ordered nested item\n",
            "> ---\n",
            "> ```swift\n",
            "> café\n"
        ]

        for input in representativeInputs {
            let joined = try XCTUnwrap(parseBlockquoteForBenchmark(input, mode: .recursiveRangeBacked), input)
            let rangeBacked = try XCTUnwrap(parseBlockquoteForBenchmark(input, mode: .paragraphFastPath), input)
            ParserCanonicalSnapshot.assertSemanticallyEqual(
                [rangeBacked],
                [joined],
                "Single-line nested blockquote source parsing must preserve recursive semantics for \(input)"
            )
        }

        let inputs = makeSingleLineNestedBlockquoteBenchmark(count: 120_000)

        let joined = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += blockBenchmarkChecksum(
                        parseBlockquoteForBenchmark(input, mode: .recursiveRangeBacked)
                    )
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let rangeBacked = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += blockBenchmarkChecksum(parseBlockquoteForBenchmark(input, mode: .paragraphFastPath))
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] single-line nested blockquote joined parse: \(formatMilliseconds(joined)) ms " +
            "source-range parse: \(formatMilliseconds(rangeBacked)) ms " +
            "speedup: \(formatRatio(joined / max(rangeBacked, 0.0001)))x"
        )

        XCTAssertLessThan(
            rangeBacked,
            joined,
            "Single-line nested blockquotes should parse nested blocks directly from the source range."
        )
    }

    func testOptimization30_RangeBackedParagraphInlineParsingAvoidsTextCopy() throws {
        let representativeInputs = [
            "Paragraph with **bold**, *italic*, and [link](https://example.com).",
            "  leading and trailing whitespace with `code`   \n",
            "first line with **bold**\nsecond line with [link](https://example.com)\n",
            "Unicode café and 世界 with escaped \\*marker\\*."
        ]

        for input in representativeInputs {
            let copying = try XCTUnwrap(parseParagraphForBenchmark(input, copying: true))
            let rangeBacked = try XCTUnwrap(parseParagraphForBenchmark(input, copying: false))
            ParserCanonicalSnapshot.assertSemanticallyEqual(
                [rangeBacked],
                [copying],
                "Range-backed paragraph inline parsing must preserve semantics for \(input)"
            )
        }

        let paragraphs = makeParagraphInlineParsingBenchmark(count: 8_000)

        let copying = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for paragraph in paragraphs {
                    checksum += blockBenchmarkChecksum(parseParagraphForBenchmark(paragraph, copying: true))
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let rangeBacked = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for paragraph in paragraphs {
                    checksum += blockBenchmarkChecksum(parseParagraphForBenchmark(paragraph, copying: false))
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] paragraph inline parse copied text: \(formatMilliseconds(copying)) ms " +
            "range-backed: \(formatMilliseconds(rangeBacked)) ms " +
            "speedup: \(formatRatio(copying / max(rangeBacked, 0.0001)))x"
        )

        XCTAssertLessThan(
            rangeBacked,
            copying,
            "Paragraph inline parsing should parse the original trimmed range instead of copying paragraph text."
        )
    }

    func testOptimization31_UTF8EmptyLineScanningAvoidsCharacterIteration() {
        let representativeInputs = [
            "\n",
            "   \n",
            "\t\t\n",
            "  text\n",
            "café\n",
            "   "
        ]

        for input in representativeInputs {
            let characterScan = isAtEmptyLineForBenchmark(input, fastPath: false)
            let utf8Scan = isAtEmptyLineForBenchmark(input, fastPath: true)
            XCTAssertEqual(utf8Scan, characterScan, "UTF-8 empty-line scan must preserve semantics for \(input)")
        }

        let inputs = makeEmptyLineScanningBenchmark(count: 120_000)

        let characterScan = median((0..<5).map { _ in
            timed {
                var count = 0
                for input in inputs {
                    if isAtEmptyLineForBenchmark(input, fastPath: false) {
                        count += 1
                    }
                }
                XCTAssertGreaterThan(count, 0)
            }
        })

        let utf8Scan = median((0..<5).map { _ in
            timed {
                var count = 0
                for input in inputs {
                    if isAtEmptyLineForBenchmark(input, fastPath: true) {
                        count += 1
                    }
                }
                XCTAssertGreaterThan(count, 0)
            }
        })

        print(
            "[BENCH] empty-line character scan: \(formatMilliseconds(characterScan)) ms " +
            "utf8 scan: \(formatMilliseconds(utf8Scan)) ms " +
            "speedup: \(formatRatio(characterScan / max(utf8Scan, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8Scan,
            characterScan,
            "Empty-line detection should scan ASCII whitespace with UTF-8 bytes instead of Character iteration."
        )
    }

    func testOptimization32_UTF8BlankLineRangeScanningAvoidsCharacterIteration() {
        let representativeInputs = [
            "",
            "   ",
            "\t\t",
            "  text",
            "\u{00A0}",
            "café"
        ]

        for input in representativeInputs {
            let range = input.startIndex..<input.endIndex
            let characterScan = BlockParser.isBlankLineByCharacterScanningForTesting(in: input, range: range)
            let utf8Scan = BlockParser.isBlankLineForTesting(in: input, range: range)
            XCTAssertEqual(utf8Scan, characterScan, "UTF-8 blank-line range scan must preserve semantics for \(input)")
        }

        let inputs = makeBlankLineRangeScanningBenchmark(count: 120_000)

        let characterScan = median((0..<5).map { _ in
            timed {
                var count = 0
                for input in inputs {
                    let range = input.startIndex..<input.endIndex
                    if BlockParser.isBlankLineByCharacterScanningForTesting(in: input, range: range) {
                        count += 1
                    }
                }
                XCTAssertGreaterThan(count, 0)
            }
        })

        let utf8Scan = median((0..<5).map { _ in
            timed {
                var count = 0
                for input in inputs {
                    let range = input.startIndex..<input.endIndex
                    if BlockParser.isBlankLineForTesting(in: input, range: range) {
                        count += 1
                    }
                }
                XCTAssertGreaterThan(count, 0)
            }
        })

        print(
            "[BENCH] blank-line range character scan: \(formatMilliseconds(characterScan)) ms " +
            "utf8 scan: \(formatMilliseconds(utf8Scan)) ms " +
            "speedup: \(formatRatio(characterScan / max(utf8Scan, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8Scan,
            characterScan,
            "Blank-line range detection should scan ASCII whitespace with UTF-8 bytes."
        )
    }

    func testOptimization33_UTF8WhitespaceRangeHelpersAvoidCharacterIteration() {
        let representativeInputs = [
            "",
            "   ",
            "\t\t",
            "  value  ",
            "\tvalue\t",
            "\nvalue\n",
            "\u{00A0}value\u{00A0}",
            "\u{2003}value\u{2003}",
            "café"
        ]

        for input in representativeInputs {
            let range = input.startIndex..<input.endIndex
            XCTAssertEqual(
                BlockParser.rangeContainsNonWhitespaceForTesting(in: input, range: range),
                BlockParser.rangeContainsNonWhitespaceByCharacterScanningForTesting(in: input, range: range),
                "UTF-8 non-whitespace scan must preserve semantics for \(input)"
            )

            XCTAssertEqual(
                offsets(
                    BlockParser.leadingWhitespaceTrimmedRangeForTesting(in: input, range: range),
                    in: input
                ),
                offsets(
                    BlockParser.leadingWhitespaceTrimmedRangeByCharacterScanningForTesting(in: input, range: range),
                    in: input
                ),
                "UTF-8 leading trim must preserve semantics for \(input)"
            )

            XCTAssertEqual(
                offsets(
                    BlockParser.trailingWhitespaceTrimmedRangeForTesting(in: input, range: range),
                    in: input
                ),
                offsets(
                    BlockParser.trailingWhitespaceTrimmedRangeByCharacterScanningForTesting(in: input, range: range),
                    in: input
                ),
                "UTF-8 trailing trim must preserve semantics for \(input)"
            )
        }

        let inputs = makeWhitespaceRangeHelperBenchmark(count: 120_000)

        let characterScan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += whitespaceRangeHelperChecksum(input, fastPath: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let utf8Scan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += whitespaceRangeHelperChecksum(input, fastPath: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] whitespace range helpers character scan: \(formatMilliseconds(characterScan)) ms " +
            "utf8 scan: \(formatMilliseconds(utf8Scan)) ms " +
            "speedup: \(formatRatio(characterScan / max(utf8Scan, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8Scan,
            characterScan,
            "Whitespace range helpers should scan ASCII whitespace with UTF-8 bytes."
        )
    }

    func testOptimization34_UTF8BlockCandidateLineScanningAvoidsCharacterIteration() {
        let representativeInputs: [(String, Bool)] = [
            ("", true),
            ("   ", true),
            ("    indented code", true),
            ("# heading", true),
            ("> quote", true),
            ("```swift", true),
            ("~~~", true),
            ("| table", true),
            ("- list", true),
            ("* list", true),
            ("+ list", true),
            ("123. ordered", true),
            ("123) ordered", true),
            ("= setext", false),
            ("= first line text", true),
            ("plain paragraph", true),
            ("\t- tab is not counted as leading spaces here", true),
            ("\u{0661}. unicode digit", true)
        ]

        for (input, isFirstLine) in representativeInputs {
            let range = input.startIndex..<input.endIndex
            XCTAssertEqual(
                BlockParser.lineStartsBlockParserCandidateForTesting(
                    in: input,
                    range: range,
                    isFirstLine: isFirstLine
                ),
                BlockParser.lineStartsBlockParserCandidateByCharacterScanningForTesting(
                    in: input,
                    range: range,
                    isFirstLine: isFirstLine
                ),
                "UTF-8 block candidate scan must preserve semantics for \(input)"
            )
        }

        let inputs = makeBlockCandidateLineScanningBenchmark(count: 120_000)

        let characterScan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for (index, input) in inputs.enumerated() {
                    let range = input.startIndex..<input.endIndex
                    if BlockParser.lineStartsBlockParserCandidateByCharacterScanningForTesting(
                        in: input,
                        range: range,
                        isFirstLine: index.isMultiple(of: 2)
                    ) {
                        checksum += 1
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let utf8Scan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for (index, input) in inputs.enumerated() {
                    let range = input.startIndex..<input.endIndex
                    if BlockParser.lineStartsBlockParserCandidateForTesting(
                        in: input,
                        range: range,
                        isFirstLine: index.isMultiple(of: 2)
                    ) {
                        checksum += 1
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] block candidate line character scan: \(formatMilliseconds(characterScan)) ms " +
            "utf8 scan: \(formatMilliseconds(utf8Scan)) ms " +
            "speedup: \(formatRatio(characterScan / max(utf8Scan, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8Scan,
            characterScan,
            "Block candidate line detection should scan ASCII prefixes with UTF-8 bytes."
        )
    }

    func testOptimization35_UTF8ParagraphBreakingBlockScanningAvoidsCharacterIteration() {
        let representativeInputs = [
            "",
            "plain paragraph",
            "  # heading",
            "###not heading",
            "### heading",
            "> quote",
            "```swift",
            "``not fence",
            "~~~",
            "---",
            "- list",
            "-not list",
            "***",
            "* list",
            "___",
            "_not rule",
            "+ list",
            "1. ordered",
            "1.not ordered",
            "\u{0661}. unicode digit",
            "\u{00A0}# unicode whitespace heading"
        ]

        for input in representativeInputs {
            let range = input.startIndex..<input.endIndex
            XCTAssertEqual(
                BlockParser.lineStartsParagraphBreakingBlockForTesting(in: input, range: range),
                BlockParser.lineStartsParagraphBreakingBlockByCharacterScanningForTesting(in: input, range: range),
                "UTF-8 paragraph-breaking scan must preserve semantics for \(input)"
            )
        }

        let inputs = makeParagraphBreakingBlockScanningBenchmark(count: 120_000)

        let characterScan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let range = input.startIndex..<input.endIndex
                    if BlockParser.lineStartsParagraphBreakingBlockByCharacterScanningForTesting(
                        in: input,
                        range: range
                    ) {
                        checksum += 1
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let utf8Scan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let range = input.startIndex..<input.endIndex
                    if BlockParser.lineStartsParagraphBreakingBlockForTesting(in: input, range: range) {
                        checksum += 1
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] paragraph-breaking block character scan: \(formatMilliseconds(characterScan)) ms " +
            "utf8 scan: \(formatMilliseconds(utf8Scan)) ms " +
            "speedup: \(formatRatio(characterScan / max(utf8Scan, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8Scan,
            characterScan,
            "Paragraph-breaking block detection should scan ASCII prefixes with UTF-8 bytes."
        )
    }

    func testOptimization48_ParagraphBreakingBlockSkipsTrailingTrimForPlainLines() {
        let representativeInputs = [
            "",
            "plain paragraph",
            "plain paragraph   ",
            "   plain paragraph with leading spaces   ",
            "# heading",
            "###not heading",
            "> quote",
            "```swift",
            "---",
            "- list",
            "- ",
            "* ",
            "+ list",
            "1. ordered",
            "1. ",
            "\u{0661}. unicode digit",
            "\u{00A0}# unicode whitespace heading"
        ]

        for input in representativeInputs {
            let range = input.startIndex..<input.endIndex
            let optimized = BlockParser.lineStartsParagraphBreakingBlockForTesting(in: input, range: range)
            XCTAssertEqual(
                optimized,
                BlockParser.lineStartsParagraphBreakingBlockByFullTrimForTesting(in: input, range: range),
                "Leading ASCII paragraph-breaking probe must preserve full-trim semantics for \(input)"
            )
            XCTAssertEqual(
                optimized,
                BlockParser.lineStartsParagraphBreakingBlockByCharacterScanningForTesting(in: input, range: range),
                "Leading ASCII paragraph-breaking probe must preserve character-scan semantics for \(input)"
            )
        }

        let inputs = makeParagraphBreakingBlockPlainProbeBenchmark(count: 160_000)

        let fullTrim = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let range = input.startIndex..<input.endIndex
                    if BlockParser.lineStartsParagraphBreakingBlockByFullTrimForTesting(in: input, range: range) {
                        checksum += 1
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let leadingProbe = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let range = input.startIndex..<input.endIndex
                    if BlockParser.lineStartsParagraphBreakingBlockForTesting(in: input, range: range) {
                        checksum += 1
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] paragraph-breaking full trim probe: \(formatMilliseconds(fullTrim)) ms " +
            "leading probe: \(formatMilliseconds(leadingProbe)) ms " +
            "speedup: \(formatRatio(fullTrim / max(leadingProbe, 0.0001)))x"
        )

        XCTAssertLessThan(
            leadingProbe,
            fullTrim,
            "Paragraph-breaking block detection should skip trailing trim for plain ASCII continuation lines."
        )
    }

    func testOptimization55_ParagraphBreakingBlockClassifiesCandidateFromFirstASCIIByte() {
        let representativeInputs = [
            "",
            "plain paragraph",
            "plain paragraph   ",
            "  # heading",
            "#\t",
            "\t#\t",
            "###not heading",
            "### heading   ",
            "> quote",
            "```swift",
            "``not fence",
            "~~~   ",
            "---",
            "---\r",
            "- list",
            "- ",
            "-not list",
            "*** trailing",
            "___",
            "_not rule",
            "+ list",
            "1. ordered",
            "1.not ordered",
            "1. ",
            "\u{0661}. unicode digit",
            "\u{00A0}# unicode whitespace heading",
            "# café",
            "---\u{00A0}"
        ]

        for input in representativeInputs {
            let range = input.startIndex..<input.endIndex
            let optimized = BlockParser.lineStartsParagraphBreakingBlockForTesting(in: input, range: range)
            XCTAssertEqual(
                optimized,
                BlockParser.lineStartsParagraphBreakingBlockByFullTrimForTesting(in: input, range: range),
                "ASCII-start paragraph-breaking probe must preserve full-trim semantics for \(input)"
            )
            XCTAssertEqual(
                optimized,
                BlockParser.lineStartsParagraphBreakingBlockByCharacterScanningForTesting(in: input, range: range),
                "ASCII-start paragraph-breaking probe must preserve character-scan semantics for \(input)"
            )
        }

        let inputs = makeParagraphBreakingBlockCandidateProbeBenchmark(count: 180_000)

        let fullTrim = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let range = input.startIndex..<input.endIndex
                    if BlockParser.lineStartsParagraphBreakingBlockByFullTrimForTesting(in: input, range: range) {
                        checksum += 1
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let asciiStart = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let range = input.startIndex..<input.endIndex
                    if BlockParser.lineStartsParagraphBreakingBlockForTesting(in: input, range: range) {
                        checksum += 1
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] paragraph-breaking candidate full trim: \(formatMilliseconds(fullTrim)) ms " +
            "ascii-start probe: \(formatMilliseconds(asciiStart)) ms " +
            "speedup: \(formatRatio(fullTrim / max(asciiStart, 0.0001)))x"
        )

        XCTAssertLessThan(
            asciiStart,
            fullTrim,
            "Paragraph-breaking block detection should classify ASCII candidates without re-trimming the whole line."
        )
    }

    func testOptimization36_UTF8WhitespaceTrimmedRangeAvoidsCharacterIteration() {
        let representativeInputs = [
            "",
            "   ",
            "\t\t",
            "  value  ",
            "\tvalue\t",
            "value",
            "\u{00A0}value\u{00A0}",
            "\u{2003}value\u{2003}",
            "\nvalue\n",
            "\u{000B}value\u{000B}"
        ]

        for input in representativeInputs {
            let range = input.startIndex..<input.endIndex
            XCTAssertEqual(
                offsets(BlockParser.whitespaceTrimmedRangeForTesting(in: input, range: range), in: input),
                offsets(
                    BlockParser.whitespaceTrimmedRangeByCharacterScanningForTesting(in: input, range: range),
                    in: input
                ),
                "UTF-8 whitespace trim must preserve semantics for \(input)"
            )
        }

        let inputs = makeWhitespaceTrimmedRangeBenchmark(count: 120_000)

        let characterScan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let range = input.startIndex..<input.endIndex
                    let trimmed = BlockParser.whitespaceTrimmedRangeByCharacterScanningForTesting(
                        in: input,
                        range: range
                    )
                    checksum += input.distance(from: input.startIndex, to: trimmed.lowerBound)
                    checksum += input.distance(from: input.startIndex, to: trimmed.upperBound)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let utf8Scan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let range = input.startIndex..<input.endIndex
                    let trimmed = BlockParser.whitespaceTrimmedRangeForTesting(in: input, range: range)
                    checksum += input.distance(from: input.startIndex, to: trimmed.lowerBound)
                    checksum += input.distance(from: input.startIndex, to: trimmed.upperBound)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] whitespace trimmed range character scan: \(formatMilliseconds(characterScan)) ms " +
            "utf8 scan: \(formatMilliseconds(utf8Scan)) ms " +
            "speedup: \(formatRatio(characterScan / max(utf8Scan, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8Scan,
            characterScan,
            "Full whitespace range trimming should scan ASCII spaces and tabs with UTF-8 bytes."
        )
    }

    func testOptimization37_UTF8ParagraphBreakScanningAvoidsStateMutationLoop() {
        let representativeInputs = [
            "",
            "   ",
            "   \n",
            "plain paragraph",
            "   > quote",
            "    indented code",
            "```swift",
            "``not fence",
            "~~~",
            "# heading",
            "###not heading",
            "####### too many hashes",
            "---",
            "-- not rule",
            "- list item",
            "***",
            "___",
            "__ not rule",
            "\u{00A0}> unicode leading space",
            "é paragraph"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                isAtParagraphBreakForBenchmark(input, fastPath: true),
                isAtParagraphBreakForBenchmark(input, fastPath: false),
                "UTF-8 paragraph-break scan must preserve semantics for \(input)"
            )
        }

        let inputs = makeParagraphBreakScanningBenchmark(count: 160_000)

        let characterScan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    if isAtParagraphBreakForBenchmark(input, fastPath: false) {
                        checksum += 1
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let utf8Scan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    if isAtParagraphBreakForBenchmark(input, fastPath: true) {
                        checksum += 1
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] paragraph-break state loop: \(formatMilliseconds(characterScan)) ms " +
            "utf8 scan: \(formatMilliseconds(utf8Scan)) ms " +
            "speedup: \(formatRatio(characterScan / max(utf8Scan, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8Scan,
            characterScan,
            "Paragraph-break detection should scan ASCII block markers without mutating ParserState."
        )
    }

    func testOptimization38_UTF8SetextHeadingProbeAvoidsRepeatedLineScans() {
        let representativeInputs = [
            "Heading\n===",
            "Heading\n---\nnext",
            "Heading\n= =",
            "Heading\n -",
            "Heading\n---x",
            "Heading\n",
            "   \n---",
            "Unicode café\n---",
            "Heading\r\n---",
            "Heading\n---\r\n"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                shouldAttemptSetextHeadingForBenchmark(input, optimized: true),
                shouldAttemptSetextHeadingForBenchmark(input, optimized: false),
                "UTF-8 setext probe must preserve semantics for \(input)"
            )
        }

        let inputs = makeSetextHeadingProbeBenchmark(count: 160_000)

        let lineRanges = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    if shouldAttemptSetextHeadingForBenchmark(input, optimized: false) {
                        checksum += 1
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let utf8Scan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    if shouldAttemptSetextHeadingForBenchmark(input, optimized: true) {
                        checksum += 1
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] setext heading line-range probe: \(formatMilliseconds(lineRanges)) ms " +
            "utf8 scan: \(formatMilliseconds(utf8Scan)) ms " +
            "speedup: \(formatRatio(lineRanges / max(utf8Scan, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8Scan,
            lineRanges,
            "Setext-heading probing should scan current and underline lines once with UTF-8 bytes."
        )
    }

    func testOptimization39_UTF8TableProbeAvoidsRepeatedLineScans() {
        let representativeInputs = [
            "| A | B |\n| - | - |",
            "A | B\n--- | ---",
            "A B\n| - | - |",
            "| A | B |\n---",
            "| A | B |\n| x | y |",
            "| A |\n|-|",
            "| A |\r\n| - |",
            "Unicode café | value\n| - | - |",
            "| A | B |",
            "\n| - | - |"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                shouldAttemptTableForBenchmark(input, optimized: true),
                shouldAttemptTableForBenchmark(input, optimized: false),
                "UTF-8 table probe must preserve semantics for \(input)"
            )
        }

        let inputs = makeTableProbeBenchmark(count: 160_000)

        let lineRanges = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    if shouldAttemptTableForBenchmark(input, optimized: false) {
                        checksum += 1
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let utf8Scan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    if shouldAttemptTableForBenchmark(input, optimized: true) {
                        checksum += 1
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] table line-range probe: \(formatMilliseconds(lineRanges)) ms " +
            "utf8 scan: \(formatMilliseconds(utf8Scan)) ms " +
            "speedup: \(formatRatio(lineRanges / max(utf8Scan, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8Scan,
            lineRanges,
            "Table probing should scan header and separator lines once with UTF-8 bytes."
        )
    }

    func testOptimization40_TableStartProbeReuseAvoidsHeaderSeparatorRescan() {
        let representativeInputs = [
            "| A | B |\n| - | - |\n| 1 | 2 |",
            "A | B\n--- | ---\n1 | 2",
            "Name | Value\n| --- | ---: |\n| café | **bold** |",
            "| A |\n|-|",
            "| A | B |\n| x | y |",
            "| A |\r\n| - |",
            "plain paragraph\n| - | - |",
            "| A | B |"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                tableParseCanonicalForBenchmark(input, optimized: true),
                tableParseCanonicalForBenchmark(input, optimized: false),
                "Reused table start probe must preserve parse result and parser position for \(input)"
            )
        }

        let inputs = makeTableStartProbeReuseBenchmark(count: 80_000)

        let rescanned = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += tableParseChecksumForBenchmark(input, optimized: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let reused = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += tableParseChecksumForBenchmark(input, optimized: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] table start rescan parse: \(formatMilliseconds(rescanned)) ms " +
            "reused probe parse: \(formatMilliseconds(reused)) ms " +
            "speedup: \(formatRatio(rescanned / max(reused, 0.0001)))x"
        )

        XCTAssertLessThan(
            reused,
            rescanned,
            "Table parsing should reuse the start probe instead of rescanning header and separator lines."
        )
    }

    func testOptimization120_TableStartProbeReusesSeparatorAlignments() throws {
        let representativeInputs = [
            "| A | B | C |\n| --- | :---: | ---: |\n| 1 | 2 | 3 |",
            "A | B\n--- | ---:\n1 | 2",
            "| Name | Value |\n|\t---\t|\t---:\t|\n| key | value |",
            "| Name | Value |\n| café- | ---: |\n| key | value |",
            "| A | B |\n| x | y |",
            "| A |\r\n| - |",
            "plain paragraph\n| --- | --- |"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                tableSeparatorAlignmentParseCanonicalForBenchmark(input, reusedAlignments: true),
                tableSeparatorAlignmentParseCanonicalForBenchmark(input, reusedAlignments: false),
                "Reused table separator alignments must preserve parse result and parser position for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeTableSeparatorAlignmentReuseBenchmark(count: 90_000)

        let reparsed = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum &+= tableSeparatorAlignmentParseChecksumForBenchmark(
                        input,
                        reusedAlignments: false
                    )
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let reused = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum &+= tableSeparatorAlignmentParseChecksumForBenchmark(
                        input,
                        reusedAlignments: true
                    )
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] table separator alignment reparse: \(formatMilliseconds(reparsed)) ms " +
            "reused probe alignment: \(formatMilliseconds(reused)) ms " +
            "speedup: \(formatRatio(reparsed / max(reused, 0.0001)))x"
        )

        XCTAssertLessThan(
            reused,
            reparsed,
            "Table parsing should reuse separator alignments carried by the start probe."
        )
        #endif
    }

    func testOptimization41_SetextProbeReuseAvoidsHeadingUnderlineRescan() {
        let representativeInputs = [
            "Heading\n===",
            "Heading\n---\nnext",
            " Heading with spaces \n---   \nnext",
            "Unicode café\n---",
            "Heading\n= =",
            "Heading\n -",
            "Heading\n---x",
            "Heading\r\n---",
            "   \n---",
            "Single line"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                setextParseCanonicalForBenchmark(input, optimized: true),
                setextParseCanonicalForBenchmark(input, optimized: false),
                "Reused setext probe must preserve parse result and parser position for \(input)"
            )
        }

        let inputs = makeSetextProbeReuseBenchmark(count: 120_000)

        let rescanned = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += setextParseChecksumForBenchmark(input, optimized: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let reused = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += setextParseChecksumForBenchmark(input, optimized: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] setext heading rescan parse: \(formatMilliseconds(rescanned)) ms " +
            "reused probe parse: \(formatMilliseconds(reused)) ms " +
            "speedup: \(formatRatio(rescanned / max(reused, 0.0001)))x"
        )

        XCTAssertLessThan(
            reused,
            rescanned,
            "Setext heading parsing should reuse the probe instead of rescanning heading and underline lines."
        )
    }

    func testOptimization79_SetextProbeReusesScannedHeadingTrim() throws {
        let representativeInputs = [
            "Heading\n===",
            "Heading\n---\nnext",
            " Heading with spaces \n---   \nnext",
            "\tTabbed heading\t\n---",
            "Unicode café\n---",
            "\u{00A0}Unicode whitespace\u{00A0}\n---",
            "Heading **bold** with [link](https://example.com)\n---",
            "Heading\r\n---",
            "Heading\n---x",
            "Single line"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                setextProbeHeadingTrimCanonicalForBenchmark(input, optimized: true),
                setextProbeHeadingTrimCanonicalForBenchmark(input, optimized: false),
                "Scanned setext heading trim must preserve parse result and parser position for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeASCIISetextHeadingTrimBenchmark(count: 140_000)

        let rescanned = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += setextProbeHeadingTrimChecksumForBenchmark(input, optimized: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let scanned = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += setextProbeHeadingTrimChecksumForBenchmark(input, optimized: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] setext probe heading trim rescan: \(formatMilliseconds(rescanned)) ms " +
            "scanned trim: \(formatMilliseconds(scanned)) ms " +
            "speedup: \(formatRatio(rescanned / max(scanned, 0.0001)))x"
        )

        XCTAssertLessThan(
            scanned,
            rescanned,
            "Setext probes should reuse ASCII heading trim bounds gathered while scanning the heading line."
        )
        #endif
    }

    func testOptimization56_ASCIIATXHeadingParsingAvoidsCharacterCursorLoop() {
        let representativeInputs = [
            "# Heading",
            "### Heading ###",
            "###### Heading with **bold** and [link](https://example.com)",
            "####### not heading",
            "#",
            "#\nnext",
            "# café",
            "# Heading\r\nnext",
            "###not heading"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                atxHeadingParseCanonicalForBenchmark(input, optimized: true),
                atxHeadingParseCanonicalForBenchmark(input, optimized: false),
                "ASCII ATX heading fast path must preserve parse result and parser position for \(input)"
            )
        }

        let inputs = makeATXHeadingParseBenchmark(count: 120_000)

        let characterScan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += atxHeadingParseChecksumForBenchmark(input, optimized: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let utf8Scan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += atxHeadingParseChecksumForBenchmark(input, optimized: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] atx heading character parse: \(formatMilliseconds(characterScan)) ms " +
            "utf8 parse: \(formatMilliseconds(utf8Scan)) ms " +
            "speedup: \(formatRatio(characterScan / max(utf8Scan, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8Scan,
            characterScan,
            "ATX heading parsing should scan ASCII heading lines with UTF-8 indices."
        )
    }

    func testOptimization57_ASCIIFencedCodeParsingAvoidsCharacterCursorLoop() {
        let representativeInputs = [
            "```swift\nprint(\"hello\")\n```",
            "~~~text\nalpha\nbeta\n~~~\nnext",
            "```\nalpha\nbeta",
            "```",
            "``\nnot a fence",
            "```swift\nlet greeting = \"こんにちは\"\nprint(\"✅\")\n```",
            "```\n```\n",
            "```swift\nline one\nline two\n```\n"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                fencedCodeParseCanonicalForBenchmark(input, optimized: true),
                fencedCodeParseCanonicalForBenchmark(input, optimized: false),
                "ASCII fenced code fast path must preserve parse result and parser position for \(input)"
            )
        }

        let inputs = makeFencedCodeParseBenchmark(count: 80_000)

        let characterScan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += fencedCodeParseChecksumForBenchmark(input, optimized: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let utf8Scan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += fencedCodeParseChecksumForBenchmark(input, optimized: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] fenced code character parse: \(formatMilliseconds(characterScan)) ms " +
            "utf8 parse: \(formatMilliseconds(utf8Scan)) ms " +
            "speedup: \(formatRatio(characterScan / max(utf8Scan, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8Scan,
            characterScan,
            "Fenced code parsing should scan ASCII fence lines with UTF-8 indices."
        )
    }

    func testOptimization109_FencedCodeUTF8ScanCarriesStateCounts() throws {
        let representativeInputs = [
            "```swift\nprint(\"hello\")\n```",
            "````swift\n```nested literal\nlet value = 1\n````\nafter",
            "~~~text\nalpha\nbeta\n~~~\nnext",
            "```\nalpha\nbeta",
            "```\nalpha\n",
            "```",
            "``\nnot a fence",
            "```swift\nlet greeting = \"こんにちは\"\nprint(\"✅\")\n```",
            "```\n```\n",
            "```swift\nline one\nline two\n```\n"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                fencedCodeStateMoveCanonicalForBenchmark(input, countedMove: true),
                fencedCodeStateMoveCanonicalForBenchmark(input, countedMove: false),
                "Counted fenced-code state movement must preserve parse result and parser position for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeFencedCodeStateMoveBenchmark(count: 36_000)

        let rescanned = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += fencedCodeStateMoveChecksumForBenchmark(input, countedMove: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let counted = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += fencedCodeStateMoveChecksumForBenchmark(input, countedMove: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] fenced code utf8 state rescan: \(formatMilliseconds(rescanned)) ms " +
            "counted move: \(formatMilliseconds(counted)) ms " +
            "speedup: \(formatRatio(rescanned / max(counted, 0.0001)))x"
        )

        XCTAssertLessThan(
            counted,
            rescanned,
            "Fenced code parsing should carry state movement counts from the UTF-8 scan."
        )
        #endif
    }

    func testOptimization111_UnicodeFencedCodeParsingStaysOnUTF8Scan() throws {
        let representativeInputs = [
            "```swift\nlet greeting = \"こんにちは\"\nprint(\"✅\")\n```",
            "```café\nalpha\n```",
            "~~~text\ncafé résumé\nnaïve jalapeño\n~~~\nnext",
            "```\nalpha\ncafé",
            "```\nalpha café\n",
            "```\ncode\n``` cierre",
            "``\nnot a fence café"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                fencedCodeParseCanonicalForBenchmark(input, optimized: true),
                fencedCodeParseCanonicalForBenchmark(input, optimized: false),
                "Unicode fenced code UTF-8 scan must preserve parse result and parser position for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeUnicodeFencedCodeParseBenchmark(count: 48_000)

        let characterScan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += unicodeFencedCodeParseChecksumForBenchmark(input, optimized: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let utf8Scan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += unicodeFencedCodeParseChecksumForBenchmark(input, optimized: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] unicode fenced code character parse: \(formatMilliseconds(characterScan)) ms " +
            "utf8 parse: \(formatMilliseconds(utf8Scan)) ms " +
            "speedup: \(formatRatio(characterScan / max(utf8Scan, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8Scan,
            characterScan,
            "Unicode fenced code parsing should stay on the UTF-8 scanner instead of falling back to character scanning."
        )
        #endif
    }

    func testOptimization58_ASCIIHorizontalRuleParsingAvoidsCharacterCursorLoop() {
        let representativeInputs = [
            "---",
            " ---\nnext",
            "   ***   \nnext",
            "_ _ _",
            "--",
            "----x",
            "    ---",
            "---\r",
            "— — —",
            "***"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                horizontalRuleParseCanonicalForBenchmark(input, optimized: true),
                horizontalRuleParseCanonicalForBenchmark(input, optimized: false),
                "ASCII horizontal rule fast path must preserve parse result and parser position for \(input)"
            )
        }

        let inputs = makeHorizontalRuleParseBenchmark(count: 220_000)

        let characterScan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += horizontalRuleParseChecksumForBenchmark(input, optimized: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let utf8Scan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += horizontalRuleParseChecksumForBenchmark(input, optimized: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] horizontal rule character parse: \(formatMilliseconds(characterScan)) ms " +
            "utf8 parse: \(formatMilliseconds(utf8Scan)) ms " +
            "speedup: \(formatRatio(characterScan / max(utf8Scan, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8Scan,
            characterScan,
            "Horizontal rule parsing should scan ASCII rule lines with UTF-8 indices."
        )
    }

    func testOptimization130_HorizontalRuleUTF8ScanCarriesStateCounts() throws {
        let representativeInputs = [
            "---",
            " ---\nnext",
            "   ***   \nnext",
            "_ _ _",
            "- - - - -",
            "--",
            "----x",
            "    ---",
            "---\r",
            "***"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                horizontalRuleStateMoveCanonicalForBenchmark(input, countedStateMove: true),
                horizontalRuleStateMoveCanonicalForBenchmark(input, countedStateMove: false),
                "Counted horizontal-rule state move must preserve parse result and parser position for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeHorizontalRuleStateMoveBenchmark(count: 320_000)

        let rescanned = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += horizontalRuleStateMoveChecksumForBenchmark(input, countedStateMove: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let counted = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += horizontalRuleStateMoveChecksumForBenchmark(input, countedStateMove: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] horizontal rule utf8 state rescan: \(formatMilliseconds(rescanned)) ms " +
            "counted: \(formatMilliseconds(counted)) ms " +
            "speedup: \(formatRatio(rescanned / max(counted, 0.0001)))x"
        )

        XCTAssertLessThan(
            counted,
            rescanned,
            "Horizontal rule parsing should reuse state counts collected by its UTF-8 scan."
        )
        #endif
    }

    func testOptimization59_ASCIIIndentedCodeParsingAvoidsCharacterCursorLoop() {
        let representativeInputs = [
            "    let x = 1\n    print(x)",
            "    alpha\n        beta\n\n    gamma\nnext",
            "    ",
            "   not enough",
            "    café",
            "    line\r\n    next",
            "        deeply indented\n    back",
            "    alpha\n  paragraph"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                indentedCodeParseCanonicalForBenchmark(input, optimized: true),
                indentedCodeParseCanonicalForBenchmark(input, optimized: false),
                "ASCII indented code fast path must preserve parse result and parser position for \(input)"
            )
        }

        let inputs = makeIndentedCodeParseBenchmark(count: 90_000)

        let characterScan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += indentedCodeParseChecksumForBenchmark(input, optimized: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let utf8Scan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += indentedCodeParseChecksumForBenchmark(input, optimized: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] indented code character parse: \(formatMilliseconds(characterScan)) ms " +
            "utf8 parse: \(formatMilliseconds(utf8Scan)) ms " +
            "speedup: \(formatRatio(characterScan / max(utf8Scan, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8Scan,
            characterScan,
            "Indented code parsing should scan ASCII lines with UTF-8 indices."
        )
    }

    func testOptimization129_IndentedCodeUTF8ScanCarriesStateCounts() throws {
        let representativeInputs = [
            "    let x = 1\n    print(x)",
            "    alpha\n        beta\n\n    gamma\nnext",
            "    ",
            "   not enough",
            "    café",
            "    line\r\n    next",
            "        deeply indented\n    back",
            "    alpha\n  paragraph",
            "    first\n   \n    after blank",
            "    first\n     \n    spaces-after-four"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                indentedCodeStateMoveCanonicalForBenchmark(input, countedStateMove: true),
                indentedCodeStateMoveCanonicalForBenchmark(input, countedStateMove: false),
                "Counted indented-code state move must preserve parse result and parser position for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeIndentedCodeParseBenchmark(count: 110_000)

        let rescanned = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += indentedCodeStateMoveChecksumForBenchmark(input, countedStateMove: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let counted = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += indentedCodeStateMoveChecksumForBenchmark(input, countedStateMove: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] indented code utf8 state rescan: \(formatMilliseconds(rescanned)) ms " +
            "counted: \(formatMilliseconds(counted)) ms " +
            "speedup: \(formatRatio(rescanned / max(counted, 0.0001)))x"
        )

        XCTAssertLessThan(
            counted,
            rescanned,
            "Indented code parsing should reuse state counts collected by its UTF-8 scan."
        )
        #endif
    }

    func testOptimization60_NonASCIIInlineRangesSkipRepeatedASCIIEligibilityScan() {
        let representativeInputs = makeNonASCIIInlineRangeBenchmark(count: 12)

        for input in representativeInputs {
            XCTAssertEqual(
                parseNonASCIIInlineRangeForBenchmark(input, repeatFullScan: false),
                parseNonASCIIInlineRangeForBenchmark(input, repeatFullScan: true),
                "Range-backed non-ASCII inline parsing must preserve semantics."
            )
        }

        let inputs = makeNonASCIIInlineRangeBenchmark(count: 8_000)

        let repeatedFullScan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let inlines = parseNonASCIIInlineRangeForBenchmark(input, repeatFullScan: true)
                    checksum += inlineNodesBenchmarkChecksum(inlines)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let checkedRange = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let inlines = parseNonASCIIInlineRangeForBenchmark(input, repeatFullScan: false)
                    checksum += inlineNodesBenchmarkChecksum(inlines)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] non-ascii inline range repeated ascii scan: \(formatMilliseconds(repeatedFullScan)) ms " +
            "checked range: \(formatMilliseconds(checkedRange)) ms " +
            "speedup: \(formatRatio(repeatedFullScan / max(checkedRange, 0.0001)))x"
        )

        XCTAssertLessThan(
            checkedRange,
            repeatedFullScan,
            "Range-backed non-ASCII inline parsing should not repeat ASCII eligibility scans."
        )
    }

    func testOptimization61_ParserStateInitializationAvoidsEagerFragmentReserveScans() {
        let representativeInputs = makeParserStateInitializationBenchmark(count: 12)

        for input in representativeInputs {
            let lazy = parserStateInitializationChecksum(input, eagerFragmentReserve: false)
            let eager = parserStateInitializationChecksum(input, eagerFragmentReserve: true)
            XCTAssertEqual(
                lazy.semantic,
                eager.semantic,
                "Lazy fragment-buffer allocation must preserve parser state initialization semantics."
            )
        }

        let inputs = makeParserStateInitializationBenchmark(count: 20_000)

        let eagerReserve = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let result = parserStateInitializationChecksum(input, eagerFragmentReserve: true)
                    checksum += result.semantic + result.reserveWork
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let lazyReserve = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let result = parserStateInitializationChecksum(input, eagerFragmentReserve: false)
                    checksum += result.semantic + result.reserveWork
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] parser state eager fragment reserve: \(formatMilliseconds(eagerReserve)) ms " +
            "lazy reserve: \(formatMilliseconds(lazyReserve)) ms " +
            "speedup: \(formatRatio(eagerReserve / max(lazyReserve, 0.0001)))x"
        )

        XCTAssertLessThan(
            lazyReserve,
            eagerReserve,
            "ParserState initialization should avoid eager fragment-buffer reserve scans."
        )
    }

    func testOptimization62_NonASCIIActiveInlineMarkerScanningUsesUTF8Bytes() {
        let representativeInputs: [(String, MarkdownConfiguration)] = [
            ("Plain café text with no markers", .default),
            ("Unicode 世界 text before **bold**", .default),
            ("Emoji 😀 text before [link](https://example.com)", .default),
            ("Mention @octocat with café", .github),
            ("Issue #42 with résumé", .github),
            ("Emoji shortcode :tada: with 世界", .github),
            ("Repository apple/swift with café", .github),
            ("Autolink https://example.com after café", .github),
            ("Commit deadbeef with résumé", .github)
        ]

        for (input, configuration) in representativeInputs {
            let state = ParserState(text: input)
            XCTAssertEqual(
                InlineParser.containsActiveInlineMarkerForTesting(state, configuration: configuration),
                InlineParser.containsActiveInlineMarkerByCharacterScanningForTesting(state, configuration: configuration),
                "UTF-8 active inline marker scanning must match Character scanning for \(input)"
            )
        }

        let inputs = makeNonASCIIActiveInlineMarkerBenchmark(count: 40_000)

        let characterScan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += activeInlineMarkerScanChecksumForBenchmark(input, optimized: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let utf8Scan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += activeInlineMarkerScanChecksumForBenchmark(input, optimized: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] non-ascii active inline marker character scan: \(formatMilliseconds(characterScan)) ms " +
            "utf8 scan: \(formatMilliseconds(utf8Scan)) ms " +
            "speedup: \(formatRatio(characterScan / max(utf8Scan, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8Scan,
            characterScan,
            "Non-ASCII active inline marker scanning should use UTF-8 bytes."
        )
    }

    func testOptimization49_UTF8TableRowPipeScanAvoidsSubstringContains() {
        let representativeRows = [
            "| cell | value |",
            "cell | value",
            "no table row",
            "Unicode café | value",
            "escaped \\| still contains byte",
            "",
            "emoji 😀 no pipe",
            "tabs\t|\tvalue"
        ]

        for row in representativeRows {
            let range = row.startIndex..<row.endIndex
            XCTAssertEqual(
                BlockParser.tableRowContainsPipeForTesting(in: row, range: range),
                BlockParser.tableRowContainsPipeBySubstringContainsForTesting(in: row, range: range),
                "UTF-8 table row pipe scan must preserve substring contains semantics for \(row)"
            )
        }

        let representativeTables = [
            "| A | B |\n| - | - |\n| 1 | 2 |\nnot a row",
            "A | B\n--- | ---\nUnicode café | **bold**\nplain continuation",
            "| A |\n|-|",
            "| A | B |\n| - | - |\nemoji 😀 | value\nnext paragraph"
        ]

        for input in representativeTables {
            XCTAssertEqual(
                tableRowPipeParseCanonicalForBenchmark(input, optimized: true),
                tableRowPipeParseCanonicalForBenchmark(input, optimized: false),
                "UTF-8 table row pipe scan must preserve table parse result and parser position for \(input)"
            )
        }

        let rows = makeTableRowPipeScanBenchmark(count: 240_000)

        let substringContains = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for row in rows {
                    let range = row.startIndex..<row.endIndex
                    if BlockParser.tableRowContainsPipeBySubstringContainsForTesting(in: row, range: range) {
                        checksum += 1
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let utf8Scan = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for row in rows {
                    let range = row.startIndex..<row.endIndex
                    if BlockParser.tableRowContainsPipeForTesting(in: row, range: range) {
                        checksum += 1
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] table row substring pipe scan: \(formatMilliseconds(substringContains)) ms " +
            "utf8 scan: \(formatMilliseconds(utf8Scan)) ms " +
            "speedup: \(formatRatio(substringContains / max(utf8Scan, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8Scan,
            substringContains,
            "Table row continuation detection should scan for pipes with UTF-8 bytes."
        )
    }

    func testOptimization80_TableRowLineScanCombinesLineEndAndPipeDetection() throws {
        let representativeTables = [
            "| A | B |\n| - | - |\n| 1 | 2 |\nnot a row",
            "A | B\n--- | ---\nrow | cell\nplain continuation",
            "| A |\n|-|",
            "| A | B |\n| - | - |\nrow without pipe",
            "| A | B |\n| - | - |\nemoji 😀 | value\nnext paragraph",
            "| A | B |\n| - | - |\ncafe\u{301} | value\nplain",
            "| A | B |\n| - | - |\ntabs\t|\tvalue\nplain"
        ]

        for input in representativeTables {
            XCTAssertEqual(
                tableRowLineScanParseCanonicalForBenchmark(input, optimized: true),
                tableRowLineScanParseCanonicalForBenchmark(input, optimized: false),
                "Combined table row line scan must preserve table parse result and parser position for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeTableRowLineScanBenchmark(count: 90_000)

        let separate = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += tableRowLineScanParseChecksumForBenchmark(input, optimized: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let combined = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += tableRowLineScanParseChecksumForBenchmark(input, optimized: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] table row separate line/pipe scans: \(formatMilliseconds(separate)) ms " +
            "combined scan: \(formatMilliseconds(combined)) ms " +
            "speedup: \(formatRatio(separate / max(combined, 0.0001)))x"
        )

        XCTAssertLessThan(
            combined,
            separate,
            "Table row collection should detect line end and pipe presence in one ASCII scan."
        )
        #endif
    }

    func testOptimization131_TableRowScanDefersFailedRowStateMove() throws {
        let representativeTables = [
            "| A | B |\n| - | - |\nplain paragraph",
            "A | B\n--- | ---\nrow | cell\nplain continuation",
            "| Name | Value |\n| --- | ---: |\n| row | code |\nemoji 😀 paragraph",
            "| A | B |\n| - | - |\ncafe\u{301} paragraph",
            "| A | B |\n| - | - |\ntabs\twithout\tpipe",
            "| A | B |\n| - | - |\n",
            "| A | B |\n| - | - |",
            "| A | B |\n| - | - |\n| 1 | 2 |\n| 3 | 4 |\nplain"
        ]

        for input in representativeTables {
            XCTAssertEqual(
                tableFailedRowStateMoveCanonicalForBenchmark(input, deferred: true),
                tableFailedRowStateMoveCanonicalForBenchmark(input, deferred: false),
                "Deferred failed table row state movement must preserve parse result and parser position for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeTableFailedRowStateMoveBenchmark(count: 120_000)

        let eagerMove = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += tableFailedRowStateMoveChecksumForBenchmark(input, deferred: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let deferredMove = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += tableFailedRowStateMoveChecksumForBenchmark(input, deferred: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] table failed row eager state move: \(formatMilliseconds(eagerMove)) ms " +
            "deferred: \(formatMilliseconds(deferredMove)) ms " +
            "speedup: \(formatRatio(eagerMove / max(deferredMove, 0.0001)))x"
        )

        XCTAssertLessThan(
            deferredMove,
            eagerMove,
            "Table row collection should not advance and rewind parser state for the first non-table row."
        )
        #endif
    }

    func testOptimization81_InlineFootnoteMatcherUsesSingleByteLoop() throws {
        let representativeInputs = [
            "Plain text with no inline footnotes.",
            "Plain carets ^ and ^^ without bracket markers.",
            "Inline note ^[footnote here] end.",
            "First ^[one] and second ^[two].",
            "Unicode inline ^[cafe\u{301} and 😀] note.",
            "Empty inline note ^[] stays literal.",
            "Unclosed inline note ^[literal text",
            "Broken then valid ^[unclosed and ^[valid] end"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                inlineFootnoteMatcherParseCanonicalForBenchmark(input, singlePass: true),
                inlineFootnoteMatcherParseCanonicalForBenchmark(input, singlePass: false),
                "Single-pass inline footnote matcher must preserve preprocessing semantics for \(input)"
            )
            XCTAssertEqual(
                MarkdownParser.inlineFootnoteMatchCountForTesting(input, singlePass: true),
                MarkdownParser.inlineFootnoteMatchCountForTesting(input, singlePass: false),
                "Single-pass inline footnote matcher must find the same match count for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeInlineFootnoteMatcherBenchmark(count: 120_000)

        let caretSearch = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += inlineFootnoteMatcherMatchChecksumForBenchmark(input, singlePass: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let singlePass = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += inlineFootnoteMatcherMatchChecksumForBenchmark(input, singlePass: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] inline footnote caret-search matcher: \(formatMilliseconds(caretSearch)) ms " +
            "single byte loop: \(formatMilliseconds(singlePass)) ms " +
            "speedup: \(formatRatio(caretSearch / max(singlePass, 0.0001)))x"
        )

        XCTAssertLessThan(
            singlePass,
            caretSearch,
            "Inline footnote matching should scan once with a byte loop instead of repeated caret searches."
        )
        #endif
    }

    func testOptimization82_InlineLiteralRunAppendReusesScannedByteCount() throws {
        let representativeInputs: [(String, MarkdownConfiguration)] = [
            (
                "Plain words before **bold** and after",
                .default
            ),
            (
                "Prefix before [link](https://example.com) suffix",
                .default
            ),
            (
                "owner/repo appears after prefix in github mode",
                .github
            ),
            (
                "https://example.com appears after prefix in github mode",
                .github
            ),
            (
                "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef appears after prefix",
                .github
            ),
            (
                "Line one before soft break\nline two with **bold**",
                .default
            ),
            (
                "Unicode café before **bold**",
                .default
            )
        ]

        for (input, configuration) in representativeInputs {
            XCTAssertEqual(
                parseInlineForLiteralRunByteCountBenchmark(
                    input,
                    knownByteCount: true,
                    configuration: configuration
                ),
                parseInlineForLiteralRunByteCountBenchmark(
                    input,
                    knownByteCount: false,
                    configuration: configuration
                ),
                "Known literal-run byte counts must preserve inline semantics for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeInlineLiteralRunByteCountBenchmark(count: 4_000)

        let recounting = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let inlines = parseInlineForLiteralRunByteCountBenchmark(
                        input,
                        knownByteCount: false,
                        configuration: .default
                    )
                    checksum += inlineNodesBenchmarkChecksum(inlines)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let counted = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let inlines = parseInlineForLiteralRunByteCountBenchmark(
                        input,
                        knownByteCount: true,
                        configuration: .default
                    )
                    checksum += inlineNodesBenchmarkChecksum(inlines)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] inline literal run append recount bytes: \(formatMilliseconds(recounting)) ms " +
            "known byte count: \(formatMilliseconds(counted)) ms " +
            "speedup: \(formatRatio(recounting / max(counted, 0.0001)))x"
        )

        XCTAssertLessThan(
            counted,
            recounting,
            "Inline literal runs should reuse the byte count already collected by the ASCII scanner."
        )
        #endif
    }

    func testOptimization83_AdvanceLineScansASCIIWithUTF8() throws {
        let representativeInputs = [
            "",
            "\nblank after",
            "plain line\nnext",
            "plain line without trailing newline",
            "   \t   \nnext",
            "line\r\nnext",
            "carriage\ronly\nnext",
            "tabs\tand spaces\n",
            "unicode café\nnext",
            "emoji \u{1F680}\nnext",
            "unterminated unicode café",
            "combining cafe\u{301} without newline"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parserStateAdvanceLineSignature(input, optimized: true),
                parserStateAdvanceLineSignature(input, optimized: false),
                "ParserState.advanceLine must preserve cursor semantics for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let input = makeParserStateAdvanceLineBenchmark(lineCount: 140_000)

        let character = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(parserStateAdvanceLineChecksum(input, optimized: false), 0)
            }
        })

        let utf8 = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(parserStateAdvanceLineChecksum(input, optimized: true), 0)
            }
        })

        print(
            "[BENCH] parser state advanceLine character: \(formatMilliseconds(character)) ms " +
            "utf8: \(formatMilliseconds(utf8)) ms " +
            "speedup: \(formatRatio(character / max(utf8, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8,
            character,
            "ParserState.advanceLine should find ASCII line endings with UTF-8 bytes instead of Character reads."
        )
        #endif
    }

    func testOptimization128_AdvanceToLineEndCarriesColumnCount() throws {
        let representativeInputs: [(input: String, startOffset: Int)] = [
            ("", 0),
            ("\nblank after", 0),
            ("plain line\nnext", 0),
            ("plain line without trailing newline", 0),
            ("   \t   \nnext", 0),
            ("line\r\nnext", 0),
            ("carriage\ronly\nnext", 0),
            ("tabs\tand spaces\n", 0),
            ("prefix plain line\nnext", 7),
            ("prefix tabs\tand spaces\nnext", 7),
            ("unicode café\nnext", 0),
            ("emoji \u{1F680}\nnext", 0),
            ("prefix unicode café\nnext", 7),
            ("unterminated unicode café", 0),
            ("combining cafe\u{301} without newline", 0)
        ]

        for (input, startOffset) in representativeInputs {
            XCTAssertEqual(
                parserStateAdvanceToLineEndSignature(input, startOffset: startOffset, optimized: true),
                parserStateAdvanceToLineEndSignature(input, startOffset: startOffset, optimized: false),
                "ParserState.advanceToLineEnd must preserve cursor semantics for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let input = makeParserStateAdvanceToLineEndBenchmark(lineCount: 220_000)

        let distance = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(parserStateAdvanceToLineEndChecksum(input, optimized: false), 0)
            }
        })

        let counted = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(parserStateAdvanceToLineEndChecksum(input, optimized: true), 0)
            }
        })

        print(
            "[BENCH] parser state advanceToLineEnd distance: \(formatMilliseconds(distance)) ms " +
            "counted: \(formatMilliseconds(counted)) ms " +
            "speedup: \(formatRatio(distance / max(counted, 0.0001)))x"
        )

        XCTAssertLessThan(
            counted,
            distance,
            "ParserState.advanceToLineEnd should reuse the scan's column count instead of calling UTF-8 distance."
        )
        #endif
    }

    func testOptimization121_ForwardMoveUsesSingleUTF8AccountingPass() throws {
        let representativeInputs = [
            ("plain ascii line", 16),
            ("prefix before target suffix", 20),
            ("line one\nline two\nline three", 23),
            ("line one\r\nline two\r\nline three", 25),
            ("tabs\tand spaces before target", 18),
            ("unicode café falls back safely", 20),
            ("emoji \u{1F680} falls back safely", 12)
        ]

        for (input, offset) in representativeInputs {
            XCTAssertEqual(
                parserStateForwardMoveSignature(input, targetOffset: offset, optimized: true),
                parserStateForwardMoveSignature(input, targetOffset: offset, optimized: false),
                "ParserState.move(to:) must preserve forward cursor semantics for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeParserStateForwardMoveBenchmark(count: 240_000)

        let advancing = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(parserStateForwardMoveChecksum(inputs, optimized: false), 0)
            }
        })

        let moved = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(parserStateForwardMoveChecksum(inputs, optimized: true), 0)
            }
        })

        print(
            "[BENCH] parser state forward move advance loop: \(formatMilliseconds(advancing)) ms " +
            "single utf8 accounting: \(formatMilliseconds(moved)) ms " +
            "speedup: \(formatRatio(advancing / max(moved, 0.0001)))x"
        )

        XCTAssertLessThan(
            moved,
            advancing,
            "ParserState.move(to:) should account ASCII forward movement in one local UTF-8 pass."
        )
        #endif
    }

    func testOptimization122_NestedEscapedBracketedLinkTextUsesUTF8BalancedScan() throws {
        let representativeInputs = [
            "[outer [inner]](http://example.com)",
            "[deep [one [two]] label](https://example.com/path)",
            #"[a \[b\]](http://example.com)"#,
            #"[escaped \\ backslash and \] close](https://example.com)"#,
            "[multi\nline [inner]](https://example.com)",
            "[café [世界]](https://example.com/path)",
            "[emoji ✅ [inner]](https://example.com/path)",
            "[outer [inner]][ref]",
            "[unterminated [inner](https://example.com)"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseLinkBalancedBracketedTextScanCanonicalForBenchmark(input, optimized: true),
                parseLinkBalancedBracketedTextScanCanonicalForBenchmark(input, optimized: false),
                "UTF-8 balanced bracketed link-text scan must preserve parse result and parser position for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let links = makeNestedEscapedBracketedLinksForParsingBenchmark(linkCount: 90_000)

        let character = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for link in links {
                    checksum &+= parseLinkBalancedBracketedTextScanChecksumForBenchmark(link, optimized: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let utf8 = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for link in links {
                    checksum &+= parseLinkBalancedBracketedTextScanChecksumForBenchmark(link, optimized: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] nested escaped bracketed link text character scan: \(formatMilliseconds(character)) ms " +
            "utf8 balanced scan: \(formatMilliseconds(utf8)) ms " +
            "speedup: \(formatRatio(character / max(utf8, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8,
            character,
            "Nested or escaped bracketed link text should balance brackets with UTF-8 bytes before falling back."
        )
        #endif
    }

    func testOptimization123_BalancedLinkResourceDestinationUsesUTF8BackslashScan() throws {
        let representativeResources = [
            #"https://example.com/a(b)c)"#,
            #"https://example.com/a(b(c)d)e)"#,
            #"https://example.com/a\)b)"#,
            #"   https://example.com/a(b)c   )"#,
            #"https://example.com/a(b)c "Title")"#,
            #"https://example.com/a(b)c 'Title')"#,
            #"https://example.com/a(b)c (Title))"#,
            #"https://example.com/café(a)b)"#,
            #"https://example.com/unterminated(a"#
        ]

        for resource in representativeResources {
            let character = parseBalancedInlineLinkResourceDestinationScanForBenchmark(resource, optimized: false)
            let utf8 = parseBalancedInlineLinkResourceDestinationScanForBenchmark(resource, optimized: true)
            switch (character, utf8) {
            case let (character?, utf8?):
                assertEqualInlineLinkResource(utf8, character, source: resource)
            case (nil, nil):
                continue
            default:
                XCTFail("UTF-8 destination backslash scan must preserve parse result for \(resource)")
            }
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let resources = makeBalancedLinkResourcesForDestinationBackslashBenchmark(resourceCount: 72_000)

        let character = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for resource in resources {
                    if let parsed = parseBalancedInlineLinkResourceDestinationScanForBenchmark(
                        resource,
                        optimized: false
                    ) {
                        checksum &+= inlineLinkResourceBenchmarkChecksum(parsed, in: resource)
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let utf8 = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for resource in resources {
                    if let parsed = parseBalancedInlineLinkResourceDestinationScanForBenchmark(
                        resource,
                        optimized: true
                    ) {
                        checksum &+= inlineLinkResourceBenchmarkChecksum(parsed, in: resource)
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] balanced link resource destination character backslash scan: \(formatMilliseconds(character)) ms " +
            "utf8 backslash scan: \(formatMilliseconds(utf8)) ms " +
            "speedup: \(formatRatio(character / max(utf8, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8,
            character,
            "Balanced link resources should probe destination escapes with UTF-8 bytes."
        )
        #endif
    }

    func testOptimization124_BalancedLinkResourceMetadataUsesUTF8Scan() throws {
        let representativeResources = [
            #"https://example.com/a(b)c)"#,
            #"https://example.com/a(b)c "Title")"#,
            #"https://example.com/a(b)c 'Title')"#,
            #"https://example.com/a(b)c (Title))"#,
            #"   https://example.com/a(b)c   "Spaced title"   )"#,
            #"https://example.com/a(b)c "Title \"quoted\"")"#,
            #"https://example.com/a(b)c "Café 世界")"#,
            #"https://example.com/a(b)c trailing-text)"#,
            #"https://example.com/a(b)c "unterminated title)"#,
            #"https://example.com/unterminated(a"#
        ]

        for resource in representativeResources {
            let character = parseBalancedInlineLinkResourceMetadataScanForBenchmark(resource, optimized: false)
            let utf8 = parseBalancedInlineLinkResourceMetadataScanForBenchmark(resource, optimized: true)
            switch (character, utf8) {
            case let (character?, utf8?):
                assertEqualInlineLinkResource(utf8, character, source: resource)
            case (nil, nil):
                continue
            default:
                XCTFail("UTF-8 balanced resource metadata scan must preserve parse result for \(resource)")
            }
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let resources = makeBalancedLinkResourcesForMetadataScanBenchmark(resourceCount: 96_000)

        let character = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for resource in resources {
                    if let parsed = parseBalancedInlineLinkResourceMetadataScanForBenchmark(
                        resource,
                        optimized: false
                    ) {
                        checksum &+= inlineLinkResourceBenchmarkChecksum(parsed, in: resource)
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let utf8 = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for resource in resources {
                    if let parsed = parseBalancedInlineLinkResourceMetadataScanForBenchmark(
                        resource,
                        optimized: true
                    ) {
                        checksum &+= inlineLinkResourceBenchmarkChecksum(parsed, in: resource)
                    }
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] balanced link resource character metadata scan: \(formatMilliseconds(character)) ms " +
            "utf8 metadata scan: \(formatMilliseconds(utf8)) ms " +
            "speedup: \(formatRatio(character / max(utf8, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8,
            character,
            "Balanced link resources should parse destination/title metadata with UTF-8 bytes."
        )
        #endif
    }

    func testOptimization125_ExtensionTriggersKeepASCIITextRunFastPath() throws {
        let explicitTriggerConfiguration = MarkdownConfiguration.default.addingExtension(
            makeBadgeExtensionForASCIITextRunBenchmark(triggered: true)
        )
        let emptyTriggerConfiguration = MarkdownConfiguration.default.addingExtension(
            makeBadgeExtensionForASCIITextRunBenchmark(triggered: false)
        )
        let representativeInputs: [(String, MarkdownConfiguration)] = [
            ("hello ::vip:: user", explicitTriggerConfiguration),
            ("plain **bold** before ::vip:: and [link](https://example.com)", explicitTriggerConfiguration),
            ("time 10:30 keeps failed trigger probes literal", explicitTriggerConfiguration),
            ("show `::vip::` inside code", explicitTriggerConfiguration),
            ("empty-trigger extension ::vip:: stays conservative", emptyTriggerConfiguration)
        ]

        for (input, configuration) in representativeInputs {
            XCTAssertEqual(
                parseInlineForExtensionAwareASCIITextRunBenchmark(input, configuration: configuration, optimized: true),
                parseInlineForExtensionAwareASCIITextRunBenchmark(input, configuration: configuration, optimized: false),
                "Extension-aware ASCII text runs must preserve inline parsing for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeExtensionAwareASCIITextRunBenchmark(count: 24_000)

        let conservative = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let inlines = parseInlineForExtensionAwareASCIITextRunBenchmark(
                        input,
                        configuration: explicitTriggerConfiguration,
                        optimized: false
                    )
                    checksum &+= inlineNodesBenchmarkChecksum(inlines)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let extensionAware = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    let inlines = parseInlineForExtensionAwareASCIITextRunBenchmark(
                        input,
                        configuration: explicitTriggerConfiguration,
                        optimized: true
                    )
                    checksum &+= inlineNodesBenchmarkChecksum(inlines)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] extension inline conservative character loop: \(formatMilliseconds(conservative)) ms " +
            "extension-aware ascii runs: \(formatMilliseconds(extensionAware)) ms " +
            "speedup: \(formatRatio(conservative / max(extensionAware, 0.0001)))x"
        )

        XCTAssertLessThan(
            extensionAware,
            conservative,
            "Explicit-trigger extensions should keep ASCII literal-run scanning enabled."
        )
        #endif
    }

    func testOptimization84_EmptyLineSkipCombinesScanAndAdvance() throws {
        let representativeInputs = [
            "",
            "\nnext",
            "   \nnext",
            "\t\t\nnext",
            "      ",
            "plain\n",
            "  plain\n",
            "\r\nnext",
            " \r\nnext",
            " café\nnext"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parserStateAdvanceIfEmptyLineSignature(input, optimized: true),
                parserStateAdvanceIfEmptyLineSignature(input, optimized: false),
                "Combined empty-line skip must preserve cursor semantics for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeEmptyLineScanningBenchmark(count: 180_000)

        let separate = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(emptyLineSkipChecksum(inputs, optimized: false), 0)
            }
        })

        let combined = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(emptyLineSkipChecksum(inputs, optimized: true), 0)
            }
        })

        print(
            "[BENCH] empty-line skip separate scan+advance: \(formatMilliseconds(separate)) ms " +
            "combined: \(formatMilliseconds(combined)) ms " +
            "speedup: \(formatRatio(separate / max(combined, 0.0001)))x"
        )

        XCTAssertLessThan(
            combined,
            separate,
            "Empty-line skipping should classify and advance blank lines in one scan."
        )
        #endif
    }

    func testOptimization85_BlockDispatchScansLeadingSpacesAndMarkersWithUTF8() throws {
        let representativeInputs = [
            "# Heading\n",
            "   # Heading\n",
            "    indented code\n",
            "```swift\nlet value = 1\n```\n",
            "> quote\n",
            "- item\n",
            "1. item\n",
            "***\n",
            "plain paragraph\n",
            "  plain paragraph\n",
            "[^note]: footnote text\n",
            "٩. unicode digit list\n",
            "\tleading tab stays paragraph\n",
            "café paragraph\n"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseBlockStartDispatchSignatureForBenchmark(input, utf8Dispatch: true),
                parseBlockStartDispatchSignatureForBenchmark(input, utf8Dispatch: false),
                "UTF-8 block start dispatch must preserve parseBlock semantics for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeBlockStartDispatchBenchmark(count: 140_000)

        let character = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += parseBlockStartDispatchChecksum(input, utf8Dispatch: false)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        let utf8 = median((0..<5).map { _ in
            timed {
                var checksum = 0
                for input in inputs {
                    checksum += parseBlockStartDispatchChecksum(input, utf8Dispatch: true)
                }
                XCTAssertGreaterThan(checksum, 0)
            }
        })

        print(
            "[BENCH] block start dispatch character: \(formatMilliseconds(character)) ms " +
            "utf8: \(formatMilliseconds(utf8)) ms " +
            "speedup: \(formatRatio(character / max(utf8, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8,
            character,
            "Block dispatch should scan leading spaces and ASCII markers with UTF-8 bytes."
        )
        #endif
    }

    func testOptimization86_ContainerContentLineEndsUseUTF8Scan() throws {
        let representativeListInputs = [
            "plain list item\n  continuation line\n",
            "[x] completed task\n  continuation with **bold**\n",
            "[ ] pending task with [link](https://example.com)\n  more text\n",
            "nested start\n  - nested item\n",
            "unicode café\n  continuation\n",
            "crlf line\r\n  continuation\r\n"
        ]

        for input in representativeListInputs {
            XCTAssertEqual(
                parseListItemLineEndSignatureForBenchmark(input, utf8LineEndScan: true),
                parseListItemLineEndSignatureForBenchmark(input, utf8LineEndScan: false),
                "UTF-8 list item line-end scan must preserve semantics for \(input)"
            )
        }

        let representativeFootnotes = [
            "[^a]: plain footnote\n    continuation line\n",
            "[^task]: [x] task-like text\n    continuation with **bold**\n",
            "[^nested]: intro\n    - nested item\n",
            "[^unicode]: café\n    continuation\n",
            "[^crlf]: first\r\n    continuation\r\n"
        ]

        for input in representativeFootnotes {
            XCTAssertEqual(
                parseFootnoteLineEndSignatureForBenchmark(input, utf8LineEndScan: true),
                parseFootnoteLineEndSignatureForBenchmark(input, utf8LineEndScan: false),
                "UTF-8 footnote line-end scan must preserve semantics for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeContainerLineEndScanBenchmark(count: 80_000)

        let character = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(
                    containerLineEndScanChecksum(inputs, utf8LineEndScan: false),
                    0
                )
            }
        })

        let utf8 = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(
                    containerLineEndScanChecksum(inputs, utf8LineEndScan: true),
                    0
                )
            }
        })

        print(
            "[BENCH] container line-end character scan: \(formatMilliseconds(character)) ms " +
            "utf8: \(formatMilliseconds(utf8)) ms " +
            "speedup: \(formatRatio(character / max(utf8, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8,
            character,
            "Container content parsing should find ASCII line ends with UTF-8 bytes."
        )
        #endif
    }

    func testOptimization87_FailedBlockCandidatesRestoreFromMarks() throws {
        let representativeTables = [
            "A | B | C\n--- | ---\nparagraph after invalid table\n",
            "| A | B |\n| :---x | --- |\nparagraph after invalid alignment\n",
            "Name | Value\n--- | --- | ---\nparagraph after invalid separator\n"
        ]

        for input in representativeTables {
            XCTAssertEqual(
                parseTableCandidateRestoreSignatureForBenchmark(input, markRestore: true),
                parseTableCandidateRestoreSignatureForBenchmark(input, markRestore: false),
                "Table candidate restore must preserve semantics for \(input)"
            )
        }

        let representativeFootnotes = [
            "[^missing-colon] text\nnext line\n",
            "[^unterminated label\nnext line\n",
            "[^]: empty label\nnext line\n"
        ]

        for input in representativeFootnotes {
            XCTAssertEqual(
                parseFootnoteCandidateRestoreSignatureForBenchmark(input, markRestore: true),
                parseFootnoteCandidateRestoreSignatureForBenchmark(input, markRestore: false),
                "Footnote candidate restore must preserve semantics for \(input)"
            )
        }

        let representativeBlocks = representativeTables + representativeFootnotes + [
            "    indented code still parses\n",
            "Heading\n---x\nparagraph fallback\n",
            "plain paragraph after failed candidates\n"
        ]

        for input in representativeBlocks {
            XCTAssertEqual(
                parseBlockCandidateRestoreSignatureForBenchmark(input, markRestore: true),
                parseBlockCandidateRestoreSignatureForBenchmark(input, markRestore: false),
                "parseBlock candidate restore must preserve semantics for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeFailedBlockCandidateRestoreBenchmark(count: 120_000)

        let indexMove = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(
                    failedBlockCandidateRestoreChecksum(inputs, markRestore: false),
                    0
                )
            }
        })

        let markRestore = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(
                    failedBlockCandidateRestoreChecksum(inputs, markRestore: true),
                    0
                )
            }
        })

        print(
            "[BENCH] failed block candidate index restore: \(formatMilliseconds(indexMove)) ms " +
            "mark restore: \(formatMilliseconds(markRestore)) ms " +
            "speedup: \(formatRatio(indexMove / max(markRestore, 0.0001)))x"
        )

        XCTAssertLessThan(
            markRestore,
            indexMove,
            "Failed block candidates should restore from saved marks instead of rescanning position."
        )
        #endif
    }

    func testOptimization88_ParagraphContinuationBreakRestoresFromMark() throws {
        let representativeInputs = [
            "Paragraph before list\n- list item\n- second item\n",
            "Paragraph before ordered list\n42. ordered item\nnext line\n",
            "Paragraph before quote\n> quoted line\n",
            "Paragraph before heading\n## Heading\n",
            "Paragraph before fence\n```swift\nlet value = 1\n```\n",
            "Paragraph before thematic break\n***\n",
            "Paragraph line one\ncontinued words stay in paragraph\n- list starts after continuation\n"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseParagraphContinuationBreakRestoreSignatureForBenchmark(input, markRestore: true),
                parseParagraphContinuationBreakRestoreSignatureForBenchmark(input, markRestore: false),
                "Paragraph continuation break restore must preserve semantics for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeParagraphContinuationBreakRestoreBenchmark(count: 120_000)

        let indexMove = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(
                    paragraphContinuationBreakRestoreChecksum(inputs, markRestore: false),
                    0
                )
            }
        })

        let markRestore = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(
                    paragraphContinuationBreakRestoreChecksum(inputs, markRestore: true),
                    0
                )
            }
        })

        print(
            "[BENCH] paragraph continuation break index move: \(formatMilliseconds(indexMove)) ms " +
            "mark restore: \(formatMilliseconds(markRestore)) ms " +
            "speedup: \(formatRatio(indexMove / max(markRestore, 0.0001)))x"
        )

        XCTAssertLessThan(
            markRestore,
            indexMove,
            "Paragraph continuation breaks should restore from a saved mark instead of rescanning position."
        )
        #endif
    }

    func testOptimization89_HTMLTagAttributeScanAvoidsIgnoredStringCopy() throws {
        let representativeInputs = [
            "<br>",
            "</span>",
            "<span class=\"name\" data-id=\"123\">",
            "<a href=\"https://example.com?q=1\" title=\"A title\">",
            "<custom-tag data-json='{\"k\":1}'>",
            "<tag\nattr=\"value\">",
            "<missing attr",
            "<é attr=\"value\">"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseHTMLTagAttributeScanCanonicalForBenchmark(input, optimized: true),
                parseHTMLTagAttributeScanCanonicalForBenchmark(input, optimized: false),
                "HTML tag attribute scan must preserve semantics for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeHTMLTagAttributeScanBenchmark(count: 180_000)

        let copying = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(
                    htmlTagAttributeScanChecksumForBenchmark(inputs, optimized: false),
                    0
                )
            }
        })

        let rangeScan = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(
                    htmlTagAttributeScanChecksumForBenchmark(inputs, optimized: true),
                    0
                )
            }
        })

        print(
            "[BENCH] html tag copied attribute scan: \(formatMilliseconds(copying)) ms " +
            "range scan: \(formatMilliseconds(rangeScan)) ms " +
            "speedup: \(formatRatio(copying / max(rangeScan, 0.0001)))x"
        )

        XCTAssertLessThan(
            rangeScan,
            copying,
            "HTML tag parsing should avoid copying ignored attribute text."
        )
        #endif
    }

    func testOptimization101_HTMLTagNameScanAvoidsIgnoredStringCopy() throws {
        let representativeInputs = [
            "<br>",
            "</span>",
            "<span class=\"name\" data-id=\"123\">",
            "<a href=\"https://example.com?q=1\" title=\"A title\">",
            "<custom-tag data-json='{\"k\":1}'>",
            "<tag\nattr=\"value\">",
            "<missing attr",
            "<1invalid>",
            "<é attr=\"value\">"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseHTMLTagNameScanCanonicalForBenchmark(input, optimized: true),
                parseHTMLTagNameScanCanonicalForBenchmark(input, optimized: false),
                "HTML tag-name scan must preserve semantics for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeHTMLTagAttributeScanBenchmark(count: 220_000)

        let copying = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(
                    htmlTagNameScanChecksumForBenchmark(inputs, optimized: false),
                    0
                )
            }
        })

        let rangeScan = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(
                    htmlTagNameScanChecksumForBenchmark(inputs, optimized: true),
                    0
                )
            }
        })

        print(
            "[BENCH] html tag copied name scan: \(formatMilliseconds(copying)) ms " +
            "range scan: \(formatMilliseconds(rangeScan)) ms " +
            "speedup: \(formatRatio(copying / max(rangeScan, 0.0001)))x"
        )

        XCTAssertLessThan(
            rangeScan,
            copying,
            "HTML tag parsing should avoid copying the tag name when only emptiness is needed."
        )
        #endif
    }

    func testOptimization90_FootnoteDefinitionHeaderScansWithUTF8() throws {
        let representativeInputs = [
            "[^note]: plain footnote\n",
            "[^long-label-with-dashes-and-123]: plain footnote\n    continuation\n",
            "[^tight]:plain footnote without space\n",
            "[^unicode-café]: unicode label falls back\n",
            "[^missing-colon] text\nnext line\n",
            "[^unterminated label\nnext line\n",
            "[^]: empty label\nnext line\n"
        ]

        for input in representativeInputs {
            XCTAssertEqual(
                parseFootnoteHeaderScanSignatureForBenchmark(input, utf8HeaderScan: true),
                parseFootnoteHeaderScanSignatureForBenchmark(input, utf8HeaderScan: false),
                "UTF-8 footnote header scan must preserve semantics for \(input)"
            )
        }

        #if DEBUG
        throw XCTSkip("Timing benchmark; run in Release with ENABLE_TESTABILITY=YES")
        #else
        let inputs = makeFootnoteHeaderScanBenchmark(count: 70_000)

        let character = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(
                    footnoteHeaderScanChecksum(inputs, utf8HeaderScan: false),
                    0
                )
            }
        })

        let utf8 = median((0..<5).map { _ in
            timed {
                XCTAssertGreaterThan(
                    footnoteHeaderScanChecksum(inputs, utf8HeaderScan: true),
                    0
                )
            }
        })

        print(
            "[BENCH] footnote header character scan: \(formatMilliseconds(character)) ms " +
            "utf8 scan: \(formatMilliseconds(utf8)) ms " +
            "speedup: \(formatRatio(character / max(utf8, 0.0001)))x"
        )

        XCTAssertLessThan(
            utf8,
            character,
            "Footnote definition headers should scan ASCII labels with UTF-8 bytes."
        )
        #endif
    }

    // MARK: - Timing Helpers

    private func timed(_ block: () -> Void) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        block()
        return CFAbsoluteTimeGetCurrent() - start
    }

    private func median(_ values: [TimeInterval]) -> TimeInterval {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    private func formatMilliseconds(_ value: TimeInterval) -> String {
        String(format: "%.2f", value * 1000)
    }

    private func formatRatio(_ value: TimeInterval) -> String {
        String(format: "%.2f", value)
    }

    // MARK: - Item 71 Parser State Advance

    private func parserStateAdvanceSignature(_ input: String, optimized: Bool) -> String {
        var state = ParserState(text: input)
        state.enableASCIIFastPathIfPossible()

        while !state.isAtEnd {
            if optimized {
                state.advance()
            } else {
                state.advanceByCharacterForTesting()
            }
        }

        return "index:\(input.distance(from: input.startIndex, to: state.currentIndex))|" +
            "line:\(state.line)|column:\(state.column)"
    }

    private func makeParserStateAdvanceBenchmark(lineCount: Int) -> String {
        var input = ""
        input.reserveCapacity(lineCount * 72)

        for index in 0..<lineCount {
            input += "Line \(index) with stable ASCII words, numbers \(index % 97), and spaces.\n"
        }

        return input
    }

    private func parserStateAdvanceChecksum(_ input: String, optimized: Bool) -> Int {
        var state = ParserState(text: input)
        state.enableASCIIFastPathIfPossible()

        while !state.isAtEnd {
            if optimized {
                state.advance()
            } else {
                state.advanceByCharacterForTesting()
            }
        }

        return input.distance(from: input.startIndex, to: state.currentIndex) ^ state.line ^ state.column
    }

    private func parserStateAdvanceLineSignature(_ input: String, optimized: Bool) -> String {
        var state = ParserState(text: input)
        if optimized {
            state.advanceLine()
        } else {
            state.advanceLineByCharacterForTesting()
        }

        return "index:\(input.distance(from: input.startIndex, to: state.currentIndex))|" +
            "line:\(state.line)|column:\(state.column)"
    }

    private func makeParserStateAdvanceLineBenchmark(lineCount: Int) -> String {
        var input = ""
        input.reserveCapacity(lineCount * 76)

        for index in 0..<lineCount {
            input += "Line \(index) with stable ASCII words, numbers \(index % 97), tabs\t, and spaces.\n"
        }

        return input
    }

    private func parserStateAdvanceLineChecksum(_ input: String, optimized: Bool) -> Int {
        var state = ParserState(text: input)
        var checksum = 0

        while !state.isAtEnd {
            if optimized {
                state.advanceLine()
            } else {
                state.advanceLineByCharacterForTesting()
            }
            checksum &+= state.line &* 31 &+ state.column
        }

        return checksum
    }

    private func parserStateAdvanceToLineEndSignature(
        _ input: String,
        startOffset: Int,
        optimized: Bool
    ) -> String {
        let boundedOffset = min(max(0, startOffset), input.count)
        let start = input.index(input.startIndex, offsetBy: boundedOffset)
        var state = ParserState(text: input)
        state.move(to: start)

        if optimized {
            state.advanceToLineEnd()
        } else {
            state.advanceToLineEndByDistanceAccountingForTesting()
        }

        return "index:\(input.distance(from: input.startIndex, to: state.currentIndex))|" +
            "line:\(state.line)|column:\(state.column)"
    }

    private func makeParserStateAdvanceToLineEndBenchmark(lineCount: Int) -> String {
        var input = ""
        input.reserveCapacity(lineCount * 80)

        for index in 0..<lineCount {
            input += "Line \(index) with stable ASCII words, numbers \(index % 97), tabs\t, and spaces.\n"
        }

        return input
    }

    private func parserStateAdvanceToLineEndChecksum(_ input: String, optimized: Bool) -> Int {
        var state = ParserState(text: input)
        state.enableASCIIFastPathIfPossible()
        var checksum = 0

        while !state.isAtEnd {
            if optimized {
                state.advanceToLineEnd()
            } else {
                state.advanceToLineEndByDistanceAccountingForTesting()
            }
            checksum &+= state.line &* 31 &+ state.column

            if !state.isAtEnd {
                state.advance()
            }
        }

        return checksum
    }

    private func parserStateForwardMoveSignature(
        _ input: String,
        targetOffset: Int,
        optimized: Bool
    ) -> String {
        let boundedOffset = min(targetOffset, input.count)
        let target = input.index(input.startIndex, offsetBy: boundedOffset)
        var state = ParserState(text: input)
        state.enableASCIIFastPathIfPossible()

        if optimized {
            state.move(to: target)
        } else {
            state.advance(to: target)
        }

        return "index:\(input.distance(from: input.startIndex, to: state.currentIndex))|" +
            "line:\(state.line)|column:\(state.column)"
    }

    private func makeParserStateForwardMoveBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 5 {
            case 0:
                inputs.append("plain ascii move target \(index) with stable words and suffix")
            case 1:
                inputs.append("line one \(index)\nline two with more ASCII words\nline three target")
            case 2:
                inputs.append("tabs\tand spaces \(index)\tbefore target with trailing words")
            case 3:
                inputs.append("short \(index)")
            default:
                inputs.append("first \(index)\nsecond \(index)\nthird \(index)\nfourth \(index)")
            }
        }

        return inputs
    }

    private func parserStateForwardMoveChecksum(_ inputs: [String], optimized: Bool) -> Int {
        var checksum = 0

        for input in inputs {
            var state = ParserState(
                text: input,
                currentIndex: input.startIndex,
                endIndex: input.endIndex,
                asciiFastPath: true
            )

            if optimized {
                state.move(to: input.endIndex)
            } else {
                state.advance(to: input.endIndex)
            }

            checksum &+= input.utf8.count &+ state.line &* 31 &+ state.column
        }

        return checksum
    }

    // MARK: - Item 24 Parallel Chunk Splitter

    private func makeParallelChunkSplitterBenchmarkMarkdown(sectionCount: Int) -> String {
        var markdown = ""
        markdown.reserveCapacity(sectionCount * 180)

        for index in 0..<sectionCount {
            markdown +=
                """
                ## Section \(index)

                Paragraph \(index) with **bold**, [link](https://example.com/\(index)), and stable ASCII words.

                Another paragraph \(index) that can be split safely after the blank line.

                """
        }

        return markdown
    }

    private func copiedChunkChecksum(_ chunks: [ParallelChunkSplitter.CopiedChunk]) -> Int {
        chunks.reduce(0) { partial, chunk in
            partial ^ chunk.index ^ chunk.startOffset ^ chunk.text.utf8.count
        }
    }

    private func rangeChunkChecksum(
        _ chunks: [ParallelChunkSplitter.RangeChunk],
        in markdown: String
    ) -> Int {
        chunks.reduce(0) { partial, chunk in
            partial ^ chunk.index ^ chunk.startOffset ^ markdown.utf8.distance(
                from: chunk.range.lowerBound,
                to: chunk.range.upperBound
            )
        }
    }

    private func parallelParseChecksum(_ blocks: [MarkdownParser.BlockNode]) -> Int {
        blocks.reduce(blocks.count) { partial, block in
            (partial &* 31) ^ parallelBlockChecksum(block)
        }
    }

    private func parallelBlockChecksum(_ block: MarkdownParser.BlockNode) -> Int {
        switch block {
        case let .heading(level, children, id):
            return level ^ (id?.utf8.count ?? 0) ^ parallelInlineChecksum(children)
        case let .paragraph(children):
            return 3 ^ parallelInlineChecksum(children)
        case let .blockquote(children):
            return 5 ^ parallelParseChecksum(children)
        case let .codeBlock(language, content):
            return 7 ^ (language?.utf8.count ?? 0) ^ content.utf8.count
        case let .list(ordered, tight, items):
            return items.reduce(ordered ? 11 : 13) { partial, item in
                partial ^ (tight ? 17 : 19) ^ item.marker.utf8.count ^ parallelParseChecksum(item.content)
            }
        case let .taskList(items):
            return items.reduce(23) { partial, item in
                partial ^ (item.isChecked ? 29 : 31) ^ parallelInlineChecksum(item.content)
            }
        case let .table(header, rows):
            return rows.reduce(37 ^ parallelTableCellChecksum(header)) { partial, row in
                partial ^ parallelTableCellChecksum(row)
            }
        case .horizontalRule:
            return 41
        case let .html(content):
            return 43 ^ content.utf8.count
        case let .footnoteDefinition(label, children):
            return 47 ^ label.utf8.count ^ parallelParseChecksum(children)
        }
    }

    private func parallelTableCellChecksum(_ cells: [MarkdownParser.TableCell]) -> Int {
        cells.reduce(cells.count) { partial, cell in
            partial ^ parallelTableAlignmentChecksum(cell.alignment) ^ parallelInlineChecksum(cell.content)
        }
    }

    private func parallelTableAlignmentChecksum(_ alignment: MarkdownParser.TableAlignment) -> Int {
        switch alignment {
        case .left: return 137
        case .center: return 139
        case .right: return 149
        case .none: return 151
        }
    }

    private func parallelInlineChecksum(_ inlines: [MarkdownParser.InlineNode]) -> Int {
        inlines.reduce(inlines.count) { partial, inline in
            (partial &* 31) ^ parallelInlineNodeChecksum(inline)
        }
    }

    private func parallelInlineNodeChecksum(_ inline: MarkdownParser.InlineNode) -> Int {
        switch inline {
        case let .text(text):
            return text.utf8.count
        case let .emphasis(children):
            return 53 ^ parallelInlineChecksum(children)
        case let .strong(children):
            return 59 ^ parallelInlineChecksum(children)
        case let .strikethrough(children):
            return 61 ^ parallelInlineChecksum(children)
        case let .code(code):
            return 67 ^ code.utf8.count
        case let .link(url, title, children):
            return 71 ^ url.absoluteString.utf8.count ^ (title?.utf8.count ?? 0) ^ parallelInlineChecksum(children)
        case let .image(url, alt, title):
            return 73 ^ url.absoluteString.utf8.count ^ alt.utf8.count ^ (title?.utf8.count ?? 0)
        case let .autolink(url, _, originalText):
            return 79 ^ url.absoluteString.utf8.count ^ originalText.utf8.count
        case let .mention(username):
            return 83 ^ username.utf8.count
        case let .issueReference(number):
            return 89 ^ number
        case let .commitSHA(sha, short):
            return 97 ^ sha.utf8.count ^ short.utf8.count
        case let .repositoryReference(owner, repo):
            return 101 ^ owner.utf8.count ^ repo.utf8.count
        case let .pullRequestReference(owner, repo, number):
            return 103 ^ owner.utf8.count ^ repo.utf8.count ^ number
        case .lineBreak:
            return 107
        case .softBreak:
            return 109
        case let .html(html):
            return 113 ^ html.utf8.count
        case let .footnoteReference(label):
            return 127 ^ label.utf8.count
        case let .extensionInline(node):
            return 131 ^ node.namespace.utf8.count ^ node.name.utf8.count ^ node.literal.utf8.count
        }
    }

    private struct IndexedParallelBlocks {
        let index: Int
        let blocks: [MarkdownParser.BlockNode]
    }

    private func makeParallelResultOrderingBenchmark(count: Int) -> [IndexedParallelBlocks] {
        var results: [IndexedParallelBlocks] = []
        results.reserveCapacity(count)

        for index in 0..<count {
            let blocks: [MarkdownParser.BlockNode] = [
                .paragraph(children: [
                    .text("chunk \(index)"),
                    .strong(children: [.text("bold")])
                ])
            ]
            results.append(IndexedParallelBlocks(index: index, blocks: blocks))
        }

        return results
    }

    private func indexedParallelBlocksChecksum(_ result: IndexedParallelBlocks) -> Int {
        result.index ^ blockArrayBenchmarkChecksum(result.blocks)
    }

    private func blockArrayBenchmarkChecksum(_ blocks: [MarkdownParser.BlockNode]) -> Int {
        blocks.reduce(0) { $0 + blockBenchmarkChecksum($1) }
    }

    // MARK: - Item 1 Baseline

    private func consumeLinesBaselineRemoveFirst(_ chunk: String) -> Int {
        var pendingText = chunk
        var lines = 0
        while let lineEnd = pendingText.firstIndex(of: "\n") {
            _ = pendingText[..<lineEnd]
            pendingText.removeFirst(pendingText.distance(from: pendingText.startIndex, to: lineEnd) + 1)
            lines += 1
        }
        return lines
    }

    // MARK: - Item 2 Synthetic LRU Comparison

    private func simulateArrayLRUTouches(keys: [String], touches: Int) -> Int {
        var dict: [String: Int] = [:]
        var order: [String] = []
        order.reserveCapacity(keys.count)
        for (index, key) in keys.enumerated() {
            dict[key] = index
            order.append(key)
        }

        var checksum = 0
        for i in 0..<touches {
            let key = keys[i % keys.count]
            if let value = dict[key] {
                checksum ^= value
            }
            if let idx = order.firstIndex(of: key) {
                order.remove(at: idx)
                order.append(key)
            }
        }

        return checksum ^ order.count
    }

    private final class LinkedNode {
        let key: String
        weak var prev: LinkedNode?
        var next: LinkedNode?

        init(key: String) {
            self.key = key
        }
    }

    private func simulateLinkedLRUTouches(keys: [String], touches: Int) -> Int {
        var map: [String: (value: Int, node: LinkedNode)] = [:]
        var tail: LinkedNode?

        @inline(__always)
        func append(_ node: LinkedNode) {
            node.prev = tail
            node.next = nil
            if let tail = tail {
                tail.next = node
            }
            tail = node
        }

        @inline(__always)
        func detach(_ node: LinkedNode) {
            let prev = node.prev
            let next = node.next
            if let prev = prev {
                prev.next = next
            }
            if let next = next {
                next.prev = prev
            } else {
                tail = prev
            }
            node.prev = nil
            node.next = nil
        }

        @inline(__always)
        func touch(_ node: LinkedNode) {
            guard tail !== node else { return }
            detach(node)
            append(node)
        }

        for (index, key) in keys.enumerated() {
            let node = LinkedNode(key: key)
            map[key] = (index, node)
            append(node)
        }

        var checksum = 0
        for i in 0..<touches {
            let key = keys[i % keys.count]
            if let hit = map[key] {
                checksum ^= hit.value
                touch(hit.node)
            }
        }

        return checksum ^ map.count
    }

    // MARK: - Item 3 Synthetic Eviction Comparison

    private func simulateMinScanLRUEvictions(capacity: Int, operations: Int) -> Int {
        var values: [Int: Int] = [:]
        var lastAccess: [Int: Int] = [:]
        values.reserveCapacity(capacity)
        lastAccess.reserveCapacity(capacity)

        var clock = 0
        var checksum = 0

        for i in 0..<operations {
            let key = i
            if let v = values[key] {
                checksum ^= v
                clock += 1
                lastAccess[key] = clock
            } else {
                if values.count >= capacity,
                   let oldest = lastAccess.min(by: { $0.value < $1.value })?.key {
                    values.removeValue(forKey: oldest)
                    lastAccess.removeValue(forKey: oldest)
                }
                clock += 1
                values[key] = key
                lastAccess[key] = clock
                checksum ^= key
            }
        }

        return checksum ^ values.count
    }

    private final class IntNode {
        let key: Int
        let value: Int
        weak var prev: IntNode?
        var next: IntNode?

        init(key: Int, value: Int) {
            self.key = key
            self.value = value
        }
    }

    private func simulateLinkedLRUEvictions(capacity: Int, operations: Int) -> Int {
        var map: [Int: IntNode] = [:]
        var head: IntNode?
        var tail: IntNode?
        map.reserveCapacity(capacity)

        @inline(__always)
        func append(_ node: IntNode) {
            node.prev = tail
            node.next = nil
            if let tail = tail {
                tail.next = node
            } else {
                head = node
            }
            tail = node
        }

        @inline(__always)
        func detach(_ node: IntNode) {
            let prev = node.prev
            let next = node.next
            if let prev = prev {
                prev.next = next
            } else {
                head = next
            }
            if let next = next {
                next.prev = prev
            } else {
                tail = prev
            }
            node.prev = nil
            node.next = nil
        }

        @inline(__always)
        func touch(_ node: IntNode) {
            guard tail !== node else { return }
            detach(node)
            append(node)
        }

        var checksum = 0
        for key in 0..<operations {
            if let node = map[key] {
                checksum ^= node.value
                touch(node)
            } else {
                if map.count >= capacity, let oldest = head {
                    detach(oldest)
                    map.removeValue(forKey: oldest.key)
                }
                let node = IntNode(key: key, value: key)
                map[key] = node
                append(node)
                checksum ^= key
            }
        }

        return checksum ^ map.count
    }

    // MARK: - Item 5 Guarded Preprocessing Comparison

    private func unguardedInlineFootnoteScanCount(_ text: String, regex: NSRegularExpression) -> Int {
        regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)).count
    }

    private func guardedInlineFootnoteScanCount(_ text: String, regex: NSRegularExpression) -> Int {
        guard text.contains("^[") else { return 0 }
        return regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)).count
    }

    private func unguardedEmojiPreprocess(_ text: String) -> String {
        GitHubEmojis.processEmojiShortcodes(text)
    }

    private func guardedEmojiPreprocess(_ text: String) -> String {
        guard text.contains(":") else { return text }
        return GitHubEmojis.processEmojiShortcodes(text)
    }

    private func makeInlineFootnoteMatcherBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 8 {
            case 0:
                inputs.append("Plain paragraph \(index) with no caret markers and enough ASCII text for scanning.")
            case 1:
                inputs.append("Caret-heavy \(index) ^ value ^ power ^^ escaped-looking \\^ text without inline notes.")
            case 2:
                inputs.append("Inline note \(index) ^[footnote \(index) with **bold** and [link](https://example.com)] end.")
            case 3:
                inputs.append("Two notes \(index) ^[first \(index)] middle ^[second \(index)] done.")
            case 4:
                inputs.append("Malformed \(index) ^[unclosed inline note and later ^ marker without close")
            case 5:
                inputs.append("Empty \(index) ^[] then valid ^[filled \(index)]")
            case 6:
                inputs.append("Unicode \(index) ^[cafe\u{301} and 😀 value \(index)] after text.")
            default:
                inputs.append("Bracket noise \(index) ^ [spaced] and ^(paren) before ^[valid \(index)].")
            }
        }

        return inputs
    }

    private func makeInlineFootnoteSourceASCIIBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 8 {
            case 0:
                inputs.append("Plain ASCII paragraph \(index) with no inline footnote markers and stable words.")
            case 1:
                inputs.append("Caret noise \(index) with ^ markers, ^^ doubles, and spaced ^ [brackets].")
            case 2:
                inputs.append("Inline note \(index) ^[footnote \(index) with **bold** and [link](https://example.com)].")
            case 3:
                inputs.append("Two notes \(index) ^[first \(index)] middle text ^[second \(index)] ending.")
            case 4:
                inputs.append("Malformed \(index) ^[unclosed note followed by ASCII content and another ^ marker.")
            case 5:
                inputs.append("Definition-looking [^note\(index)] reference plus [^note\(index)]: definition text.")
            case 6:
                inputs.append("GitHub-ish \(index) @reviewer\(index % 97) #\(index) owner/repo and :rocket: shortcode.")
            default:
                inputs.append("Long ASCII run \(index) " + String(repeating: "word\(index % 31) ", count: 12))
            }
        }

        return inputs
    }

    private func makeInlineFootnoteContiguousStorageBenchmark() -> [String] {
        var documents: [String] = []
        documents.reserveCapacity(6)

        for seed in 0..<6 {
            var document = "# Inline footnote storage benchmark \(seed)\n\n"
            document.reserveCapacity(420_000)

            for index in 0..<3_500 {
                switch (index + seed) % 10 {
                case 0:
                    document += "Plain paragraph \(index) with no inline footnote markers and stable ASCII words.\n"
                case 1:
                    document += "Caret noise \(index) with ^ markers, ^^ doubles, and spaced ^ [brackets].\n"
                case 2:
                    document += "Inline note \(index) ^[footnote \(index) with **bold** and [link](https://example.com)].\n"
                case 3:
                    document += "Two notes \(index) ^[first \(index)] middle text ^[second \(index)] ending.\n"
                case 4:
                    document += "Malformed \(index) ^[unclosed note followed by ASCII content and another ^ marker.\n"
                case 5:
                    document += "Definition-looking [^note\(index)] reference plus [^note\(index)]: definition text.\n"
                case 6:
                    document += "Unicode \(index) cafe\u{301} with inline note ^[resume\u{301} text].\n"
                case 7:
                    document += "GitHub-ish \(index) @reviewer\(index % 97) #\(index) owner/repo and :rocket: shortcode.\n"
                case 8:
                    document += "Empty inline note \(index) ^[] then valid ^[filled \(index)] after literal text.\n"
                default:
                    document += "Long ASCII run \(index) " + String(repeating: "word\(index % 31) ", count: 12) + "\n"
                }
            }

            documents.append(document)
        }

        return documents
    }

    private func inlineFootnoteMatcherParseCanonicalForBenchmark(
        _ markdown: String,
        singlePass: Bool
    ) -> String {
        let blocks: [MarkdownParser.BlockNode]
        if singlePass {
            blocks = MarkdownParser.parse(markdown, configuration: .default)
        } else {
            blocks = MarkdownParser.parseByCaretSearchInlineFootnotePreprocessForTesting(
                markdown,
                configuration: .default
            )
        }
        return ParserCanonicalSnapshot.canonicalDescription(for: blocks)
    }

    private func inlineFootnoteMatcherMatchChecksumForBenchmark(
        _ markdown: String,
        singlePass: Bool
    ) -> Int {
        MarkdownParser.inlineFootnoteMatchCountForTesting(markdown, singlePass: singlePass) + markdown.utf8.count
    }

    // MARK: - Item 7 Streaming Updates

    private func makeAppendOnlyStreamingUpdates(updateCount: Int) -> [String] {
        var updates: [String] = []
        updates.reserveCapacity(updateCount)

        for index in 0..<updateCount {
            updates.append(
                """
                ## Tick \(index)

                Update line \(index) with some markdown text and [link](https://example.com/\(index)).

                """
            )
        }

        return updates
    }

    private func makeRevealOffsetBenchmarkMarkdown(sectionCount: Int) -> String {
        var markdown = ""
        markdown.reserveCapacity(sectionCount * 140)

        for index in 0..<sectionCount {
            markdown +=
                """
                ## Section \(index)

                Paragraph \(index) with **bold words**, *emphasis*, `code`, and [link](https://example.com/\(index)).

                """
        }

        return markdown
    }

    private func flattenRevealWithPostWalkOffset(
        _ blocks: [MarkdownParser.BlockNode],
        granularity: RevealGranularity,
        atomOffset: Int,
        blockOffset: Int,
        countableOffset: Int
    ) -> RevealModel {
        RevealFlattener
            .flatten(blocks, granularity: granularity, configuration: .default)
            .offsetBy(atomID: atomOffset, blockID: blockOffset, countable: countableOffset)
    }

    private func flattenRevealWithOffsetAwarePath(
        _ blocks: [MarkdownParser.BlockNode],
        granularity: RevealGranularity,
        atomOffset: Int,
        blockOffset: Int,
        countableOffset: Int
    ) -> RevealModel {
        RevealFlattener.flatten(
            blocks,
            granularity: granularity,
            configuration: .default,
            atomIDOffset: atomOffset,
            blockIDOffset: blockOffset,
            countableOffset: countableOffset
        )
    }

    private func assertRevealModelsHaveSameBlocksAndAtoms(
        _ lhs: RevealModel,
        _ rhs: RevealModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.blocks.count, rhs.blocks.count, file: file, line: line)

        for (leftBlock, rightBlock) in zip(lhs.blocks, rhs.blocks) {
            XCTAssertEqual(leftBlock.id, rightBlock.id, file: file, line: line)
            XCTAssertEqual(leftBlock.kind, rightBlock.kind, file: file, line: line)
            XCTAssertEqual(leftBlock.firstRevealIndex, rightBlock.firstRevealIndex, file: file, line: line)
            XCTAssertEqual(leftBlock.words.count, rightBlock.words.count, file: file, line: line)

            for (leftWord, rightWord) in zip(leftBlock.words, rightBlock.words) {
                XCTAssertEqual(leftWord.id, rightWord.id, file: file, line: line)
                XCTAssertEqual(leftWord.isWhitespace, rightWord.isWhitespace, file: file, line: line)
                XCTAssertEqual(leftWord.isLineBreak, rightWord.isLineBreak, file: file, line: line)
                XCTAssertEqual(leftWord.atoms.count, rightWord.atoms.count, file: file, line: line)

                for (leftAtom, rightAtom) in zip(leftWord.atoms, rightWord.atoms) {
                    XCTAssertEqual(leftAtom.id, rightAtom.id, file: file, line: line)
                    XCTAssertEqual(leftAtom.isCountable, rightAtom.isCountable, file: file, line: line)
                    XCTAssertEqual(leftAtom.revealIndex, rightAtom.revealIndex, file: file, line: line)
                    XCTAssertEqual(leftAtom.url, rightAtom.url, file: file, line: line)
                    XCTAssertEqual(revealAtomText(leftAtom), revealAtomText(rightAtom), file: file, line: line)
                }
            }
        }
    }

    private func revealModelLightChecksum(_ model: RevealModel) -> Int {
        var checksum = model.blocks.count ^ model.countableCount ^ model.atomCount

        if let firstBlock = model.blocks.first {
            checksum ^= firstBlock.id
            checksum ^= firstBlock.firstRevealIndex
            checksum ^= firstBlock.words.count
            checksum ^= firstBlock.words.first?.id ?? 0
            checksum ^= firstBlock.words.first?.atoms.first?.id ?? 0
        }

        if let lastBlock = model.blocks.last {
            checksum ^= lastBlock.id
            checksum ^= lastBlock.firstRevealIndex
            checksum ^= lastBlock.words.count
            checksum ^= lastBlock.words.last?.id ?? 0
            checksum ^= lastBlock.words.last?.atoms.last?.id ?? 0
        }

        return checksum
    }

    private func revealAtomText(_ atom: RevealAtom) -> String {
        switch atom.kind {
        case .text(let text), .space(let text):
            return String(text.characters)
        case .lineBreak:
            return "\n"
        case .block:
            return ""
        }
    }

    // MARK: - Item 8 Inline Composition

    private func makeDeepNestedInlineNodes(depth: Int, fanout: Int) -> [MarkdownParser.InlineNode] {
        if depth == 0 {
            return (0..<fanout).map { .text("leaf-\($0)") }
        }

        let children = makeDeepNestedInlineNodes(depth: depth - 1, fanout: fanout)
        switch depth % 3 {
        case 0:
            return [.strong(children: children), .text(" "), .emphasis(children: children)]
        case 1:
            return [.emphasis(children: children), .text(" "), .strikethrough(children: children)]
        default:
            return [.strikethrough(children: children), .text(" "), .strong(children: children)]
        }
    }

    private func renderInlineBaselineRecursive(_ nodes: [MarkdownParser.InlineNode], baseFont: Font?) -> AttributedString {
        var result = AttributedString()
        for node in nodes {
            result += renderNodeBaselineRecursive(node, baseFont: baseFont)
        }
        return result
    }

    private func renderNodeBaselineRecursive(_ node: MarkdownParser.InlineNode, baseFont: Font?) -> AttributedString {
        switch node {
        case .text(let text):
            var value = AttributedString(text)
            if let baseFont = baseFont {
                value.font = baseFont
            }
            return value

        case .emphasis(let children):
            var value = renderInlineBaselineRecursive(children, baseFont: baseFont)
            value.font = (baseFont ?? .body).italic()
            return value

        case .strong(let children):
            var value = renderInlineBaselineRecursive(children, baseFont: baseFont)
            value.font = (baseFont ?? .body).bold()
            return value

        case .strikethrough(let children):
            var value = renderInlineBaselineRecursive(children, baseFont: baseFont)
            var attrs = AttributeContainer()
            if let baseFont = baseFont {
                attrs.font = baseFont
            }
            attrs.strikethroughStyle = .single
            value.mergeAttributes(attrs)
            return value

        default:
            return AttributedString("?")
        }
    }

    private struct SyntheticInlineContext {
        let baseFont: Font?
        let forcedFont: Font?
        let isStrikethrough: Bool

        func withEmphasis() -> SyntheticInlineContext {
            guard forcedFont == nil else { return self }
            return SyntheticInlineContext(
                baseFont: baseFont,
                forcedFont: (baseFont ?? .body).italic(),
                isStrikethrough: isStrikethrough
            )
        }

        func withStrong() -> SyntheticInlineContext {
            guard forcedFont == nil else { return self }
            return SyntheticInlineContext(
                baseFont: baseFont,
                forcedFont: (baseFont ?? .body).bold(),
                isStrikethrough: isStrikethrough
            )
        }

        func withStrikethrough() -> SyntheticInlineContext {
            SyntheticInlineContext(
                baseFont: baseFont,
                forcedFont: forcedFont ?? baseFont,
                isStrikethrough: true
            )
        }
    }

    private func renderInlineOptimizedBuilder(_ nodes: [MarkdownParser.InlineNode], baseFont: Font?) -> AttributedString {
        var result = AttributedString()
        let context = SyntheticInlineContext(baseFont: baseFont, forcedFont: nil, isStrikethrough: false)
        appendInlineOptimized(nodes, to: &result, context: context)
        return result
    }

    private func appendInlineOptimized(
        _ nodes: [MarkdownParser.InlineNode],
        to result: inout AttributedString,
        context: SyntheticInlineContext
    ) {
        for node in nodes {
            switch node {
            case .text(let text):
                var value = AttributedString(text)
                if let forcedFont = context.forcedFont {
                    value.font = forcedFont
                } else if let baseFont = context.baseFont {
                    value.font = baseFont
                }
                if context.isStrikethrough {
                    value.strikethroughStyle = .single
                }
                result.append(value)

            case .emphasis(let children):
                appendInlineOptimized(children, to: &result, context: context.withEmphasis())

            case .strong(let children):
                appendInlineOptimized(children, to: &result, context: context.withStrong())

            case .strikethrough(let children):
                appendInlineOptimized(children, to: &result, context: context.withStrikethrough())

            default:
                result.append(AttributedString("?"))
            }
        }
    }

    private func countBaselineIntermediateAttributedNodes(_ nodes: [MarkdownParser.InlineNode]) -> Int {
        nodes.reduce(0) { $0 + countBaselineIntermediateNode($1) }
    }

    private func countBaselineIntermediateNode(_ node: MarkdownParser.InlineNode) -> Int {
        switch node {
        case .text:
            return 1
        case .emphasis(let children), .strong(let children), .strikethrough(let children):
            return 1 + countBaselineIntermediateAttributedNodes(children)
        default:
            return 1
        }
    }

    private func countOptimizedIntermediateAttributedNodes(_ nodes: [MarkdownParser.InlineNode]) -> Int {
        nodes.reduce(0) { $0 + countOptimizedIntermediateNode($1) }
    }

    private func countOptimizedIntermediateNode(_ node: MarkdownParser.InlineNode) -> Int {
        switch node {
        case .text:
            return 1
        case .emphasis(let children), .strong(let children), .strikethrough(let children):
            return countOptimizedIntermediateAttributedNodes(children)
        default:
            return 1
        }
    }

    // MARK: - Item 6 Table Data

    private func makeLargeTableForWidthMeasurement() -> (header: [MarkdownParser.TableCell], rows: [[MarkdownParser.TableCell]]) {
        let header: [MarkdownParser.TableCell] = (0..<8).map { column in
            MarkdownParser.TableCell(
                content: [
                    .text("Header \(column) "),
                    .strong(children: [.text("Col\(column)")])
                ],
                alignment: .left
            )
        }

        var rows: [[MarkdownParser.TableCell]] = []
        rows.reserveCapacity(240)
        for rowIndex in 0..<240 {
            var row: [MarkdownParser.TableCell] = []
            row.reserveCapacity(8)
            for column in 0..<8 {
                let alignment: MarkdownParser.TableAlignment
                switch column % 3 {
                case 0: alignment = .left
                case 1: alignment = .center
                default: alignment = .right
                }

                row.append(
                    MarkdownParser.TableCell(
                        content: [
                            .text("row\(rowIndex)-col\(column) value "),
                            .emphasis(children: [.text("em\(rowIndex % 11)")]),
                            .text(" "),
                            .code("let v\(column) = \(rowIndex * (column + 1))")
                        ],
                        alignment: alignment
                    )
                )
            }
            rows.append(row)
        }

        return (header, rows)
    }

    private func makeASCIITableRowsForParsingBenchmark(rowCount: Int) -> [String] {
        var rows: [String] = []
        rows.reserveCapacity(rowCount)

        for row in 0..<rowCount {
            rows.append(
                "| **row\(row)** value | *style \(row % 13)* | [doc](https://example.com/\(row)) | " +
                "`let x = \(row)` | @octo #\(row % 500) :rocket: owner/repo deadbeefdeadbeefdeadbeefdeadbeefdeadbeef |"
            )
        }

        return rows
    }

    private func makeASCIITableRowsForSinglePassBenchmark(rowCount: Int) -> [String] {
        var rows: [String] = []
        rows.reserveCapacity(rowCount)

        for row in 0..<rowCount {
            switch row % 6 {
            case 0:
                rows.append("| alpha \(row) | beta \(row) | gamma \(row) |")
            case 1:
                rows.append("alpha \(row)|beta \(row)|gamma \(row)")
            case 2:
                rows.append("| **bold \(row)** | [doc](https://example.com/\(row)) | `code \(row)` |")
            case 3:
                rows.append("| | middle \(row) | |")
            case 4:
                rows.append("| left \(row)    |    center \(row)    | right \(row) |")
            default:
                rows.append("plain \(row)|*em \(row % 17)*|@octo #\(row % 500)")
            }
        }

        return rows
    }

    private func makeASCIITableAlignmentBenchmark(count: Int) -> [String] {
        var lines: [String] = []
        lines.reserveCapacity(count)

        for index in 0..<count {
            switch index % 8 {
            case 0:
                lines.append("| --- | :---: | ---: | --- |")
            case 1:
                lines.append("--- | :--- | ---: | :---:")
            case 2:
                lines.append("| - | :-: | -: |")
            case 3:
                lines.append("|   ---   |   :---:   |   ---:   |")
            case 4:
                lines.append("| --- | x | --- |")
            case 5:
                lines.append("|     | --- |")
            case 6:
                lines.append("| --- | --- | --- | --- | --- |")
            default:
                lines.append("---")
            }
        }

        return lines
    }

    private func tableAlignmentChecksum(_ alignments: [MarkdownParser.TableAlignment]) -> Int {
        var checksum = alignments.count
        for alignment in alignments {
            switch alignment {
            case .left:
                checksum += 1
            case .center:
                checksum += 2
            case .right:
                checksum += 3
            case .none:
                checksum += 4
            }
        }
        return checksum
    }

    private func makeASCIITableBlockForParsingBenchmark(rowCount: Int) -> String {
        var table = "| Name | Style | Link | Code | GitHub |\n|---|:---:|---:|---|---|\n"
        let rows = makeASCIITableRowsForParsingBenchmark(rowCount: rowCount)
        for (index, row) in rows.enumerated() {
            table += row
            if index != rows.count - 1 {
                table += "\n"
            }
        }
        return table
    }

    private func makeASCIIBlockquoteForParsingBenchmark(lineCount: Int) -> String {
        var markdown = ""
        markdown.reserveCapacity(lineCount * 58)

        for line in 0..<lineCount {
            markdown += "> quoted line \(line) with several plain words value \(line % 97)\n"
            if line % 17 == 0 {
                markdown += "lazy continuation \(line) with more words\n"
            }
            if line % 31 == 0 {
                markdown += ">\n"
            }
        }

        return markdown
    }

    private func makeLazyASCIIBlockquoteLineScanBenchmark(lineCount: Int) -> String {
        var markdown = "> quoted root line with ordinary ASCII words\n"
        markdown.reserveCapacity(lineCount * 72)

        for line in 0..<lineCount {
            markdown += "lazy continuation \(line) with several ordinary words value \(line % 97)\n"
            if line % 29 == 0 {
                markdown += "> quoted reset \(line) with plain continuation words\n"
            }
        }

        return markdown
    }

    private enum BlockquoteBenchmarkMode {
        case copyingLines
        case recursiveRangeBacked
        case paragraphFastPathJoiningSingleRanges
        case paragraphFastPathSeparateLineClassification
        case paragraphFastPath
    }

    private func parseBlockquoteForBenchmark(
        _ markdown: String,
        copying: Bool
    ) -> MarkdownParser.BlockNode? {
        parseBlockquoteForBenchmark(markdown, mode: copying ? .copyingLines : .paragraphFastPath)
    }

    private func parseBlockquoteForBenchmark(
        _ markdown: String,
        mode: BlockquoteBenchmarkMode
    ) -> MarkdownParser.BlockNode? {
        var state = ParserState(text: markdown)
        switch mode {
        case .copyingLines:
            return BlockParser.parseBlockquoteByCopyingLinesForTesting(&state, configuration: .default)
        case .recursiveRangeBacked:
            return BlockParser.parseBlockquoteByRecursivelyParsingJoinedContentForTesting(&state, configuration: .default)
        case .paragraphFastPathJoiningSingleRanges:
            return BlockParser.parseBlockquoteByJoiningSingleParagraphsForTesting(&state, configuration: .default)
        case .paragraphFastPathSeparateLineClassification:
            return BlockParser.parseBlockquoteBySeparateLineClassificationForTesting(&state, configuration: .default)
        case .paragraphFastPath:
            return BlockParser.parseBlockquote(&state, configuration: .default)
        }
    }

    private func makeSingleLineBlockquoteBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 8 {
            case 0:
                inputs.append("> plain quoted content \(index) with stable ASCII words\n")
            case 1:
                inputs.append("> **bold \(index)** and *italic* quoted text\n")
            case 2:
                inputs.append("> [link](https://example.com/\(index)) and `code`\n")
            case 3:
                inputs.append("> repo apple/swift#\(index) and @octocat\n")
            case 4:
                inputs.append("> Unicode café \(index) with emoji :tada:\n")
            case 5:
                inputs.append("> escaped \\*marker\\* and plain text \(index)\n")
            case 6:
                inputs.append(">  leading and trailing \(index)   \n")
            default:
                inputs.append("> <https://example.com/\(index)>\n")
            }
        }

        return inputs
    }

    private func makeSingleLineNestedBlockquoteBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 6 {
            case 0:
                inputs.append("> # Nested heading \(index)\n")
            case 1:
                inputs.append("> ## Nested heading \(index) with **literal** markers\n")
            case 2:
                inputs.append("> - nested list item \(index)\n")
            case 3:
                inputs.append("> 1. ordered nested item \(index)\n")
            case 4:
                inputs.append("> ---\n")
            default:
                inputs.append("> ```swift\n")
            }
        }

        return inputs
    }

    private func makeParagraphInlineParsingBenchmark(count: Int) -> [String] {
        var paragraphs: [String] = []
        paragraphs.reserveCapacity(count)

        for index in 0..<count {
            paragraphs.append(
                "Paragraph \(index) with **bold \(index % 17)**, *italic \(index % 13)*, " +
                "[link](https://example.com/\(index) \"Title\"), `code \(index % 29)`, and stable ASCII words.\n"
            )
        }

        return paragraphs
    }

    private func makeParagraphContinuationLineScanBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 10 {
            case 0:
                inputs.append(
                    "Paragraph \(index) starts with stable ASCII words\n" +
                    "continuation \(index) keeps the same paragraph open with more words\n" +
                    "final continuation \(index) includes `code` and **bold** text\n"
                )
            case 1:
                inputs.append(
                    "Leading text \(index)\n" +
                    "   indented continuation \(index) still belongs to the paragraph\n" +
                    "\t tabbed continuation \(index) also stays in paragraph text\n"
                )
            case 2:
                inputs.append("Paragraph before list \(index)\n- list item \(index)\n- second item\n")
            case 3:
                inputs.append("Paragraph before ordered list \(index)\n\(index % 997). ordered item\nnext\n")
            case 4:
                inputs.append("Paragraph \(index)\n###not heading \(index)\ncontinued words\n")
            case 5:
                inputs.append("Paragraph \(index)\n-not a list marker \(index)\ncontinued words\n")
            case 6:
                inputs.append("Paragraph \(index)\n= not a setext underline\ncontinued words\n")
            case 7:
                inputs.append("Paragraph \(index)\n-- not a rule\n__ not a rule\n")
            case 8:
                inputs.append("Paragraph \(index)\ncontinued words \(index)\n> blockquote starts\n")
            default:
                inputs.append("Paragraph \(index)\ncontinued words \(index)\n```swift\nlet value = \(index)\n```\n")
            }
        }

        return inputs
    }

    private func makeParagraphContinuationBreakRestoreBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 8 {
            case 0:
                inputs.append("Paragraph before list \(index)\n- list item \(index)\n- second item\n")
            case 1:
                inputs.append("Paragraph before ordered list \(index)\n\(index % 997 + 1). ordered item\nnext line\n")
            case 2:
                inputs.append("Paragraph before quote \(index)\n> quoted line \(index)\n")
            case 3:
                inputs.append("Paragraph before heading \(index)\n## Heading \(index)\n")
            case 4:
                inputs.append("Paragraph before fence \(index)\n```swift\nlet value = \(index)\n```\n")
            case 5:
                inputs.append("Paragraph before thematic break \(index)\n***\n")
            case 6:
                inputs.append("Paragraph \(index)\ncontinued words stay in paragraph \(index)\n- list starts after continuation\n")
            default:
                inputs.append("Paragraph \(index)\ncontinued words stay in paragraph \(index)\n> blockquote after continuation\n")
            }
        }

        return inputs
    }

    private func parseParagraphForBenchmark(
        _ markdown: String,
        copying: Bool
    ) -> MarkdownParser.BlockNode? {
        var state = ParserState(text: markdown)
        if copying {
            return BlockParser.parseParagraphByCopyingTextForTesting(&state, configuration: .default)
        }
        return BlockParser.parseParagraph(&state, configuration: .default)
    }

    private func parseParagraphSignatureForBenchmark(
        _ markdown: String,
        sharedContinuationLineScan: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let start = state.currentIndex
        let block = parseParagraphForBenchmark(
            &state,
            sharedContinuationLineScan: sharedContinuationLineScan
        )
        let canonical = block.map { ParserCanonicalSnapshot.canonicalDescription(for: [$0]) } ?? "nil\n"
        let offset = state.text.distance(from: start, to: state.currentIndex)
        return "\(canonical)line:\(state.line),column:\(state.column),offset:\(offset)"
    }

    private func parseParagraphContinuationChecksumForBenchmark(
        _ markdown: String,
        sharedContinuationLineScan: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        let start = state.currentIndex
        let block = parseParagraphForBenchmark(
            &state,
            sharedContinuationLineScan: sharedContinuationLineScan
        )
        let offset = state.text.distance(from: start, to: state.currentIndex)
        return blockBenchmarkChecksum(block) + state.line + state.column + offset
    }

    private func parseParagraphForBenchmark(
        _ state: inout ParserState,
        sharedContinuationLineScan: Bool
    ) -> MarkdownParser.BlockNode? {
        if sharedContinuationLineScan {
            return BlockParser.parseParagraph(&state, configuration: .default)
        }
        return BlockParser.parseParagraphByRescanningContinuationLinesForTesting(&state, configuration: .default)
    }

    private func parseParagraphContinuationBreakRestoreSignatureForBenchmark(
        _ markdown: String,
        markRestore: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let start = state.currentIndex
        let block = parseParagraphContinuationBreakRestoreForBenchmark(&state, markRestore: markRestore)
        let canonical = block.map { ParserCanonicalSnapshot.canonicalDescription(for: [$0]) } ?? "nil\n"
        let offset = state.text.distance(from: start, to: state.currentIndex)
        return "\(canonical)line:\(state.line),column:\(state.column),offset:\(offset)"
    }

    private func paragraphContinuationBreakRestoreChecksum(
        _ inputs: [String],
        markRestore: Bool
    ) -> Int {
        var checksum = 0

        for input in inputs {
            var state = ParserState(text: input)
            let start = state.currentIndex
            let block = parseParagraphContinuationBreakRestoreForBenchmark(&state, markRestore: markRestore)
            checksum &+= blockBenchmarkChecksum(block)
            checksum &+= state.line &* 31 &+ state.column
            checksum &+= state.text.distance(from: start, to: state.currentIndex)
        }

        return checksum
    }

    private func parseParagraphContinuationBreakRestoreForBenchmark(
        _ state: inout ParserState,
        markRestore: Bool
    ) -> MarkdownParser.BlockNode? {
        if markRestore {
            return BlockParser.parseParagraph(&state, configuration: .default)
        }

        return BlockParser.parseParagraphByMovingBackToContinuationBreakForTesting(
            &state,
            configuration: .default
        )
    }

    private func parseKnownParagraphForBenchmark(
        _ markdown: String,
        skipKnownFirstBreak: Bool
    ) -> MarkdownParser.BlockNode? {
        var state = ParserState(text: markdown)
        if skipKnownFirstBreak {
            return BlockParser.parseParagraphSkippingKnownFirstBreakForTesting(&state, configuration: .default)
        }
        return BlockParser.parseParagraph(&state, configuration: .default)
    }

    private func parseBlockForBenchmark(
        _ markdown: String,
        gated: Bool = true
    ) -> (block: MarkdownParser.BlockNode?, preservedPosition: Bool) {
        var state = ParserState(text: markdown)
        let start = state.currentIndex
        let block: MarkdownParser.BlockNode?
        if gated {
            block = BlockParser.parseBlock(&state, configuration: .default)
        } else {
            block = BlockParser.parseBlockByAlwaysProbingParagraphStartForTesting(&state, configuration: .default)
        }
        return (block, state.currentIndex == start)
    }

    private func parseBlockSignatureForBenchmark(
        _ markdown: String,
        gated: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let start = state.currentIndex
        let block: MarkdownParser.BlockNode?
        if gated {
            block = BlockParser.parseBlock(&state, configuration: .default)
        } else {
            block = BlockParser.parseBlockByAlwaysProbingParagraphStartForTesting(&state, configuration: .default)
        }

        let canonical = block.map { ParserCanonicalSnapshot.canonicalDescription(for: [$0]) } ?? "nil\n"
        let offset = state.text.distance(from: start, to: state.currentIndex)
        return "\(canonical)line:\(state.line),column:\(state.column),offset:\(offset)"
    }

    private func parseBlockSignatureForBenchmark(
        _ markdown: String,
        sharedParagraphStartProbes: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let start = state.currentIndex
        let block: MarkdownParser.BlockNode?
        if sharedParagraphStartProbes {
            block = BlockParser.parseBlock(&state, configuration: .default)
        } else {
            block = BlockParser.parseBlockBySeparateParagraphStartProbesForTesting(&state, configuration: .default)
        }

        let canonical = block.map { ParserCanonicalSnapshot.canonicalDescription(for: [$0]) } ?? "nil\n"
        let offset = state.text.distance(from: start, to: state.currentIndex)
        return "\(canonical)line:\(state.line),column:\(state.column),offset:\(offset)"
    }

    private func parseBlockDispatchChecksumForBenchmark(
        _ markdown: String,
        gated: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        let block: MarkdownParser.BlockNode?
        if gated {
            block = BlockParser.parseBlock(&state, configuration: .default)
        } else {
            block = BlockParser.parseBlockByAlwaysProbingParagraphStartForTesting(&state, configuration: .default)
        }
        return blockBenchmarkChecksum(block) + state.line + state.column
    }

    private func parseBlockDispatchChecksumForBenchmark(
        _ markdown: String,
        sharedParagraphStartProbes: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        let block: MarkdownParser.BlockNode?
        if sharedParagraphStartProbes {
            block = BlockParser.parseBlock(&state, configuration: .default)
        } else {
            block = BlockParser.parseBlockBySeparateParagraphStartProbesForTesting(&state, configuration: .default)
        }
        return blockBenchmarkChecksum(block) + state.line + state.column
    }

    private func parseBlockStartDispatchSignatureForBenchmark(
        _ markdown: String,
        utf8Dispatch: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let start = state.currentIndex
        let block = utf8Dispatch
            ? BlockParser.parseBlock(&state, configuration: .default)
            : BlockParser.parseBlockByCharacterDispatchForTesting(&state, configuration: .default)

        let canonical = block.map { ParserCanonicalSnapshot.canonicalDescription(for: [$0]) } ?? "nil\n"
        let offset = state.text.distance(from: start, to: state.currentIndex)
        return "\(canonical)line:\(state.line),column:\(state.column),offset:\(offset)"
    }

    private func parseBlockStartDispatchChecksum(
        _ markdown: String,
        utf8Dispatch: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        let start = state.currentIndex
        let block = utf8Dispatch
            ? BlockParser.parseBlock(&state, configuration: .default)
            : BlockParser.parseBlockByCharacterDispatchForTesting(&state, configuration: .default)
        let offset = state.text.distance(from: start, to: state.currentIndex)
        return blockBenchmarkChecksum(block) + state.line + state.column + offset
    }

    private func makeBlockStartDispatchBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 12 {
            case 0:
                inputs.append("# Heading \(index)\n")
            case 1:
                inputs.append("   # Heading \(index)\n")
            case 2:
                inputs.append("plain paragraph \(index)\n")
            case 3:
                inputs.append("  plain paragraph \(index)\n")
            case 4:
                inputs.append("- item \(index)\n")
            case 5:
                inputs.append("\(index % 100). ordered item \(index)\n")
            case 6:
                inputs.append("***\n")
            case 7:
                inputs.append("> quote \(index)\n")
            case 8:
                inputs.append("```swift\nlet value = \(index)\n```\n")
            case 9:
                inputs.append("    indented code \(index)\n")
            case 10:
                inputs.append("[^note\(index)]: footnote \(index)\n")
            default:
                inputs.append("café paragraph \(index)\n")
            }
        }

        return inputs
    }

    private func parseListItemLineEndSignatureForBenchmark(
        _ markdown: String,
        utf8LineEndScan: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let item = utf8LineEndScan
            ? BlockParser.parseListItemContent(&state, indent: 0, marker: "-", configuration: .github)
            : BlockParser.parseListItemContentByCharacterLineEndScanningForTesting(
                &state,
                indent: 0,
                marker: "-",
                configuration: .github
            )
        let canonical = ParserCanonicalSnapshot.canonicalDescription(
            for: [.list(ordered: false, tight: false, items: [item])]
        )
        let offset = markdown.distance(from: markdown.startIndex, to: state.currentIndex)
        return "\(canonical)line:\(state.line),column:\(state.column),offset:\(offset)"
    }

    private func parseFootnoteLineEndSignatureForBenchmark(
        _ markdown: String,
        utf8LineEndScan: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let block = utf8LineEndScan
            ? BlockParser.parseFootnoteDefinition(&state, configuration: .github)
            : BlockParser.parseFootnoteDefinitionByCharacterLineEndScanningForTesting(
                &state,
                configuration: .github
            )
        let canonical = block.map { ParserCanonicalSnapshot.canonicalDescription(for: [$0]) } ?? "nil\n"
        let offset = markdown.distance(from: markdown.startIndex, to: state.currentIndex)
        return "\(canonical)line:\(state.line),column:\(state.column),offset:\(offset)"
    }

    private func parseFootnoteHeaderScanSignatureForBenchmark(
        _ markdown: String,
        utf8HeaderScan: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let block = utf8HeaderScan
            ? BlockParser.parseFootnoteDefinition(&state, configuration: .github)
            : BlockParser.parseFootnoteDefinitionByCharacterHeaderScanningForTesting(
                &state,
                configuration: .github
            )
        let canonical = block.map { ParserCanonicalSnapshot.canonicalDescription(for: [$0]) } ?? "nil\n"
        let offset = markdown.distance(from: markdown.startIndex, to: state.currentIndex)
        return "\(canonical)line:\(state.line),column:\(state.column),offset:\(offset)"
    }

    private func parseFootnoteContinuationPrefixSignatureForBenchmark(
        _ markdown: String,
        utf8Prefix: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let block = utf8Prefix
            ? BlockParser.parseFootnoteDefinition(&state, configuration: .github)
            : BlockParser.parseFootnoteDefinitionByCharacterContinuationPrefixForTesting(
                &state,
                configuration: .github
            )
        let canonical = block.map { ParserCanonicalSnapshot.canonicalDescription(for: [$0]) } ?? "nil\n"
        let offset = markdown.distance(from: markdown.startIndex, to: state.currentIndex)
        return "\(canonical)line:\(state.line),column:\(state.column),offset:\(offset)"
    }

    private func makeFootnoteHeaderScanBenchmark(count: Int) -> [String] {
        let repeatedLabel = String(repeating: "ascii-label-", count: 10)
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            inputs.append("[^note-\(index)-\(repeatedLabel)]: footnote \(index)\n")
        }

        return inputs
    }

    private func makeFootnoteContinuationPrefixBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 6 {
            case 0:
                inputs.append(
                    """
                    [^note\(index)]: first line \(index)
                        continuation \(index) with stable ASCII text
                        final continuation \(index)
                    """
                )
            case 1:
                inputs.append(
                    """
                    [^tab\(index)]: first line \(index)
                    \tcontinuation \(index) with `code`
                    \tfinal continuation \(index)
                    """
                )
            case 2:
                inputs.append(
                    """
                    [^mixed\(index)]: first line \(index)
                       \tcontinuation \(index) after spaces and tab
                        final continuation \(index)
                    """
                )
            case 3:
                inputs.append(
                    """
                    [^short\(index)]: first line \(index)
                       not a continuation \(index)
                    trailing paragraph \(index)
                    """
                )
            case 4:
                inputs.append(
                    """
                    [^nested\(index)]: intro \(index)
                        - nested item \(index)
                        - second nested item \(index)
                    """
                )
            default:
                inputs.append(
                    """
                    [^link\(index)]: first line \(index)
                        continuation \(index) with [link](https://example.com/\(index))
                        continuation \(index) with **bold**
                    """
                )
            }
        }

        return inputs
    }

    private func footnoteContinuationPrefixChecksum(
        _ inputs: [String],
        utf8Prefix: Bool
    ) -> Int {
        var checksum = 0

        for input in inputs {
            var state = ParserState(text: input)
            let start = state.currentIndex
            let block = utf8Prefix
                ? BlockParser.parseFootnoteDefinition(&state, configuration: .github)
                : BlockParser.parseFootnoteDefinitionByCharacterContinuationPrefixForTesting(
                    &state,
                    configuration: .github
                )
            checksum &+= blockBenchmarkChecksum(block)
            checksum &+= state.line &* 47 &+ state.column
            checksum &+= input.distance(from: start, to: state.currentIndex)
        }

        return checksum
    }

    private func footnoteHeaderScanChecksum(
        _ inputs: [String],
        utf8HeaderScan: Bool
    ) -> Int {
        var checksum = 0

        for input in inputs {
            var state = ParserState(text: input)
            let start = state.currentIndex
            let block = utf8HeaderScan
                ? BlockParser.parseFootnoteDefinition(&state, configuration: .github)
                : BlockParser.parseFootnoteDefinitionByCharacterHeaderScanningForTesting(
                    &state,
                    configuration: .github
                )
            checksum &+= blockBenchmarkChecksum(block)
            checksum &+= state.line &* 43 &+ state.column
            checksum &+= input.distance(from: start, to: state.currentIndex)
        }

        return checksum
    }

    private func makeContainerLineEndScanBenchmark(count: Int) -> [(list: String, footnote: String)] {
        var inputs: [(list: String, footnote: String)] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            let list = """
            [x] list item \(index) with plain ASCII text and `code`
              continuation \(index) with [link](https://example.com/\(index))
              final continuation \(index) with **bold** text
            """
            let footnote = """
            [^note\(index)]: footnote \(index) with plain ASCII text and `code`
                continuation \(index) with [link](https://example.com/\(index))
                final continuation \(index) with **bold** text
            """
            inputs.append((list, footnote))
        }

        return inputs
    }

    private func containerLineEndScanChecksum(
        _ inputs: [(list: String, footnote: String)],
        utf8LineEndScan: Bool
    ) -> Int {
        var checksum = 0

        for input in inputs {
            var listState = ParserState(text: input.list)
            let item = utf8LineEndScan
                ? BlockParser.parseListItemContent(&listState, indent: 0, marker: "-", configuration: .github)
                : BlockParser.parseListItemContentByCharacterLineEndScanningForTesting(
                    &listState,
                    indent: 0,
                    marker: "-",
                    configuration: .github
                )
            checksum &+= listItemBenchmarkChecksum(item)
            checksum &+= listState.line &* 31 &+ listState.column

            var footnoteState = ParserState(text: input.footnote)
            let footnote = utf8LineEndScan
                ? BlockParser.parseFootnoteDefinition(&footnoteState, configuration: .github)
                : BlockParser.parseFootnoteDefinitionByCharacterLineEndScanningForTesting(
                    &footnoteState,
                    configuration: .github
                )
            checksum &+= blockBenchmarkChecksum(footnote)
            checksum &+= footnoteState.line &* 37 &+ footnoteState.column
        }

        return checksum
    }

    private func parseBlockCandidateRestoreSignatureForBenchmark(
        _ markdown: String,
        markRestore: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let start = state.currentIndex
        let block = markRestore
            ? BlockParser.parseBlock(&state, configuration: .github)
            : BlockParser.parseBlockByIndexMoveCandidateRestoreForTesting(&state, configuration: .github)
        let canonical = block.map { ParserCanonicalSnapshot.canonicalDescription(for: [$0]) } ?? "nil\n"
        let offset = markdown.distance(from: start, to: state.currentIndex)
        return "\(canonical)line:\(state.line),column:\(state.column),offset:\(offset)"
    }

    private func parseTableCandidateRestoreSignatureForBenchmark(
        _ markdown: String,
        markRestore: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let start = state.currentIndex
        let block = markRestore
            ? BlockParser.parseTableUsingStartProbeForTesting(&state, configuration: .github)
            : BlockParser.parseTableByIndexMoveCandidateRestoreForTesting(&state, configuration: .github)
        let canonical = block.map { ParserCanonicalSnapshot.canonicalDescription(for: [$0]) } ?? "nil\n"
        let offset = markdown.distance(from: start, to: state.currentIndex)
        return "\(canonical)line:\(state.line),column:\(state.column),offset:\(offset)"
    }

    private func parseFootnoteCandidateRestoreSignatureForBenchmark(
        _ markdown: String,
        markRestore: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let start = state.currentIndex
        let block = markRestore
            ? BlockParser.parseFootnoteDefinition(&state, configuration: .github)
            : BlockParser.parseFootnoteDefinitionByIndexMoveCandidateRestoreForTesting(
                &state,
                configuration: .github
            )
        let canonical = block.map { ParserCanonicalSnapshot.canonicalDescription(for: [$0]) } ?? "nil\n"
        let offset = markdown.distance(from: start, to: state.currentIndex)
        return "\(canonical)line:\(state.line),column:\(state.column),offset:\(offset)"
    }

    private func makeFailedBlockCandidateRestoreBenchmark(
        count: Int
    ) -> [(block: String, table: String, footnote: String)] {
        var inputs: [(block: String, table: String, footnote: String)] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            let table: String
            switch index % 3 {
            case 0:
                table = """
                A \(index) | B \(index) | C \(index)
                --- | ---
                paragraph after invalid table \(index)
                """
            case 1:
                table = """
                | A \(index) | B \(index) |
                | :---x | --- |
                paragraph after invalid alignment \(index)
                """
            default:
                table = """
                Name \(index) | Value \(index)
                --- | --- | ---
                paragraph after invalid separator \(index)
                """
            }

            let footnote: String
            switch index % 3 {
            case 0:
                footnote = "[^missing-colon-\(index)] text after label\nnext line \(index)\n"
            case 1:
                footnote = "[^unterminated-\(index)\nnext line \(index)\n"
            default:
                footnote = "[^]: empty label \(index)\nnext line \(index)\n"
            }

            let block = index.isMultiple(of: 2) ? table : footnote
            inputs.append((block, table, footnote))
        }

        return inputs
    }

    private func failedBlockCandidateRestoreChecksum(
        _ inputs: [(block: String, table: String, footnote: String)],
        markRestore: Bool
    ) -> Int {
        var checksum = 0

        for input in inputs {
            var blockState = ParserState(text: input.block)
            let start = blockState.currentIndex
            let block = markRestore
                ? BlockParser.parseBlock(&blockState, configuration: .github)
                : BlockParser.parseBlockByIndexMoveCandidateRestoreForTesting(
                    &blockState,
                    configuration: .github
                )
            checksum &+= blockBenchmarkChecksum(block)
            checksum &+= blockState.line &* 31 &+ blockState.column
            checksum &+= input.block.distance(from: start, to: blockState.currentIndex)

            var tableState = ParserState(text: input.table)
            let table = markRestore
                ? BlockParser.parseTableUsingStartProbeForTesting(&tableState, configuration: .github)
                : BlockParser.parseTableByIndexMoveCandidateRestoreForTesting(
                    &tableState,
                    configuration: .github
                )
            checksum &+= blockBenchmarkChecksum(table)
            checksum &+= tableState.line &* 37 &+ tableState.column

            var footnoteState = ParserState(text: input.footnote)
            let footnote = markRestore
                ? BlockParser.parseFootnoteDefinition(&footnoteState, configuration: .github)
                : BlockParser.parseFootnoteDefinitionByIndexMoveCandidateRestoreForTesting(
                    &footnoteState,
                    configuration: .github
                )
            checksum &+= blockBenchmarkChecksum(footnote)
            checksum &+= footnoteState.line &* 41 &+ footnoteState.column
        }

        return checksum
    }

    private func makeBlockDispatchProbeEligibilityBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 10 {
            case 0:
                inputs.append("plain paragraph \(index)\n")
            case 1:
                inputs.append("line \(index)\ncontinued text\n")
            case 2:
                inputs.append("  leading paragraph \(index)\n")
            case 3:
                inputs.append("\tleading tab text \(index)\n")
            case 4:
                inputs.append("###not heading \(index)\n")
            case 5:
                inputs.append("Paragraph \(index) without table\nnot underline\n")
            case 6:
                inputs.append("A \(index) | B\nnot sep\n")
            case 7:
                inputs.append("Heading \(index)\n---x\n")
            case 8:
                inputs.append("unicode café \(index)\n")
            default:
                inputs.append("words \(index) with `code` and **bold**\n")
            }
        }

        return inputs
    }

    private func makeBlockDispatchSharedLineClassificationBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 10 {
            case 0:
                inputs.append("A \(index) | B\n--- | ---\nrow | cell\n")
            case 1:
                inputs.append("Name \(index) | Value\n| --- | ---: |\n| row | `code` |\n")
            case 2:
                inputs.append("A \(index) | B\nnot a separator\n")
            case 3:
                inputs.append("Heading \(index)\n---\nnext paragraph\n")
            case 4:
                inputs.append("Heading \(index)\n===\nnext paragraph\n")
            case 5:
                inputs.append("Heading \(index)\n---x\n")
            case 6:
                inputs.append("plain paragraph \(index)\ncontinued words\n")
            case 7:
                inputs.append("plain paragraph \(index)\n")
            case 8:
                inputs.append("Unicode café \(index) | value\n| - | - |\n")
            default:
                inputs.append("Unicode café \(index)\n---\n")
            }
        }

        return inputs
    }

    private func makeKnownParagraphFirstLineBreakBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 8 {
            case 0:
                inputs.append("plain \(index)\n")
            case 1:
                inputs.append("  indented \(index)\n")
            case 2:
                inputs.append("line \(index)\ncontinued\n")
            case 3:
                inputs.append("###not heading \(index)\n")
            case 4:
                inputs.append("-- not rule \(index)\n")
            case 5:
                inputs.append("__ not rule \(index)\n")
            case 6:
                inputs.append("unicode café \(index)\n")
            default:
                inputs.append("words \(index) with `code` and **bold**\n")
            }
        }

        return inputs
    }

    private func makeEmptyLineScanningBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 4 {
            case 0:
                inputs.append("   \t  \n")
            case 1:
                inputs.append("\t\t\n")
            case 2:
                inputs.append("  text \(index)\n")
            default:
                inputs.append("      ")
            }
        }

        return inputs
    }

    private func isAtEmptyLineForBenchmark(_ markdown: String, fastPath: Bool) -> Bool {
        let state = ParserState(text: markdown)
        if fastPath {
            return state.isAtEmptyLine()
        }
        return state.isAtEmptyLineByCharacterScanningForTesting()
    }

    private func parserStateAdvanceIfEmptyLineSignature(_ input: String, optimized: Bool) -> String {
        var state = ParserState(text: input)
        let advanced = optimized
            ? state.advanceIfAtEmptyLine()
            : state.advanceIfAtEmptyLineBySeparateScanForTesting()

        return "advanced:\(advanced)|index:\(input.distance(from: input.startIndex, to: state.currentIndex))|" +
            "line:\(state.line)|column:\(state.column)"
    }

    private func emptyLineSkipChecksum(_ inputs: [String], optimized: Bool) -> Int {
        var checksum = 0

        for input in inputs {
            var state = ParserState(text: input)
            let advanced = optimized
                ? state.advanceIfAtEmptyLine()
                : state.advanceIfAtEmptyLineBySeparateScanForTesting()
            checksum &+= advanced ? 17 : 3
            checksum &+= state.line &* 31 &+ state.column
        }

        return checksum
    }

    private func makeBlankLineRangeScanningBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 4 {
            case 0:
                inputs.append("      ")
            case 1:
                inputs.append("\t  \t")
            case 2:
                inputs.append("  value \(index)")
            default:
                inputs.append("")
            }
        }

        return inputs
    }

    private func makeWhitespaceRangeHelperBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 5 {
            case 0:
                inputs.append("    value \(index) with trailing space    ")
            case 1:
                inputs.append("\t\tvalue \(index)\t")
            case 2:
                inputs.append("value \(index) with no trim")
            case 3:
                inputs.append("        ")
            default:
                inputs.append("\nvalue \(index)\n")
            }
        }

        return inputs
    }

    private func makeBlockCandidateLineScanningBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 8 {
            case 0:
                inputs.append("plain paragraph line \(index) with stable ASCII words")
            case 1:
                inputs.append("   plain paragraph line \(index) after spaces")
            case 2:
                inputs.append("    indented code line \(index)")
            case 3:
                inputs.append("## heading \(index)")
            case 4:
                inputs.append("- list item \(index)")
            case 5:
                inputs.append("\(index % 997). ordered item")
            case 6:
                inputs.append("= setext continuation")
            default:
                inputs.append("| table candidate | \(index) |")
            }
        }

        return inputs
    }

    private func makeContentLineFastPathBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 10 {
            case 0:
                inputs.append("plain paragraph line \(index) with stable ASCII words")
            case 1:
                inputs.append("   plain paragraph line \(index) after spaces")
            case 2:
                inputs.append("    indented code line \(index)")
            case 3:
                inputs.append("")
            case 4:
                inputs.append("   ")
            case 5:
                inputs.append("## heading \(index)")
            case 6:
                inputs.append("- list item \(index)")
            case 7:
                inputs.append("\(index % 997). ordered item")
            case 8:
                inputs.append("= setext continuation")
            default:
                inputs.append("| table candidate | \(index) |")
            }
        }

        return inputs
    }

    private func makeParagraphBreakingBlockScanningBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 10 {
            case 0:
                inputs.append("plain continuation line \(index) with stable ASCII words")
            case 1:
                inputs.append("   plain continuation line \(index) after spaces")
            case 2:
                inputs.append("## heading \(index)")
            case 3:
                inputs.append("###not heading \(index)")
            case 4:
                inputs.append("> quote \(index)")
            case 5:
                inputs.append("```swift")
            case 6:
                inputs.append("- list item \(index)")
            case 7:
                inputs.append("\(index % 997). ordered item")
            case 8:
                inputs.append("---")
            default:
                inputs.append("_not horizontal rule \(index)")
            }
        }

        return inputs
    }

    private func makeWhitespaceTrimmedRangeBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 6 {
            case 0:
                inputs.append("plain value \(index)")
            case 1:
                inputs.append("  leading value \(index)")
            case 2:
                inputs.append("trailing value \(index)   ")
            case 3:
                inputs.append("   both sides value \(index)   ")
            case 4:
                inputs.append("\t\ttabbed value \(index)\t")
            default:
                inputs.append("      ")
            }
        }

        return inputs
    }

    private func makeParagraphBreakScanningBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 10 {
            case 0:
                inputs.append("plain paragraph line \(index) with stable ASCII words")
            case 1:
                inputs.append("   plain paragraph line \(index)")
            case 2:
                inputs.append("   > quote \(index)")
            case 3:
                inputs.append("```swift")
            case 4:
                inputs.append("``not fence \(index)")
            case 5:
                inputs.append("### heading \(index)")
            case 6:
                inputs.append("###not heading \(index)")
            case 7:
                inputs.append("---")
            case 8:
                inputs.append("- list item \(index)")
            default:
                inputs.append("   ")
            }
        }

        return inputs
    }

    private func makeParagraphBreakingBlockPlainProbeBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 10 {
            case 0:
                inputs.append("plain continuation line \(index) with stable ASCII words                    ")
            case 1:
                inputs.append("   indented paragraph continuation \(index) with trailing spaces            ")
            case 2:
                inputs.append("https://example.com/docs/\(index)        ")
            case 3:
                inputs.append("paragraph \(index) with trailing tabs\t\t")
            case 4:
                inputs.append("# heading \(index)")
            case 5:
                inputs.append("- list item \(index)")
            case 6:
                inputs.append("---")
            case 7:
                inputs.append("- ")
            case 8:
                inputs.append("\u{00A0}# unicode whitespace heading \(index)")
            default:
                inputs.append("\(index % 997). ordered item")
            }
        }

        return inputs
    }

    private func makeParagraphBreakingBlockCandidateProbeBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 12 {
            case 0:
                inputs.append("# heading \(index)                                      ")
            case 1:
                inputs.append("### heading \(index)\t\t")
            case 2:
                inputs.append("> quote \(index)                                        ")
            case 3:
                inputs.append("```swift                                                ")
            case 4:
                inputs.append("~~~                                                     ")
            case 5:
                inputs.append("---                                                     ")
            case 6:
                inputs.append("***                                                     ")
            case 7:
                inputs.append("___                                                     ")
            case 8:
                inputs.append("- list item \(index)                                    ")
            case 9:
                inputs.append("+ list item \(index)                                    ")
            case 10:
                inputs.append("\(index % 997). ordered item                            ")
            default:
                inputs.append("plain paragraph \(index)                                ")
            }
        }

        return inputs
    }

    private func isAtParagraphBreakForBenchmark(_ markdown: String, fastPath: Bool) -> Bool {
        var state = ParserState(text: markdown)
        if fastPath {
            return BlockParser.isAtParagraphBreakForTesting(&state)
        }
        return BlockParser.isAtParagraphBreakByCharacterScanningForTesting(&state)
    }

    private func makeSetextHeadingProbeBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 8 {
            case 0:
                inputs.append("Heading \(index)\n===")
            case 1:
                inputs.append("Heading \(index)\n---")
            case 2:
                inputs.append("Paragraph \(index)\nnot underline")
            case 3:
                inputs.append("   \n---")
            case 4:
                inputs.append("Unicode café \(index)\n---")
            case 5:
                inputs.append("Heading \(index)\n---x")
            case 6:
                inputs.append("Heading \(index)\n")
            default:
                inputs.append("Single line \(index) with no underline")
            }
        }

        return inputs
    }

    private func shouldAttemptSetextHeadingForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> Bool {
        let state = ParserState(text: markdown)
        if optimized {
            return BlockParser.shouldAttemptSetextHeadingForTesting(state)
        }
        return BlockParser.shouldAttemptSetextHeadingByLineRangesForTesting(state)
    }

    private func makeTableProbeBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 8 {
            case 0:
                inputs.append("| A \(index) | B |\n| - | - |")
            case 1:
                inputs.append("A \(index) | B\n--- | ---")
            case 2:
                inputs.append("Paragraph \(index) without table marker\n| - | - |")
            case 3:
                inputs.append("| A \(index) | B |\n---")
            case 4:
                inputs.append("| A \(index) | B |\n| x | y |")
            case 5:
                inputs.append("Unicode café \(index) | value\n| - | - |")
            case 6:
                inputs.append("| A \(index) | B |")
            default:
                inputs.append("plain paragraph \(index)")
            }
        }

        return inputs
    }

    private func shouldAttemptTableForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> Bool {
        let state = ParserState(text: markdown)
        if optimized {
            return BlockParser.shouldAttemptTableForTesting(state)
        }
        return BlockParser.shouldAttemptTableByLineRangesForTesting(state)
    }

    private func makeTableStartProbeReuseBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 4 {
            case 0:
                inputs.append("| A \(index) | B |\n| - | - |")
            case 1:
                inputs.append("A \(index) | B\n--- | ---")
            case 2:
                inputs.append("| Name | Value |\n| --- | ---: |\n| row \(index) | code |")
            default:
                inputs.append("Unicode café \(index) | value\n| - | - |")
            }
        }

        return inputs
    }

    private func makeTableSeparatorAlignmentReuseBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 6 {
            case 0:
                inputs.append("| A \(index) | B | C |\n| --- | :---: | ---: |")
            case 1:
                inputs.append("Name \(index) | Value | Status\n--- | ---: | :---:")
            case 2:
                inputs.append("| Key \(index) | Value |\n|\t---\t|\t---:\t|")
            case 3:
                inputs.append("| A \(index) | B |\n| :- | -: |\n| 1 | 2 |")
            case 4:
                inputs.append("| A \(index) | B |\n| ---- | ---- |")
            default:
                inputs.append("Left \(index) | Center | Right\n:--- | :---: | ---:")
            }
        }

        return inputs
    }

    private func tableParseCanonicalForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let block = parseTableForBenchmark(&state, optimized: optimized)
        let canonical: String
        if let block {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [block])
        } else {
            canonical = "nil"
        }
        return "\(canonical)|index:\(state.currentIndex)|line:\(state.line)|column:\(state.column)"
    }

    private func tableParseChecksumForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        guard let block = parseTableForBenchmark(&state, optimized: optimized) else {
            return state.line + state.column
        }

        if case let .table(header, rows) = block {
            return header.count + rows.count + state.line + state.column
        }

        return state.line + state.column
    }

    private func parseTableForBenchmark(
        _ state: inout ParserState,
        optimized: Bool
    ) -> MarkdownParser.BlockNode? {
        if optimized {
            return BlockParser.parseTableUsingStartProbeForTesting(&state, configuration: .github)
        }

        guard BlockParser.shouldAttemptTableForTesting(state) else {
            return nil
        }
        return BlockParser.parseTableByRescanningStartLinesForTesting(&state, configuration: .github)
    }

    private func tableSeparatorAlignmentParseCanonicalForBenchmark(
        _ markdown: String,
        reusedAlignments: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let block = parseTableSeparatorAlignmentForBenchmark(&state, reusedAlignments: reusedAlignments)
        let canonical: String
        if let block {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [block])
        } else {
            canonical = "nil"
        }
        return "\(canonical)|index:\(state.currentIndex)|line:\(state.line)|column:\(state.column)"
    }

    private func tableSeparatorAlignmentParseChecksumForBenchmark(
        _ markdown: String,
        reusedAlignments: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        guard let block = parseTableSeparatorAlignmentForBenchmark(&state, reusedAlignments: reusedAlignments) else {
            return state.line + state.column
        }

        if case let .table(header, rows) = block {
            let headerChecksum = header.reduce(0) { $0 + tableCellBenchmarkChecksum($1) }
            let rowChecksum = rows.flatMap { $0 }.reduce(0) { $0 + tableCellBenchmarkChecksum($1) }
            return headerChecksum + rowChecksum + state.line + state.column
        }

        return state.line + state.column
    }

    private func parseTableSeparatorAlignmentForBenchmark(
        _ state: inout ParserState,
        reusedAlignments: Bool
    ) -> MarkdownParser.BlockNode? {
        if reusedAlignments {
            return BlockParser.parseTableUsingStartProbeForTesting(&state, configuration: .github)
        }

        return BlockParser.parseTableByReparsingSeparatorAlignmentsForTesting(&state, configuration: .github)
    }

    private func makeSetextProbeReuseBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 4 {
            case 0:
                inputs.append("Heading \(index)\n===")
            case 1:
                inputs.append("Heading \(index)\n---")
            case 2:
                inputs.append(" Unicode café \(index) \n---   ")
            default:
                inputs.append("Heading **\(index)** with [link](https://example.com)\n---")
            }
        }

        return inputs
    }

    private func makeASCIISetextHeadingTrimBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 5 {
            case 0:
                inputs.append("Heading \(index)\n===")
            case 1:
                inputs.append(" Heading \(index) with leading space \n---   ")
            case 2:
                inputs.append("\tTabbed heading \(index)\t\n---")
            case 3:
                inputs.append("Heading **\(index)** with [link](https://example.com)\n---")
            default:
                inputs.append("Plain ASCII heading \(index) with trailing spaces   \n===")
            }
        }

        return inputs
    }

    private func makeATXHeadingParseBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 8 {
            case 0:
                inputs.append("# Heading \(index)")
            case 1:
                inputs.append("## Heading \(index) with Stable ASCII Words")
            case 2:
                inputs.append("### Heading \(index) ###")
            case 3:
                inputs.append("#### Heading \(index) with **bold** text")
            case 4:
                inputs.append("###### Heading \(index) with [link](https://example.com)")
            case 5:
                inputs.append("####### not heading \(index)")
            case 6:
                inputs.append("#")
            default:
                inputs.append("###not heading \(index)")
            }
        }

        return inputs
    }

    private func makeFencedCodeParseBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 6 {
            case 0:
                inputs.append("```swift\nprint(\"hello \(index)\")\n```")
            case 1:
                inputs.append("~~~text\nalpha \(index)\nbeta \(index)\n~~~")
            case 2:
                inputs.append("```\nline one \(index)\nline two \(index)\nline three \(index)\n```")
            case 3:
                inputs.append("```json\n{\"value\": \(index)}\n```\nnext")
            case 4:
                inputs.append("```\nunclosed \(index)\nline")
            default:
                inputs.append("``\nnot a fence \(index)")
            }
        }

        return inputs
    }

    private func makeFencedCodeStateMoveBenchmark(count: Int) -> [String] {
        func makeBody(index: Int, lineCount: Int) -> String {
            var body = ""
            body.reserveCapacity(lineCount * 72)
            for line in 0..<lineCount {
                if line > 0 {
                    body += "\n"
                }
                body += "let value\(line) = \(index + line) // stable ascii payload for fenced code"
            }
            return body
        }

        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 6 {
            case 0:
                let body = makeBody(index: index, lineCount: 12)
                inputs.append("```swift\n\(body)\n```")
            case 1:
                let body = makeBody(index: index, lineCount: 18)
                inputs.append("~~~text\n\(body)\n~~~\nnext paragraph")
            case 2:
                let body = makeBody(index: index, lineCount: 24)
                inputs.append("```\n\(body)")
            case 3:
                let body = makeBody(index: index, lineCount: 10)
                inputs.append("````swift\n```nested literal \(index)\n\(body)\n````\nafter")
            case 4:
                let body = makeBody(index: index, lineCount: 16)
                inputs.append("```json\n{\"index\": \(index)}\n\(body)\n```\n")
            default:
                let body = makeBody(index: index, lineCount: 8)
                inputs.append("```\n\(body)\n")
            }
        }

        return inputs
    }

    private func makeUnicodeFencedCodeParseBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 6 {
            case 0:
                inputs.append(
                    "```swift\nlet greeting = \"こんにちは \(index)\"\nprint(\"✅ \(index)\")\n```"
                )
            case 1:
                inputs.append(
                    "~~~text\ncafé résumé \(index)\nnaïve jalapeño \(index)\n~~~\nnext"
                )
            case 2:
                inputs.append(
                    "```json\n{\"message\":\"こんにちは \(index)\",\"emoji\":\"✅\"}\n```"
                )
            case 3:
                inputs.append(
                    "````café\nUnicode info \(index)\nline \(index)\n````"
                )
            case 4:
                inputs.append(
                    "```\nline \(index) 世界\nline \(index) café\n```\n"
                )
            default:
                inputs.append(
                    "```\nemoji ✅ \(index)\n"
                )
            }
        }

        return inputs
    }

    private func makeHorizontalRuleParseBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 10 {
            case 0:
                inputs.append("---")
            case 1:
                inputs.append(" ---\nnext")
            case 2:
                inputs.append("   ***   ")
            case 3:
                inputs.append("_ _ _")
            case 4:
                inputs.append("- - - - -")
            case 5:
                inputs.append("--")
            case 6:
                inputs.append("----x")
            case 7:
                inputs.append("    ---")
            case 8:
                inputs.append("***\nnext")
            default:
                inputs.append("paragraph \(index)")
            }
        }

        return inputs
    }

    private func makeHorizontalRuleStateMoveBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 8 {
            case 0:
                inputs.append("---")
            case 1:
                inputs.append(" ---\nnext")
            case 2:
                inputs.append("   ***   \nnext")
            case 3:
                inputs.append("_ _ _")
            case 4:
                inputs.append("- - - - -")
            case 5:
                inputs.append("***\nnext")
            case 6:
                inputs.append("___   ")
            default:
                inputs.append("--")
            }
        }

        return inputs
    }

    private func makeIndentedCodeParseBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 6 {
            case 0:
                inputs.append("    let value\(index) = \(index)\n    print(value\(index))")
            case 1:
                inputs.append("    alpha \(index)\n        beta \(index)\n\n    gamma \(index)\nnext")
            case 2:
                inputs.append("        deeply indented \(index)\n    back \(index)")
            case 3:
                inputs.append("    line with trailing spaces \(index)    \n    next")
            case 4:
                inputs.append("    ")
            default:
                inputs.append("   not indented code \(index)")
            }
        }

        return inputs
    }

    private struct NonASCIIInlineRangeBenchmarkInput {
        let source: String
        let range: Range<String.Index>
    }

    private struct ParserStateInitializationBenchmarkInput {
        let source: String
        let range: Range<String.Index>
    }

    private func makeNonASCIIInlineRangeBenchmark(count: Int) -> [NonASCIIInlineRangeBenchmarkInput] {
        var inputs: [NonASCIIInlineRangeBenchmarkInput] = []
        inputs.reserveCapacity(count)

        let asciiPrefix = String(repeating: "plain ascii prefix with no markdown markers ", count: 24)
        let asciiSuffix = String(repeating: " trailing ascii context ", count: 8)

        for index in 0..<count {
            let target: String
            switch index % 6 {
            case 0:
                target = "café inline plain text \(index)"
            case 1:
                target = "Unicode 世界 text with **bold \(index)**"
            case 2:
                target = "emoji 😀 text and `code \(index)`"
            case 3:
                target = "escaped \\*marker\\* with naïve word \(index)"
            case 4:
                target = "link [éxample \(index)](https://example.com)"
            default:
                target = "mixed résumé text with *italic \(index)*"
            }

            let source = asciiPrefix + target + asciiSuffix
            let rangeStart = source.index(source.startIndex, offsetBy: asciiPrefix.count)
            let rangeEnd = source.index(rangeStart, offsetBy: target.count)
            inputs.append(NonASCIIInlineRangeBenchmarkInput(source: source, range: rangeStart..<rangeEnd))
        }

        return inputs
    }

    private func makeParserStateInitializationBenchmark(count: Int) -> [ParserStateInitializationBenchmarkInput] {
        var inputs: [ParserStateInitializationBenchmarkInput] = []
        inputs.reserveCapacity(count)

        let asciiPrefix = String(repeating: "state init ascii prefix ", count: 18)
        let asciiSuffix = String(repeating: " suffix context ", count: 8)

        for index in 0..<count {
            let target: String
            switch index % 5 {
            case 0:
                target = "plain paragraph \(index) with ascii content"
            case 1:
                target = "café range \(index) with non-ascii text"
            case 2:
                target = "inline **bold \(index)** and `code`"
            case 3:
                target = "世界 range \(index) with [link](https://example.com)"
            default:
                target = "emoji 😀 range \(index) and escaped \\*marker\\*"
            }

            let source = asciiPrefix + target + asciiSuffix
            let rangeStart = source.index(source.startIndex, offsetBy: asciiPrefix.count)
            let rangeEnd = source.index(rangeStart, offsetBy: target.count)
            inputs.append(ParserStateInitializationBenchmarkInput(source: source, range: rangeStart..<rangeEnd))
        }

        return inputs
    }

    private func makeNonASCIIActiveInlineMarkerBenchmark(
        count: Int
    ) -> [(markdown: String, configuration: MarkdownConfiguration)] {
        var inputs: [(markdown: String, configuration: MarkdownConfiguration)] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 6 {
            case 0:
                inputs.append((
                    "café résumé naïve jalapeño \(index) " + String(repeating: "世界 ", count: 8),
                    .default
                ))
            case 1:
                inputs.append((
                    "こんにちは plain unicode text \(index) " + String(repeating: "emoji 😀 ", count: 8),
                    .default
                ))
            case 2:
                inputs.append(("plain non-ascii prefix \(index) before **bold**", .default))
            case 3:
                inputs.append(("emoji 😀 text \(index) before [link](https://example.com)", .default))
            case 4:
                inputs.append(("Mention @octocat with café issue #\(index)", .github))
            default:
                inputs.append((
                    "Repository apple/swift with résumé \(index) and emoji shortcode :tada:",
                    .github
                ))
            }
        }

        return inputs
    }

    private func makeTableRowPipeScanBenchmark(count: Int) -> [String] {
        var rows: [String] = []
        rows.reserveCapacity(count)

        for index in 0..<count {
            switch index % 8 {
            case 0:
                rows.append("| row \(index) | value | status |")
            case 1:
                rows.append("row \(index) | value | status")
            case 2:
                rows.append("plain paragraph row \(index) without separators")
            case 3:
                rows.append("Unicode café \(index) | **bold** | [link](https://example.com)")
            case 4:
                rows.append("emoji 😀 row \(index) without pipe")
            case 5:
                rows.append("tabs\t|\tvalue\t|\t\(index)")
            case 6:
                rows.append("long plain row \(index) with stable ASCII words and trailing spaces          ")
            default:
                rows.append("")
            }
        }

        return rows
    }

    private func makeTableRowLineScanBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 6 {
            case 0:
                inputs.append("| A \(index) | B |\n| - | - |\n| 1 | 2 |\nplain")
            case 1:
                inputs.append("A \(index) | B\n--- | ---\nrow | cell\nplain continuation")
            case 2:
                inputs.append("| Name | Value |\n| --- | ---: |\n| row \(index) | code |\n| next | value |\nplain")
            case 3:
                inputs.append("| A \(index) | B |\n| - | - |\nrow without pipe")
            case 4:
                inputs.append("| A \(index) | B |\n| - | - |\ntabs\t|\tvalue\nplain")
            default:
                inputs.append("| A \(index) | B |\n| - | - |\nrow \(index) | value | status\n")
            }
        }

        return inputs
    }

    private func makeTableFailedRowStateMoveBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 8 {
            case 0:
                inputs.append("| A \(index) | B |\n| - | - |\nplain paragraph \(index) without pipe")
            case 1:
                inputs.append("A \(index) | B\n--- | ---\nrow | cell\nplain continuation \(index)")
            case 2:
                inputs.append(
                    "| Name | Value |\n| --- | ---: |\n| row \(index) | code |\nlong plain row \(index) with no separator"
                )
            case 3:
                inputs.append("| A \(index) | B |\n| - | - |\nemoji 😀 paragraph \(index)")
            case 4:
                inputs.append("| A \(index) | B |\n| - | - |\ncafe\u{301} paragraph \(index)")
            case 5:
                inputs.append("| A \(index) | B |\n| - | - |\ntabs\twithout\tpipe \(index)")
            case 6:
                inputs.append("| A \(index) | B |\n| - | - |\n")
            default:
                inputs.append("| A \(index) | B |\n| - | - |\n| 1 | 2 |\n| 3 | 4 |\nplain \(index)")
            }
        }

        return inputs
    }

    private func tableRowPipeParseCanonicalForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let block = parseTableRowPipeForBenchmark(&state, optimized: optimized)
        let canonical: String
        if let block {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [block])
        } else {
            canonical = "nil"
        }
        return "\(canonical)|index:\(state.currentIndex)|line:\(state.line)|column:\(state.column)"
    }

    private func tableRowLineScanParseCanonicalForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let block = parseTableRowLineScanForBenchmark(&state, optimized: optimized)
        let canonical: String
        if let block {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [block])
        } else {
            canonical = "nil"
        }
        return "\(canonical)|index:\(state.currentIndex)|line:\(state.line)|column:\(state.column)"
    }

    private func tableRowLineScanParseChecksumForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        guard let block = parseTableRowLineScanForBenchmark(&state, optimized: optimized) else {
            return state.line + state.column
        }

        if case let .table(header, rows) = block {
            return header.count + rows.count + state.line + state.column
        }

        return state.line + state.column
    }

    private func tableFailedRowStateMoveCanonicalForBenchmark(
        _ markdown: String,
        deferred: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let block = parseTableFailedRowStateMoveForBenchmark(&state, deferred: deferred)
        let canonical: String
        if let block {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [block])
        } else {
            canonical = "nil"
        }
        return "\(canonical)|index:\(state.currentIndex)|line:\(state.line)|column:\(state.column)"
    }

    private func tableFailedRowStateMoveChecksumForBenchmark(
        _ markdown: String,
        deferred: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        guard let block = parseTableFailedRowStateMoveForBenchmark(&state, deferred: deferred) else {
            return state.line + state.column
        }

        if case let .table(header, rows) = block {
            return header.count + rows.count + state.line + state.column
        }

        return state.line + state.column
    }

    private func atxHeadingParseCanonicalForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let block = parseATXHeadingForBenchmark(&state, optimized: optimized)
        let canonical: String
        if let block {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [block])
        } else {
            canonical = "nil"
        }
        return "\(canonical)|index:\(state.currentIndex)|line:\(state.line)|column:\(state.column)"
    }

    private func atxHeadingParseChecksumForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        let block = parseATXHeadingForBenchmark(&state, optimized: optimized)
        return blockBenchmarkChecksum(block) + state.line + state.column
    }

    private func parseATXHeadingForBenchmark(
        _ state: inout ParserState,
        optimized: Bool
    ) -> MarkdownParser.BlockNode? {
        if optimized {
            return BlockParser.parseATXHeading(&state, configuration: .github)
        }
        return BlockParser.parseATXHeadingByCharacterScanningForTesting(&state, configuration: .github)
    }

    private func fencedCodeParseCanonicalForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let block = parseFencedCodeForBenchmark(&state, optimized: optimized)
        let canonical: String
        if let block {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [block])
        } else {
            canonical = "nil"
        }
        return "\(canonical)|index:\(state.currentIndex)|line:\(state.line)|column:\(state.column)"
    }

    private func fencedCodeParseChecksumForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        let block = parseFencedCodeForBenchmark(&state, optimized: optimized)
        return blockBenchmarkChecksum(block) + state.line + state.column
    }

    private func unicodeFencedCodeParseChecksumForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        let block = parseFencedCodeForBenchmark(&state, optimized: optimized)
        let offset = markdown.distance(from: markdown.startIndex, to: state.currentIndex)
        return blockBenchmarkChecksum(block) + offset + state.line + state.column
    }

    private func parseFencedCodeForBenchmark(
        _ state: inout ParserState,
        optimized: Bool
    ) -> MarkdownParser.BlockNode? {
        if optimized {
            return BlockParser.parseFencedCodeBlock(&state)
        }
        return BlockParser.parseFencedCodeBlockByCharacterScanningForTesting(&state)
    }

    private func fencedCodeStateMoveCanonicalForBenchmark(
        _ markdown: String,
        countedMove: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let block = parseFencedCodeStateMoveForBenchmark(&state, countedMove: countedMove)
        let canonical: String
        if let block {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [block])
        } else {
            canonical = "nil"
        }
        return "\(canonical)|index:\(state.currentIndex)|line:\(state.line)|column:\(state.column)"
    }

    private func fencedCodeStateMoveChecksumForBenchmark(
        _ markdown: String,
        countedMove: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        let block = parseFencedCodeStateMoveForBenchmark(&state, countedMove: countedMove)
        let offset = markdown.distance(from: markdown.startIndex, to: state.currentIndex)
        return blockBenchmarkChecksum(block) + offset + state.line + state.column
    }

    private func parseFencedCodeStateMoveForBenchmark(
        _ state: inout ParserState,
        countedMove: Bool
    ) -> MarkdownParser.BlockNode? {
        if countedMove {
            return BlockParser.parseFencedCodeBlock(&state)
        }
        return BlockParser.parseFencedCodeBlockByRescanningUTF8StateForTesting(&state)
    }

    private func horizontalRuleParseCanonicalForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let block = parseHorizontalRuleForBenchmark(&state, optimized: optimized)
        let canonical: String
        if let block {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [block])
        } else {
            canonical = "nil"
        }
        return "\(canonical)|index:\(state.currentIndex)|line:\(state.line)|column:\(state.column)"
    }

    private func horizontalRuleParseChecksumForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        let block = parseHorizontalRuleForBenchmark(&state, optimized: optimized)
        return blockBenchmarkChecksum(block) + state.line + state.column
    }

    private func parseHorizontalRuleForBenchmark(
        _ state: inout ParserState,
        optimized: Bool
    ) -> MarkdownParser.BlockNode? {
        if optimized {
            return BlockParser.parseHorizontalRule(&state)
        }
        return BlockParser.parseHorizontalRuleByCharacterScanningForTesting(&state)
    }

    private func horizontalRuleStateMoveCanonicalForBenchmark(
        _ markdown: String,
        countedStateMove: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let block = parseHorizontalRuleStateMoveForBenchmark(&state, countedStateMove: countedStateMove)
        let canonical: String
        if let block {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [block])
        } else {
            canonical = "nil"
        }
        return "\(canonical)|index:\(state.currentIndex)|line:\(state.line)|column:\(state.column)"
    }

    private func horizontalRuleStateMoveChecksumForBenchmark(
        _ markdown: String,
        countedStateMove: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        let block = parseHorizontalRuleStateMoveForBenchmark(&state, countedStateMove: countedStateMove)
        return blockBenchmarkChecksum(block) + state.line + state.column
    }

    private func parseHorizontalRuleStateMoveForBenchmark(
        _ state: inout ParserState,
        countedStateMove: Bool
    ) -> MarkdownParser.BlockNode? {
        if countedStateMove {
            return BlockParser.parseHorizontalRule(&state)
        }
        return BlockParser.parseHorizontalRuleByRescanningUTF8StateForTesting(&state)
    }

    private func indentedCodeParseCanonicalForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let block = parseIndentedCodeForBenchmark(&state, optimized: optimized)
        let canonical: String
        if let block {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [block])
        } else {
            canonical = "nil"
        }
        return "\(canonical)|index:\(state.currentIndex)|line:\(state.line)|column:\(state.column)"
    }

    private func indentedCodeParseChecksumForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        let block = parseIndentedCodeForBenchmark(&state, optimized: optimized)
        return blockBenchmarkChecksum(block) + state.line + state.column
    }

    private func indentedCodeStateMoveCanonicalForBenchmark(
        _ markdown: String,
        countedStateMove: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let block = parseIndentedCodeStateMoveForBenchmark(&state, countedStateMove: countedStateMove)
        let canonical: String
        if let block {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [block])
        } else {
            canonical = "nil"
        }
        return "\(canonical)|index:\(state.currentIndex)|line:\(state.line)|column:\(state.column)"
    }

    private func indentedCodeStateMoveChecksumForBenchmark(
        _ markdown: String,
        countedStateMove: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        let block = parseIndentedCodeStateMoveForBenchmark(&state, countedStateMove: countedStateMove)
        return blockBenchmarkChecksum(block) + state.line + state.column
    }

    private func parseIndentedCodeForBenchmark(
        _ state: inout ParserState,
        optimized: Bool
    ) -> MarkdownParser.BlockNode? {
        if optimized {
            return BlockParser.parseIndentedCodeBlock(&state)
        }
        return BlockParser.parseIndentedCodeBlockByCharacterScanningForTesting(&state)
    }

    private func parseIndentedCodeStateMoveForBenchmark(
        _ state: inout ParserState,
        countedStateMove: Bool
    ) -> MarkdownParser.BlockNode? {
        if countedStateMove {
            return BlockParser.parseIndentedCodeBlock(&state)
        }
        return BlockParser.parseIndentedCodeBlockByRescanningUTF8StateForTesting(&state)
    }

    private func parseNonASCIIInlineRangeForBenchmark(
        _ input: NonASCIIInlineRangeBenchmarkInput,
        repeatFullScan: Bool
    ) -> [MarkdownParser.InlineNode] {
        var state = ParserState(
            text: input.source,
            currentIndex: input.range.lowerBound,
            endIndex: input.range.upperBound
        )
        if repeatFullScan {
            state.repeatFullTextASCIIEligibilityScanForTesting()
        }
        return InlineParser.parseInlineElements(&state, configuration: .default)
    }

    private func parserStateInitializationChecksum(
        _ input: ParserStateInitializationBenchmarkInput,
        eagerFragmentReserve: Bool
    ) -> (semantic: Int, reserveWork: Int) {
        var reserveWork = 0
        if eagerFragmentReserve {
            var fullScratch = String()
            let fullReserve = min(input.source.count, 1024)
            fullScratch.reserveCapacity(fullReserve)
            fullScratch.append("x")

            var rangeScratch = String()
            let rangeReserve = min(
                input.source.utf8.distance(from: input.range.lowerBound, to: input.range.upperBound),
                1024
            )
            rangeScratch.reserveCapacity(rangeReserve)
            rangeScratch.append("x")

            reserveWork = fullReserve +
                rangeReserve +
                fullScratch.utf8.count +
                rangeScratch.utf8.count
        }

        let fullState = ParserState(text: input.source)
        let rangeState = ParserState(
            text: input.source,
            currentIndex: input.range.lowerBound,
            endIndex: input.range.upperBound
        )

        let semantic = fullState.line +
            fullState.column +
            rangeState.line +
            rangeState.column +
            (fullState.currentIndex == input.source.startIndex ? 1 : 0) +
            (rangeState.currentIndex == input.range.lowerBound ? 1 : 0)

        return (semantic, reserveWork)
    }

    private func activeInlineMarkerScanChecksumForBenchmark(
        _ input: (markdown: String, configuration: MarkdownConfiguration),
        optimized: Bool
    ) -> Int {
        let state = ParserState(text: input.markdown)
        let hasMarker: Bool
        if optimized {
            hasMarker = InlineParser.containsActiveInlineMarkerForTesting(state, configuration: input.configuration)
        } else {
            hasMarker = InlineParser.containsActiveInlineMarkerByCharacterScanningForTesting(
                state,
                configuration: input.configuration
            )
        }

        return (hasMarker ? 7 : 11) + state.line + state.column
    }

    private func parseTableRowPipeForBenchmark(
        _ state: inout ParserState,
        optimized: Bool
    ) -> MarkdownParser.BlockNode? {
        if optimized {
            return BlockParser.parseTableUsingStartProbeForTesting(&state, configuration: .github)
        }
        return BlockParser.parseTableByCheckingRowsWithSubstringContainsForTesting(&state, configuration: .github)
    }

    private func parseTableRowLineScanForBenchmark(
        _ state: inout ParserState,
        optimized: Bool
    ) -> MarkdownParser.BlockNode? {
        if optimized {
            return BlockParser.parseTableUsingStartProbeForTesting(&state, configuration: .github)
        }
        return BlockParser.parseTableBySeparateRowLineAndPipeScansForTesting(&state, configuration: .github)
    }

    private func parseTableFailedRowStateMoveForBenchmark(
        _ state: inout ParserState,
        deferred: Bool
    ) -> MarkdownParser.BlockNode? {
        if deferred {
            return BlockParser.parseTableUsingStartProbeForTesting(&state, configuration: .github)
        }
        return BlockParser.parseTableByEagerFailedRowStateMoveForTesting(&state, configuration: .github)
    }

    private func setextParseCanonicalForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let block = parseSetextForBenchmark(&state, optimized: optimized)
        let canonical: String
        if let block {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [block])
        } else {
            canonical = "nil"
        }
        return "\(canonical)|index:\(state.currentIndex)|line:\(state.line)|column:\(state.column)"
    }

    private func setextParseChecksumForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        guard let block = parseSetextForBenchmark(&state, optimized: optimized) else {
            return state.line + state.column
        }

        if case let .heading(level, children, id) = block {
            return level + children.count + (id?.count ?? 0) + state.line + state.column
        }

        return state.line + state.column
    }

    private func setextProbeHeadingTrimCanonicalForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let block = parseSetextProbeHeadingTrimForBenchmark(&state, optimized: optimized)
        let canonical: String
        if let block {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [block])
        } else {
            canonical = "nil"
        }
        return "\(canonical)|index:\(state.currentIndex)|line:\(state.line)|column:\(state.column)"
    }

    private func setextProbeHeadingTrimChecksumForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        guard let block = parseSetextProbeHeadingTrimForBenchmark(&state, optimized: optimized) else {
            return state.line + state.column
        }

        if case let .heading(level, children, id) = block {
            return level + children.count + (id?.count ?? 0) + state.line + state.column
        }

        return state.line + state.column
    }

    private func parseSetextForBenchmark(
        _ state: inout ParserState,
        optimized: Bool
    ) -> MarkdownParser.BlockNode? {
        if optimized {
            return BlockParser.parseSetextHeadingUsingProbeForTesting(&state, configuration: .github)
        }

        let originalState = state
        _ = BlockParser.shouldAttemptSetextHeadingForTesting(originalState)

        var rescanState = originalState
        let block = BlockParser.parseSetextHeadingByRescanningLinesForTesting(&rescanState, configuration: .github)
        state = rescanState
        return block
    }

    private func parseSetextProbeHeadingTrimForBenchmark(
        _ state: inout ParserState,
        optimized: Bool
    ) -> MarkdownParser.BlockNode? {
        if optimized {
            return BlockParser.parseSetextHeadingUsingProbeForTesting(&state, configuration: .github)
        }

        return BlockParser.parseSetextHeadingUsingProbeWithTrimRescanForTesting(
            &state,
            configuration: .github
        )
    }

    private func whitespaceRangeHelperChecksum(_ input: String, fastPath: Bool) -> Int {
        let range = input.startIndex..<input.endIndex

        let containsNonWhitespace: Bool
        let leadingRange: Range<String.Index>
        let trailingRange: Range<String.Index>

        if fastPath {
            containsNonWhitespace = BlockParser.rangeContainsNonWhitespaceForTesting(in: input, range: range)
            leadingRange = BlockParser.leadingWhitespaceTrimmedRangeForTesting(in: input, range: range)
            trailingRange = BlockParser.trailingWhitespaceTrimmedRangeForTesting(in: input, range: range)
        } else {
            containsNonWhitespace = BlockParser.rangeContainsNonWhitespaceByCharacterScanningForTesting(
                in: input,
                range: range
            )
            leadingRange = BlockParser.leadingWhitespaceTrimmedRangeByCharacterScanningForTesting(
                in: input,
                range: range
            )
            trailingRange = BlockParser.trailingWhitespaceTrimmedRangeByCharacterScanningForTesting(
                in: input,
                range: range
            )
        }

        var checksum = containsNonWhitespace ? 1 : 2
        checksum += leadingRange.lowerBound == input.startIndex ? 3 : 5
        checksum += leadingRange.upperBound == input.endIndex ? 7 : 11
        checksum += trailingRange.lowerBound == input.startIndex ? 13 : 17
        checksum += trailingRange.upperBound == input.endIndex ? 19 : 23
        return checksum
    }

    private func offsets(_ range: Range<String.Index>, in input: String) -> [Int] {
        [
            input.distance(from: input.startIndex, to: range.lowerBound),
            input.distance(from: input.startIndex, to: range.upperBound)
        ]
    }

    private func makeASCIIFootnoteForParsingBenchmark(lineCount: Int) -> String {
        var markdown = "[^bench]: first line with plain words and a benchmark value\n"
        markdown.reserveCapacity(lineCount * 58)

        for line in 0..<lineCount {
            markdown += "    continuation \(line) with plain words and stable ASCII text\n"
        }

        return markdown
    }

    private func parseFootnoteForBenchmark(
        _ markdown: String,
        copying: Bool
    ) -> MarkdownParser.BlockNode? {
        var state = ParserState(text: markdown)
        if copying {
            return BlockParser.parseFootnoteDefinitionByCopyingLinesForTesting(&state, configuration: .default)
        }
        return BlockParser.parseFootnoteDefinition(&state, configuration: .default)
    }

    private func parsePlainFootnoteParagraphForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> MarkdownParser.BlockNode? {
        var state = ParserState(text: markdown)
        if optimized {
            return BlockParser.parseFootnoteDefinition(&state, configuration: .default)
        }
        return BlockParser.parseFootnoteDefinitionByJoiningSingleParagraphForTesting(
            &state,
            configuration: .default
        )
    }

    private func makeSingleLineFootnoteBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 8 {
            case 0:
                inputs.append("[^note-\(index)]: plain footnote content with stable ASCII words")
            case 1:
                inputs.append("[^note-\(index)]: **bold \(index)** and *italic* text")
            case 2:
                inputs.append("[^note-\(index)]: [link](https://example.com/\(index)) and `code`")
            case 3:
                inputs.append("[^note-\(index)]: repo apple/swift#\(index) and @octocat")
            case 4:
                inputs.append("[^note-\(index)]: Unicode café \(index) with emoji :tada:")
            case 5:
                inputs.append("[^note-\(index)]: escaped \\*marker\\* and plain text")
            case 6:
                inputs.append("[^note-\(index)]:  leading and trailing \(index)   ")
            default:
                inputs.append("[^note-\(index)]: <https://example.com/\(index)>")
            }
        }

        return inputs
    }

    private func parseSingleLineFootnoteForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> MarkdownParser.BlockNode? {
        var state = ParserState(text: markdown)
        if optimized {
            return BlockParser.parseFootnoteDefinition(&state, configuration: .github)
        }
        return BlockParser.parseFootnoteDefinitionByJoiningSingleParagraphForTesting(
            &state,
            configuration: .github
        )
    }

    private func makeASCIIListItemContentForParsingBenchmark(lineCount: Int) -> String {
        var markdown = "first line with plain words and a benchmark value\n"
        markdown.reserveCapacity(lineCount * 60)

        for line in 0..<lineCount {
            markdown += "  continuation \(line) with plain words and stable ASCII text\n"
        }

        return markdown
    }

    private func parseListItemContentForBenchmark(
        _ markdown: String,
        copying: Bool
    ) -> MarkdownParser.ListItem {
        var state = ParserState(text: markdown)
        if copying {
            return BlockParser.parseListItemContentByCopyingLinesForTesting(
                &state,
                indent: 0,
                marker: "-",
                configuration: .default
            )
        }
        return BlockParser.parseListItemContent(&state, indent: 0, marker: "-", configuration: .default)
    }

    private func parsePlainListItemParagraphForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> MarkdownParser.ListItem {
        var state = ParserState(text: markdown)
        if optimized {
            return BlockParser.parseListItemContent(&state, indent: 0, marker: "-", configuration: .default)
        }
        return BlockParser.parseListItemContentByJoiningSingleParagraphForTesting(
            &state,
            indent: 0,
            marker: "-",
            configuration: .default
        )
    }

    private func plainContainerParagraphChecksum(
        blockquote: String,
        listItem: String,
        footnote: String,
        optimized: Bool
    ) -> Int {
        let blockquoteMode: BlockquoteBenchmarkMode = optimized
            ? .paragraphFastPath
            : .paragraphFastPathJoiningSingleRanges
        return blockBenchmarkChecksum(parseBlockquoteForBenchmark(blockquote, mode: blockquoteMode)) +
            listItemBenchmarkChecksum(parsePlainListItemParagraphForBenchmark(listItem, optimized: optimized)) +
            blockBenchmarkChecksum(parsePlainFootnoteParagraphForBenchmark(footnote, optimized: optimized))
    }

    private func makeNonBlankPlainParagraphRangeBenchmark(
        lineCount: Int
    ) -> (source: String, ranges: [Range<String.Index>], reservedUTF8Count: Int) {
        var source = ""
        source.reserveCapacity(lineCount * 64)
        for line in 0..<lineCount {
            if line == 0 {
                source += "  leading line \(line) with stable plain ASCII words\n"
            } else if line == lineCount - 1 {
                source += "trailing line \(line) with stable plain ASCII words   \n"
            } else {
                source += "middle line \(line) with stable plain ASCII words\n"
            }
        }

        let ranges = lineRanges(in: source)
        let reservedUTF8Count = ranges.reduce(0) { partial, range in
            guard let lower = range.lowerBound.samePosition(in: source.utf8),
                  let upper = range.upperBound.samePosition(in: source.utf8) else {
                return partial + source[range].utf8.count
            }
            return partial + source.utf8.distance(from: lower, to: upper)
        }
        return (source, ranges, reservedUTF8Count)
    }

    private func makeJoinedTrimmedContentBenchmark(
        lineCount: Int
    ) -> (source: String, ranges: [Range<String.Index>], reservedUTF8Count: Int) {
        var source = ""
        source.reserveCapacity(lineCount * 72)
        source += "   \n\n"

        for line in 0..<lineCount {
            switch line % 7 {
            case 0:
                source += "  **bold \(line)** and *italic* text with [link](https://example.com/\(line))\n"
            case 1:
                source += "plain middle line \(line) with `code` and stable ASCII words\n"
            case 2:
                source += "\n"
            case 3:
                source += "  trailing spaces line \(line) with words   \n"
            case 4:
                source += "    indented-ish paragraph line \(line) should stay as content\n"
            case 5:
                source += "[ref \(line)](https://example.com/docs/\(line)) plus text\n"
            default:
                source += "last-ish content \(line) before another paragraph marker\n"
            }
        }

        source += "   \n\n"
        let ranges = lineRangesExcludingTrailingNewlines(in: source)
        return (source, ranges, reservedUTF8CountForRanges(ranges, in: source))
    }

    private func lineRanges(in source: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var lineStart = source.startIndex
        var index = source.startIndex

        while index < source.endIndex {
            if source[index] == "\n" {
                if lineStart < index {
                    ranges.append(lineStart..<index)
                }
                lineStart = source.index(after: index)
            }
            index = source.index(after: index)
        }

        if lineStart < source.endIndex {
            ranges.append(lineStart..<source.endIndex)
        }
        return ranges
    }

    private func reservedUTF8CountForRanges(
        _ ranges: [Range<String.Index>],
        in source: String
    ) -> Int {
        ranges.reduce(0) { partial, range in
            guard let lower = range.lowerBound.samePosition(in: source.utf8),
                  let upper = range.upperBound.samePosition(in: source.utf8) else {
                return partial + source[range].utf8.count
            }
            return partial + source.utf8.distance(from: lower, to: upper)
        }
    }

    private func joinedTrimmedContentForBenchmark(
        source: String,
        ranges: [Range<String.Index>],
        reservedUTF8Count: Int,
        materializeRanges: Bool
    ) -> String {
        BlockParser.joinedTrimmedContentForTesting(
            from: ranges,
            in: source,
            reservedUTF8Count: reservedUTF8Count,
            materializeRanges: materializeRanges
        )
    }

    private func joinedTrimmedContentChecksumForBenchmark(
        source: String,
        ranges: [Range<String.Index>],
        reservedUTF8Count: Int,
        materializeRanges: Bool
    ) -> Int {
        let content = joinedTrimmedContentForBenchmark(
            source: source,
            ranges: ranges,
            reservedUTF8Count: reservedUTF8Count,
            materializeRanges: materializeRanges
        )
        return content.utf8.count +
            Int(content.utf8.first ?? 0) +
            Int(content.utf8.last ?? 0)
    }

    private func plainTextParagraphHelperChecksum(
        source: String,
        ranges: [Range<String.Index>],
        reservedUTF8Count: Int,
        optimized: Bool
    ) -> Int {
        let inlines: [MarkdownParser.InlineNode]?
        if optimized {
            inlines = BlockParser.plainTextParagraphInlinesFromNonBlankSourceRangesForTesting(
                from: ranges,
                in: source,
                reservedUTF8Count: reservedUTF8Count,
                configuration: .default
            )
        } else {
            inlines = BlockParser.plainTextParagraphInlinesFromSourceRangesForTesting(
                from: ranges,
                in: source,
                reservedUTF8Count: reservedUTF8Count,
                configuration: .default
            )
        }
        return inlineNodesBenchmarkChecksum(inlines ?? [])
    }

    private func parseListForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> MarkdownParser.BlockNode? {
        var state = ParserState(text: markdown)
        if optimized {
            return BlockParser.parseList(&state, configuration: .github)
        }
        return BlockParser.parseListByCharacterMarkerParsingForTesting(&state, configuration: .github)
    }

    private func parseListIndentForBenchmark(
        _ markdown: String,
        utf8Indent: Bool
    ) -> MarkdownParser.BlockNode? {
        var state = ParserState(text: markdown)
        if utf8Indent {
            return BlockParser.parseList(&state, configuration: .github)
        }
        return BlockParser.parseListByCharacterIndentScanningForTesting(&state, configuration: .github)
    }

    private func parseListMarkerSignatureForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> String? {
        var state = ParserState(text: markdown)
        return BlockParser.parseListMarkerSignatureForTesting(
            &state,
            useASCIIListMarkerFastPath: optimized
        )
    }

    private func parseListMarkerMoveSignatureForBenchmark(
        _ markdown: String,
        countedMove: Bool
    ) -> String? {
        var state = ParserState(text: markdown)
        return BlockParser.parseListMarkerSignatureForTesting(
            &state,
            useASCIIListMarkerFastPath: true,
            useCountedASCIIListMarkerMove: countedMove
        )
    }

    private func parseListMarkerMoveCanonicalForBenchmark(
        _ markdown: String,
        countedMove: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let block = countedMove
            ? BlockParser.parseList(&state, configuration: .github)
            : BlockParser.parseListByRecountingASCIIListMarkerMoveForTesting(&state, configuration: .github)
        let description = block.map { ParserCanonicalSnapshot.canonicalDescription(for: [$0]) } ?? "nil"
        let offset = markdown.utf8.distance(from: markdown.utf8.startIndex, to: state.currentIndex)
        return "\(description)|\(offset)|\(state.line)|\(state.column)"
    }

    private func parseIndentedListMarkerSignatureForBenchmark(
        _ markdown: String,
        utf8Indent: Bool
    ) -> String? {
        var state = ParserState(text: markdown)
        return BlockParser.parseIndentedListMarkerSignatureForTesting(
            &state,
            limit: 3,
            useASCIIListIndentFastPath: utf8Indent
        )
    }

    private func makeASCIIListMarkerBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 6 {
            case 0:
                inputs.append("- item \(index)")
            case 1:
                inputs.append("* item \(index)")
            case 2:
                inputs.append("+ item \(index)")
            case 3:
                inputs.append("\(index % 1_000). ordered \(index)")
            case 4:
                inputs.append("\(index % 1_000)) ordered \(index)")
            default:
                inputs.append("- task-like [ ] item \(index)")
            }
        }

        return inputs
    }

    private func makeASCIIListMarkerMoveBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 6 {
            case 0:
                inputs.append("- item \(index)")
            case 1:
                inputs.append("* item \(index)")
            case 2:
                inputs.append("+ item \(index)")
            case 3:
                inputs.append("\(100_000_000 + index). ordered \(index)")
            case 4:
                inputs.append("\(100_000_000 + index)) ordered \(index)")
            default:
                inputs.append("123456789. stable ordered \(index)")
            }
        }

        return inputs
    }

    private func makeASCIIListMarkerIndentBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 8 {
            case 0:
                inputs.append("- item \(index)")
            case 1:
                inputs.append(" - item \(index)")
            case 2:
                inputs.append("  * item \(index)")
            case 3:
                inputs.append("   + item \(index)")
            case 4:
                inputs.append(" \(index % 1_000). ordered \(index)")
            case 5:
                inputs.append("  \(index % 1_000)) ordered \(index)")
            case 6:
                inputs.append("   - task-like [ ] item \(index)")
            default:
                inputs.append("   9. final ordered \(index)")
            }
        }

        return inputs
    }

    private func makeSingleLineListItemContentBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 8 {
            case 0:
                inputs.append("plain list item \(index) with stable ASCII words")
            case 1:
                inputs.append("**bold \(index)** and *italic* text")
            case 2:
                inputs.append("[x] completed task \(index) with `code`")
            case 3:
                inputs.append("[ ] pending task \(index) with [link](https://example.com)")
            case 4:
                inputs.append("# literal heading \(index)")
            case 5:
                inputs.append("  leading and trailing \(index)   ")
            case 6:
                inputs.append("repo apple/swift#\(index) and @octocat")
            default:
                inputs.append("Unicode café \(index) with emoji :tada:")
            }
        }

        return inputs
    }

    private func makeSingleLineNestedListItemContentBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 7 {
            case 0:
                inputs.append("- nested list item \(index)")
            case 1:
                inputs.append("1. ordered nested item \(index)")
            case 2:
                inputs.append("> nested quote \(index)")
            case 3:
                inputs.append("---")
            case 4:
                inputs.append("```swift")
            case 5:
                inputs.append("# literal heading \(index)")
            default:
                inputs.append("Unicode café paragraph \(index)")
            }
        }

        return inputs
    }

    private func parseSingleLineListItemForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> MarkdownParser.ListItem {
        var state = ParserState(text: markdown)
        if optimized {
            return BlockParser.parseListItemContent(&state, indent: 0, marker: "-", configuration: .github)
        }
        return BlockParser.parseListItemContentByJoiningSingleParagraphForTesting(
            &state,
            indent: 0,
            marker: "-",
            configuration: .github
        )
    }

    private func parseSingleLineListItemRangeReuseForBenchmark(
        _ markdown: String,
        reuseSingleTrimmedRange: Bool
    ) -> MarkdownParser.ListItem {
        var state = ParserState(text: markdown)
        if reuseSingleTrimmedRange {
            return BlockParser.parseListItemContent(&state, indent: 0, marker: "-", configuration: .github)
        }
        return BlockParser.parseListItemContentByRecomputingSingleTrimmedRangeForTesting(
            &state,
            indent: 0,
            marker: "-",
            configuration: .github
        )
    }

    private func makeTaskMarkerBytePeekBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 8 {
            case 0:
                inputs.append("[x] done \(index)")
            case 1:
                inputs.append("[X] uppercase \(index)")
            case 2:
                inputs.append("[ ] todo \(index)")
            case 3:
                inputs.append("[o] malformed \(index)")
            case 4:
                inputs.append("[x]missing trailing space \(index)")
            case 5:
                inputs.append("[ ] café \(index)")
            case 6:
                inputs.append("plain item \(index)")
            default:
                inputs.append("[ ] ")
            }
        }

        return inputs
    }

    private func makeListItemContinuationPrefixBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 6 {
            case 0:
                inputs.append(
                    """
                    first line \(index)
                      continuation \(index) with stable ASCII text
                      final continuation \(index)
                    """
                )
            case 1:
                inputs.append(
                    """
                    [x] completed \(index)
                      continuation \(index) with `code`
                      trailing continuation \(index)
                    """
                )
            case 2:
                inputs.append(
                    """
                    first line \(index)
                        over-indented continuation \(index)
                      normal continuation \(index)
                    """
                )
            case 3:
                inputs.append(
                    """
                    first line \(index)
                      - nested list item \(index)
                    """
                )
            case 4:
                inputs.append(
                    """
                    first line \(index)
                      1. ordered nested item \(index)
                    """
                )
            default:
                inputs.append(
                    """
                    first line \(index)
                      continuation \(index) with [link](https://example.com/\(index))
                      continuation \(index) with **bold**
                    """
                )
            }
        }

        return inputs
    }

    private func parseTaskMarkerListItemForBenchmark(
        _ markdown: String,
        utf8TaskMarker: Bool
    ) -> (item: MarkdownParser.ListItem, offset: Int, line: Int, column: Int) {
        var state = ParserState(text: markdown)
        let item: MarkdownParser.ListItem
        if utf8TaskMarker {
            item = BlockParser.parseListItemContent(&state, indent: 0, marker: "-", configuration: .github)
        } else {
            item = BlockParser.parseListItemContentByPeekingTaskMarkerForTesting(
                &state,
                indent: 0,
                marker: "-",
                configuration: .github
            )
        }

        let offset = markdown.utf8.distance(from: markdown.utf8.startIndex, to: state.currentIndex)
        return (item, offset, state.line, state.column)
    }

    private func parseListItemContinuationPrefixForBenchmark(
        _ markdown: String,
        utf8Prefix: Bool
    ) -> (item: MarkdownParser.ListItem, offset: Int, line: Int, column: Int) {
        var state = ParserState(text: markdown)
        let item: MarkdownParser.ListItem
        if utf8Prefix {
            item = BlockParser.parseListItemContent(&state, indent: 0, marker: "-", configuration: .github)
        } else {
            item = BlockParser.parseListItemContentByCharacterContinuationPrefixForTesting(
                &state,
                indent: 0,
                marker: "-",
                configuration: .github
            )
        }

        let offset = markdown.utf8.distance(from: markdown.utf8.startIndex, to: state.currentIndex)
        return (item, offset, state.line, state.column)
    }

    private func listItemBenchmarkChecksum(_ item: MarkdownParser.ListItem) -> Int {
        item.marker.utf8.count +
            (item.isTask ? 3 : 5) +
            (item.isChecked == true ? 7 : 11) +
            item.content.reduce(0) { $0 + blockBenchmarkChecksum($1) }
    }

    private func blockBenchmarkChecksum(_ node: MarkdownParser.BlockNode?) -> Int {
        guard let node else {
            return 0
        }

        switch node {
        case .heading(let level, let children, let id):
            return level + (id?.utf8.count ?? 0) + children.reduce(0) { $0 + inlineNodeBenchmarkChecksum($1) }
        case .paragraph(let children):
            return 1 + children.reduce(0) { $0 + inlineNodeBenchmarkChecksum($1) }
        case .blockquote(let children):
            return 2 + children.reduce(0) { $0 + blockBenchmarkChecksum($1) }
        case .codeBlock(let language, let content):
            return 3 + (language?.utf8.count ?? 0) + content.utf8.count
        case .list(let ordered, let tight, let items):
            return (ordered ? 5 : 7) + (tight ? 11 : 13) + items.reduce(0) { partial, item in
                partial + item.marker.utf8.count + item.content.reduce(0) { $0 + blockBenchmarkChecksum($1) }
            }
        case .taskList(let items):
            return 17 + items.reduce(0) { partial, item in
                partial + (item.isChecked ? 1 : 0) + item.content.reduce(0) { $0 + inlineNodeBenchmarkChecksum($1) }
            }
        case .table(let header, let rows):
            let headerChecksum = header.reduce(0) { $0 + tableCellBenchmarkChecksum($1) }
            let rowChecksum = rows.flatMap { $0 }.reduce(0) { $0 + tableCellBenchmarkChecksum($1) }
            return 19 + headerChecksum + rowChecksum
        case .horizontalRule:
            return 23
        case .html(let content):
            return 29 + content.utf8.count
        case .footnoteDefinition(let label, let children):
            return 31 + label.utf8.count + children.reduce(0) { $0 + blockBenchmarkChecksum($1) }
        }
    }

    private func tableCellBenchmarkChecksum(_ cell: MarkdownParser.TableCell) -> Int {
        let alignmentValue: Int
        switch cell.alignment {
        case .left: alignmentValue = 1
        case .center: alignmentValue = 2
        case .right: alignmentValue = 3
        case .none: alignmentValue = 4
        }
        return alignmentValue + cell.content.reduce(0) { $0 + inlineNodeBenchmarkChecksum($1) }
    }

    private func lineRangesExcludingTrailingNewlines(in source: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var lineStart = source.startIndex
        var index = source.startIndex

        while index < source.endIndex {
            if source[index] == "\n" {
                ranges.append(lineStart..<index)
                lineStart = source.index(after: index)
            }
            index = source.index(after: index)
        }

        ranges.append(lineStart..<source.endIndex)
        return ranges
    }

    private func makeASCIILinksForParsingBenchmark(linkCount: Int) -> [String] {
        var links: [String] = []
        links.reserveCapacity(linkCount)

        for index in 0..<linkCount {
            links.append(
                "[**Guide \(index)** and *topic \(index % 17)*](https://example.com/docs/\(index)?ref=glimmer \"Title \(index)\")"
            )
        }

        return links
    }

    private func makeASCIILinksForBracketedTextMoveBenchmark(linkCount: Int) -> [String] {
        var links: [String] = []
        links.reserveCapacity(linkCount)

        for index in 0..<linkCount {
            links.append(
                "[Glimmer parser performance guide \(index) with inline markers **bold** and `code`]" +
                "(https://example.com/docs/\(index)?ref=glimmer \"Title \(index)\")"
            )
        }

        return links
    }

    private func makeUnicodeSimpleBracketedLinksForParsingBenchmark(linkCount: Int) -> [String] {
        var links: [String] = []
        links.reserveCapacity(linkCount)

        for index in 0..<linkCount {
            switch index % 6 {
            case 0:
                links.append("[Glimmer café guide \(index)](https://example.com/docs/\(index))")
            case 1:
                links.append("[こんにちは parser \(index)](https://example.com/docs/\(index) \"Title \(index)\")")
            case 2:
                links.append("[Résumé parser guide \(index)](https://example.com/docs/\(index))")
            case 3:
                links.append("[Emoji ✅ performance \(index)](https://example.com/docs/\(index))")
            case 4:
                links.append("[Mixed ASCII and 世界 \(index)](https://example.com/docs/\(index))")
            default:
                links.append("[naïve jalapeño parser \(index)](https://example.com/docs/\(index))")
            }
        }

        return links
    }

    private func makeNestedEscapedBracketedLinksForParsingBenchmark(linkCount: Int) -> [String] {
        var links: [String] = []
        links.reserveCapacity(linkCount)

        for index in 0..<linkCount {
            switch index % 5 {
            case 0:
                links.append("[Guide [parser \(index)] details](https://example.com/docs/\(index))")
            case 1:
                links.append(#"[Escaped \[brackets \] guide \#(index)](https://example.com/docs/\#(index))"#)
            case 2:
                links.append("[Deep [one [two \(index)]] label](https://example.com/docs/\(index) \"Title \(index)\")")
            case 3:
                links.append(#"[Backslash \\ and escaped \] closer \#(index)](https://example.com/docs/\#(index))"#)
            default:
                links.append("[Line one \(index)\nline two [nested \(index % 19)]](https://example.com/docs/\(index))")
            }
        }

        return links
    }

    private func makeASCIIAutolinksForMoveBenchmark(count: Int) -> [String] {
        var links: [String] = []
        links.reserveCapacity(count)

        for index in 0..<count {
            switch index % 8 {
            case 0:
                links.append("https://example.com/docs/\(index)?ref=glimmer")
            case 1:
                links.append("https://example.com/docs/\(index),")
            case 2:
                links.append("http://example.com/a(\(index)))")
            case 3:
                links.append("www.example.com/path/\(index)")
            case 4:
                links.append("mailto:octocat\(index)@example.com")
            case 5:
                links.append("ftp://example.com/file-\(index).txt")
            case 6:
                links.append("<https://example.com/docs/\(index)>")
            default:
                links.append("<octocat\(index)@example.com>")
            }
        }

        return links
    }

    private func makeUnresolvedReferenceLinksForParsingBenchmark(linkCount: Int) -> [String] {
        var links: [String] = []
        links.reserveCapacity(linkCount)

        for index in 0..<linkCount {
            switch index % 5 {
            case 0:
                links.append("[label-\(index)][reference-\(index)-with-long-unused-label]")
            case 1:
                links.append("[outer [inner \(index)]][reference-\(index)]")
            case 2:
                links.append("[café \(index)][référence-\(index)-unused]")
            case 3:
                links.append("[label-\(index)][]")
            default:
                links.append("[label-\(index)][unterminated-reference-\(index)")
            }
        }

        return links
    }

    private func makeInlineFootnoteReferenceMoveBenchmark(count: Int) -> [String] {
        var references: [String] = []
        references.reserveCapacity(count)

        for index in 0..<count {
            switch index % 7 {
            case 0:
                references.append("[^\(index)]")
            case 1:
                references.append("[^long-ascii-label-\(index)]")
            case 2:
                references.append("[^label_with_underscore_\(index)]")
            case 3:
                references.append("[^mix-\(index)-A9]")
            case 4:
                references.append("[^]")
            case 5:
                references.append("[^unclosed-\(index)")
            default:
                references.append("[^line-\(index)\n]")
            }
        }

        return references
    }

    private func makeBareASCIIAutolinksForSchemeBenchmark(count: Int) -> [String] {
        var links: [String] = []
        links.reserveCapacity(count)

        for index in 0..<count {
            switch index % 6 {
            case 0:
                links.append("https://example.com/docs/\(index)?ref=glimmer")
            case 1:
                links.append("http://example.com/a(\(index)))")
            case 2:
                links.append("www.example.com/path/\(index)")
            case 3:
                links.append("mailto:octocat\(index)@example.com")
            case 4:
                links.append("ftp://example.com/file-\(index).txt")
            default:
                links.append("plain-text-\(index)")
            }
        }

        return links
    }

    private func makeASCIIAutolinksForTailTrimBenchmark(count: Int) -> [String] {
        var links: [String] = []
        links.reserveCapacity(count)

        for index in 0..<count {
            switch index % 8 {
            case 0:
                links.append("https://example.com/docs/\(index)?ref=glimmer.")
            case 1:
                links.append("https://example.com/docs/\(index).,;:?!")
            case 2:
                links.append("http://example.com/a(\(index)))")
            case 3:
                links.append("www.example.com/a[\(index)]]")
            case 4:
                links.append("mailto:octocat\(index)@example.com;")
            case 5:
                links.append("<https://example.com/docs/\(index).>")
            case 6:
                links.append("https://example.com/docs/\(index)?ref=glimmer")
            default:
                links.append("https://example.com/cafe-\(index).")
            }
        }

        return links
    }

    private func makeRejectedAngleAutolinksForCopyBenchmark(count: Int) -> [String] {
        var links: [String] = []
        links.reserveCapacity(count)

        for index in 0..<count {
            switch index % 8 {
            case 0:
                links.append("<span>")
            case 1:
                links.append("</span>")
            case 2:
                links.append("<br>")
            case 3:
                links.append("<custom-tag-\(index)>")
            case 4:
                links.append("<h\(index % 6 + 1)>")
            case 5:
                links.append("<em>")
            case 6:
                links.append("<img/>")
            default:
                links.append("<invalid-\(index)>")
            }
        }

        return links
    }

    private func makeASCIIInlineCodeTrimBenchmark(count: Int) -> [String] {
        var codes: [String] = []
        codes.reserveCapacity(count)

        for index in 0..<count {
            switch index % 7 {
            case 0:
                codes.append("`inline code \(index)`")
            case 1:
                codes.append("`   padded code \(index)   `")
            case 2:
                codes.append("`\tTabbed code \(index)\t`")
            case 3:
                codes.append("`` code with ` nested tick \(index) ``")
            case 4:
                codes.append("` code line \(index)\n`")
            case 5:
                codes.append("`     `")
            default:
                codes.append("`unclosed code \(index)")
            }
        }

        return codes
    }

    private func makeFailedASCIIInlineCodeSpanBenchmark(documentCount: Int, runCount: Int) -> [String] {
        var documents: [String] = []
        documents.reserveCapacity(documentCount)

        for documentIndex in 0..<documentCount {
            var markdown = "prefix \(documentIndex) "
            markdown.reserveCapacity(runCount * (runCount + 32))

            for runLength in 1...runCount {
                markdown += String(repeating: "`", count: runLength)
                markdown += " unmatched-\(documentIndex)-\(runLength) "
            }

            markdown += "tail \(documentIndex)"
            documents.append(markdown)
        }

        return documents
    }

    private func makeHTMLTagAttributeScanBenchmark(count: Int) -> [String] {
        var tags: [String] = []
        tags.reserveCapacity(count)

        for index in 0..<count {
            switch index % 8 {
            case 0:
                tags.append("<span class=\"name-\(index)\" data-id=\"\(index)\" data-role=\"inline\">")
            case 1:
                tags.append("<a href=\"https://example.com/path/\(index)?q=\(index % 97)\" title=\"Title \(index)\">")
            case 2:
                tags.append("<img src=\"https://example.com/image-\(index).png\" alt=\"Image \(index)\" loading=\"lazy\">")
            case 3:
                tags.append("<custom-tag data-alpha=\"\(index)\" data-beta=\"\(index + 1)\" data-gamma=\"\(index + 2)\">")
            case 4:
                tags.append("<br>")
            case 5:
                tags.append("</span>")
            case 6:
                tags.append("<tag\nattr=\"value-\(index)\">")
            default:
                tags.append("<missing attr \(index)")
            }
        }

        return tags
    }

    private func parseHTMLTagAttributeScanCanonicalForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseHTMLTagAttributeScanForBenchmark(&state, optimized: optimized)
        let canonical: String
        if let node {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [.paragraph(children: [node])])
        } else {
            canonical = "nil"
        }
        let offset = markdown.distance(from: markdown.startIndex, to: state.currentIndex)
        return "\(canonical)|offset:\(offset)|line:\(state.line)|column:\(state.column)"
    }

    private func htmlTagAttributeScanChecksumForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseHTMLTagAttributeScanForBenchmark(&state, optimized: optimized)
        return (node.map { inlineNodeBenchmarkChecksum($0) } ?? 0) +
            markdown.distance(from: markdown.startIndex, to: state.currentIndex) +
            state.line +
            state.column
    }

    private func htmlTagAttributeScanChecksumForBenchmark(
        _ tags: [String],
        optimized: Bool
    ) -> Int {
        var checksum = 0
        for tag in tags {
            checksum &+= htmlTagAttributeScanChecksumForBenchmark(tag, optimized: optimized)
        }
        return checksum
    }

    private func parseHTMLTagAttributeScanForBenchmark(
        _ state: inout ParserState,
        optimized: Bool
    ) -> MarkdownParser.InlineNode? {
        if optimized {
            return InlineParser.parseHTMLTag(&state)
        }

        return InlineParser.parseHTMLTagByCopyingIgnoredAttributeScanForTesting(&state)
    }

    private func parseHTMLTagNameScanCanonicalForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseHTMLTagNameScanForBenchmark(&state, optimized: optimized)
        let canonical: String
        if let node {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [.paragraph(children: [node])])
        } else {
            canonical = "nil"
        }
        let offset = markdown.distance(from: markdown.startIndex, to: state.currentIndex)
        return "\(canonical)|offset:\(offset)|line:\(state.line)|column:\(state.column)"
    }

    private func htmlTagNameScanChecksumForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseHTMLTagNameScanForBenchmark(&state, optimized: optimized)
        return (node.map { inlineNodeBenchmarkChecksum($0) } ?? 0) +
            markdown.distance(from: markdown.startIndex, to: state.currentIndex) +
            state.line +
            state.column
    }

    private func htmlTagNameScanChecksumForBenchmark(
        _ tags: [String],
        optimized: Bool
    ) -> Int {
        var checksum = 0
        for tag in tags {
            checksum &+= htmlTagNameScanChecksumForBenchmark(tag, optimized: optimized)
        }
        return checksum
    }

    private func parseHTMLTagNameScanForBenchmark(
        _ state: inout ParserState,
        optimized: Bool
    ) -> MarkdownParser.InlineNode? {
        if optimized {
            return InlineParser.parseHTMLTag(&state)
        }

        return InlineParser.parseHTMLTagByCopyingTagNameForTesting(&state)
    }

    private func parseAutolinkMoveCanonicalForBenchmark(
        _ markdown: String,
        asciiMove: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseAutolinkMoveForBenchmark(&state, asciiMove: asciiMove)
        let canonical: String
        if let node {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [.paragraph(children: [node])])
        } else {
            canonical = "nil"
        }
        return "\(canonical)|index:\(state.currentIndex)|line:\(state.line)|column:\(state.column)"
    }

    private func parseAutolinkMoveChecksumForBenchmark(
        _ markdown: String,
        asciiMove: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseAutolinkMoveForBenchmark(&state, asciiMove: asciiMove)
        return (node.map { inlineNodeBenchmarkChecksum($0) } ?? 0) +
            markdown.distance(from: markdown.startIndex, to: state.currentIndex) +
            state.line +
            state.column
    }

    private func parseAutolinkMoveForBenchmark(
        _ state: inout ParserState,
        asciiMove: Bool
    ) -> MarkdownParser.InlineNode? {
        let angleBracketMode = state.current() == "<"
        if asciiMove {
            return InlineParser.parseUnifiedAutolink(&state, angleBracketMode: angleBracketMode)
        }
        return InlineParser.parseUnifiedAutolinkByMovingWithCharactersForTesting(
            &state,
            angleBracketMode: angleBracketMode
        )
    }

    private func parseAutolinkCountedMoveCanonicalForBenchmark(
        _ markdown: String,
        countedMove: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseAutolinkCountedMoveForBenchmark(&state, countedMove: countedMove)
        let canonical: String
        if let node {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [.paragraph(children: [node])])
        } else {
            canonical = "nil"
        }
        return "\(canonical)|index:\(state.currentIndex)|line:\(state.line)|column:\(state.column)"
    }

    private func parseAutolinkCountedMoveChecksumForBenchmark(
        _ markdown: String,
        countedMove: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseAutolinkCountedMoveForBenchmark(&state, countedMove: countedMove)
        return (node.map { inlineNodeBenchmarkChecksum($0) } ?? 0) +
            markdown.distance(from: markdown.startIndex, to: state.currentIndex) +
            state.line +
            state.column
    }

    private func parseAutolinkCountedMoveForBenchmark(
        _ state: inout ParserState,
        countedMove: Bool
    ) -> MarkdownParser.InlineNode? {
        let angleBracketMode = state.current() == "<"
        if countedMove {
            return InlineParser.parseUnifiedAutolink(&state, angleBracketMode: angleBracketMode)
        }
        return InlineParser.parseUnifiedAutolinkByRecountingASCIIMoveForTesting(
            &state,
            angleBracketMode: angleBracketMode
        )
    }

    private func parseAutolinkTailTrimCanonicalForBenchmark(
        _ markdown: String,
        byteTrim: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseAutolinkTailTrimForBenchmark(&state, byteTrim: byteTrim)
        let canonical: String
        if let node {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [.paragraph(children: [node])])
        } else {
            canonical = "nil"
        }
        return "\(canonical)|index:\(state.currentIndex)|line:\(state.line)|column:\(state.column)"
    }

    private func parseAutolinkTailTrimChecksumForBenchmark(
        _ markdown: String,
        byteTrim: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseAutolinkTailTrimForBenchmark(&state, byteTrim: byteTrim)
        return (node.map { inlineNodeBenchmarkChecksum($0) } ?? 0) +
            markdown.distance(from: markdown.startIndex, to: state.currentIndex) +
            state.line +
            state.column
    }

    private func parseAutolinkTailTrimForBenchmark(
        _ state: inout ParserState,
        byteTrim: Bool
    ) -> MarkdownParser.InlineNode? {
        let angleBracketMode = state.current() == "<"
        if byteTrim {
            return InlineParser.parseUnifiedAutolink(&state, angleBracketMode: angleBracketMode)
        }
        return InlineParser.parseUnifiedAutolinkByTrimmingTailWithCharactersForTesting(
            &state,
            angleBracketMode: angleBracketMode
        )
    }

    private func parseAngleAutolinkCopyCanonicalForBenchmark(
        _ markdown: String,
        deferRejectedCopy: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseAngleAutolinkCopyForBenchmark(&state, deferRejectedCopy: deferRejectedCopy)
        let canonical: String
        if let node {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [.paragraph(children: [node])])
        } else {
            canonical = "nil"
        }
        return "\(canonical)|index:\(state.currentIndex)|line:\(state.line)|column:\(state.column)"
    }

    private func parseAngleAutolinkCopyChecksumForBenchmark(
        _ markdown: String,
        deferRejectedCopy: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseAngleAutolinkCopyForBenchmark(&state, deferRejectedCopy: deferRejectedCopy)
        return (node.map { inlineNodeBenchmarkChecksum($0) } ?? 17) +
            markdown.distance(from: markdown.startIndex, to: state.currentIndex) +
            state.line +
            state.column
    }

    private func parseAngleAutolinkCopyForBenchmark(
        _ state: inout ParserState,
        deferRejectedCopy: Bool
    ) -> MarkdownParser.InlineNode? {
        let angleBracketMode = state.current() == "<"
        if deferRejectedCopy {
            return InlineParser.parseUnifiedAutolink(&state, angleBracketMode: angleBracketMode)
        }

        return InlineParser.parseUnifiedAutolinkByCopyingRejectedAngleContentForTesting(
            &state,
            angleBracketMode: angleBracketMode
        )
    }

    private func parseFootnoteReferenceMoveCanonicalForBenchmark(
        _ markdown: String,
        countedMove: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseFootnoteReferenceMoveForBenchmark(&state, countedMove: countedMove)
        let canonical: String
        if let node {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [.paragraph(children: [node])])
        } else {
            canonical = "nil"
        }
        return "\(canonical)|index:\(state.currentIndex)|line:\(state.line)|column:\(state.column)"
    }

    private func parseFootnoteReferenceMoveChecksumForBenchmark(
        _ markdown: String,
        countedMove: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseFootnoteReferenceMoveForBenchmark(&state, countedMove: countedMove)
        return (node.map { inlineNodeBenchmarkChecksum($0) } ?? 0) +
            markdown.distance(from: markdown.startIndex, to: state.currentIndex) +
            state.line +
            state.column
    }

    private func parseFootnoteReferenceMoveForBenchmark(
        _ state: inout ParserState,
        countedMove: Bool
    ) -> MarkdownParser.InlineNode? {
        if countedMove {
            return InlineParser.parseFootnoteReference(&state)
        }
        return InlineParser.parseFootnoteReferenceByRecountingASCIIMoveForTesting(&state)
    }

    private func parseAutolinkSchemeCanonicalForBenchmark(
        _ markdown: String,
        asciiScheme: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseAutolinkSchemeForBenchmark(&state, asciiScheme: asciiScheme)
        let canonical: String
        if let node {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [.paragraph(children: [node])])
        } else {
            canonical = "nil"
        }
        return "\(canonical)|index:\(state.currentIndex)|line:\(state.line)|column:\(state.column)"
    }

    private func parseAutolinkSchemeChecksumForBenchmark(
        _ markdown: String,
        asciiScheme: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseAutolinkSchemeForBenchmark(&state, asciiScheme: asciiScheme)
        return (node.map { inlineNodeBenchmarkChecksum($0) } ?? 0) +
            markdown.distance(from: markdown.startIndex, to: state.currentIndex) +
            state.line +
            state.column
    }

    private func parseAutolinkSchemeForBenchmark(
        _ state: inout ParserState,
        asciiScheme: Bool
    ) -> MarkdownParser.InlineNode? {
        let angleBracketMode = state.current() == "<"
        if asciiScheme {
            return InlineParser.parseUnifiedAutolink(&state, angleBracketMode: angleBracketMode)
        }
        return InlineParser.parseUnifiedAutolinkByDetectingSchemeWithCharactersForTesting(
            &state,
            angleBracketMode: angleBracketMode
        )
    }

    private func parseInlineCodeTrimCanonicalForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseInlineCodeTrimForBenchmark(&state, optimized: optimized)
        let canonical: String
        if let node {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [.paragraph(children: [node])])
        } else {
            canonical = "nil"
        }
        return "\(canonical)|index:\(state.currentIndex)|line:\(state.line)|column:\(state.column)"
    }

    private func parseInlineCodeTrimChecksumForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseInlineCodeTrimForBenchmark(&state, optimized: optimized)
        return (node.map { inlineNodeBenchmarkChecksum($0) } ?? 0) +
            markdown.distance(from: markdown.startIndex, to: state.currentIndex) +
            state.line +
            state.column
    }

    private func parseInlineCodeTrimForBenchmark(
        _ state: inout ParserState,
        optimized: Bool
    ) -> MarkdownParser.InlineNode? {
        if optimized {
            return InlineParser.parseInlineCode(&state)
        }
        return InlineParser.parseASCIIInlineCodeByTrimmingCopiedContentForTesting(&state)
    }

    private func makeSimpleLinkResourcesForParsingBenchmark(resourceCount: Int) -> [String] {
        var resources: [String] = []
        resources.reserveCapacity(resourceCount)

        for index in 0..<resourceCount {
            resources.append("https://example.com/docs/\(index)?ref=glimmer)")
        }

        return resources
    }

    private func makeUnicodeSimpleLinkResourcesForParsingBenchmark(resourceCount: Int) -> [String] {
        var resources: [String] = []
        resources.reserveCapacity(resourceCount)

        for index in 0..<resourceCount {
            switch index % 6 {
            case 0:
                resources.append("https://example.com/docs/\(index)-café)")
            case 1:
                resources.append("https://example.com/search?q=こんにちは-\(index))")
            case 2:
                resources.append("https://example.com/docs/\(index) \"Café title \(index)\")")
            case 3:
                resources.append("https://example.com/docs/\(index) 'Résumé title \(index)')")
            case 4:
                resources.append("https://example.com/docs/\(index) \"こんにちは ✅ \(index)\")")
            default:
                resources.append("   https://example.com/café-\(index)   )")
            }
        }

        return resources
    }

    private func makeBalancedLinkResourcesForDestinationBackslashBenchmark(resourceCount: Int) -> [String] {
        var resources: [String] = []
        resources.reserveCapacity(resourceCount)

        for index in 0..<resourceCount {
            switch index % 6 {
            case 0:
                resources.append("https://example.com/docs/\(index)/section(a)b)")
            case 1:
                resources.append("https://example.com/docs/\(index)/section(a(b)c)d)")
            case 2:
                resources.append("   https://example.com/docs/\(index)/section(a)b   )")
            case 3:
                resources.append("https://example.com/docs/\(index)/section(a)b \"Title \(index)\")")
            case 4:
                resources.append("https://example.com/docs/\(index)/section(a)b 'Title \(index)')")
            default:
                resources.append("https://example.com/docs/\(index)/section(a)b (Title \(index)))")
            }
        }

        return resources
    }

    private func makeBalancedLinkResourcesForMetadataScanBenchmark(resourceCount: Int) -> [String] {
        var resources: [String] = []
        resources.reserveCapacity(resourceCount)

        for index in 0..<resourceCount {
            switch index % 8 {
            case 0:
                resources.append("https://example.com/docs/\(index)/section(a)b)")
            case 1:
                resources.append("https://example.com/docs/\(index)/section(a)b \"Title \(index)\")")
            case 2:
                resources.append("https://example.com/docs/\(index)/section(a)b 'Title \(index)'   )")
            case 3:
                resources.append("https://example.com/docs/\(index)/section(a)b (Title \(index)))")
            case 4:
                resources.append("   https://example.com/docs/\(index)/section(a(b)c)d   \"Spaced title \(index)\"   )")
            case 5:
                resources.append("https://example.com/docs/\(index)/section(a)b \"Title \\\"quoted\\\" \(index)\")")
            case 6:
                resources.append("https://example.com/docs/\(index)/section(a)b \"Café title \(index)\"   )")
            default:
                resources.append("https://example.com/docs/\(index)/section(a)b trailing-text)")
            }
        }

        return resources
    }

    private func makeExtensionAwareASCIITextRunBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        let prefix = String(repeating: "alpha beta gamma delta epsilon ", count: 4)
        let suffix = String(repeating: " zeta eta theta iota kappa", count: 4)

        for index in 0..<count {
            switch index % 4 {
            case 0:
                inputs.append("\(prefix)\(index) before ::vip:: after\(suffix)")
            case 1:
                inputs.append("\(prefix)\(index) before **bold \(index % 17)** and ::vip:: after\(suffix)")
            case 2:
                inputs.append("\(prefix)\(index) with failed colon 10:30 and trailing words\(suffix)")
            default:
                inputs.append("\(prefix)\(index) before [link](https://example.com/\(index)) then ::vip::\(suffix)")
            }
        }

        return inputs
    }

    private func makeInvalidInlineURLValidationBenchmark(count: Int) -> [(link: String, image: String)] {
        let invalidDestinations = [
            "http://[",
            "http://%",
            "http://exa<mple.com",
            "http://{"
        ]
        var inputs: [(link: String, image: String)] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            let label = "**bold \(index)** and `code \(index % 17)` with [nested \(index % 11)] " +
                "plus escaped \\[ bracket"
            let destination = invalidDestinations[index % invalidDestinations.count]
            inputs.append((
                link: "[\(label)](\(destination))",
                image: "![\(label)](\(destination))"
            ))
        }

        return inputs
    }

    private func parseLinkForBenchmark(_ markdown: String, copying: Bool) -> MarkdownParser.InlineNode? {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        if copying {
            return InlineParser.parseLinkByCopyingTextAndDestinationForTesting(&state, configuration: .default)
        }
        return InlineParser.parseLink(&state, configuration: .default)
    }

    private func parseInlineURLValidationCanonicalForBenchmark(
        _ markdown: String,
        image: Bool,
        earlyValidation: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseInlineURLValidationForBenchmark(
            &state,
            image: image,
            earlyValidation: earlyValidation
        )
        let canonical: String
        if let node {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [.paragraph(children: [node])])
        } else {
            canonical = "nil"
        }
        let offset = markdown.distance(from: markdown.startIndex, to: state.currentIndex)
        return "\(canonical)|offset:\(offset)|line:\(state.line)|column:\(state.column)"
    }

    private func parseInlineURLValidationChecksumForBenchmark(
        _ markdown: String,
        image: Bool,
        earlyValidation: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseInlineURLValidationForBenchmark(
            &state,
            image: image,
            earlyValidation: earlyValidation
        )
        return (node.map { inlineNodeBenchmarkChecksum($0) } ?? 1) +
            markdown.distance(from: markdown.startIndex, to: state.currentIndex) +
            state.line +
            state.column
    }

    private func parseInlineURLValidationForBenchmark(
        _ state: inout ParserState,
        image: Bool,
        earlyValidation: Bool
    ) -> MarkdownParser.InlineNode? {
        if image {
            if earlyValidation {
                return InlineParser.parseImage(&state, configuration: .github)
            }
            return InlineParser.parseImageByParsingAltBeforeURLValidationForTesting(
                &state,
                configuration: .github
            )
        }

        if earlyValidation {
            return InlineParser.parseLink(&state, configuration: .github)
        }
        return InlineParser.parseLinkByParsingContentBeforeURLValidationForTesting(
            &state,
            configuration: .github
        )
    }

    private func parseLinkResourceMoveForBenchmark(
        _ markdown: String,
        asciiMove: Bool
    ) -> MarkdownParser.InlineNode? {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        if asciiMove {
            return InlineParser.parseLink(&state, configuration: .default)
        }
        return InlineParser.parseLinkByMovingResourceWithCharactersForTesting(&state, configuration: .default)
    }

    private func parseLinkResourceByteCountCanonicalForBenchmark(
        _ markdown: String,
        countedByteCount: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseLinkResourceByteCountForBenchmark(&state, countedByteCount: countedByteCount)
        let canonical: String
        if let node {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [.paragraph(children: [node])])
        } else {
            canonical = "nil"
        }
        let offset = markdown.distance(from: markdown.startIndex, to: state.currentIndex)
        return "\(canonical)|offset:\(offset)|line:\(state.line)|column:\(state.column)"
    }

    private func parseLinkResourceByteCountChecksumForBenchmark(
        _ markdown: String,
        countedByteCount: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseLinkResourceByteCountForBenchmark(&state, countedByteCount: countedByteCount)
        return (node.map { inlineNodeBenchmarkChecksum($0) } ?? 0) +
            markdown.distance(from: markdown.startIndex, to: state.currentIndex) +
            state.line +
            state.column
    }

    private func parseLinkResourceByteCountForBenchmark(
        _ state: inout ParserState,
        countedByteCount: Bool
    ) -> MarkdownParser.InlineNode? {
        if countedByteCount {
            return InlineParser.parseLink(&state, configuration: .default)
        }
        return InlineParser.parseLinkByRecountingSimpleResourceByteCountForTesting(&state, configuration: .default)
    }

    private func parseLinkBracketedTextMoveCanonicalForBenchmark(
        _ markdown: String,
        countedMove: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseLinkBracketedTextMoveForBenchmark(&state, countedMove: countedMove)
        let canonical: String
        if let node {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [.paragraph(children: [node])])
        } else {
            canonical = "nil"
        }
        return "\(canonical)|index:\(state.currentIndex)|line:\(state.line)|column:\(state.column)"
    }

    private func parseLinkBracketedTextMoveChecksumForBenchmark(
        _ markdown: String,
        countedMove: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseLinkBracketedTextMoveForBenchmark(&state, countedMove: countedMove)
        return (node.map { inlineNodeBenchmarkChecksum($0) } ?? 0) +
            markdown.distance(from: markdown.startIndex, to: state.currentIndex) +
            state.line +
            state.column
    }

    private func parseLinkBracketedTextMoveForBenchmark(
        _ state: inout ParserState,
        countedMove: Bool
    ) -> MarkdownParser.InlineNode? {
        if countedMove {
            return InlineParser.parseLink(&state, configuration: .default)
        }
        return InlineParser.parseLinkByRecountingBracketedTextMoveForTesting(&state, configuration: .default)
    }

    private func parseLinkBracketedTextScanCanonicalForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseLinkBracketedTextScanForBenchmark(&state, optimized: optimized)
        let canonical: String
        if let node {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [.paragraph(children: [node])])
        } else {
            canonical = "nil"
        }
        return "\(canonical)|index:\(state.currentIndex)|line:\(state.line)|column:\(state.column)"
    }

    private func parseLinkBracketedTextScanChecksumForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseLinkBracketedTextScanForBenchmark(&state, optimized: optimized)
        return (node.map { inlineNodeBenchmarkChecksum($0) } ?? 0) +
            markdown.distance(from: markdown.startIndex, to: state.currentIndex) +
            state.line +
            state.column
    }

    private func parseLinkBracketedTextScanForBenchmark(
        _ state: inout ParserState,
        optimized: Bool
    ) -> MarkdownParser.InlineNode? {
        if optimized {
            return InlineParser.parseLink(&state, configuration: .default)
        }
        return InlineParser.parseLinkByCharacterSimpleBracketedTextForTesting(&state, configuration: .default)
    }

    private func parseLinkBalancedBracketedTextScanCanonicalForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseLinkBalancedBracketedTextScanForBenchmark(&state, optimized: optimized)
        let canonical: String
        if let node {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [.paragraph(children: [node])])
        } else {
            canonical = "nil"
        }
        return "\(canonical)|index:\(state.currentIndex)|line:\(state.line)|column:\(state.column)"
    }

    private func parseLinkBalancedBracketedTextScanChecksumForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseLinkBalancedBracketedTextScanForBenchmark(&state, optimized: optimized)
        return (node.map { inlineNodeBenchmarkChecksum($0) } ?? 0) +
            markdown.distance(from: markdown.startIndex, to: state.currentIndex) +
            state.line +
            state.column
    }

    private func parseLinkBalancedBracketedTextScanForBenchmark(
        _ state: inout ParserState,
        optimized: Bool
    ) -> MarkdownParser.InlineNode? {
        if optimized {
            return InlineParser.parseLink(&state, configuration: .default)
        }
        return InlineParser.parseLinkByCharacterBalancedBracketedTextForTesting(&state, configuration: .default)
    }

    private func parseLinkReferenceLabelScanCanonicalForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseLinkReferenceLabelScanForBenchmark(&state, optimized: optimized)
        let canonical: String
        if let node {
            canonical = ParserCanonicalSnapshot.canonicalDescription(for: [.paragraph(children: [node])])
        } else {
            canonical = "nil"
        }
        return "\(canonical)|index:\(state.currentIndex)|line:\(state.line)|column:\(state.column)"
    }

    private func parseLinkReferenceLabelScanChecksumForBenchmark(
        _ markdown: String,
        optimized: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let node = parseLinkReferenceLabelScanForBenchmark(&state, optimized: optimized)
        return (node.map { inlineNodeBenchmarkChecksum($0) } ?? 0) +
            markdown.distance(from: markdown.startIndex, to: state.currentIndex) +
            state.line +
            state.column +
            markdown.utf8.count
    }

    private func parseLinkReferenceLabelScanForBenchmark(
        _ state: inout ParserState,
        optimized: Bool
    ) -> MarkdownParser.InlineNode? {
        if optimized {
            return InlineParser.parseLink(&state, configuration: .default)
        }
        return InlineParser.parseLinkByScanningUnresolvedReferenceLabelForTesting(&state, configuration: .default)
    }

    private func linkBenchmarkChecksum(_ node: MarkdownParser.InlineNode) -> Int {
        guard case .link(let url, let title, let children) = node else {
            return 0
        }

        return url.absoluteString.utf8.count + (title?.utf8.count ?? 0) + children.count
    }

    private func parseInlineLinkResourceForBenchmark(
        _ resource: String,
        fastPath: Bool
    ) -> InlineParser.InlineLinkResource? {
        if fastPath {
            return InlineParser.parseInlineLinkResourceForTesting(
                in: resource,
                from: resource.startIndex,
                to: resource.endIndex
            )
        }

        return InlineParser.parseInlineLinkResourceWithBalancedScanForTesting(
            in: resource,
            from: resource.startIndex,
            to: resource.endIndex
        )
    }

    private func parseBalancedInlineLinkResourceDestinationScanForBenchmark(
        _ resource: String,
        optimized: Bool
    ) -> InlineParser.InlineLinkResource? {
        if optimized {
            return InlineParser.parseInlineLinkResourceWithBalancedScanForTesting(
                in: resource,
                from: resource.startIndex,
                to: resource.endIndex
            )
        }

        return InlineParser.parseInlineLinkResourceWithCharacterDestinationBackslashScanForTesting(
            in: resource,
            from: resource.startIndex,
            to: resource.endIndex
        )
    }

    private func parseBalancedInlineLinkResourceMetadataScanForBenchmark(
        _ resource: String,
        optimized: Bool
    ) -> InlineParser.InlineLinkResource? {
        if optimized {
            return InlineParser.parseInlineLinkResourceWithBalancedScanForTesting(
                in: resource,
                from: resource.startIndex,
                to: resource.endIndex
            )
        }

        return InlineParser.parseInlineLinkResourceWithCharacterMetadataScanForTesting(
            in: resource,
            from: resource.startIndex,
            to: resource.endIndex
        )
    }

    private func makeBadgeExtensionForASCIITextRunBenchmark(triggered: Bool) -> MarkdownExtension {
        let triggerCharacters: Set<Character> = triggered ? [":"] : []
        return MarkdownExtension(
            id: "example.badges",
            version: 1,
            triggerCharacters: triggerCharacters,
            parseInline: { context in
                guard context.remaining.hasPrefix("::vip::") else { return nil }
                return MarkdownExtensionInlineMatch(
                    name: "badge",
                    literal: "::vip::",
                    fields: ["kind": "vip"],
                    endIndex: context.index(offsetBy: 7)
                )
            }
        )
    }

    private func parseInlineForExtensionAwareASCIITextRunBenchmark(
        _ markdown: String,
        configuration: MarkdownConfiguration,
        optimized: Bool
    ) -> [MarkdownParser.InlineNode] {
        var state = ParserState(text: markdown)
        if optimized {
            return InlineParser.parseInlineElements(&state, configuration: configuration)
        }

        return InlineParser.parseInlineElementsByDisablingExtensionAwareASCIITextRunsForTesting(
            &state,
            configuration: configuration
        )
    }

    private func assertEqualInlineLinkResource(
        _ lhs: InlineParser.InlineLinkResource,
        _ rhs: InlineParser.InlineLinkResource,
        source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.destination, rhs.destination, file: file, line: line)
        XCTAssertEqual(lhs.title, rhs.title, file: file, line: line)
        XCTAssertEqual(
            source.distance(from: source.startIndex, to: lhs.after),
            source.distance(from: source.startIndex, to: rhs.after),
            file: file,
            line: line
        )
    }

    private func inlineLinkResourceBenchmarkChecksum(
        _ resource: InlineParser.InlineLinkResource,
        in source: String
    ) -> Int {
        resource.destination.utf8.count +
            (resource.title?.utf8.count ?? 0) +
            source.distance(from: source.startIndex, to: resource.after)
    }

    private func makeUnmatchedASCIIEmphasisForParsingBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            inputs.append(
                """
                ***Unmatched emphasis candidate \(index) with a long ASCII payload, \
                several words, numbers \(index % 97), escaped \\ markers, and no closing delimiter.
                """
            )
        }

        return inputs
    }

    private func parseEmphasisForBenchmark(
        _ markdown: String,
        onePass: Bool
    ) -> MarkdownParser.InlineNode? {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        let delimiter = markdown.first ?? "*"
        if onePass {
            return InlineParser.parseEmphasis(&state, delimiter: delimiter, configuration: .default)
        }
        return InlineParser.parseEmphasisByRetryingDelimiterCountsForTesting(
            &state,
            delimiter: delimiter,
            configuration: .default
        )
    }

    private func makeASCIIStrikethroughForParsingBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            inputs.append(
                "~~Removed value \(index) with **bold \(index % 13)**, `code \(index % 29)`, and ASCII words~~"
            )
        }

        return inputs
    }

    private func parseStrikethroughForBenchmark(
        _ markdown: String,
        fastPath: Bool
    ) -> MarkdownParser.InlineNode? {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()
        if fastPath {
            return InlineParser.parseStrikethrough(&state, configuration: .default)
        }
        return InlineParser.parseStrikethroughByCharacterScanningForTesting(&state, configuration: .default)
    }

    private func makeMixedInlineLiteralRunBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            inputs.append(
                """
                Prefix words \(index) before **bold \(index % 17)**, \
                middle text before [link \(index % 23)](https://example.com/docs/\(index)), \
                more words before `code \(index % 31)`, then *italic \(index % 43)* and trailing ASCII text.
                """
            )
        }

        return inputs
    }

    private func parseInlineForLiteralRunBufferBenchmark(
        _ markdown: String,
        deferredLiteralRuns: Bool,
        configuration: MarkdownConfiguration
    ) -> [MarkdownParser.InlineNode] {
        var state = ParserState(text: markdown)
        if deferredLiteralRuns {
            return InlineParser.parseInlineElements(&state, configuration: configuration)
        }
        return InlineParser.parseInlineElementsByCopyingLiteralRunsForTesting(&state, configuration: configuration)
    }

    private func makeInlineLiteralRunByteCountBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        let firstRun = String(
            repeating: "alpha beta gamma delta epsilon zeta eta theta ",
            count: 10
        )
        let secondRun = String(
            repeating: "iota kappa lambda mu nu xi omicron pi ",
            count: 8
        )
        let thirdRun = String(
            repeating: "rho sigma tau upsilon phi chi psi omega ",
            count: 8
        )

        for index in 0..<count {
            inputs.append(
                """
                \(firstRun)\(index) before **bold \(index % 17)** \(secondRun) \
                before [link \(index % 23)](https://example.com/docs/\(index)) \(thirdRun) \
                before `code \(index % 31)` \(firstRun) and trailing ASCII words \(index).
                """
            )
        }

        return inputs
    }

    private func parseInlineForLiteralRunByteCountBenchmark(
        _ markdown: String,
        knownByteCount: Bool,
        configuration: MarkdownConfiguration
    ) -> [MarkdownParser.InlineNode] {
        var state = ParserState(text: markdown)
        if knownByteCount {
            return InlineParser.parseInlineElements(&state, configuration: configuration)
        }
        return InlineParser.parseInlineElementsByRecountingLiteralRunBytesForTesting(
            &state,
            configuration: configuration
        )
    }

    private func makeASCIITextRunDispatchBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            inputs.append(
                "Plain ASCII prefix \(index) with many words before **bold \(index % 17)** and trailing text"
            )
        }

        return inputs
    }

    private func consumeASCIITextRunForBenchmark(
        _ markdown: String,
        simple: Bool
    ) -> (consumed: Bool, offset: Int) {
        var state = ParserState(text: markdown)
        state.enableASCIIFastPathIfPossible()

        let consumed: Bool
        if simple {
            consumed = InlineParser.consumeSimpleASCIITextRunForTesting(
                &state,
                enableMentions: true,
                enableIssueReferences: true,
                enableEmojiShortcodes: true
            )
        } else {
            consumed = InlineParser.consumeCandidateValidatedASCIITextRunForTesting(
                &state,
                enableMentions: true,
                enableIssueReferences: true,
                enableEmojiShortcodes: true
            )
        }

        let offset = state.text.utf8.distance(from: state.text.startIndex, to: state.currentIndex)
        return (consumed, offset)
    }

    private func makeASCIIInlinePlainTextPrescanBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            inputs.append(
                "Plain ASCII prefix \(index) with many words before **bold \(index % 17)** and trailing text"
            )
        }

        return inputs
    }

    private func makeGFMCandidateDispatchBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            inputs.append(
                """
                Prefix \(index) before https://example.com/path/\(index) then \
                owner\(index % 19)/repo\(index % 23) and \
                swiftlang/swift-markdown#\(index % 997) with \
                deadbeefcafebabe\(index % 10) plus ffffftp://example.com/text.
                """
            )
        }

        return inputs
    }

    private func makeGFMCandidateValidationGateBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 4 {
            case 0:
                inputs.append(
                    """
                    Zyzz qrst uvxyz qrst uvxyz qrst uvxyz qrst uvxyz before \
                    https://example.com/path/\(index) and owner/repo.
                    """
                )
            case 1:
                inputs.append(
                    """
                    Qrst yz uvxyz qrst yz uvxyz qrst yz uvxyz before \
                    swiftlang/swift-markdown#\(index % 997) and deadbeefcafebabe.
                    """
                )
            case 2:
                inputs.append(
                    """
                    Qrst yz uvxyz punctuation only; qrst yz uvxyz punctuation only; \
                    qrst yz uvxyz punctuation only.
                    """
                )
            default:
                inputs.append(
                    """
                    Zyzz qrst uvxyz before ffffftp://example.com/text and \
                    owner\(index % 31)/repo\(index % 37).
                    """
                )
            }
        }

        return inputs
    }

    private func makeGFMLeafMoveBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            inputs.append(
                """
                @reviewer\(index % 97) closed #\(index + 1) with :rocket: and :sparkles: in \
                owner\(index % 29)/repo\(index % 31)#\(index % 997). \
                Commit deadbeefcafebabe\(index % 10) followed up in swiftlang/swift-markdown.
                """
            )
        }

        return inputs
    }

    private func makeGFMLeafBoundaryBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 4 {
            case 0:
                inputs.append(
                    """
                    @reviewer\(index % 97) closed #\(index + 1) in \
                    owner\(index % 29)/repo\(index % 31)#\(index % 997) near deadbeefcafebabe\(index % 10).
                    """
                )
            case 1:
                inputs.append(
                    """
                    Email user\(index)@example.com keeps text; @owner\(index % 13) and \
                    swiftlang/swift-markdown#\(index % 997) should parse.
                    """
                )
            case 2:
                inputs.append(
                    """
                    prefix@skip \(index) abc#\(index) xdeadbeefcafebabe deadbeefcafebabeX \
                    plus ABCDEF1234567890.
                    """
                )
            default:
                inputs.append(
                    """
                    /owner\(index % 17)/repo :owner\(index % 19)/repo @owner\(index % 23)/repo \
                    owner\(index % 29)/repo\(index % 31)#not owner\(index % 31)/repo\(index % 37)#\(index % 997).
                    """
                )
            }
        }

        return inputs
    }

    private func makeMentionUsernameCopyBenchmark(count: Int) -> [String] {
        var inputs: [String] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 5 {
            case 0:
                inputs.append(
                    "Contact @example\(index % 97).com about @valid\(index % 31) and #\(index % 997)."
                )
            case 1:
                inputs.append(
                    "Domain-like @docs-\(index % 19).example.org should stay text before @reviewer\(index % 23)."
                )
            case 2:
                inputs.append(
                    "Ordinary email user\(index)@example.com rejects before username scanning, then @owner\(index % 17)."
                )
            case 3:
                inputs.append(
                    "Valid mentions @octocat\(index % 29), @swift_\(index % 31), and @repo-owner\(index % 37)."
                )
            default:
                inputs.append(
                    "Mixed prefix@skip\(index) plus (@alice\(index % 41)) and trailing @domain\(index % 43).io."
                )
            }
        }

        return inputs
    }

    private func makeASCIIInlineByteDispatchBenchmark(
        count: Int
    ) -> [(markdown: String, configuration: MarkdownConfiguration)] {
        var inputs: [(markdown: String, configuration: MarkdownConfiguration)] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 6 {
            case 0:
                inputs.append((
                    "Prefix \(index) before **bold \(index % 17)** and _italic_ then `code`.",
                    .default
                ))
            case 1:
                inputs.append((
                    "[link \(index)](https://example.com/\(index)) and ![alt](https://example.com/i.png)",
                    .default
                ))
            case 2:
                inputs.append((
                    "~~gone \(index)~~ <https://example.com/\(index)> <span class=\"x\">html</span>",
                    .github
                ))
            case 3:
                inputs.append((
                    "@reviewer\(index % 97) closed #\(index + 1) with :rocket: in owner/repo#\(index % 997).",
                    .github
                ))
            case 4:
                inputs.append((
                    "See https://example.com/path/\(index) and www.example.com plus deadbeefcafebabe\(index % 10).",
                    .github
                ))
            default:
                inputs.append((
                    "Failed *marker \(index) and [link plus ! image and <not closed before owner/repo.",
                    .github
                ))
            }
        }

        return inputs
    }

    private func makeASCIIBackslashEscapeDispatchBenchmark(
        count: Int
    ) -> [(markdown: String, configuration: MarkdownConfiguration)] {
        var inputs: [(markdown: String, configuration: MarkdownConfiguration)] = []
        inputs.reserveCapacity(count)

        for index in 0..<count {
            switch index % 5 {
            case 0:
                inputs.append((
                    "Escaped \\*marker \(index)\\* and \\_literal\\_ before **bold \(index % 17)**.",
                    .default
                ))
            case 1:
                inputs.append((
                    "Escaped \\[bracket \(index)\\] and \\(paren\\) around [link](https://example.com/\(index)).",
                    .default
                ))
            case 2:
                inputs.append((
                    "Escaped \\#\(index) \\@octocat \\:rocket: before #\(index + 1) and @reviewer\(index % 97).",
                    .github
                ))
            case 3:
                inputs.append((
                    "Escaped \\!image \\<tag> \\~strike\\~ before owner\(index % 29)/repo\(index % 31).",
                    .github
                ))
            default:
                inputs.append((
                    "Trailing escaped-looking slash \(index) \\ and more text before deadbeefcafebabe\(index % 10).",
                    .github
                ))
            }
        }

        return inputs
    }

    private func makeSourceASCIIInlineRangeBenchmark(sectionCount: Int) -> String {
        var markdown = ""
        markdown.reserveCapacity(sectionCount * 760)

        for index in 0..<sectionCount {
            markdown +=
                """
                ## Section \(index) with **bold \(index % 17)** and `code`

                Paragraph \(index) starts with [link text](https://example.com/\(index)) and \
                continues with @reviewer\(index % 97), #\(index + 1), :rocket:, owner\(index % 29)/repo\(index % 31), \
                and deadbeefcafebabe\(index % 10).

                - list item \(index) with **bold** and [link](https://example.com/list/\(index))
                  continuation \(index) with `code` and owner\(index % 31)/repo\(index % 37)#\(index % 997)

                > quoted line \(index) with _emphasis_ and https://example.com/quote/\(index)
                > second quoted line \(index) with :sparkles: and deadbeefcafebabe\(index % 10)

                [^note\(index)]: footnote \(index) with **bold** and [link](https://example.com/note/\(index))

                """
        }

        return markdown
    }

    private func parseInlineForGFMCandidateDispatchBenchmark(
        _ markdown: String,
        cachedDispatch: Bool
    ) -> [MarkdownParser.InlineNode] {
        var state = ParserState(text: markdown)
        if cachedDispatch {
            return InlineParser.parseInlineElements(&state, configuration: .github)
        }
        return InlineParser.parseInlineElementsByReprobingASCIICandidatesForTesting(&state, configuration: .github)
    }

    private func parseInlineForGFMCandidateValidationGateCanonicalForBenchmark(
        _ markdown: String,
        gated: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let inlines: [MarkdownParser.InlineNode]
        if gated {
            inlines = InlineParser.parseInlineElements(&state, configuration: .github)
        } else {
            inlines = InlineParser.parseInlineElementsWithUngatedASCIICandidateValidationForTesting(
                &state,
                configuration: .github
            )
        }

        let canonical = ParserCanonicalSnapshot.canonicalDescription(for: [.paragraph(children: inlines)])
        let offset = markdown.distance(from: markdown.startIndex, to: state.currentIndex)
        return "\(canonical)|offset:\(offset)|line:\(state.line)|column:\(state.column)"
    }

    private func parseInlineForGFMCandidateValidationGateBenchmark(
        _ markdown: String,
        gated: Bool
    ) -> [MarkdownParser.InlineNode] {
        var state = ParserState(text: markdown)
        if gated {
            return InlineParser.parseInlineElements(&state, configuration: .github)
        }
        return InlineParser.parseInlineElementsWithUngatedASCIICandidateValidationForTesting(
            &state,
            configuration: .github
        )
    }

    private func parseInlineForGFMLeafMoveCanonicalForBenchmark(
        _ markdown: String,
        countedMove: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let inlines: [MarkdownParser.InlineNode]
        if countedMove {
            inlines = InlineParser.parseInlineElements(&state, configuration: .github)
        } else {
            inlines = InlineParser.parseInlineElementsByRecountingGFMLeafMovesForTesting(&state, configuration: .github)
        }

        let canonical = ParserCanonicalSnapshot.canonicalDescription(for: [.paragraph(children: inlines)])
        let offset = markdown.distance(from: markdown.startIndex, to: state.currentIndex)
        return "\(canonical)|offset:\(offset)|line:\(state.line)|column:\(state.column)"
    }

    private func parseInlineForGFMLeafMoveBenchmark(
        _ markdown: String,
        countedMove: Bool
    ) -> [MarkdownParser.InlineNode] {
        var state = ParserState(text: markdown)
        if countedMove {
            return InlineParser.parseInlineElements(&state, configuration: .github)
        }
        return InlineParser.parseInlineElementsByRecountingGFMLeafMovesForTesting(&state, configuration: .github)
    }

    private func parseInlineForGFMLeafBoundaryCanonicalForBenchmark(
        _ markdown: String,
        asciiBytes: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let inlines: [MarkdownParser.InlineNode]
        if asciiBytes {
            inlines = InlineParser.parseInlineElements(&state, configuration: .github)
        } else {
            inlines = InlineParser.parseInlineElementsByCheckingGFMLeafBoundariesWithCharactersForTesting(
                &state,
                configuration: .github
            )
        }

        let canonical = ParserCanonicalSnapshot.canonicalDescription(for: [.paragraph(children: inlines)])
        let offset = markdown.distance(from: markdown.startIndex, to: state.currentIndex)
        return "\(canonical)|offset:\(offset)|line:\(state.line)|column:\(state.column)"
    }

    private func parseInlineForGFMLeafBoundaryBenchmark(
        _ markdown: String,
        asciiBytes: Bool
    ) -> [MarkdownParser.InlineNode] {
        var state = ParserState(text: markdown)
        if asciiBytes {
            return InlineParser.parseInlineElements(&state, configuration: .github)
        }
        return InlineParser.parseInlineElementsByCheckingGFMLeafBoundariesWithCharactersForTesting(
            &state,
            configuration: .github
        )
    }

    private func parseInlineForMentionUsernameCopyCanonicalForBenchmark(
        _ markdown: String,
        deferredCopy: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let inlines = parseInlineForMentionUsernameCopyBenchmark(
            &state,
            deferredCopy: deferredCopy
        )
        let canonical = ParserCanonicalSnapshot.canonicalDescription(for: [.paragraph(children: inlines)])
        let offset = markdown.distance(from: markdown.startIndex, to: state.currentIndex)
        return "\(canonical)|offset:\(offset)|line:\(state.line)|column:\(state.column)"
    }

    private func parseInlineForMentionUsernameCopyBenchmark(
        _ markdown: String,
        deferredCopy: Bool
    ) -> [MarkdownParser.InlineNode] {
        var state = ParserState(text: markdown)
        return parseInlineForMentionUsernameCopyBenchmark(&state, deferredCopy: deferredCopy)
    }

    private func parseInlineForMentionUsernameCopyBenchmark(
        _ state: inout ParserState,
        deferredCopy: Bool
    ) -> [MarkdownParser.InlineNode] {
        if deferredCopy {
            return InlineParser.parseInlineElements(&state, configuration: .github)
        }
        return InlineParser.parseInlineElementsByCopyingMentionUsernamesBeforeEmailRejectionForTesting(
            &state,
            configuration: .github
        )
    }

    private func parseInlineForASCIIByteDispatchCanonicalForBenchmark(
        _ markdown: String,
        configuration: MarkdownConfiguration,
        byteDispatch: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let inlines: [MarkdownParser.InlineNode]
        if byteDispatch {
            inlines = InlineParser.parseInlineElements(&state, configuration: configuration)
        } else {
            inlines = InlineParser.parseInlineElementsBySwitchingASCIIDispatchWithCharactersForTesting(
                &state,
                configuration: configuration
            )
        }

        let canonical = ParserCanonicalSnapshot.canonicalDescription(for: [.paragraph(children: inlines)])
        let offset = markdown.distance(from: markdown.startIndex, to: state.currentIndex)
        return "\(canonical)|offset:\(offset)|line:\(state.line)|column:\(state.column)"
    }

    private func parseInlineForASCIIByteDispatchBenchmark(
        _ input: (markdown: String, configuration: MarkdownConfiguration),
        byteDispatch: Bool
    ) -> [MarkdownParser.InlineNode] {
        var state = ParserState(text: input.markdown)
        if byteDispatch {
            return InlineParser.parseInlineElements(&state, configuration: input.configuration)
        }
        return InlineParser.parseInlineElementsBySwitchingASCIIDispatchWithCharactersForTesting(
            &state,
            configuration: input.configuration
        )
    }

    private func parseInlineForASCIIEscapeDispatchCanonicalForBenchmark(
        _ markdown: String,
        configuration: MarkdownConfiguration,
        byteEscapes: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let inlines: [MarkdownParser.InlineNode]
        if byteEscapes {
            inlines = InlineParser.parseInlineElements(&state, configuration: configuration)
        } else {
            inlines = InlineParser.parseInlineElementsByHandlingASCIIEscapesWithCharactersForTesting(
                &state,
                configuration: configuration
            )
        }

        let canonical = ParserCanonicalSnapshot.canonicalDescription(for: [.paragraph(children: inlines)])
        let offset = markdown.distance(from: markdown.startIndex, to: state.currentIndex)
        return "\(canonical)|offset:\(offset)|line:\(state.line)|column:\(state.column)"
    }

    private func parseInlineForASCIIEscapeDispatchBenchmark(
        _ input: (markdown: String, configuration: MarkdownConfiguration),
        byteEscapes: Bool
    ) -> [MarkdownParser.InlineNode] {
        var state = ParserState(text: input.markdown)
        if byteEscapes {
            return InlineParser.parseInlineElements(&state, configuration: input.configuration)
        }
        return InlineParser.parseInlineElementsByHandlingASCIIEscapesWithCharactersForTesting(
            &state,
            configuration: input.configuration
        )
    }

    private func parseInlineForFailedCodeSpanCanonicalForBenchmark(
        _ markdown: String,
        configuration: MarkdownConfiguration,
        cachedFailures: Bool
    ) -> String {
        var state = ParserState(text: markdown)
        let inlines = parseInlineForFailedCodeSpanBenchmark(
            &state,
            configuration: configuration,
            cachedFailures: cachedFailures
        )
        let canonical = ParserCanonicalSnapshot.canonicalDescription(for: [.paragraph(children: inlines)])
        let offset = markdown.distance(from: markdown.startIndex, to: state.currentIndex)
        return "\(canonical)|offset:\(offset)|line:\(state.line)|column:\(state.column)"
    }

    private func parseInlineFailedCodeSpanChecksumForBenchmark(
        _ markdown: String,
        cachedFailures: Bool
    ) -> Int {
        var state = ParserState(text: markdown)
        let inlines = parseInlineForFailedCodeSpanBenchmark(
            &state,
            configuration: .default,
            cachedFailures: cachedFailures
        )
        return inlineNodesBenchmarkChecksum(inlines) +
            markdown.distance(from: markdown.startIndex, to: state.currentIndex) +
            state.line +
            state.column
    }

    private func parseInlineForFailedCodeSpanBenchmark(
        _ state: inout ParserState,
        configuration: MarkdownConfiguration,
        cachedFailures: Bool
    ) -> [MarkdownParser.InlineNode] {
        if cachedFailures {
            return InlineParser.parseInlineElements(&state, configuration: configuration)
        }
        return InlineParser.parseInlineElementsByReprobingFailedInlineCodeSpansForTesting(
            &state,
            configuration: configuration
        )
    }

    private func parseInlineForPlainTextPrescanBenchmark(
        _ markdown: String,
        prescan: Bool
    ) -> [MarkdownParser.InlineNode] {
        var state = ParserState(text: markdown)
        if prescan {
            return InlineParser.parseInlineElementsByPrescanningPlainTextForTesting(&state, configuration: .default)
        }
        return InlineParser.parseInlineElements(&state, configuration: .default)
    }

    private func inlineNodesBenchmarkChecksum(_ nodes: [MarkdownParser.InlineNode]) -> Int {
        nodes.reduce(0) { $0 + inlineNodeBenchmarkChecksum($1) }
    }

    private func inlineNodeBenchmarkChecksum(_ node: MarkdownParser.InlineNode) -> Int {
        switch node {
        case .text(let text), .code(let text), .html(let text), .footnoteReference(let text):
            return text.utf8.count
        case .emphasis(let children), .strong(let children), .strikethrough(let children):
            return 1 + children.reduce(0) { $0 + inlineNodeBenchmarkChecksum($1) }
        case .link(let url, let title, let children):
            return url.absoluteString.utf8.count +
                (title?.utf8.count ?? 0) +
                children.reduce(0) { $0 + inlineNodeBenchmarkChecksum($1) }
        case .image(let url, let alt, let title):
            return url.absoluteString.utf8.count + alt.utf8.count + (title?.utf8.count ?? 0)
        case .autolink(let url, _, let originalText):
            return url.absoluteString.utf8.count + originalText.utf8.count
        case .mention(let username):
            return username.utf8.count
        case .issueReference(let number):
            return number
        case .commitSHA(let sha, let short):
            return sha.utf8.count + short.utf8.count
        case .repositoryReference(let owner, let repo):
            return owner.utf8.count + repo.utf8.count
        case .pullRequestReference(let owner, let repo, let number):
            return owner.utf8.count + repo.utf8.count + number
        case .lineBreak, .softBreak:
            return 1
        case .extensionInline(let node):
            return node.namespace.utf8.count + node.name.utf8.count + node.literal.utf8.count + node.fields.count
        }
    }

    // MARK: - Item 13 Inline Measurement Data

    private func makeRepresentativeInlineMeasurementSamples() throws -> [[MarkdownParser.InlineNode]] {
        let exampleURL = try XCTUnwrap(URL(string: "https://example.com/docs/table"))
        return [
            [.text("Plain table content")],
            [.strong(children: [.text("Bold"), .text(" header")])],
            [.emphasis(children: [.text("Italic value")])],
            [.strikethrough(children: [.text("Removed value")])],
            [.code("let value = row.count")],
            [.link(url: exampleURL, title: "Example", children: [.text("linked text")])],
            [.autolink(exampleURL, .url, originalText: "https://example.com/docs/table")],
            [.mention(username: "alice"), .text(" opened "), .issueReference(number: 42)],
            [
                .repositoryReference(owner: "openai", repo: "glimmer"),
                .text(" "),
                .pullRequestReference(owner: "openai", repo: "glimmer", number: 7)
            ],
            [.commitSHA(sha: "abcdef1234567890", short: "abcdef1")],
            [.image(url: exampleURL, alt: "diagram alt text", title: nil)],
            [.text("before"), .softBreak, .text("after")],
            [.text("before"), .lineBreak, .text("after")],
            [.footnoteReference(label: "inline-1"), .text(" footnote")],
            [
                .extensionInline(
                    MarkdownParser.ExtensionNode(
                        namespace: "test",
                        name: "token",
                        literal: "{{token}}",
                        fields: [:]
                    )
                )
            ]
        ]
    }

}

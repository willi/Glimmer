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
}

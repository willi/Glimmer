import XCTest
@testable import Glimmer

final class ParallelSplitterTests: XCTestCase {
    func testRangeSplitterUTF8ClassificationMatchesRepeatedScanEdges() {
        let documents = [
            "",
            "alpha\n",
            "alpha\r\nbeta\r\n\nend",
            "emoji \u{1F680} before split\n\ncafe\u{0301} after\n",
            "```\n| not a table |\n- not a list\n```\n\nnext\n",
            "  ```\nnot a fence because leading space\n```\n",
            "| A | B |\n|:---:|---:|\n| x | y |\n\n",
            "A | B\n| - | - |\n\n",
            "> quote\nlazy continuation\n   \nstill quoted until true blank\n\nnext\n",
            " > not a blockquote start\n\n",
            "- item\n-\titem is continuation\n\n",
            "1.foo\n1.\n1) item\n\u{0661}. unicode ordered\n\u{0661}2. mixed ordered\n\n",
            "Heading\n=\n\nHeading\n-=-\n\n"
        ]

        for markdown in documents {
            for chunkSize in [1, 8, 16, 64] {
                assertRangeChunksEqualToRepeatedScan(markdown, chunkSize: chunkSize)
            }
        }
    }

    func testParallelPreservesSetextHeading() {
        let cfg = ParallelMarkdownParser.ParallelConfiguration(concurrency: 2, minimumSizeThreshold: 0, chunkSize: 10, preserveOrder: true)
        let parser = ParallelMarkdownParser(parallelConfig: cfg, markdownConfig: .default)
        let md = "Heading\n=====\n\nNext"
        let blocks = parser.parse(md)
        XCTAssertTrue(blocks.contains { if case .heading(let level, _, _) = $0 { return level == 1 } else { return false } })
    }

    func testParallelPreservesBlockquoteAndList() {
        let cfg = ParallelMarkdownParser.ParallelConfiguration(concurrency: 2, minimumSizeThreshold: 0, chunkSize: 8, preserveOrder: true)
        let parser = ParallelMarkdownParser(parallelConfig: cfg, markdownConfig: .default)
        let md = "> quote line 1\n> quote line 2\n\n- a\n- b\n"
        let blocks = parser.parse(md)
        XCTAssertTrue(blocks.contains { if case .blockquote = $0 { return true } else { return false } })
        XCTAssertTrue(blocks.contains { if case .list = $0 { return true } else { return false } })
    }

    func testParallelRangeChunksMatchSerialParserForBoundaryCorpus() {
        let markdown = ParserBoundaryCorpus.parallelChunkBoundary(repetitions: 18)
        let serial = MarkdownParser.parse(markdown, configuration: .github)

        for chunkSize in [16, 48, 257] {
            let cfg = ParallelMarkdownParser.ParallelConfiguration(
                concurrency: 3,
                minimumSizeThreshold: 0,
                chunkSize: chunkSize,
                preserveOrder: true
            )
            let parser = ParallelMarkdownParser(parallelConfig: cfg, markdownConfig: .github)
            let parallel = parser.parse(markdown)

            ParserCanonicalSnapshot.assertSemanticallyEqual(
                parallel,
                serial,
                "Parallel parser semantic output changed for chunkSize \(chunkSize)"
            )
        }
    }

    private func assertRangeChunksEqualToRepeatedScan(
        _ markdown: String,
        chunkSize: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let repeated = ParallelChunkSplitter.splitRangesByRepeatedLineScanningForTesting(
            markdown: markdown,
            chunkSize: chunkSize
        )
        let classified = ParallelChunkSplitter.splitRanges(markdown: markdown, chunkSize: chunkSize)

        XCTAssertEqual(classified.count, repeated.count, file: file, line: line)

        for (lhs, rhs) in zip(classified, repeated) {
            XCTAssertEqual(lhs.index, rhs.index, file: file, line: line)
            XCTAssertEqual(lhs.startOffset, rhs.startOffset, file: file, line: line)
            XCTAssertEqual(lhs.range.lowerBound, rhs.range.lowerBound, file: file, line: line)
            XCTAssertEqual(lhs.range.upperBound, rhs.range.upperBound, file: file, line: line)
            XCTAssertEqual(markdown[lhs.range], markdown[rhs.range], file: file, line: line)
        }
    }
}

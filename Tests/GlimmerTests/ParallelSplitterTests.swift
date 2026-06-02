import XCTest
@testable import Glimmer

final class ParallelSplitterTests: XCTestCase {
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
}


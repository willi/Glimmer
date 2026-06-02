import XCTest
@testable import Glimmer

final class StreamingParserTests: XCTestCase {
    func testStreamingChunkBoundaries() {
        let parser = StreamingMarkdownParser(configuration: .default)
        var blocks: [MarkdownParser.BlockNode] = []
        blocks.append(contentsOf: parser.parseChunk("# Title\n"))
        blocks.append(contentsOf: parser.parseChunk("\nParagraph"))
        blocks.append(contentsOf: parser.parseChunk(" continues.\n"))
        blocks.append(contentsOf: parser.finish())

        // Expect a heading and a paragraph
        XCTAssertTrue(blocks.contains { if case .heading = $0 { return true } else { return false } })
        XCTAssertTrue(blocks.contains { if case .paragraph = $0 { return true } else { return false } })
    }

    func testStreamingTablesCollects() {
        let parser = StreamingMarkdownParser(configuration: .default)
        var blocks: [MarkdownParser.BlockNode] = []
        blocks += parser.parseChunk("| H1 | H2 |\n")
        blocks += parser.parseChunk("| --- | ---:|\n")
        blocks += parser.parseChunk("| a | b |\n")
        blocks += parser.parseChunk("| c | d |\n")
        // Non-table line flushes the table
        blocks += parser.parseChunk("Paragraph after table.\n")
        blocks += parser.finish()

        XCTAssertTrue(blocks.contains { if case .table = $0 { return true } else { return false } })
    }

    func testStreamingTableFalsePositiveHeader() {
        let parser = StreamingMarkdownParser(configuration: .default)
        var blocks: [MarkdownParser.BlockNode] = []
        // Header-like line but next line is not a separator
        blocks += parser.parseChunk("| Not | A Table |\n")
        blocks += parser.parseChunk("Not a separator\n")
        blocks += parser.finish()

        // Should not contain a table; should contain paragraph(s)
        XCTAssertFalse(blocks.contains { if case .table = $0 { return true } else { return false } })
        XCTAssertTrue(blocks.contains { if case .paragraph = $0 { return true } else { return false } })
    }

    func testStreamingTableFlushesAtEOFWithoutTrailingNonTableLine() {
        let parser = StreamingMarkdownParser(configuration: .default)
        var blocks: [MarkdownParser.BlockNode] = []
        blocks += parser.parseChunk("| H1 | H2 |\n")
        blocks += parser.parseChunk("| --- | --- |\n")
        blocks += parser.parseChunk("| a | b |\n")
        blocks += parser.finish()

        XCTAssertTrue(blocks.contains { if case .table = $0 { return true } else { return false } })
    }

    func testStreamingPendingTableHeaderFlushesAsParagraphAtEOF() {
        let parser = StreamingMarkdownParser(configuration: .default)
        var blocks: [MarkdownParser.BlockNode] = []
        blocks += parser.parseChunk("| maybe | just text |\n")
        blocks += parser.finish()

        XCTAssertFalse(blocks.isEmpty)
        XCTAssertTrue(blocks.contains { if case .paragraph = $0 { return true } else { return false } })
        XCTAssertFalse(blocks.contains { if case .table = $0 { return true } else { return false } })
    }
}

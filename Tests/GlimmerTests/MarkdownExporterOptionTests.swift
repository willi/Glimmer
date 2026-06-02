import XCTest
@testable import Glimmer

final class MarkdownExporterOptionTests: XCTestCase {
    func testExporterUsesSetextForLevelOneWhenATXDisabled() {
        let blocks: [MarkdownParser.BlockNode] = [
            .heading(level: 1, children: [.text("Title")], id: nil)
        ]

        var options = MarkdownExporter.ExportOptions()
        options.useATXHeaders = false
        options.includeTrailingNewline = false

        let exported = MarkdownExporter.export(blocks, options: options)
        XCTAssertTrue(exported.contains("Title\n====="))
    }

    func testExporterUsesCustomUnorderedListMarker() {
        let blocks = MarkdownParser.parse("- one\n- two")

        var options = MarkdownExporter.ExportOptions()
        options.unorderedListMarker = "*"
        options.includeTrailingNewline = false

        let exported = MarkdownExporter.export(blocks, options: options)
        XCTAssertTrue(exported.contains("* one"))
        XCTAssertTrue(exported.contains("* two"))
    }

    func testExporterUsesCustomEmphasisAndStrongMarkers() {
        let inlines: [MarkdownParser.InlineNode] = [
            .emphasis(children: [.text("it")]),
            .text(" "),
            .strong(children: [.text("bold")])
        ]

        var options = MarkdownExporter.ExportOptions()
        options.emphasisMarker = "_"
        options.strongMarker = "__"

        let exported = MarkdownExporter.exportInlines(inlines, options: options)
        XCTAssertEqual(exported, "_it_ __bold__")
    }

    func testExporterPreservesTaskCheckboxState() {
        let blocks = MarkdownParser.parse("""
        - [ ] todo
        - [x] done
        """)

        var options = MarkdownExporter.ExportOptions()
        options.includeTrailingNewline = false

        let exported = MarkdownExporter.export(blocks, options: options)
        XCTAssertTrue(exported.contains("- [ ] todo"))
        XCTAssertTrue(exported.contains("- [x] done"))
    }

    func testExporterEscapesMarkdownSpecialCharactersInText() {
        let inlines: [MarkdownParser.InlineNode] = [.text("a*b [x] (y)")]
        let exported = MarkdownExporter.exportInlines(inlines)

        XCTAssertTrue(exported.contains("a\\*b"))
        XCTAssertTrue(exported.contains("\\[x\\]"))
        XCTAssertTrue(exported.contains("\\(y\\)"))
    }
}

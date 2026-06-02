import XCTest
@testable import Glimmer

final class CustomRendererTests: XCTestCase {
    func testHTMLRendererRendersGitHubReferencesAndAutolinks() {
        let markdown = "@alice fixed #42 in owner/repo and owner/repo#7 at https://example.com commit deadbeef."
        let blocks = MarkdownParser.parse(markdown)
        let renderer = HTMLMarkdownRenderer()
        let html = renderer.render(blocks: blocks, configuration: .default)

        XCTAssertTrue(html.contains("https://github.com/alice"))
        XCTAssertTrue(html.contains("class=\"issue-ref\">#42"))
        XCTAssertTrue(html.contains("https://github.com/owner/repo\""))
        XCTAssertTrue(html.contains("https://github.com/owner/repo/pull/7"))
        XCTAssertTrue(html.contains("class=\"commit-sha\">deadbee"))
        XCTAssertTrue(html.contains("class=\"autolink\">https://example.com"))
    }

    func testHTMLRendererWrapInHTMLIncludesBoilerplate() {
        var options = HTMLMarkdownRenderer.HTMLRenderOptions()
        options.wrapInHTML = true
        options.includeCSS = true

        let renderer = HTMLMarkdownRenderer(options: options)
        let html = renderer.render(
            blocks: [.paragraph(children: [.text("hello")])],
            configuration: .default
        )

        XCTAssertTrue(html.contains("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("<style>"))
        XCTAssertTrue(html.contains("<body>"))
        XCTAssertTrue(html.contains("hello"))
    }

    func testPlainTextRendererStripsFormattingMarkers() {
        let markdown = """
        # Title

        This is **bold** and [link](https://example.com) with ![logo](https://img.test).
        """
        let blocks = MarkdownParser.parse(markdown)
        let renderer = PlainTextMarkdownRenderer()
        let text = renderer.render(blocks: blocks, configuration: .default)

        XCTAssertTrue(text.contains("TITLE"))
        XCTAssertTrue(text.contains("bold"))
        XCTAssertTrue(text.contains("link"))
        XCTAssertTrue(text.contains("[Image: logo]"))
        XCTAssertFalse(text.contains("**"))
        XCTAssertFalse(text.contains("]("))
    }

    func testPlainTextRendererTaskListNodeFormatting() {
        let blocks: [MarkdownParser.BlockNode] = [
            .taskList(items: [
                MarkdownParser.TaskListItem(isChecked: false, content: [.text("todo")]),
                MarkdownParser.TaskListItem(isChecked: true, content: [.text("done")])
            ])
        ]

        let renderer = PlainTextMarkdownRenderer()
        let text = renderer.render(blocks: blocks, configuration: .default)

        XCTAssertTrue(text.contains("[ ] todo"))
        XCTAssertTrue(text.contains("[x] done"))
    }
}

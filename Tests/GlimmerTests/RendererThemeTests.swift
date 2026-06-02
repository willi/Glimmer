import XCTest
@testable import Glimmer

final class RendererThemeTests: XCTestCase {
    func testCodeBlockUsesThemeBackground() {
        let md = """
        ```swift
        print("hi")
        ```
        """
        var config = MarkdownConfiguration()
        config.codeBlockTheme = .dark

        // Render via public API
        let rendered = Glimmer.parseToAttributedString(md, configuration: config)

        // Find a run with background color matching theme
        var found = false
        rendered.runs.forEach { run in
            if let bg = run.backgroundColor, bg == CodeHighlightingTheme.dark.background {
                found = true
            }
        }
        XCTAssertTrue(found, "Expected code block to use theme background")
    }
}


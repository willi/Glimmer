import XCTest
import SwiftUI
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

    func testDefaultPlainTextInlineAvoidsExplicitPrimaryForegroundColor() {
        let rendered = MarkdownRenderer().renderInlines(
            [.text("plain")],
            configuration: .default
        )

        XCTAssertEqual(String(rendered.characters), "plain")
        XCTAssertNil(rendered.runs.first?.foregroundColor)
    }

    func testSinglePlainTextInlineUsesBaseFontAndTextColor() {
        var config = MarkdownConfiguration.default
        config.textColor = .red
        let baseFont = Font.title2
        let rendered = MarkdownRenderer().renderInlines(
            [.text("plain")],
            configuration: config,
            baseFont: baseFont
        )

        XCTAssertEqual(String(rendered.characters), "plain")
        XCTAssertEqual(rendered.runs.first?.font, baseFont)
        XCTAssertEqual(rendered.runs.first?.foregroundColor, config.textColor)
    }

    func testLinkContextStylesNestedInlineRuns() {
        var config = MarkdownConfiguration.default
        config.linkColor = .purple
        let rendered = Glimmer.parseToAttributedString(
            "[**bold** and `code`](https://example.com)",
            configuration: config
        )

        let linkedRuns = rendered.runs.filter { $0.link?.host == "example.com" }
        XCTAssertFalse(linkedRuns.isEmpty)
        XCTAssertTrue(linkedRuns.allSatisfy { $0.foregroundColor == config.linkColor })
        XCTAssertTrue(linkedRuns.contains { $0.backgroundColor == config.codeBackgroundColor })
    }

    func testLinkContextOverridesCustomPlainTextColor() {
        var config = MarkdownConfiguration.default
        config.textColor = .red
        config.linkColor = .green
        let rendered = Glimmer.parseToAttributedString("[plain](https://example.com)", configuration: config)

        let linkRun = rendered.runs.first { $0.link?.host == "example.com" }
        XCTAssertEqual(linkRun?.foregroundColor, config.linkColor)
    }

    func testHeadingAppliesHeadingFontWithoutDroppingInlineStyling() {
        var config = MarkdownConfiguration.default
        config.headingFonts[0] = .title
        config.linkColor = .green
        config.codeBackgroundColor = .yellow

        let rendered = Glimmer.parseToAttributedString(
            "# Plain [link](https://example.com) `code`",
            configuration: config
        )

        XCTAssertEqual(String(rendered.characters), "Plain link code")
        XCTAssertTrue(rendered.runs.allSatisfy { $0.font == config.headingFonts[0] })

        let linkRun = rendered.runs.first { $0.link?.host == "example.com" }
        XCTAssertEqual(linkRun?.foregroundColor, config.linkColor)

        let codeRun = rendered.runs.first { run in
            String(rendered[run.range].characters) == "code"
        }
        XCTAssertEqual(codeRun?.backgroundColor, config.codeBackgroundColor)
    }

    func testBuiltInInlineRenderPlanPreservesNestedStyling() throws {
        var config = MarkdownConfiguration.default
        config.linkColor = .green
        config.mentionColor = .orange
        config.issueColor = .purple
        config.codeBackgroundColor = .yellow

        let url = try XCTUnwrap(URL(string: "https://example.com"))
        var renderer = MarkdownRenderer()
        renderer.beginSession(configuration: config)

        let rendered = renderer.renderInlines(
            [
                .text("plain "),
                .strong(children: [.text("bold")]),
                .text(" "),
                .emphasis(children: [.text("italic")]),
                .text(" "),
                .link(url: url, title: nil, children: [.text("link "), .code("code")]),
                .text(" "),
                .strikethrough(children: [.text("strike")]),
                .text(" "),
                .mention(username: "octocat"),
                .text(" "),
                .issueReference(number: 42),
                .text(" "),
                .footnoteReference(label: "1")
            ],
            configuration: config,
            baseFont: .body
        )

        XCTAssertEqual(String(rendered.characters), "plain bold italic link code strike @octocat #42 [1]")

        let codeRun = rendered.runs.first { String(rendered[$0.range].characters) == "code" }
        XCTAssertEqual(codeRun?.backgroundColor, config.codeBackgroundColor)
        XCTAssertEqual(codeRun?.link?.host, "example.com")
        XCTAssertEqual(codeRun?.foregroundColor, config.linkColor)

        let strikeRun = rendered.runs.first { String(rendered[$0.range].characters) == "strike" }
        XCTAssertEqual(strikeRun?.strikethroughStyle, .single)

        let mentionRun = rendered.runs.first { String(rendered[$0.range].characters) == "@octocat" }
        XCTAssertEqual(mentionRun?.foregroundColor, config.mentionColor)

        let issueRun = rendered.runs.first { String(rendered[$0.range].characters) == "#42" }
        XCTAssertEqual(issueRun?.foregroundColor, config.issueColor)

        let footnoteRun = rendered.runs.first { String(rendered[$0.range].characters) == "[1]" }
        XCTAssertEqual(footnoteRun?.link?.fragment, "footnote-1")
    }
}

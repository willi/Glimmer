import XCTest
@testable import Glimmer

final class ParserFeatureCoverageTests: XCTestCase {
    func testSetextHeadingParsesLevelAndID() {
        let markdown = """
        Setext Title
        ============
        """

        let blocks = MarkdownParser.parse(markdown)
        guard case .heading(let level, let children, let id) = blocks.first else {
            return XCTFail("Expected first block to be a heading")
        }

        XCTAssertEqual(level, 1)
        XCTAssertEqual(id, "setext-title")
        XCTAssertEqual(extractText(children), "Setext Title")
    }

    func testHorizontalRuleParsesAsDedicatedBlock() {
        let markdown = """
        Before

        ---

        After
        """

        let blocks = MarkdownParser.parse(markdown)
        XCTAssertTrue(blocks.contains { if case .horizontalRule = $0 { return true } else { return false } })
    }

    func testBlockquoteParsesWithNestedParagraph() {
        let markdown = """
        > Quote line 1
        > Quote line 2
        """

        let blocks = MarkdownParser.parse(markdown)
        guard case .blockquote(let children) = blocks.first else {
            return XCTFail("Expected blockquote")
        }
        guard case .paragraph(let inlines) = children.first else {
            return XCTFail("Expected paragraph inside blockquote")
        }

        XCTAssertTrue(extractText(inlines).contains("Quote line 1"))
        XCTAssertTrue(extractText(inlines).contains("Quote line 2"))
    }

    func testIndentedCodeBlockParses() {
        let markdown = """
            let x = 1
            print(x)
        """

        let blocks = MarkdownParser.parse(markdown)
        guard case .codeBlock(let language, let content) = blocks.first else {
            return XCTFail("Expected code block")
        }

        XCTAssertNil(language)
        XCTAssertTrue(content.contains("let x = 1"))
        XCTAssertTrue(content.contains("print(x)"))
    }

    func testFencedCodeBlockParsesLanguageAndContent() {
        let markdown = """
        ```swift
        print("hello")
        ```
        """

        let blocks = MarkdownParser.parse(markdown)
        guard case .codeBlock(let language, let content) = blocks.first else {
            return XCTFail("Expected code block")
        }

        XCTAssertEqual(language, "swift")
        XCTAssertTrue(content.contains("print(\"hello\")"))
    }

    func testTaskListCheckboxesAreCapturedOnListItems() {
        let markdown = """
        - [ ] open
        - [x] done
        """

        let blocks = MarkdownParser.parse(markdown)
        guard case .list(let ordered, _, let items) = blocks.first else {
            return XCTFail("Expected list block")
        }

        XCTAssertFalse(ordered)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.isTask), [true, true])
        XCTAssertEqual(items.map(\.isChecked), [false, true])
    }

    func testFootnoteReferenceAndDefinitionParse() {
        let markdown = """
        Ref[^1]

        [^1]: Footnote text
        """

        let blocks = MarkdownParser.parse(markdown)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected first block to be paragraph")
        }
        XCTAssertTrue(inlines.contains { if case .footnoteReference(let label) = $0 { return label == "1" } else { return false } })

        let definition = blocks.first { block in
            if case .footnoteDefinition(let label, _) = block {
                return label == "1"
            }
            return false
        }
        guard case .footnoteDefinition(_, let children) = definition else {
            return XCTFail("Expected footnote definition")
        }
        guard case .paragraph(let footnoteInlines) = children.first else {
            return XCTFail("Expected paragraph in footnote definition")
        }
        XCTAssertTrue(extractText(footnoteInlines).contains("Footnote text"))
    }

    func testIssueReferenceParses() {
        let markdown = "Fixes #123."
        let blocks = MarkdownParser.parse(markdown)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }

        XCTAssertTrue(inlines.contains { if case .issueReference(let n) = $0 { return n == 123 } else { return false } })
    }

    func testInlineFormattingParsesEmphasisStrongStrikeAndCode() {
        let markdown = "*italic* **bold** ~~gone~~ `code`"
        let blocks = MarkdownParser.parse(markdown)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }

        XCTAssertTrue(inlines.contains { if case .emphasis = $0 { return true } else { return false } })
        XCTAssertTrue(inlines.contains { if case .strong = $0 { return true } else { return false } })
        XCTAssertTrue(inlines.contains { if case .strikethrough = $0 { return true } else { return false } })
        XCTAssertTrue(inlines.contains { if case .code(let text) = $0 { return text == "code" } else { return false } })
    }

    func testInlineHTMLTagParsesAsHTMLNode() {
        let markdown = "Hello <br> world"
        let blocks = MarkdownParser.parse(markdown)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }

        XCTAssertTrue(inlines.contains { if case .html(let html) = $0 { return html == "<br>" } else { return false } })
    }

    func testEmojiShortcodeParsesToUnicodeText() {
        let markdown = ":rocket:"
        let blocks = MarkdownParser.parse(markdown)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }

        XCTAssertTrue(inlines.contains { if case .text(let text) = $0 { return text.contains("🚀") } else { return false } })
    }

    func testCustomEmojiShortcodeParsesAsImageWhenAvailable() throws {
        guard GitHubEmojis.emojiMap["octocat"] != nil else {
            throw XCTSkip("octocat shortcode is not present in emoji map")
        }

        let markdown = ":octocat:"
        let blocks = MarkdownParser.parse(markdown)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }

        XCTAssertTrue(inlines.contains {
            if case .image(_, let alt, _) = $0 {
                return alt == ":octocat:"
            }
            return false
        })
    }

    private func extractText(_ inlines: [MarkdownParser.InlineNode]) -> String {
        inlines.map { inline in
            switch inline {
            case .text(let text):
                return text
            case .emphasis(let children), .strong(let children), .strikethrough(let children):
                return extractText(children)
            case .code(let code):
                return code
            case .link(_, _, let children):
                return extractText(children)
            case .autolink(_, _, let original):
                return original
            case .mention(let username):
                return "@\(username)"
            case .issueReference(let number):
                return "#\(number)"
            case .commitSHA(_, let short):
                return short
            case .repositoryReference(let owner, let repo):
                return "\(owner)/\(repo)"
            case .pullRequestReference(let owner, let repo, let number):
                return "\(owner)/\(repo)#\(number)"
            case .lineBreak, .softBreak:
                return "\n"
            case .html(let html):
                return html
            case .image(_, let alt, _):
                return alt
            case .footnoteReference(let label):
                return "[^\(label)]"
            }
        }.joined()
    }
}

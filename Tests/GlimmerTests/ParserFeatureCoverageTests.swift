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

    func testSetextHeadingIDMatchesATXSlugification() {
        let setextMarkdown = """
        Mixed Heading! Value 42
        =======================
        """
        let atxMarkdown = "# Mixed Heading! Value 42"

        let setextBlocks = MarkdownParser.parse(setextMarkdown)
        let atxBlocks = MarkdownParser.parse(atxMarkdown)
        guard case .heading(_, _, let setextID) = setextBlocks.first,
              case .heading(_, _, let atxID) = atxBlocks.first else {
            return XCTFail("Expected heading blocks")
        }

        XCTAssertEqual(setextID, atxID)
        XCTAssertEqual(setextID, "mixed-heading-value-42")
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

    func testBlockquoteLazyContinuationStopsBeforeNewBlockStarts() {
        let markdown = """
        > Quote line
        - list item

        > Second quote
        # Heading

        > Third quote
        | A | B |
        |---|---|
        | 1 | 2 |
        """

        let blocks = MarkdownParser.parse(markdown, configuration: .github)
        XCTAssertEqual(blocks.count, 6)

        guard case .blockquote(let firstQuote) = blocks[0],
              case .list = blocks[1],
              case .blockquote(let secondQuote) = blocks[2],
              case .heading = blocks[3],
              case .blockquote(let thirdQuote) = blocks[4],
              case .table = blocks[5] else {
            return XCTFail("Expected lazy blockquote continuations to stop before list, heading, and table blocks")
        }

        XCTAssertEqual(extractBlockText(firstQuote), "Quote line")
        XCTAssertEqual(extractBlockText(secondQuote), "Second quote")
        XCTAssertEqual(extractBlockText(thirdQuote), "Third quote")
    }

    func testBlockquotePreservesMarkedBlankLinesAsParagraphBreaks() {
        let markdown = """
        > first paragraph
        >
        > second paragraph
        """

        let blocks = MarkdownParser.parse(markdown)
        guard case .blockquote(let children) = blocks.first else {
            return XCTFail("Expected blockquote")
        }

        XCTAssertEqual(children.count, 2)
        guard case .paragraph(let first) = children[0],
              case .paragraph(let second) = children[1] else {
            return XCTFail("Expected two paragraphs inside blockquote")
        }
        XCTAssertEqual(extractText(first), "first paragraph")
        XCTAssertEqual(extractText(second), "second paragraph")
    }

    func testBlockquoteParsesNestedBlocksAfterRangeBackedCollection() {
        let markdown = """
        > ## Quoted Heading
        >
        > - first
        > - second
        >
        > ```swift
        > let x = 1
        > ```
        >
        > | A | B |
        > |---|---|
        > | 1 | 2 |
        """

        let blocks = MarkdownParser.parse(markdown, configuration: .github)
        guard case .blockquote(let children) = blocks.first else {
            return XCTFail("Expected blockquote")
        }

        XCTAssertEqual(children.count, 4)
        guard case .heading(let level, let heading, _) = children[0],
              case .list = children[1],
              case .codeBlock(let language, let content) = children[2],
              case .table(let header, let rows) = children[3] else {
            return XCTFail("Expected heading, list, code block, and table inside blockquote")
        }
        XCTAssertEqual(level, 2)
        XCTAssertEqual(extractText(heading), "Quoted Heading")
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(content, "let x = 1")
        XCTAssertEqual(header.map { extractText($0.content) }, ["A", "B"])
        XCTAssertEqual(rows.count, 1)
    }

    func testBlockquoteLazyContinuationAndUnicodeTextStayInQuote() {
        let markdown = """
        > café quoted
        continued 世界

        outside
        """

        let blocks = MarkdownParser.parse(markdown)
        XCTAssertEqual(blocks.count, 2)
        guard case .blockquote(let children) = blocks[0],
              case .paragraph(let outside) = blocks[1] else {
            return XCTFail("Expected blockquote followed by outside paragraph")
        }

        XCTAssertEqual(extractBlockText(children), "café quoted\ncontinued 世界")
        XCTAssertEqual(extractText(outside), "outside")
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

    func testIndentedCodeBlockPreservesBlankLinesAndExtraIndentation() {
        let markdown = """
            alpha
                beta

            gamma
        next
        """

        let blocks = MarkdownParser.parse(markdown)
        XCTAssertEqual(blocks.count, 2)
        guard case .codeBlock(let language, let content) = blocks.first else {
            return XCTFail("Expected first block to be code block")
        }
        guard case .paragraph(let inlines) = blocks.last else {
            return XCTFail("Expected paragraph after indented code block")
        }

        XCTAssertNil(language)
        XCTAssertEqual(content, "alpha\n    beta\n\ngamma")
        XCTAssertEqual(extractText(inlines), "next")
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

    func testFencedCodeBlockPreservesExactMultilineContent() {
        let markdown = """
        ```swift
        line one
        line two
        ```
        """

        let blocks = MarkdownParser.parse(markdown)
        guard case .codeBlock(let language, let content) = blocks.first else {
            return XCTFail("Expected code block")
        }

        XCTAssertEqual(language, "swift")
        XCTAssertEqual(content, "line one\nline two")
    }

    func testTildeFencedCodeBlockParses() {
        let markdown = """
        ~~~text
        alpha
        beta
        ~~~
        """

        let blocks = MarkdownParser.parse(markdown)
        guard case .codeBlock(let language, let content) = blocks.first else {
            return XCTFail("Expected code block")
        }

        XCTAssertEqual(language, "text")
        XCTAssertEqual(content, "alpha\nbeta")
    }

    func testUnclosedFencedCodeBlockPreservesContentWithoutTrailingNewline() {
        let markdown = """
        ```
        alpha
        beta
        """

        let blocks = MarkdownParser.parse(markdown)
        guard case .codeBlock(let language, let content) = blocks.first else {
            return XCTFail("Expected code block")
        }

        XCTAssertNil(language)
        XCTAssertEqual(content, "alpha\nbeta")
    }

    func testFencedCodeBlockPreservesUnicodeContent() {
        let markdown = """
        ```swift
        let greeting = "こんにちは"
        print("✅")
        ```
        """

        let blocks = MarkdownParser.parse(markdown)
        guard case .codeBlock(let language, let content) = blocks.first else {
            return XCTFail("Expected code block")
        }

        XCTAssertEqual(language, "swift")
        XCTAssertEqual(content, "let greeting = \"こんにちは\"\nprint(\"✅\")")
    }

    func testMultilineParagraphPreservesUnicodeContent() {
        let markdown = """
        Hello こんにちは
        second line ✅
        """

        let blocks = MarkdownParser.parse(markdown)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }

        XCTAssertEqual(extractText(inlines), "Hello こんにちは\nsecond line ✅")
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

    func testListItemParagraphContinuationPreservesInlineMarkdownAndUnicode() {
        let markdown = """
        - first line with *emphasis*
          continued line with こんにちは and `code`
        - second item
        """

        let blocks = MarkdownParser.parse(markdown)
        guard case .list(false, _, let items) = blocks.first else {
            return XCTFail("Expected unordered list")
        }
        XCTAssertEqual(items.count, 2)

        guard case .paragraph(let firstInlines) = items[0].content.first else {
            return XCTFail("Expected first item to be a paragraph")
        }

        XCTAssertEqual(extractText(firstInlines), "first line with emphasis\ncontinued line with こんにちは and code")
        XCTAssertTrue(firstInlines.contains { if case .emphasis = $0 { return true } else { return false } })
        XCTAssertTrue(firstInlines.contains { if case .code("code") = $0 { return true } else { return false } })
    }

    func testListItemNestedBlocksStillUseBlockParserFallback() {
        let markdown = """
        - parent
            - nested item
            - nested second
        after
        """

        let blocks = MarkdownParser.parse(markdown)
        XCTAssertEqual(blocks.count, 2)

        guard case .list(false, _, let outerItems) = blocks[0] else {
            return XCTFail("Expected outer list")
        }
        XCTAssertEqual(outerItems.count, 1)
        XCTAssertGreaterThanOrEqual(outerItems[0].content.count, 2)

        guard case .paragraph(let parentInlines) = outerItems[0].content[0] else {
            return XCTFail("Expected parent paragraph")
        }
        XCTAssertEqual(extractText(parentInlines), "parent")

        guard case .list(false, _, let nestedItems) = outerItems[0].content[1] else {
            return XCTFail("Expected nested list fallback")
        }
        XCTAssertEqual(nestedItems.count, 2)

        guard case .paragraph(let afterInlines) = blocks[1] else {
            return XCTFail("Expected parsing to resume after list")
        }
        XCTAssertEqual(extractText(afterInlines), "after")
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

    func testFootnoteDefinitionPreservesTrimmedContinuationBlocks() {
        let markdown = "[^note]:   First line with *emphasis*   \n" +
            "    continued line with こんにちは\n" +
            "    \n" +
            "    - nested item\n" +
            "    - second item\n" +
            "\n" +
            "after"

        let blocks = MarkdownParser.parse(markdown)
        XCTAssertEqual(blocks.count, 2)

        guard case .footnoteDefinition(let label, let children) = blocks[0] else {
            return XCTFail("Expected first block to be a footnote definition")
        }
        XCTAssertEqual(label, "note")
        XCTAssertGreaterThanOrEqual(children.count, 2)

        guard case .paragraph(let paragraphInlines) = children.first else {
            return XCTFail("Expected footnote definition to start with a paragraph")
        }
        XCTAssertEqual(extractText(paragraphInlines), "First line with emphasis   \ncontinued line with こんにちは")
        XCTAssertTrue(paragraphInlines.contains { if case .emphasis = $0 { return true } else { return false } })

        guard case .list(let ordered, _, let items) = children[1] else {
            return XCTFail("Expected nested list inside footnote definition")
        }
        XCTAssertFalse(ordered)
        XCTAssertEqual(items.count, 2)

        guard case .paragraph(let afterInlines) = blocks[1] else {
            return XCTFail("Expected parsing to resume after the footnote definition")
        }
        XCTAssertEqual(extractText(afterInlines), "after")
    }

    func testFootnoteDefinitionAcceptsTabContinuation() {
        let markdown = "[^tab]: start\n\tcontinued with `code`"
        let blocks = MarkdownParser.parse(markdown)

        guard case .footnoteDefinition("tab", let children) = blocks.first,
              case .paragraph(let inlines) = children.first else {
            return XCTFail("Expected tab-indented footnote continuation")
        }

        XCTAssertEqual(extractText(inlines), "start\ncontinued with code")
        XCTAssertTrue(inlines.contains { if case .code("code") = $0 { return true } else { return false } })
    }

    func testIssueReferenceParses() {
        let markdown = "Fixes #123."
        let blocks = MarkdownParser.parse(markdown, configuration: .github)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }

        XCTAssertTrue(inlines.contains { if case .issueReference(let n) = $0 { return n == 123 } else { return false } })
    }

    func testAutolinkDispatchDoesNotBlockRepositoryReference() {
        let markdown = "See https://example.com and hello/world"
        let blocks = MarkdownParser.parse(markdown, configuration: .github)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }

        XCTAssertTrue(inlines.contains {
            if case .autolink(_, .url, let originalText) = $0 {
                return originalText == "https://example.com"
            }
            return false
        })
        XCTAssertTrue(inlines.contains {
            if case .repositoryReference(let owner, let repo) = $0 {
                return owner == "hello" && repo == "world"
            }
            return false
        })
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

    func testStrikethroughPreservesNestedInlineContentAndUnicodeFallback() {
        let markdown = "~~gone **bold** and `code`~~ plus ~~café 世界~~"
        let blocks = MarkdownParser.parse(markdown)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }

        let strikes = inlines.compactMap { inline -> [MarkdownParser.InlineNode]? in
            if case .strikethrough(let children) = inline {
                return children
            }
            return nil
        }

        XCTAssertEqual(strikes.count, 2)
        XCTAssertEqual(extractText(strikes[0]), "gone bold and code")
        XCTAssertTrue(strikes[0].contains { if case .strong = $0 { return true } else { return false } })
        XCTAssertTrue(strikes[0].contains { if case .code("code") = $0 { return true } else { return false } })
        XCTAssertEqual(extractText(strikes[1]), "café 世界")
    }

    func testInlineCodeRequiresEqualLengthBacktickRun() {
        let markdown = "`foo``bar` tail"
        let blocks = MarkdownParser.parse(markdown)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }
        guard case .code(let code) = inlines.first else {
            return XCTFail("Expected first inline to be code")
        }

        XCTAssertEqual(code, "foo``bar")
        XCTAssertEqual(extractText(inlines), "foo``bar tail")
    }

    func testInlineCodePreservesUnicodeContent() {
        let markdown = "`こんにちは ✅`"
        let blocks = MarkdownParser.parse(markdown)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }
        guard case .code(let code) = inlines.first else {
            return XCTFail("Expected first inline to be code")
        }

        XCTAssertEqual(code, "こんにちは ✅")
    }

    func testInlineCodeCanSpanSoftBreak() {
        let markdown = """
        `one
        two`
        """
        let blocks = MarkdownParser.parse(markdown)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }
        guard case .code(let code) = inlines.first else {
            return XCTFail("Expected first inline to be code")
        }

        XCTAssertEqual(code, "one\ntwo")
    }

    func testInlineCodeSupportsLongerBacktickFence() {
        let markdown = "``one ` tick``"
        let blocks = MarkdownParser.parse(markdown)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }
        guard case .code(let code) = inlines.first else {
            return XCTFail("Expected first inline to be code")
        }

        XCTAssertEqual(code, "one ` tick")
    }

    func testUnclosedInlineCodeBacktickRemainsLiteral() {
        let markdown = "`unterminated"
        let blocks = MarkdownParser.parse(markdown)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }

        XCTAssertEqual(extractText(inlines), "`unterminated")
    }

    func testUnclosedInlineCodeBacktickRunsRemainLiteral() {
        let markdown = "`one ``two ```three ````four"
        let blocks = MarkdownParser.parse(markdown)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }

        XCTAssertEqual(extractText(inlines), markdown)
    }

    func testInlineHTMLTagParsesAsHTMLNode() {
        let markdown = "Hello <br> world"
        let blocks = MarkdownParser.parse(markdown)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }

        XCTAssertTrue(inlines.contains { if case .html(let html) = $0 { return html == "<br>" } else { return false } })
    }

    func testMultilineParagraphPreservesSoftBreakText() {
        let markdown = "alpha **one**\nbeta `two`\n\nnext"
        let blocks = MarkdownParser.parse(markdown)

        XCTAssertEqual(blocks.count, 2)
        guard case .paragraph(let firstParagraph) = blocks.first else {
            return XCTFail("Expected first block to be paragraph")
        }
        guard case .paragraph(let secondParagraph) = blocks.last else {
            return XCTFail("Expected second block to be paragraph")
        }

        XCTAssertEqual(extractText(firstParagraph), "alpha one\nbeta two")
        XCTAssertEqual(extractText(secondParagraph), "next")
    }

    func testParagraphInterruptsBeforeIndentedListContinuation() {
        let markdown = "Intro\n  - item"
        let blocks = MarkdownParser.parse(markdown)

        XCTAssertEqual(blocks.count, 2)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected first block to be paragraph")
        }
        guard case .list(let ordered, _, let items) = blocks.last else {
            return XCTFail("Expected second block to be list")
        }

        XCTAssertEqual(extractText(inlines), "Intro")
        XCTAssertFalse(ordered)
        XCTAssertEqual(items.count, 1)
    }

    func testBareListMarkerLineDoesNotInterruptParagraph() {
        let markdown = "Intro\n+   \ncontinued"
        let blocks = MarkdownParser.parse(markdown)

        XCTAssertEqual(blocks.count, 1)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }

        XCTAssertEqual(extractText(inlines), "Intro\n+   \ncontinued")
    }

    func testEmojiShortcodeParsesToUnicodeText() {
        let markdown = ":rocket:"
        let blocks = MarkdownParser.parse(markdown, configuration: .github)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }

        XCTAssertTrue(inlines.contains { if case .text(let text) = $0 { return text.contains("🚀") } else { return false } })
    }

    func testCommonEmojiShortcodesParseToUnicodeText() {
        let markdown = ":rocket: :tada: :sparkles:"
        let blocks = MarkdownParser.parse(markdown, configuration: .github)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }

        let text = extractText(inlines)
        XCTAssertTrue(text.contains("🚀"))
        XCTAssertTrue(text.contains("🎉"))
        XCTAssertTrue(text.contains("✨"))
    }

    func testPublicPreprocessStillExpandsEmojiShortcodes() {
        let preprocessed = MarkdownParser.preprocess(":rocket:", configuration: .github)

        XCTAssertTrue(preprocessed.contains("🚀"))
    }

    func testCustomEmojiShortcodeParsesAsImageWhenAvailable() throws {
        guard GitHubEmojis.emojiMap["octocat"] != nil else {
            throw XCTSkip("octocat shortcode is not present in emoji map")
        }

        let markdown = ":octocat:"
        let blocks = MarkdownParser.parse(markdown, configuration: .github)
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
            case .extensionInline(let node):
                return node.literal
            }
        }.joined()
    }

    private func extractBlockText(_ blocks: [MarkdownParser.BlockNode]) -> String {
        blocks.map { block in
            switch block {
            case .paragraph(let children), .heading(_, let children, _):
                return extractText(children)
            case .blockquote(let children):
                return extractBlockText(children)
            case .list(_, _, let items):
                return items.map { extractBlockText($0.content) }.joined(separator: "\n")
            case .taskList(let items):
                return items.map { extractText($0.content) }.joined(separator: "\n")
            case .table(let header, let rows):
                return (header.map { extractText($0.content) } +
                        rows.flatMap { $0.map { extractText($0.content) } }).joined(separator: " ")
            case .codeBlock(_, let content), .html(let content):
                return content
            case .horizontalRule, .footnoteDefinition:
                return ""
            }
        }.joined(separator: "\n")
    }
}

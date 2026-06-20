import Glimmer
import Markdown
import XCTest

final class MarkdownSemanticParityTests: XCTestCase {
    func testGlimmerMatchesAppleSwiftMarkdownForSupportedSemanticFixtures() {
        let fixtures: [(name: String, markdown: String, configuration: MarkdownConfiguration)] = [
            (
                "basic inline markup",
                """
                # Title

                Paragraph with *emphasis*, **strong text**, and `code`.
                """,
                .default
            ),
            (
                "links and images",
                """
                [site](https://example.com "Example title") and ![diagram alt](https://example.com/image.png).
                """,
                .default
            ),
            (
                "lists",
                """
                - one
                - two with *style*

                1. first
                2. second with **bold**
                """,
                .default
            ),
            (
                "blockquote code and thematic break",
                """
                > quoted **text**

                ```swift
                let x = 1
                ```

                ---
                """,
                .default
            ),
            (
                "gfm table",
                """
                | A | B |
                |---|---:|
                | *x* | `y` |
                | plain | [z](https://example.com/z) |
                """,
                .github
            )
        ]

        for fixture in fixtures {
            let glimmer = glimmerSignature(
                MarkdownParser.parse(fixture.markdown, configuration: fixture.configuration)
            )
            let apple = appleSignature(Document(parsing: fixture.markdown))
            XCTAssertEqual(glimmer, apple, "Semantic signature mismatch for \(fixture.name)")
        }
    }

    // MARK: - Glimmer Signatures

    private func glimmerSignature(_ blocks: [MarkdownParser.BlockNode]) -> [String] {
        blocks.map(glimmerBlockSignature)
    }

    private func glimmerBlockSignature(_ block: MarkdownParser.BlockNode) -> String {
        switch block {
        case .heading(let level, let children, _):
            return "heading:\(level):\(glimmerInlineSignature(children))"
        case .paragraph(let children):
            return "paragraph:\(glimmerInlineSignature(children))"
        case .blockquote(let children):
            return "blockquote:\(glimmerSignature(children).joined(separator: "|"))"
        case .codeBlock(let language, let content):
            return "codeBlock:\(language ?? ""):\(trimTrailingNewlines(content))"
        case .list(let ordered, _, let items):
            let itemSignatures = items
                .map { glimmerSignature($0.content).joined(separator: "|") }
                .joined(separator: ";")
            return "list:\(ordered ? "ordered" : "unordered"):\(itemSignatures)"
        case .taskList(let items):
            let itemSignatures = items
                .map { "\($0.isChecked ? "checked" : "unchecked"):\(glimmerInlineSignature($0.content))" }
                .joined(separator: ";")
            return "taskList:\(itemSignatures)"
        case .table(let header, let rows):
            let headerSignature = glimmerTableRowSignature(header)
            let rowSignatures = rows.map(glimmerTableRowSignature).joined(separator: ";")
            return "table:\(headerSignature):\(rowSignatures)"
        case .horizontalRule:
            return "thematicBreak"
        case .html(let content):
            return "html:\(content)"
        case .footnoteDefinition(let label, let children):
            return "footnote:\(label):\(glimmerSignature(children).joined(separator: "|"))"
        }
    }

    private func glimmerTableRowSignature(_ row: [MarkdownParser.TableCell]) -> String {
        row.map { glimmerInlineSignature($0.content) }.joined(separator: ",")
    }

    private func glimmerInlineSignature(_ nodes: [MarkdownParser.InlineNode]) -> String {
        nodes.map(glimmerInlineNodeSignature).joined()
    }

    private func glimmerInlineNodeSignature(_ node: MarkdownParser.InlineNode) -> String {
        switch node {
        case .text(let text):
            return text
        case .emphasis(let children):
            return "<em>\(glimmerInlineSignature(children))</em>"
        case .strong(let children):
            return "<strong>\(glimmerInlineSignature(children))</strong>"
        case .strikethrough(let children):
            return "<strike>\(glimmerInlineSignature(children))</strike>"
        case .code(let code):
            return "<code>\(code)</code>"
        case .link(let url, let title, let children):
            return "<link:\(url.absoluteString):\(title ?? "")>\(glimmerInlineSignature(children))</link>"
        case .image(let url, let alt, let title):
            return "<image:\(url.absoluteString):\(title ?? "")>\(alt)</image>"
        case .autolink(let url, _, let originalText):
            return "<link:\(url.absoluteString):>\(originalText)</link>"
        case .lineBreak:
            return "\n"
        case .softBreak:
            return " "
        case .html(let content):
            return "<html>\(content)</html>"
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
        case .footnoteReference(let label):
            return "[^\(label)]"
        case .extensionInline(let node):
            return node.literal
        }
    }

    // MARK: - Apple Swift Markdown Signatures

    private func appleSignature(_ document: Document) -> [String] {
        document.children.map(appleBlockSignature)
    }

    private func appleBlockSignature(_ markup: any Markup) -> String {
        switch markup {
        case let heading as Heading:
            return "heading:\(heading.level):\(appleInlineSignature(heading.children))"
        case let paragraph as Paragraph:
            return "paragraph:\(appleInlineSignature(paragraph.children))"
        case let blockquote as BlockQuote:
            return "blockquote:\(blockquote.children.map(appleBlockSignature).joined(separator: "|"))"
        case let codeBlock as CodeBlock:
            return "codeBlock:\(codeBlock.language ?? ""):\(trimTrailingNewlines(codeBlock.code))"
        case let list as OrderedList:
            return appleListSignature(kind: "ordered", list.children)
        case let list as UnorderedList:
            return appleListSignature(kind: "unordered", list.children)
        case let table as Table:
            let headerSignature = appleTableRowSignature(table.head.children)
            let bodyRows = table.body.children.map { row in appleTableRowSignature(row.children) }
            return "table:\(headerSignature):\(bodyRows.joined(separator: ";"))"
        case _ as ThematicBreak:
            return "thematicBreak"
        case let html as HTMLBlock:
            return "html:\(html.rawHTML)"
        default:
            return "unsupported:\(type(of: markup)):\(markup.children.map(appleBlockSignature).joined(separator: "|"))"
        }
    }

    private func appleListSignature(kind: String, _ items: MarkupChildren) -> String {
        let itemSignatures = items
            .map { item in item.children.map(appleBlockSignature).joined(separator: "|") }
            .joined(separator: ";")
        return "list:\(kind):\(itemSignatures)"
    }

    private func appleTableRowSignature(_ cells: MarkupChildren) -> String {
        cells.map { appleInlineSignature($0.children) }.joined(separator: ",")
    }

    private func appleInlineSignature(_ children: MarkupChildren) -> String {
        children.map(appleInlineNodeSignature).joined()
    }

    private func appleInlineNodeSignature(_ markup: any Markup) -> String {
        switch markup {
        case let text as Text:
            return text.string
        case let emphasis as Emphasis:
            return "<em>\(appleInlineSignature(emphasis.children))</em>"
        case let strong as Strong:
            return "<strong>\(appleInlineSignature(strong.children))</strong>"
        case let strikethrough as Strikethrough:
            return "<strike>\(appleInlineSignature(strikethrough.children))</strike>"
        case let code as InlineCode:
            return "<code>\(code.code)</code>"
        case let link as Link:
            return "<link:\(link.destination ?? ""):\(link.title ?? "")>\(appleInlineSignature(link.children))</link>"
        case let image as Image:
            return "<image:\(image.source ?? ""):\(image.title ?? "")>\(appleInlineSignature(image.children))</image>"
        case _ as LineBreak:
            return "\n"
        case _ as SoftBreak:
            return " "
        case let html as InlineHTML:
            return "<html>\(html.rawHTML)</html>"
        default:
            return "unsupportedInline:\(type(of: markup)):\(markup.children.map(appleInlineNodeSignature).joined())"
        }
    }

    private func trimTrailingNewlines(_ text: String) -> String {
        var result = text
        while result.last == "\n" {
            result.removeLast()
        }
        return result
    }
}

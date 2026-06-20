import XCTest
@testable import Glimmer

final class InlineRangeParserTests: XCTestCase {
    func testBoundedInlineStateRemainderStopsAtRangeEnd() {
        let markdown = "outer **alpha *beta* gamma** suffix"
        let start = markdown.range(of: "alpha")!.lowerBound
        let end = markdown.range(of: "** suffix")!.lowerBound

        var state = ParserState(text: markdown, currentIndex: start, endIndex: end)
        var configuration = MarkdownConfiguration.default
        configuration.maxInlineIterations = 1

        let inlines = InlineParser.parseInlineElements(&state, configuration: configuration)

        XCTAssertEqual(plainText(inlines), "alpha *beta* gamma")
    }

    func testRangeBackedNestedEmphasisPreservesSemantics() {
        let blocks = MarkdownParser.parse("Before **alpha *beta* gamma** after", configuration: .default)

        guard case let .paragraph(children)? = blocks.first else {
            return XCTFail("Expected paragraph")
        }

        XCTAssertEqual(plainText(children), "Before alpha beta gamma after")
        XCTAssertTrue(containsStrongWithNestedEmphasis(children))
    }

    private func containsStrongWithNestedEmphasis(_ inlines: [MarkdownParser.InlineNode]) -> Bool {
        for inline in inlines {
            if case let .strong(children) = inline,
               children.contains(where: { child in
                   if case .emphasis = child { return true }
                   return false
               }) {
                return true
            }
        }
        return false
    }

    private func plainText(_ inlines: [MarkdownParser.InlineNode]) -> String {
        inlines.map { inline in
            switch inline {
            case let .text(text):
                return text
            case let .emphasis(children), let .strong(children), let .strikethrough(children):
                return plainText(children)
            case let .code(code):
                return code
            case let .link(_, _, children):
                return plainText(children)
            case let .image(_, alt, _):
                return alt
            case let .autolink(_, _, originalText):
                return originalText
            case let .mention(username):
                return "@\(username)"
            case let .issueReference(number):
                return "#\(number)"
            case let .commitSHA(_, short):
                return short
            case let .repositoryReference(owner, repo):
                return "\(owner)/\(repo)"
            case let .pullRequestReference(owner, repo, number):
                return "\(owner)/\(repo)#\(number)"
            case .lineBreak, .softBreak:
                return "\n"
            case let .html(html):
                return html
            case let .footnoteReference(label):
                return "[^\(label)]"
            case let .extensionInline(node):
                return node.literal
            }
        }.joined()
    }
}

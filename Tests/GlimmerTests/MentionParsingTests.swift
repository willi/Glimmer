import XCTest
@testable import Glimmer

final class MentionParsingTests: XCTestCase {
    func testEmailNotMention() {
        let md = "Contact user@example.com please"
        let blocks = MarkdownParser.parse(md, configuration: .github)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        XCTAssertFalse(children.contains { if case .mention = $0 { return true } else { return false } })
    }

    func testDomainLikeMentionNotMention() {
        let md = "Contact @example.com please"
        let blocks = MarkdownParser.parse(md, configuration: .github)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        XCTAssertFalse(children.contains { if case .mention = $0 { return true } else { return false } })
    }

    func testMentionInParens() {
        let md = "Hello (@alice)"
        let blocks = MarkdownParser.parse(md, configuration: .github)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        XCTAssertTrue(children.contains { if case .mention(let u) = $0 { return u == "alice" } else { return false } })
    }

    func testBoldLinkedMentionWithInlineAvatarDoesNotLeak() {
        // SuperMe's SFM preprocess emits a bold-wrapped link with an inline avatar
        // image + name: `**[![avatar](img) Name](profile)**`. This must parse to a
        // strong > link — no literal `](url)` or `**` text may leak (the symptom of
        // the old nested-strong form `**[ … **Name** … ](url)**`).
        let md = "**[![avatar](https://api.superme.ai/avatar/2) Casey Winters](https://superme.ai/u/2)**"
        let blocks = MarkdownParser.parse(md, configuration: .github)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }

        func texts(_ nodes: [MarkdownParser.InlineNode]) -> [String] {
            nodes.flatMap { node -> [String] in
                switch node {
                case .text(let s): return [s]
                case .emphasis(let c), .strong(let c): return texts(c)
                case .link(_, _, let c): return texts(c)
                default: return []
                }
            }
        }
        func hasLink(_ nodes: [MarkdownParser.InlineNode]) -> Bool {
            nodes.contains { node in
                switch node {
                case .link: return true
                case .emphasis(let c), .strong(let c): return hasLink(c)
                default: return false
                }
            }
        }

        XCTAssertTrue(hasLink(children), "Expected a parsed link, not leaked text")
        for fragment in texts(children) {
            XCTAssertFalse(fragment.contains("]("), "Leaked link syntax: \(fragment)")
            XCTAssertFalse(fragment.contains("**"), "Leaked bold marker: \(fragment)")
        }
    }
}

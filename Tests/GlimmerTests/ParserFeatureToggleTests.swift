import XCTest
@testable import Glimmer

final class ParserFeatureToggleTests: XCTestCase {
    func testDisableMentionsLeavesPlainText() {
        var config = MarkdownConfiguration.default
        config.enableMentions = false

        let blocks = MarkdownParser.parse("Hello @alice", configuration: config)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }

        XCTAssertFalse(inlines.contains { if case .mention = $0 { return true } else { return false } })
        XCTAssertTrue(flatten(inlines).contains("@alice"))
    }

    func testDisableIssueReferencesLeavesPlainText() {
        var config = MarkdownConfiguration.default
        config.enableIssueReferences = false

        let blocks = MarkdownParser.parse("Fix #42", configuration: config)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }

        XCTAssertFalse(inlines.contains { if case .issueReference = $0 { return true } else { return false } })
        XCTAssertTrue(flatten(inlines).contains("#42"))
    }

    func testDisableAutolinksLeavesBareURLAsText() {
        var config = MarkdownConfiguration.default
        config.enableAutolinks = false

        let blocks = MarkdownParser.parse("Visit https://example.com", configuration: config)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }

        XCTAssertFalse(inlines.contains { if case .autolink = $0 { return true } else { return false } })
        XCTAssertTrue(flatten(inlines).contains("https://example.com"))
    }

    func testDisableCommitSHAsLeavesPlainText() {
        var config = MarkdownConfiguration.default
        config.enableCommitSHAs = false

        let blocks = MarkdownParser.parse("deadbeef should stay text", configuration: config)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }

        XCTAssertFalse(inlines.contains { if case .commitSHA = $0 { return true } else { return false } })
        XCTAssertTrue(flatten(inlines).contains("deadbeef"))
    }

    func testDisableRepositoryReferencesLeavesPlainText() {
        var config = MarkdownConfiguration.default
        config.enableRepositoryReferences = false

        let blocks = MarkdownParser.parse("owner/repo and owner/repo#33", configuration: config)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }

        XCTAssertFalse(inlines.contains {
            if case .repositoryReference = $0 { return true }
            if case .pullRequestReference = $0 { return true }
            return false
        })
        XCTAssertTrue(flatten(inlines).contains("owner/repo"))
    }

    func testDisableEmojiShortcodesLeavesOriginalText() {
        var config = MarkdownConfiguration.default
        config.enableEmojiShortcodes = false

        let blocks = MarkdownParser.parse(":rocket:", configuration: config)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }

        XCTAssertTrue(flatten(inlines).contains(":rocket:"))
    }

    func testDisableFootnotesSkipsFootnoteNodes() {
        var config = MarkdownConfiguration.default
        config.enableFootnotes = false

        let markdown = """
        Ref[^1]

        [^1]: Footnote text
        """
        let blocks = MarkdownParser.parse(markdown, configuration: config)

        XCTAssertFalse(blocks.contains { if case .footnoteDefinition = $0 { return true } else { return false } })
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }
        XCTAssertFalse(inlines.contains { if case .footnoteReference = $0 { return true } else { return false } })
        XCTAssertTrue(flatten(inlines).contains("[^1]"))
    }

    func testDispatchFeaturesParseWithoutRepositoryAutolinkOrSHAScanners() {
        var config = MarkdownConfiguration.default
        config.enableMentions = true
        config.enableIssueReferences = true
        config.enableEmojiShortcodes = true
        config.enableRepositoryReferences = false
        config.enableAutolinks = false
        config.enableCommitSHAs = false

        let blocks = MarkdownParser.parse("Ship @alice #42 :rocket: owner/repo deadbeef", configuration: config)
        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected paragraph")
        }

        XCTAssertTrue(inlines.contains { if case .mention("alice") = $0 { return true } else { return false } })
        XCTAssertTrue(inlines.contains { if case .issueReference(42) = $0 { return true } else { return false } })
        XCTAssertTrue(flatten(inlines).contains("🚀"))
        XCTAssertFalse(inlines.contains { if case .repositoryReference = $0 { return true } else { return false } })
        XCTAssertFalse(inlines.contains { if case .commitSHA = $0 { return true } else { return false } })
    }

    private func flatten(_ inlines: [MarkdownParser.InlineNode]) -> String {
        inlines.map { inline in
            switch inline {
            case .text(let text):
                return text
            case .emphasis(let children), .strong(let children), .strikethrough(let children):
                return flatten(children)
            case .code(let code):
                return code
            case .link(_, _, let children):
                return flatten(children)
            case .image(_, let alt, _):
                return alt
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
            case .footnoteReference(let label):
                return "[^\(label)]"
            case .extensionInline(let node):
                return node.literal
            }
        }.joined()
    }
}

import XCTest
@testable import Glimmer

final class MarkdownParserTests: XCTestCase {
    
    func testBasicMarkdownParsing() {
        let markdown = "# Hello World\n\nThis is **bold** text."
        let blocks = MarkdownParser.parse(markdown)
        
        XCTAssertFalse(blocks.isEmpty, "Parser should return blocks")
        XCTAssertEqual(blocks.count, 2, "Should parse heading and paragraph")
    }
    
    func testEmptyMarkdown() {
        let blocks = MarkdownParser.parse("")
        XCTAssertTrue(blocks.isEmpty, "Empty markdown should return no blocks")
    }
    
    func testConfigurationDefaults() {
        // GitHub-specific extensions are opt-in: all disabled by default.
        let config = MarkdownConfiguration.default
        XCTAssertFalse(config.enableMentions, "Mentions should be disabled by default")
        XCTAssertFalse(config.enableIssueReferences, "Issue references should be disabled by default")
        XCTAssertFalse(config.enableAutolinks, "Autolinks should be disabled by default")
        XCTAssertFalse(config.enableCommitSHAs, "Commit SHAs should be disabled by default")
        XCTAssertFalse(config.enableRepositoryReferences, "Repo references should be disabled by default")
        XCTAssertFalse(config.enablePullRequestReferences, "PR references should be disabled by default")
        XCTAssertFalse(config.enableEmojiShortcodes, "Emoji shortcodes should be disabled by default")
    }

    func testGitHubPresetEnablesAllGitHubFeatures() {
        let config = MarkdownConfiguration.github
        XCTAssertTrue(config.enableMentions)
        XCTAssertTrue(config.enableIssueReferences)
        XCTAssertTrue(config.enableAutolinks)
        XCTAssertTrue(config.enableCommitSHAs)
        XCTAssertTrue(config.enableRepositoryReferences)
        XCTAssertTrue(config.enablePullRequestReferences)
        XCTAssertTrue(config.enableEmojiShortcodes)
    }

    func testGitHubFeaturesDisabledByDefaultInParsing() {
        let md = "@alice fixed #42 in owner/repo at https://example.com :rocket:"
        let blocks = MarkdownParser.parse(md)
        guard case .paragraph(let inlines) = blocks.first else { return XCTFail("Expected paragraph") }
        XCTAssertFalse(inlines.contains { if case .mention = $0 { return true } else { return false } })
        XCTAssertFalse(inlines.contains { if case .issueReference = $0 { return true } else { return false } })
        XCTAssertFalse(inlines.contains { if case .repositoryReference = $0 { return true } else { return false } })
        XCTAssertFalse(inlines.contains { if case .autolink = $0 { return true } else { return false } })
        XCTAssertFalse(inlines.contains { if case .image = $0 { return true } else { return false } })
    }
    
    func testCachedParser() {
        let parser = CachedMarkdownParser()
        let markdown = "# Test"
        
        let blocks1 = parser.parse(markdown, configuration: .default)
        let blocks2 = parser.parse(markdown, configuration: .default)
        
        XCTAssertEqual(blocks1.count, blocks2.count, "Cached parser should return consistent results")
    }
}
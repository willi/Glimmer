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
        let config = MarkdownConfiguration.default
        XCTAssertTrue(config.enableMentions, "Mentions should be enabled by default")
        XCTAssertTrue(config.enableIssueReferences, "Issue references should be enabled by default")
    }
    
    func testCachedParser() {
        let parser = CachedMarkdownParser()
        let markdown = "# Test"
        
        let blocks1 = parser.parse(markdown, configuration: .default)
        let blocks2 = parser.parse(markdown, configuration: .default)
        
        XCTAssertEqual(blocks1.count, blocks2.count, "Cached parser should return consistent results")
    }
}
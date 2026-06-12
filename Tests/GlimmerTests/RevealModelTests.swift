import XCTest
import SwiftUI
@testable import Glimmer

final class RevealModelTests: XCTestCase {

    // MARK: - Renderer session

    func testStandaloneInlineCodeStyledAfterBeginSession() {
        let config = MarkdownConfiguration.default
        var renderer = MarkdownRenderer()
        renderer.beginSession(configuration: config)
        let attributed = renderer.renderInlines(
            [.code("let x = 1")], configuration: config
        )
        XCTAssertEqual(attributed.runs.first?.font, config.codeFont,
                       "code inline must get codeFont without a full render(blocks:) pass")
    }

    func testStandaloneMentionColoredAfterBeginSession() {
        let config = MarkdownConfiguration.default
        var renderer = MarkdownRenderer()
        renderer.beginSession(configuration: config)
        let attributed = renderer.renderInlines(
            [.mention(username: "octocat")], configuration: config
        )
        XCTAssertEqual(attributed.runs.first?.foregroundColor, config.mentionColor)
    }
}

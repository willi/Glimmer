import XCTest
@testable import Glimmer

final class MarkdownLinterRuleTests: XCTestCase {
    func testConsistentHeadingStyleDetectsMixedATXAndSetext() {
        let markdown = """
        # Top

        Setext Heading
        --------------
        """

        let issues = MarkdownLinter.lint(markdown, configuration: .default)
        XCTAssertTrue(issues.contains { $0.rule == "consistent-heading-style" })
    }

    func testConsistentListMarkersDetectsMixedUnorderedMarkers() {
        let markdown = """
        # Top

        - one
        * two
        """

        let issues = MarkdownLinter.lint(markdown, configuration: .default)
        XCTAssertTrue(issues.contains { $0.rule == "consistent-list-markers" })
    }

    func testConsistentCodeFenceDetectsMixedFenceTypes() {
        let markdown =
            "# Top\n\n" +
            "```swift\nlet a = 1\n```\n\n" +
            "~~~swift\nlet b = 2\n~~~\n"

        let issues = MarkdownLinter.lint(markdown, configuration: .default)
        XCTAssertTrue(issues.contains { $0.rule == "consistent-code-fence" })
    }
}

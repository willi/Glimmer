import XCTest
@testable import Glimmer

final class MarkdownLinterAdditionalRuleTests: XCTestCase {
    func testRequireTitleHeadingRule() {
        let issues = lint("## Subtitle")
        XCTAssertTrue(issues.contains { $0.rule == "require-title-heading" })
    }

    func testBlankLineAroundHeadingsRule() {
        let markdown = """
        # Title
        ## Subtitle
        """
        let issues = lint(markdown)
        XCTAssertTrue(issues.contains { $0.rule == "blank-line-around-headings" })
    }

    func testHeadingLengthRule() {
        let markdown = "# \(String(repeating: "a", count: 70))"
        let issues = lint(markdown) { config in
            config.maxHeadingLength = 20
        }
        XCTAssertTrue(issues.contains { $0.rule == "heading-length" })
    }

    func testIncrementalHeadingsRule() {
        let markdown = """
        # H1

        ### H3
        """
        let issues = lint(markdown)
        XCTAssertTrue(issues.contains { $0.rule == "incremental-headings" })
    }

    func testNoEmptyListItemsRule() {
        let markdown = "# T\n\n- \n- filled"
        let issues = lint(markdown)
        XCTAssertTrue(issues.contains { $0.rule == "no-empty-list-items" })
    }

    func testLineLengthRuleRespectsIgnoreCodeBlocks() {
        let longLine = String(repeating: "x", count: 120)
        let markdown = """
        ```swift
        \(longLine)
        ```
        """

        let ignored = lint(markdown) { config in
            config.maxLineLength = 20
            config.ignoreCodeBlocks = true
        }
        XCTAssertFalse(ignored.contains { $0.rule == "line-length" })

        let notIgnored = lint(markdown) { config in
            config.maxLineLength = 20
            config.ignoreCodeBlocks = false
        }
        XCTAssertTrue(notIgnored.contains { $0.rule == "line-length" })
    }

    func testNoTrailingSpacesAllowsHardBreakTwoSpaces() {
        let markdown = """
        # T

        line with hard break  
        next
        """
        let issues = lint(markdown)
        XCTAssertFalse(issues.contains { $0.rule == "no-trailing-spaces" })
    }

    func testNoTrailingSpacesFlagsSingleTrailingSpace() {
        let markdown = """
        # T

        bad trailing space 
        """
        let issues = lint(markdown)
        XCTAssertTrue(issues.contains { $0.rule == "no-trailing-spaces" })
    }

    func testNoMultipleBlankLinesRule() {
        let markdown = """
        # T


        paragraph
        """
        let issues = lint(markdown)
        XCTAssertTrue(issues.contains { $0.rule == "no-multiple-blank-lines" })
    }

    func testNoMultipleSpacesRuleRespectsIgnoreTables() {
        let markdown = """
        # T

        | Col A  A | Col B |
        | --- | --- |
        | row  row | x |
        """

        let ignored = lint(markdown) { config in
            config.ignoreTables = true
        }
        XCTAssertFalse(ignored.contains { $0.rule == "no-multiple-spaces" })

        let notIgnored = lint(markdown) { config in
            config.ignoreTables = false
        }
        XCTAssertTrue(notIgnored.contains { $0.rule == "no-multiple-spaces" })
    }

    func testNoEmptyLinksRule() {
        let markdown = "# T\n\n[](https://example.com)"
        let issues = lint(markdown)
        XCTAssertTrue(issues.contains { $0.rule == "no-empty-links" })
    }

    func testNoBrokenLocalLinksRule() {
        let missingPath = "/tmp/glimmer-missing-\(UUID().uuidString)"
        let markdown = "# T\n\n[local](file://\(missingPath))"
        let issues = lint(markdown)
        XCTAssertTrue(issues.contains { $0.rule == "no-broken-local-links" })
    }

    func testFencedCodeLanguageRule() {
        let markdown = """
        # T

        ```
        let x = 1
        ```
        """
        let issues = lint(markdown)
        XCTAssertTrue(issues.contains { $0.rule == "fenced-code-language" })
    }

    func testNoEmptyCodeBlocksRule() {
        let markdown = """
        # T

        ```swift

        ```
        """
        let issues = lint(markdown)
        XCTAssertTrue(issues.contains { $0.rule == "no-empty-code-blocks" })
    }

    private func lint(_ markdown: String, configure: (inout MarkdownLinter.LintConfiguration) -> Void = { _ in }) -> [MarkdownLinter.LintIssue] {
        var config = MarkdownLinter.LintConfiguration.default
        configure(&config)
        return MarkdownLinter.lint(markdown, configuration: config)
    }
}

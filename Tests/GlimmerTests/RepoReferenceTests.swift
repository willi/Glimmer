import XCTest
@testable import Glimmer

final class RepoReferenceTests: XCTestCase {
    func testRepositoryReferenceParsed() {
        let md = "See owner/repo for details."
        let blocks = MarkdownParser.parse(md, configuration: .github)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        XCTAssertTrue(children.contains { if case .repositoryReference(let owner, let repo) = $0 { return owner == "owner" && repo == "repo" } else { return false } })
    }

    func testPullRequestReferenceParsed() {
        let md = "Fix in owner/repo#42"
        let blocks = MarkdownParser.parse(md, configuration: .github)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        XCTAssertTrue(children.contains { if case .pullRequestReference(let owner, let repo, let num) = $0 { return owner == "owner" && repo == "repo" && num == 42 } else { return false } })
    }

    func testRepoReferencePreferredOverSHA() {
        // The repo part looks hex-like but must still parse as repo reference
        let md = "Check owner/abcdef"
        let blocks = MarkdownParser.parse(md, configuration: .github)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        XCTAssertTrue(children.contains { if case .repositoryReference(let owner, let repo) = $0 { return owner == "owner" && repo == "abcdef" } else { return false } })
        // Ensure no commit SHA captured here
        XCTAssertFalse(children.contains { if case .commitSHA = $0 { return true } else { return false } })
    }

    func testHexLikeRepoOwnerPreferredOverSHA() {
        let md = "Check abcdef1/repo now"
        let blocks = MarkdownParser.parse(md, configuration: .github)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }

        XCTAssertTrue(children.contains {
            if case .repositoryReference(let owner, let repo) = $0 {
                return owner == "abcdef1" && repo == "repo"
            }
            return false
        })
        XCTAssertFalse(children.contains { if case .commitSHA = $0 { return true } else { return false } })
    }

    func testCommitSHABoundaryRequired() {
        let md = "Commit deadbeef now"
        let blocks = MarkdownParser.parse(md, configuration: .github)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        XCTAssertTrue(children.contains { if case .commitSHA(let full, let short) = $0 { return full.lowercased() == "deadbeef" && short.lowercased() == "deadbee" } else { return false } })
    }

    func testCommitSHANotWhenAlnumFollows() {
        let md = "deadbeefx should not be SHA"
        let blocks = MarkdownParser.parse(md, configuration: .github)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        XCTAssertFalse(children.contains { if case .commitSHA = $0 { return true } else { return false } })
    }

    func testOverflowIssueReferenceRemainsText() {
        let hugeNumber = String(repeating: "9", count: 40)
        let md = "Fix #\(hugeNumber)x now"
        let blocks = MarkdownParser.parse(md, configuration: .github)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }

        XCTAssertFalse(children.contains { if case .issueReference = $0 { return true } else { return false } })
        XCTAssertEqual(children.compactMap { inline -> String? in
            if case .text(let text) = inline { return text }
            return nil
        }.joined(), md)
    }

    func testRepoNotParsedAfterAtContext() {
        let md = "Ping @owner/repo about this"
        let blocks = MarkdownParser.parse(md, configuration: .github)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        XCTAssertFalse(children.contains { if case .repositoryReference = $0 { return true } else { return false } })
    }

    func testRepoNotParsedInsideURL() {
        let md = "Visit http://github.com/owner/repo for info"
        let blocks = MarkdownParser.parse(md, configuration: .github)
        guard case let .paragraph(children) = blocks.first else { return XCTFail("Expected paragraph") }
        // Expect an autolink, not a repo reference
        XCTAssertTrue(children.contains { if case .autolink = $0 { return true } else { return false } })
        XCTAssertFalse(children.contains { if case .repositoryReference = $0 { return true } else { return false } })
    }
}

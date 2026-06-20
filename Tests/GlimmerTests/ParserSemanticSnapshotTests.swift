import Foundation
import XCTest
@testable import Glimmer

final class ParserSemanticSnapshotTests: XCTestCase {
    func testRepresentativeCorpusSemanticSnapshots() {
        let cases: [SnapshotCase] = [
            SnapshotCase(
                name: "defaultInline",
                markdown: Self.makeDefaultInlineCorpus(sections: 8),
                configuration: .default,
                expectedBlockCount: 17,
                expectedHash: "158dde883cfb63e8"
            ),
            SnapshotCase(
                name: "githubFeatures",
                markdown: Self.makeGitHubCorpus(sections: 8),
                configuration: .github,
                expectedBlockCount: 41,
                expectedHash: "1e4274494101721c"
            ),
            SnapshotCase(
                name: "mixedProfiling",
                markdown: ProfilingBenchmarkTests.makeCorpus(sections: 4),
                configuration: .github,
                expectedBlockCount: 41,
                expectedHash: "011eac23b005410b"
            )
        ]

        for snapshotCase in cases {
            let blocks = MarkdownParser.parse(snapshotCase.markdown, configuration: snapshotCase.configuration)
            let canonical = ParserCanonicalSnapshot.canonicalDescription(for: blocks)
            let hash = ParserCanonicalSnapshot.stableHash(canonical)

            XCTAssertEqual(
                blocks.count,
                snapshotCase.expectedBlockCount,
                "\(snapshotCase.name) block count changed"
            )
            XCTAssertEqual(
                hash,
                snapshotCase.expectedHash,
                "\(snapshotCase.name) semantic hash changed; actual hash: \(hash)"
            )
        }
    }

    private struct SnapshotCase {
        let name: String
        let markdown: String
        let configuration: MarkdownConfiguration
        let expectedBlockCount: Int
        let expectedHash: String
    }

    private static func makeDefaultInlineCorpus(sections: Int) -> String {
        var output = "# Default Inline Corpus\n\n"

        for index in 0..<sections {
            output += """
            ## Section \(index)

            Paragraph \(index) has **bold**, *italic*, ~~struck~~, `inline code`, [a link](https://example.com/\(index)),
            an image ![alt \(index)](https://example.com/image-\(index).png "Image \(index)"), and escaped \\*markers\\*.

            """
        }

        return output
    }

    private static func makeGitHubCorpus(sections: Int) -> String {
        var output = "# GitHub Feature Corpus\n\n"

        for index in 0..<sections {
            output += """
            ## GitHub Section \(index) :rocket:

            Work item \(index) mentions @octocat\(index % 7), issue #\(100 + index), repository apple/swift, pull request
            swiftlang/swift-markdown#\(index), autolink https://github.com/glimmer/issue\(index), and commit
            deadbeefdeadbeefdeadbeefdeadbeefdeadbeef. Emoji :tada: :sparkles: :rocket: appear repeatedly.

            - [x] Completed task \(index) with @reviewer\(index % 5)
            - [ ] Pending task for repo owner\(index % 9)/project\(index)

            Footnote reference here.[^\(index)]

            [^\(index)]: Footnote content for section \(index) with @mention and #\(index).

            """
        }

        return output
    }
}

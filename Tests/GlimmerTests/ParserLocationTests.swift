import XCTest
@testable import Glimmer

final class ParserLocationTests: XCTestCase {
    func testParseWithLocationsRemainsAccurateAfterSetextBacktrack() {
        let markdown = """
        First line
        --x
        # Real Heading
        """

        let located = MarkdownParser.parseWithLocations(markdown, configuration: .default)

        let heading = located.first { locatedBlock in
            guard case .heading(_, let children, _) = locatedBlock.node else { return false }
            return children.contains {
                if case .text(let text) = $0 {
                    return text.contains("Real Heading")
                }
                return false
            }
        }

        XCTAssertEqual(heading?.startLine, 3)
    }
}

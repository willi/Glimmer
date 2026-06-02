import XCTest
@testable import Glimmer

final class MarkdownViewStableIDTests: XCTestCase {
    func testPairsUseUniqueIDsForRepeatedEquivalentBlocks() {
        let blocks: [MarkdownParser.BlockNode] = [
            .paragraph(children: [.text("Same")]),
            .paragraph(children: [.text("Same")]),
            .paragraph(children: [.text("Same")])
        ]

        let ids = MarkdownBlockStableID.pairs(for: blocks).map(\.id)

        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(Set(ids).count, 3)

        let parsed = ids.compactMap(parseID)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertTrue(parsed.allSatisfy { $0.base == parsed[0].base })
        XCTAssertEqual(parsed.map(\.occurrence), [0, 1, 2])
    }

    func testPairsTrackOccurrencesPerBaseID() {
        let blocks: [MarkdownParser.BlockNode] = [
            .paragraph(children: [.text("Same")]),
            .horizontalRule,
            .paragraph(children: [.text("Same")]),
            .horizontalRule
        ]

        let parsed = MarkdownBlockStableID.pairs(for: blocks).compactMap { parseID($0.id) }
        XCTAssertEqual(parsed.count, 4)

        let paragraphOccurrences = parsed.filter { $0.base.hasPrefix("p|") }.map(\.occurrence)
        let ruleOccurrences = parsed.filter { $0.base == "hr" }.map(\.occurrence)

        XCTAssertEqual(paragraphOccurrences, [0, 1])
        XCTAssertEqual(ruleOccurrences, [0, 1])
    }

    private func parseID(_ id: String) -> (base: String, occurrence: Int)? {
        let parts = id.split(separator: "#", maxSplits: 1).map(String.init)
        guard parts.count == 2, let occurrence = Int(parts[1]) else {
            return nil
        }
        return (base: parts[0], occurrence: occurrence)
    }
}

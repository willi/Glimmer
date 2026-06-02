import XCTest
@testable import Glimmer

final class FootnotePreprocessTests: XCTestCase {
    func testInlineFootnoteCreatesDefinition() {
        let md = "Inline note ^[footnote here] end."
        let blocks = MarkdownParser.parse(md, configuration: .default)

        // Expect a paragraph and a footnote definition appended
        XCTAssertGreaterThanOrEqual(blocks.count, 2)
        guard case .footnoteDefinition(let label, let children) = blocks.last else {
            return XCTFail("Expected last block to be footnoteDefinition")
        }
        XCTAssertTrue(label.hasPrefix("inline-"))
        XCTAssertFalse(children.isEmpty, "Footnote content should exist")
    }
}


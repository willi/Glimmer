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

    func testMultipleInlineFootnotesPreserveExistingLabelOrder() {
        let md = "First ^[one] and second ^[two]."
        let blocks = MarkdownParser.parse(md, configuration: .default)

        guard case .paragraph(let inlines) = blocks.first else {
            return XCTFail("Expected first block to be a paragraph")
        }

        let referenceLabels = inlines.compactMap { node -> String? in
            if case .footnoteReference(let label) = node {
                return label
            }
            return nil
        }
        XCTAssertEqual(referenceLabels, ["inline-2", "inline-1"])

        let definitionLabels = blocks.compactMap { block -> String? in
            if case .footnoteDefinition(let label, _) = block {
                return label
            }
            return nil
        }
        XCTAssertEqual(definitionLabels, ["inline-1", "inline-2"])
    }
}

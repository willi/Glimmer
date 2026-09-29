import XCTest
@testable import Glimmer

final class GlimmerConformanceTests: XCTestCase {
    func testCommonMarkExamplesWithHTMLProduceBlocks() throws {
        let examples = try SpecExamples.load("spec")
        XCTAssertGreaterThan(examples.count, 600)
        assertProducesBlocks(examples)
    }

    func testGFMExtensionExamplesWithHTMLProduceBlocks() throws {
        let examples = try SpecExamples.load("extensions")
        XCTAssertGreaterThan(examples.count, 20)
        assertProducesBlocks(examples)
    }

    func testEveryNodeKindIsReachable() throws {
        var kinds = Set<String>()
        for example in try SpecExamples.load("spec") + SpecExamples.load("extensions") {
            for block in GlimmerParser.parse(example.markdown) { collectKinds(block, into: &kinds) }
        }
        let expected: Set<String> = [
            "paragraph", "heading", "blockQuote", "list", "task", "codeBlock", "table", "thematicBreak", "htmlBlock",
            "text", "code", "emphasis", "strong", "strikethrough", "link", "image", "softBreak", "lineBreak", "html",
            "footnoteDefinitions", "footnoteReference",
        ]
        XCTAssertEqual(expected.subtracting(kinds), [], "node kinds never produced")
    }

    // MARK: - Helpers

    /// Smoke coverage, not semantic conformance: nonempty reference HTML must produce at least one block.
    /// Fixture options and Glimmer's presentation differ, so this does not compare the contents or HTML bytes.
    private func assertProducesBlocks(_ examples: [SpecExample], file: StaticString = #filePath, line: UInt = #line) {
        for example in examples where !example.html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            XCTAssertFalse(
                GlimmerParser.parse(example.markdown).isEmpty,
                "\(example.file) example \(example.number) produced no blocks: \(example.markdown.debugDescription)",
                file: file, line: line
            )
        }
    }

    private func collectKinds(_ block: GlimmerBlock, into kinds: inout Set<String>) {
        switch block {
        case .paragraph(let inlines):
            kinds.insert("paragraph"); inlines.forEach { collectKinds($0, into: &kinds) }
        case .heading(_, let inlines):
            kinds.insert("heading"); inlines.forEach { collectKinds($0, into: &kinds) }
        case .blockQuote(let blocks):
            kinds.insert("blockQuote"); blocks.forEach { collectKinds($0, into: &kinds) }
        case .list(let list):
            kinds.insert("list")
            for item in list.items {
                if item.checkbox != nil { kinds.insert("task") }
                item.blocks.forEach { collectKinds($0, into: &kinds) }
            }
        case .codeBlock:
            kinds.insert("codeBlock")
        case .table(let table):
            kinds.insert("table")
            (table.header + table.rows.flatMap { $0 }).forEach { $0.forEach { collectKinds($0, into: &kinds) } }
        case .thematicBreak:
            kinds.insert("thematicBreak")
        case .htmlBlock:
            kinds.insert("htmlBlock")
        case .footnoteDefinitions(let notes):
            kinds.insert("footnoteDefinitions")
            notes.forEach { $0.blocks.forEach { collectKinds($0, into: &kinds) } }
        }
    }

    private func collectKinds(_ inline: GlimmerInline, into kinds: inout Set<String>) {
        switch inline {
        case .text: kinds.insert("text")
        case .code: kinds.insert("code")
        case .emphasis(let children): kinds.insert("emphasis"); children.forEach { collectKinds($0, into: &kinds) }
        case .strong(let children): kinds.insert("strong"); children.forEach { collectKinds($0, into: &kinds) }
        case .strikethrough(let children): kinds.insert("strikethrough"); children.forEach { collectKinds($0, into: &kinds) }
        case .link(_, _, let children): kinds.insert("link"); children.forEach { collectKinds($0, into: &kinds) }
        case .image: kinds.insert("image")
        case .softBreak: kinds.insert("softBreak")
        case .lineBreak: kinds.insert("lineBreak")
        case .html: kinds.insert("html")
        case .footnoteReference: kinds.insert("footnoteReference")
        }
    }
}

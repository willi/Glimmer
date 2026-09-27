import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerStreamingDocumentTests: XCTestCase {
    private let composer = GlimmerComposer(theme: .default)

    private func freshCompose(_ markdown: String, isStreaming: Bool) -> NSAttributedString {
        composer.compose(GlimmerParser.parse(isStreaming ? GlimmerTailHealer.heal(markdown) : markdown))
    }

    func testFirstUpdateInsertsEverything() throws {
        let document = GlimmerStreamingDocument(composer: composer)
        let edit = try XCTUnwrap(document.update(markdown: "Hello **wor", isStreaming: true))
        XCTAssertEqual(edit.range, NSRange(location: 0, length: 0))
        XCTAssertEqual(document.text.string, "Hello wor")
        let font = document.text.attribute(.font, at: 6, effectiveRange: nil) as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false, "the healed tail is already bold")
    }

    func testAppendingToTheLastParagraphReplacesOnlyIt() throws {
        let document = GlimmerStreamingDocument(composer: composer)
        _ = document.update(markdown: "Para one.\n\nPara tw", isStreaming: true)
        let edit = try XCTUnwrap(document.update(markdown: "Para one.\n\nPara two.", isStreaming: true))
        XCTAssertEqual(edit.range.location, ("Para one.\n" as NSString).length)
        XCTAssertEqual(document.text.string, "Para one.\nPara two.")
    }

    func testAppendingToALongListReplacesOnlyTheItemsThatChanged() throws {
        let document = GlimmerStreamingDocument(composer: composer)
        let items = (1...50).map { "- Item \($0) of a long list" }.joined(separator: "\n")
        _ = document.update(markdown: items, isStreaming: true)
        let edit = try XCTUnwrap(document.update(markdown: items + " grows", isStreaming: true))
        // The whole list re-composes, but TextKit should re-lay out only the last item (and, for a tight list, the
        // item before it, whose spacing may change).
        let secondToLast = (document.text.string as NSString).range(of: "Item 49").location
        XCTAssertGreaterThanOrEqual(edit.range.location, secondToLast - 2)
        assertEquivalent(document.text, freshCompose(items + " grows", isStreaming: true), "matches a fresh compose")
    }

    func testGrowingCodeBlockKeepsItsAttachment() throws {
        let document = GlimmerStreamingDocument(composer: composer)
        _ = document.update(markdown: "Run:\n\n```swift\nlet a", isStreaming: true)
        let before = try XCTUnwrap(blockAttachments(in: document.text).first)
        let edit = try XCTUnwrap(document.update(markdown: "Run:\n\n```swift\nlet a = 1\nlet b", isStreaming: true))
        XCTAssertTrue(blockAttachments(in: document.text).first === before, "the growing code block keeps its attachment")
        let update = try XCTUnwrap(edit.embedUpdates.first)
        XCTAssertTrue(update.attachment === before)
        guard case .codeBlock(_, let code, _) = update.embed else { return XCTFail("expected a code block, got \(update.embed)") }
        XCTAssertEqual(code, "let a = 1\nlet b")
    }

    func testGrowingTableKeepsItsAttachment() throws {
        let document = GlimmerStreamingDocument(composer: composer)
        _ = document.update(markdown: "| a | b |\n|---|---|\n| 1 | 2 |", isStreaming: true)
        let before = try XCTUnwrap(blockAttachments(in: document.text).first)
        let edit = try XCTUnwrap(document.update(markdown: "| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |", isStreaming: true))
        XCTAssertTrue(blockAttachments(in: document.text).first === before)
        guard case .table(_, let rows, _) = edit.embedUpdates.first?.embed else { return XCTFail("expected a table update") }
        XCTAssertEqual(rows.count, 2)
    }

    func testChangedFenceLanguageGetsANewAttachment() throws {
        let document = GlimmerStreamingDocument(composer: composer)
        _ = document.update(markdown: "```py", isStreaming: true)
        let before = try XCTUnwrap(blockAttachments(in: document.text).first)
        _ = document.update(markdown: "```python\nx = 1", isStreaming: true)
        let after = try XCTUnwrap(blockAttachments(in: document.text).first)
        XCTAssertFalse(after === before, "a different language is a different code block")
        guard case .codeBlock(let language, _, _) = after.embed else { return XCTFail("expected a code block") }
        XCTAssertEqual(language, "python")
    }

    func testEmbeddedAttachmentsReportDocumentOffsets() {
        let document = GlimmerStreamingDocument(composer: composer)
        _ = document.update(markdown: "Intro.\n\n```\nx\n```\n\nMiddle.\n\n---", isStreaming: false)
        let offsets = document.embeddedAttachments.map(\.offset)
        let string = document.text.string as NSString
        XCTAssertEqual(offsets.count, 2)
        for offset in offsets { XCTAssertEqual(string.character(at: offset), 0xFFFC) }
    }

    func testNewBlockReinsertsTheSeparator() throws {
        let document = GlimmerStreamingDocument(composer: composer)
        _ = document.update(markdown: "One", isStreaming: true)
        let edit = try XCTUnwrap(document.update(markdown: "One\n\nTwo", isStreaming: true))
        XCTAssertEqual(edit.range, NSRange(location: 3, length: 0))
        XCTAssertEqual(edit.replacement.string, "\nTwo")
        XCTAssertEqual(document.text.string, "One\nTwo")
    }

    func testUnchangedMarkdownReturnsNil() {
        let document = GlimmerStreamingDocument(composer: composer)
        _ = document.update(markdown: "Same", isStreaming: true)
        XCTAssertNil(document.update(markdown: "Same", isStreaming: true))
    }

    func testReplacedTextFallsBackToAFullParse() throws {
        let document = GlimmerStreamingDocument(composer: composer)
        _ = document.update(markdown: "Alpha\n\nBeta", isStreaming: true)
        let edit = try XCTUnwrap(document.update(markdown: "Gamma\n\nBeta", isStreaming: true))
        XCTAssertEqual(edit.range.location, 0)
        XCTAssertEqual(document.text.string, "Gamma\nBeta")
    }

    func testEndingStreamUsesRawMarkdown() {
        let document = GlimmerStreamingDocument(composer: composer)
        _ = document.update(markdown: "Say **bol", isStreaming: true)
        XCTAssertEqual(document.text.string, "Say bol")
        _ = document.update(markdown: "Say **bol", isStreaming: false)
        XCTAssertEqual(document.text.string, "Say **bol", "the settled render must match a static render exactly")
    }

    func testRemovingBlocksTrimsTheSeparator() throws {
        let document = GlimmerStreamingDocument(composer: composer)
        _ = document.update(markdown: "One\n\nTwo", isStreaming: true)
        _ = try XCTUnwrap(document.update(markdown: "One", isStreaming: false))
        XCTAssertEqual(document.text.string, "One")
    }

    func testEveryPrefixMatchesAFreshCompose() {
        let markdown = """
        # Title

        Some **bold** and `code` with a [link](https://example.com).

        - one
        - two with *em*
          - nested

        > quoted **text**

        ```swift
        let x = 1
        ```

        | a | b |
        |---|---|
        | 1 | 2 |

        Last paragraph.
        """
        let document = GlimmerStreamingDocument(composer: composer)
        let mirror = NSMutableAttributedString()
        let characters = Array(markdown)
        var previousLastOffset = 0
        for end in stride(from: 1, through: characters.count, by: 2) {
            let prefix = String(characters[..<end])
            if let edit = document.update(markdown: prefix, isStreaming: true) {
                XCTAssertGreaterThanOrEqual(edit.range.location, min(previousLastOffset, mirror.length),
                                            "committed blocks changed at prefix \(end)")
                mirror.replaceCharacters(in: edit.range, with: edit.replacement)
            }
            assertEquivalent(document.text, freshCompose(prefix, isStreaming: true), "prefix \(end)")
            assertEquivalent(mirror, document.text, "mirror at prefix \(end)")
            // The last two blocks are open (see GlimmerStreamingDocument); everything before them is committed.
            previousLastOffset = max(0, (document.blockOffsets.dropLast().last ?? 1) - 1)
        }
        if let edit = document.update(markdown: markdown, isStreaming: false) {
            mirror.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        assertEquivalent(document.text, freshCompose(markdown, isStreaming: false), "final")
        assertEquivalent(mirror, document.text, "final mirror")
    }
}

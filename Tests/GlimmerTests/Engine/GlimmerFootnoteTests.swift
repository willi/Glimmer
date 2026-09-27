import UIKit
import XCTest
@testable import Glimmer

/// Footnotes as the web renders them (remark-gfm): superscript numbers in order of first reference, and the notes as an
/// ordered list after the answer's last block, under a thin rule.
@MainActor
final class GlimmerFootnoteTests: XCTestCase {
    private let theme = GlimmerTheme.default

    private func composed(_ markdown: String, rendersNotes: Bool = true) -> NSAttributedString {
        var composer = GlimmerComposer(theme: theme)
        composer.rendersFootnoteDefinitions = rendersNotes
        return composer.compose(GlimmerParser.parse(markdown))
    }

    /// The footnote markers in `text`: each run carrying a `[^label]` source.
    private func markers(in text: NSAttributedString) -> [(number: String, source: String, attributes: [NSAttributedString.Key: Any])] {
        var result: [(String, String, [NSAttributedString.Key: Any])] = []
        text.enumerateAttribute(.glimmerSource, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let source = value as? String, source.hasPrefix("[^") else { return }
            result.append(((text.string as NSString).substring(with: range), source, text.attributes(at: range.location, effectiveRange: nil)))
        }
        return result
    }

    func testAReferenceIsASuperscriptNumber() throws {
        let text = composed("Fact[^a] and more[^b].\n\n[^a]: One.\n[^b]: Two.")
        let found = markers(in: text)
        XCTAssertEqual(found.map(\.number), ["1", "2"])
        XCTAssertEqual(found.map(\.source), ["[^a]", "[^b]"])
        let first = try XCTUnwrap(found.first)
        XCTAssertEqual((first.attributes[.font] as? UIFont)?.pointSize, theme.footnoteFont.pointSize)
        XCTAssertGreaterThan(first.attributes[.baselineOffset] as? CGFloat ?? 0, 0)
        XCTAssertEqual(first.attributes[.foregroundColor] as? UIColor, theme.linkColor)
    }

    func testNumbersFollowFirstReference() {
        let text = composed("B[^b], a[^a], b again[^b].\n\n[^a]: A.\n[^b]: B.")
        XCTAssertEqual(markers(in: text).map(\.number), ["1", "2", "1"])
    }

    func testNotesFollowTheLastBlockInMarkerOrder() throws {
        let text = composed("B[^b] then a[^a].\n\n[^a]: Note A.\n[^b]: Note B.")
        let string = text.string
        let rule = try XCTUnwrap(string.range(of: "\u{FFFC}"), "a rule before the notes")
        let notes = String(string[rule.upperBound...])
        let noteB = try XCTUnwrap(notes.range(of: "Note B."))
        let noteA = try XCTUnwrap(notes.range(of: "Note A."))
        XCTAssertLessThan(noteB.lowerBound, noteA.lowerBound, "note 1 (b) comes first")
        XCTAssertTrue(notes.contains("1.") && notes.contains("2."))
        XCTAssertFalse(string.contains("Footnotes"))
        let location = (string as NSString).range(of: "Note A.").location
        XCTAssertEqual((text.attribute(.font, at: location, effectiveRange: nil) as? UIFont)?.pointSize, theme.footnoteFont.pointSize)
        XCTAssertEqual(text.attribute(.foregroundColor, at: location, effectiveRange: nil) as? UIColor, theme.secondaryTextColor)
    }

    func testAOneWordDefinitionIsANote() {
        let text = composed("See[^1].\n\n[^1]: Yes.")
        XCTAssertTrue(text.string.hasPrefix("See1."))
        XCTAssertTrue(text.string.hasSuffix("Yes."), text.string)
    }

    func testAReferenceWithoutADefinitionStaysASuperscript() {
        let text = composed("See[^x].")
        XCTAssertEqual(markers(in: text).map(\.number), ["1"])
        XCTAssertFalse(text.string.contains("\u{FFFC}"), "no notes, no rule")
    }

    func testFootnotesCopyTheirSource() {
        let text = composed("See[^1].\n\n[^1]: Yes.")
        let all = NSRange(location: 0, length: text.length)
        XCTAssertEqual(GlimmerMarkdownSerializer.markdown(from: text, range: all), "See[^1].\n\n[^1]: Yes.")
        // Plain text writes list markers as their markdown and puts no blank line before a list, as for any list.
        XCTAssertEqual(GlimmerMarkdownSerializer.plainText(from: text, range: all), "See1.\n[^1]: Yes.")
    }

    func testANoteOfTwoParagraphsCopiesWithFourSpaces() {
        let text = composed("See[^1].\n\n[^1]: First.\n\n    Second.")
        let markdown = GlimmerMarkdownSerializer.markdown(from: text, range: NSRange(location: 0, length: text.length))
        XCTAssertEqual(markdown, "See[^1].\n\n[^1]: First.\n\n    Second.")
    }

    func testNotesAreHiddenWhileStreaming() {
        let text = composed("See[^1].\n\n[^1]: Yes.", rendersNotes: false)
        XCTAssertEqual(text.string, "See1.")
    }
}

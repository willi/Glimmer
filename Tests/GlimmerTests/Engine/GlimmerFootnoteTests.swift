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

    // MARK: - Streaming

    private func waitForDocument(_ view: GlimmerView) {
        let deadline = Date().addingTimeInterval(5)
        while view.pendingDocument != nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }
        view.layoutIfNeeded()
    }

    func testAMarkerKeepsItsNumberWhenItsDefinitionArrives() {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil, reveal: .none))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: "A[^x] b[^y].", isStreaming: true, revealID: "notes")
        waitForDocument(view)
        XCTAssertEqual(markers(in: view.textView.textStorage).map(\.number), ["1", "2"])
        view.update(markdown: "A[^x] b[^y].\n\n[^y]: Why.\n[^x]: Ex.", isStreaming: true, revealID: "notes")
        waitForDocument(view)
        XCTAssertEqual(markers(in: view.textView.textStorage).map(\.number), ["1", "2"])
        XCTAssertFalse(view.textView.textStorage.string.contains("Ex."), "notes wait for the answer to settle")
        view.update(markdown: "A[^x] b[^y].\n\n[^y]: Why.\n[^x]: Ex.", isStreaming: false, revealID: "notes")
        waitForDocument(view)
        let string = view.textView.textStorage.string
        XCTAssertEqual(markers(in: view.textView.textStorage).map(\.number), ["1", "2"])
        let ex = try? XCTUnwrap(string.range(of: "Ex."))
        let why = try? XCTUnwrap(string.range(of: "Why."))
        XCTAssertNotNil(ex)
        XCTAssertNotNil(why)
        if let ex, let why { XCTAssertLessThan(ex.lowerBound, why.lowerBound, "note 1 (x) first") }
        _ = window
    }

    /// A footnote definition counts as a reference definition: from then on every update re-parses in full.
    func testAFootnoteDefinitionTurnsOnFullReparses() {
        XCTAssertTrue(GlimmerStreamingDocument.hasLinkReferenceDefinition("[^1]: A note."))
        XCTAssertTrue(GlimmerStreamingDocument.hasLinkReferenceDefinition("[a]: https://example.com"))
        XCTAssertFalse(GlimmerStreamingDocument.hasLinkReferenceDefinition("See [^1] and [a]."))
    }

    /// Streamed with the smooth reveal, then settled: markers keep their numbers and the notes appear, in order.
    func testFootnotesSettleUnderTheSmoothReveal() {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let clock = ManualRevealClock()
        view.clock = clock
        let window = hostInWindow(view, width: 390, height: 800)
        let full = "A[^x] and b[^y].\n\n[^y]: Why.\n[^x]: Ex."
        for end in [8, 18, 30, full.count] {
            view.update(markdown: String(full.prefix(end)), isStreaming: true, revealID: "smooth-notes")
            waitForDocument(view)
            clock.advance(to: clock.now + 0.5)
        }
        view.update(markdown: full, isStreaming: false, revealID: "smooth-notes")
        waitForDocument(view)
        clock.advance(to: clock.now + 30)
        XCTAssertNil(view.engine, "the reveal finished")
        let string = view.textView.textStorage.string
        XCTAssertEqual(markers(in: view.textView.textStorage).map(\.number), ["1", "2"])
        let ex = string.range(of: "Ex."), why = string.range(of: "Why.")
        XCTAssertNotNil(ex)
        XCTAssertNotNil(why)
        if let ex, let why { XCTAssertLessThan(ex.lowerBound, why.lowerBound, "note 1 (x) first") }
        _ = window
    }

    func testFootnotesStreamWithoutMovingShownText() {
        assertStreamingKeepsShownTextInPlace("""
        Glimmer renders footnotes[^fn] the way the web does. A marker whose note comes later[^late] is a number \
        right away.

        [^fn]: Numbered by first reference.

        More text after a definition keeps streaming, and a third marker[^fn] reuses its number.

        [^late]: This note arrived last.
        """)
    }

    func testTheNextAnswerInTheSameViewNumbersFromOne() {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil, reveal: .none))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: "A[^x] b[^y].", isStreaming: true, revealID: "first")
        waitForDocument(view)
        view.update(markdown: "New answer[^1] here.", isStreaming: true, revealID: "second")
        waitForDocument(view)
        XCTAssertEqual(markers(in: view.textView.textStorage).map(\.number), ["1"])
        _ = window
    }

    func testReplacingTheTailKeepsFootnoteNumbersDistinct() {
        let document = GlimmerStreamingDocument(composer: GlimmerComposer(theme: theme))
        _ = document.update(markdown: "A[^a].\n\nB[^b].", isStreaming: true)
        _ = document.update(markdown: "A[^a].\n\nC[^c].", isStreaming: true)
        _ = document.update(markdown: "A[^a].\n\nC[^c].", isStreaming: false)
        XCTAssertEqual(document.text.string, "A1.\nC2.")
    }

    func testAReplacementWithTheSameHealedTextKeepsItsFootnoteNumbers() {
        let document = GlimmerStreamingDocument(composer: GlimmerComposer(theme: theme))
        _ = document.update(markdown: "A[^a].\n\n**Bold**", isStreaming: true)
        _ = document.update(markdown: "A[^a].\n\n**Bold", isStreaming: true)
        _ = document.update(markdown: "A[^a].\n\n**Bold**\n\nC[^c].", isStreaming: true)
        XCTAssertEqual(document.text.string, "A1.\nBold\nC2.")
    }

    func testVoiceOverReadsANotesNumber() {
        let text = composed("See[^1].\n\n[^1]: Yes.")
        let spoken = GlimmerMarkdownSerializer.plainText(from: text, range: NSRange(location: 0, length: text.length), forAccessibility: true)
        XCTAssertEqual(spoken, "See1.\n1. Yes.")
    }
}

import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerAccessibilityTests: XCTestCase {
    private let answer = "First sentence of the answer arrives now. Then a second sentence follows it closely, and more."
    private let theme = GlimmerTheme.default

    private func revealingView() -> (GlimmerView, ManualRevealClock, UIWindow) {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let clock = ManualRevealClock()
        view.clock = clock
        return (view, clock, hostInWindow(view, width: 320, height: 800))
    }

    func testRevealingViewIsOneElementWithTheRevealedText() async {
        let (view, clock, window) = revealingView()
        view.update(markdown: answer, isStreaming: true)
        await view.pendingDocument?.value
        clock.advance(to: 0.2)
        XCTAssertTrue(view.isAccessibilityElement)
        XCTAssertTrue(view.textView.accessibilityElementsHidden)
        let label = view.accessibilityLabel ?? ""
        XCTAssertFalse(label.isEmpty)
        XCTAssertLessThan(label.count, answer.count, "only what is revealed")
        XCTAssertTrue(answer.hasPrefix(label))
        _ = window
    }

    func testSettleHandsAccessibilityBackToTheTextView() async {
        let (view, clock, window) = revealingView()
        view.update(markdown: answer, isStreaming: true)
        await view.pendingDocument?.value
        XCTAssertTrue(view.isAccessibilityElement, "one element while revealing")
        view.update(markdown: answer, isStreaming: false)
        await view.pendingDocument?.value
        clock.advance(to: 30)
        XCTAssertNil(view.engine)
        XCTAssertFalse(view.isAccessibilityElement)
        XCTAssertFalse(view.textView.accessibilityElementsHidden)
        _ = window
    }

    func testRevealLabelFollowsAReplacedStream() async {
        let (view, clock, window) = revealingView()
        view.update(markdown: answer, isStreaming: true)
        await view.pendingDocument?.value
        clock.advance(to: 0.5)
        let regenerated = "A short new answer that replaces the first one."
        view.update(markdown: regenerated, isStreaming: true)
        await view.pendingDocument?.value
        clock.advance(to: 1.5)
        XCTAssertTrue(view.isAccessibilityElement)
        let label = view.accessibilityLabel ?? ""
        XCTAssertFalse(label.isEmpty)
        XCTAssertLessThanOrEqual(label.count, regenerated.count)
        XCTAssertTrue(regenerated.hasPrefix(label), label)
        _ = window
    }

    func testCodeBlockReadsItsLanguageAndOffersCopy() {
        let code = GlimmerCodeBlockView(code: "let x = 1", language: "swift", theme: theme, highlighter: GlimmerBasicHighlighter())
        XCTAssertEqual(code.textView.accessibilityLabel, "Code, swift")
        XCTAssertFalse(code.languageLabel.isAccessibilityElement)
        let elements = code.accessibilityElements as? [NSObject] ?? []
        XCTAssertTrue(elements.contains(code.textView))
        XCTAssertTrue(elements.contains(code.copyButton))
        let plain = GlimmerCodeBlockView(code: "x", language: nil, theme: theme, highlighter: GlimmerBasicHighlighter())
        XCTAssertEqual(plain.textView.accessibilityLabel, "Code")
    }

    func testTableIsADataTableWithHeaders() throws {
        let cell = { (text: String) in NSAttributedString(string: text) }
        let table = GlimmerTableView(header: [cell("Name"), cell("Value")], rows: [[cell("a"), cell("1")], [cell("b"), cell("2")]],
                                     alignments: [.none, .none], theme: theme)
        table.frame = CGRect(x: 0, y: 0, width: 300, height: table.embedHeight(forWidth: 300))
        table.layoutIfNeeded()
        XCTAssertEqual(table.accessibilityContainerType, .dataTable)
        XCTAssertEqual((table.accessibilityElements ?? []).compactMap { $0 as? GlimmerTableCellElement }.count, 6,
                       "every cell, header row first")
        XCTAssertEqual(table.accessibilityRowCount(), 3)
        XCTAssertEqual(table.accessibilityColumnCount(), 2)
        let element = try XCTUnwrap(table.accessibilityDataTableCellElement(forRow: 2, column: 1) as? UIAccessibilityElement)
        XCTAssertEqual(element.accessibilityLabel, "2")
        let headers = table.accessibilityHeaderElements(forColumn: 1)?.compactMap { ($0 as? UIAccessibilityElement)?.accessibilityLabel }
        XCTAssertEqual(headers, ["Value"])
    }

    func testChipReadsItsAccessibilityLabel() {
        let text = "Ada"
        let token = GlimmerInlineToken(range: text.startIndex..<text.endIndex, kind: "mention", displayText: "@Ada",
                                       source: "[Ada,@1]", accessibilityLabel: "Mention, Ada")
        let chip = GlimmerInlineAttachment(token: token, glimmerExtension: NoViewExtension(), theme: theme)
        XCTAssertEqual(chip.chipView().accessibilityLabel, "Mention, Ada")
        let plainToken = GlimmerInlineToken(range: text.startIndex..<text.endIndex, kind: "k", displayText: "@Ada", source: "s")
        let plainChip = GlimmerInlineAttachment(token: plainToken, glimmerExtension: NoViewExtension(), theme: theme)
        XCTAssertEqual(plainChip.chipView().accessibilityLabel, "@Ada")
    }
}

private struct NoViewExtension: GlimmerExtension {}

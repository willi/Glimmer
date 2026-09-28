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

    /// UIKit's accessibility reads a text view's `attributedText` on a background queue (building paragraph elements
    /// for a long text). The getter must not be a main-actor override, or Swift's isolation check traps.
    func testTheTextCanBeReadOffTheMainThread() {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil, reveal: .none))
        let window = hostInWindow(view, width: 320, height: 800)
        view.update(markdown: "A [link](https://example.com) in a paragraph.")
        nonisolated(unsafe) let textView: NSObject = view.textView
        nonisolated(unsafe) var text: NSAttributedString?
        let read = expectation(description: "read off the main thread")
        // `async`, not `sync`: a sync block runs on the calling (main) thread.
        DispatchQueue.global().async {
            text = textView.value(forKey: "attributedText") as? NSAttributedString
            read.fulfill()
        }
        wait(for: [read], timeout: 5)
        XCTAssertEqual(text?.string, "A link in a paragraph.")
        _ = window
    }

    /// The same for the text view's other overridden properties UIKit may read: they must not trap off the main thread.
    func testTheFrameAndOffsetCanBeReadOffTheMainThread() {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil, reveal: .none))
        let window = hostInWindow(view, width: 320, height: 800)
        view.update(markdown: "A short answer.")
        settle(view)
        let expectedFrame = view.textView.accessibilityFrame
        nonisolated(unsafe) let textView: NSObject = view.textView
        nonisolated(unsafe) var offset: CGPoint?
        nonisolated(unsafe) var frame: CGRect?
        let read = expectation(description: "read off the main thread")
        DispatchQueue.global().async {
            offset = (textView.value(forKey: "contentOffset") as? NSValue)?.cgPointValue
            frame = (textView.value(forKey: "accessibilityFrame") as? NSValue)?.cgRectValue
            read.fulfill()
        }
        wait(for: [read], timeout: 5)
        XCTAssertEqual(offset, .zero)
        XCTAssertEqual(frame, expectedFrame)
        XCTAssertLessThan(expectedFrame.height, 100, "the frame hugs the text, not the tall text view")
        _ = window
    }

    /// The view's own accessibility is safe to read off the main thread too: whether it is one element and its traits
    /// exactly, and its label as the main thread last read it (the text storage can't be read from there).
    func testTheViewsAccessibilityCanBeReadOffTheMainThread() async {
        let (view, clock, window) = revealingView()
        view.update(markdown: answer, isStreaming: true)
        await view.pendingDocument?.value
        clock.advance(to: 0.5)
        let onMain = view.accessibilityLabel
        XCTAssertNotNil(onMain)
        nonisolated(unsafe) let object: NSObject = view
        nonisolated(unsafe) var element: Bool?
        nonisolated(unsafe) var traits: UInt64?
        nonisolated(unsafe) var label: String?
        let read = expectation(description: "read off the main thread")
        DispatchQueue.global().async {
            element = (object.value(forKey: "isAccessibilityElement") as? NSNumber)?.boolValue
            traits = (object.value(forKey: "accessibilityTraits") as? NSNumber)?.uint64Value
            label = object.value(forKey: "accessibilityLabel") as? String
            read.fulfill()
        }
        await fulfillment(of: [read], timeout: 5)
        XCTAssertEqual(element, true)
        XCTAssertEqual(traits.map { UIAccessibilityTraits(rawValue: $0) }, [.staticText, .updatesFrequently])
        XCTAssertEqual(label, onMain)
        _ = window
    }

    /// A table's accessibility is safe to read off the main thread: its cells as the main thread last built them, each
    /// cell's frame as the main thread last read it.
    func testATablesAccessibilityCanBeReadOffTheMainThread() throws {
        let cell = { (text: String) in NSAttributedString(string: text) }
        let table = GlimmerTableView(header: [cell("Name"), cell("Value")], rows: [[cell("a"), cell("1")]],
                                     alignments: [.none, .none], theme: theme)
        let window = hostInWindow(table, width: 300, height: table.embedHeight(forWidth: 300))
        table.layoutIfNeeded()
        XCTAssertEqual(table.accessibilityElements?.count, 4)
        let element = try XCTUnwrap(table.accessibilityDataTableCellElement(forRow: 1, column: 1) as? GlimmerTableCellElement)
        let frameOnMain = element.accessibilityFrame
        XCTAssertGreaterThan(frameOnMain.width, 0)
        nonisolated(unsafe) let tableObject: NSObject = table
        nonisolated(unsafe) let cellObject: NSObject = element
        nonisolated(unsafe) var elements: Int?, rows: Int?, columns: Int?, headers: Int?
        nonisolated(unsafe) var found: AnyObject?, frame: CGRect?, rowRange: NSRange?
        let read = expectation(description: "read off the main thread")
        DispatchQueue.global().async {
            elements = (tableObject.value(forKey: "accessibilityElements") as? [Any])?.count
            rows = (tableObject.value(forKey: "accessibilityRowCount") as? NSNumber)?.intValue
            columns = (tableObject.value(forKey: "accessibilityColumnCount") as? NSNumber)?.intValue
            typealias CellAt = @convention(c) (AnyObject, Selector, Int, Int) -> AnyObject?
            let cellAt = NSSelectorFromString("accessibilityDataTableCellElementForRow:column:")
            found = unsafeBitCast(tableObject.method(for: cellAt), to: CellAt.self)(tableObject, cellAt, 1, 1)
            typealias HeadersFor = @convention(c) (AnyObject, Selector, Int) -> NSArray?
            let headersFor = NSSelectorFromString("accessibilityHeaderElementsForColumn:")
            headers = unsafeBitCast(tableObject.method(for: headersFor), to: HeadersFor.self)(tableObject, headersFor, 1)?.count
            frame = (cellObject.value(forKey: "accessibilityFrame") as? NSValue)?.cgRectValue
            rowRange = (cellObject.value(forKey: "accessibilityRowRange") as? NSValue)?.rangeValue
            read.fulfill()
        }
        wait(for: [read], timeout: 5)
        XCTAssertEqual(elements, 4)
        XCTAssertEqual(rows, 2)
        XCTAssertEqual(columns, 2)
        XCTAssertTrue(found === element)
        XCTAssertEqual(headers, 1)
        XCTAssertEqual(frame, frameOnMain)
        XCTAssertEqual(rowRange, NSRange(location: 1, length: 1))
        _ = window
    }

    func testReplacingTheTextStillForgetsWhatWasMeasured() {
        let textView = GlimmerTextView()
        textView.frame = CGRect(x: 0, y: 0, width: 320, height: 800)
        let version = textView.textVersion
        textView.replaceText(with: NSAttributedString(string: "New text"))
        XCTAssertNotEqual(textView.textVersion, version)
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

    func testAHostCanGroupASettledAnswer() {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let window = hostInWindow(view, width: 320, height: 800)
        view.update(markdown: "Grouped **answer**.")
        view.isAccessibilityElement = true
        XCTAssertTrue(view.isAccessibilityElement)
        XCTAssertEqual(view.accessibilityLabel, "Grouped answer.")
        view.accessibilityLabel = "The host's own label"
        XCTAssertEqual(view.accessibilityLabel, "The host's own label", "a host's label wins")
        view.isAccessibilityElement = false
        XCTAssertFalse(view.isAccessibilityElement)
        _ = window
    }

    func testTheRevealingLabelReadsChipsLikeTheSettledChip() async {
        var configuration = GlimmerConfiguration(imageLoader: nil)
        configuration.extensions = [LabeledCitationExtension()]
        let view = GlimmerView(configuration: configuration)
        let clock = ManualRevealClock()
        view.clock = clock
        let window = hostInWindow(view, width: 320, height: 800)
        view.update(markdown: "Sources say so [3] and more words follow here to keep revealing.", isStreaming: true)
        await view.pendingDocument?.value
        clock.advance(to: 3)
        XCTAssertTrue((view.accessibilityLabel ?? "").contains("Source 3"), view.accessibilityLabel ?? "nil")
        _ = window
    }

    func testTaskCheckboxesSayWhetherTheyAreDone() {
        let text = GlimmerComposer(theme: theme).compose(GlimmerParser.parse("- [x] done\n- [ ] open"))
        XCTAssertTrue(text.string.contains("Checked"))
        XCTAssertTrue(text.string.contains("Unchecked"))
        XCTAssertEqual(GlimmerMarkdownSerializer.markdown(from: text, range: NSRange(location: 0, length: text.length)),
                       "- [x] done\n- [ ] open", "copy still writes the task syntax")
    }

    func testLibraryStringsAreInTheCatalog() throws {
        // Everything VoiceOver reads from Glimmer itself goes through Localizable.xcstrings, so it can be translated.
        let path = try XCTUnwrap(GlimmerStrings.bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en"))
        let table = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
        for key in ["Code", "Code, %@", "Copy code", "Checked, ", "Unchecked, "] {
            XCTAssertNotNil(table[key], key)
        }
    }
}

private struct NoViewExtension: GlimmerExtension {}

private struct LabeledCitationExtension: GlimmerExtension {
    func scan(_ text: String) -> [GlimmerInlineToken] {
        text.ranges(of: #/\[\d+\]/#).map { range in
            let label = String(text[range])
            return GlimmerInlineToken(range: range, kind: "citation", displayText: label, source: label,
                                      accessibilityLabel: "Source \(label.dropFirst().dropLast())")
        }
    }
}

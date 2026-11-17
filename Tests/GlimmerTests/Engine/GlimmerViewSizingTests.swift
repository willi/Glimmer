import XCTest
@testable import Glimmer

private struct ChipExtension: GlimmerExtension {
    func scan(_ text: String) -> [GlimmerInlineToken] {
        text.ranges(of: #/\[\d+\]/#).map { range in
            let label = String(text[range])
            return GlimmerInlineToken(range: range, kind: "chip", payload: [:], displayText: label, source: label)
        }
    }

    @MainActor func makeInlineView(for token: GlimmerInlineToken, theme: GlimmerTheme) -> UIView? {
        let box = UIView()
        box.frame = CGRect(x: 0, y: 0, width: 120, height: 20)
        return box
    }
}

@MainActor
final class GlimmerViewSizingTests: XCTestCase {
    private var windows: [UIWindow] = []

    private func settledView(_ markdown: String, extensions: [any GlimmerExtension] = []) -> GlimmerView {
        let view = GlimmerView(configuration: GlimmerConfiguration(extensions: extensions, imageLoader: nil, reveal: .none))
        view.update(markdown: markdown)
        windows.append(hostInWindow(view, width: 320, height: view.sizeThatFits(CGSize(width: 320, height: 10_000)).height))
        return view
    }

    func testShortTextFitsNarrowerThanTheMaximum() {
        let width = settledView("Hi").fittingWidth(maximum: 320)
        XCTAssertGreaterThan(width, 0)
        XCTAssertLessThan(width, 100)
    }

    func testWrappedTextFillsTheMaximum() {
        let width = settledView(String(repeating: "word ", count: 80)).fittingWidth(maximum: 320)
        XCTAssertGreaterThan(width, 280)
        XCTAssertLessThanOrEqual(width, 320)
    }

    func testTheLongestLineWins() {
        let short = settledView("a").fittingWidth(maximum: 320)
        let both = settledView("a\n\nthe longer line here").fittingWidth(maximum: 320)
        XCTAssertEqual(both, settledView("the longer line here").fittingWidth(maximum: 320), accuracy: 0.5)
        XCTAssertGreaterThan(both, short)
    }

    func testACodeBlockTakesTheMaximum() {
        XCTAssertEqual(settledView("```\nx\n```").fittingWidth(maximum: 320), 320)
    }

    func testAnInlineChipCountsTowardItsLine() {
        let plain = settledView("Hi").fittingWidth(maximum: 320)
        let chip = settledView("Hi [1]", extensions: [ChipExtension()]).fittingWidth(maximum: 320)
        XCTAssertGreaterThan(chip, plain + 100)
    }

    func testLineBottomsListEachLineInOrder() {
        let measurer = GlimmerTextMeasurer(
            text: NSAttributedString(string: "a\nb\nc", attributes: [.font: UIFont.systemFont(ofSize: 17)]),
            width: 200, insets: UIEdgeInsets(top: 5, left: 0, bottom: 0, right: 0), lineFragmentPadding: 0
        )
        XCTAssertEqual(measurer.lineBottoms.count, 3)
        XCTAssertEqual(measurer.lineBottoms, measurer.lineBottoms.sorted())
        XCTAssertGreaterThan(measurer.lineBottoms[0], 5)
    }
}

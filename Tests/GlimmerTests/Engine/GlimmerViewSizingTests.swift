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

    func testWrappedLinesHaveEvenlySpacedIncreasingBottoms() {
        let font = UIFont.systemFont(ofSize: 17)
        let measurer = GlimmerTextMeasurer(
            text: NSAttributedString(string: String(repeating: "word ", count: 80), attributes: [.font: font]),
            width: 200, insets: UIEdgeInsets(top: 5, left: 0, bottom: 0, right: 0), lineFragmentPadding: 0
        )
        let bottoms = measurer.lineBottoms
        XCTAssertGreaterThan(bottoms.count, 3)
        XCTAssertEqual(bottoms[0], 5 + ceil(font.lineHeight), accuracy: 1.5)
        let step = bottoms[1] - bottoms[0]
        XCTAssertGreaterThan(step, 0)
        for index in 1..<bottoms.count {
            XCTAssertEqual(bottoms[index] - bottoms[index - 1], step, accuracy: 1.5)
        }
    }

    func testEmptyTextFitsZeroWidth() {
        XCTAssertEqual(settledView("").fittingWidth(maximum: 320), 0)
    }

    func testFittingWidthFollowsATextSizeChange() {
        let view = settledView("Hello there")
        let before = view.fittingWidth(maximum: 320)
        view.traitOverrides.preferredContentSizeCategory = .accessibilityExtraLarge
        settle(view)
        XCTAssertGreaterThan(view.fittingWidth(maximum: 320), before)
    }

    func testACapAboveTheFullHeightReturnsTheFullHeight() {
        let view = settledView("a<br>b")
        let full = view.sizeThatFits(CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)).height
        XCTAssertEqual(view.height(forWidth: 320, notExceeding: full + 50), full)
    }

    func testACapKeepsOnlyWholeLines() {
        let twoLines = settledView("a<br>b").sizeThatFits(CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)).height
        let threeLines = settledView("a<br>b<br>c").sizeThatFits(CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)).height
        let cap = (twoLines + threeLines) / 2
        XCTAssertEqual(settledView("a<br>b<br>c<br>d").height(forWidth: 320, notExceeding: cap), twoLines, accuracy: 0.5)
    }

    func testACapOnALongTextKeepsOnlyTheWholeLinesThatFit() {
        let lines = (1...400).map { "line \($0)" }.joined(separator: "<br>")
        let view = settledView(lines)
        let oneLine = settledView("line").sizeThatFits(CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)).height
        let capped = view.height(forWidth: 320, notExceeding: 300)
        // Whole lines only: the bottom inset plus a multiple of the line height.
        XCTAssertLessThanOrEqual(capped, 300)
        XCTAssertGreaterThan(capped, 300 - oneLine - 1)
        XCTAssertEqual(view.height(forWidth: 320, notExceeding: 300), capped)
    }

    func testTheMeasurerStopsAtTheLimitAndKeepsEveryLineWithoutOne() {
        let text = NSAttributedString(string: (1...400).map { "line \($0)" }.joined(separator: "\n"))
        func measure(limit: CGFloat?) -> GlimmerTextMeasurer {
            GlimmerTextMeasurer(text: text, width: 320, insets: .zero, lineFragmentPadding: 5, limit: limit)
        }
        let all = measure(limit: nil)
        let stopped = measure(limit: 300)
        XCTAssertLessThan(stopped.lineBottoms.count, all.lineBottoms.count)
        XCTAssertEqual(stopped.lineBottoms.filter { $0 <= 300 }, all.lineBottoms.filter { $0 <= 300 })
        XCTAssertEqual(stopped.lineBottoms.last(where: { $0 <= 300 }), all.lineBottoms.last(where: { $0 <= 300 }))
    }

    func testACapBelowTheFirstLineReturnsZero() {
        XCTAssertEqual(settledView("a<br>b").height(forWidth: 320, notExceeding: 2), 0)
    }

    private func fullHeight(_ markdown: String) -> CGFloat {
        settledView(markdown).sizeThatFits(CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)).height
    }

    func testACapNeverLandsInsideAnEmbed() {
        let markdown = "a<br>b\n\n```\nlet x = 1\nlet y = 2\nlet z = 3\n```\n\nc<br>d"
        let before = fullHeight("a<br>b")
        let withEmbed = fullHeight("a<br>b\n\n```\nlet x = 1\nlet y = 2\nlet z = 3\n```")
        XCTAssertGreaterThan(withEmbed, before + 20)
        let view = settledView(markdown)
        // A cap in the middle of the embed keeps the lines above it; a cap at its bottom keeps the embed whole.
        let inside = view.height(forWidth: 320, notExceeding: (before + withEmbed) / 2)
        XCTAssertEqual(inside, before, accuracy: 1.5)
        let after = view.height(forWidth: 320, notExceeding: withEmbed + 1)
        XCTAssertEqual(after, withEmbed, accuracy: 1.5)
    }

    func testAnEmbedTallerThanTheCapAtTheTopGivesZero() {
        let view = settledView("```\nlet x = 1\nlet y = 2\nlet z = 3\n```\n\nafter")
        XCTAssertEqual(view.height(forWidth: 320, notExceeding: 20), 0)
    }

    func testACapNeverExceedsTheMaximum() {
        let view = settledView("a<br>b<br>c<br>d")
        let full = view.sizeThatFits(CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)).height
        for cap in stride(from: 10.3, to: full, by: 3.7) {
            XCTAssertLessThanOrEqual(view.height(forWidth: 320, notExceeding: cap), cap)
        }
    }
}

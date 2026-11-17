import SwiftUI
import UIKit
import XCTest
@testable import Glimmer

/// Additive line spacing per role (`lineSpacing`, `headingLineSpacing`, `codeLineSpacing`), measured on laid-out text.
///
/// TextKit 2 puts a paragraph's `lineSpacing` above each of its lines except the first line of the text, and nothing
/// below its last line. Glimmer takes the same amount off the space above the paragraph, so only the gaps between a
/// paragraph's own lines grow.
@MainActor
final class GlimmerLineSpacingTests: XCTestCase {
    private var windows: [UIWindow] = []
    private let width: CGFloat = 320
    private let body = UIFont.systemFont(ofSize: 16)
    private let wrapping = "A paragraph long enough to wrap onto a second line and then a third line in a narrow view."

    override func tearDown() {
        windows.forEach { $0.isHidden = true }
        windows = []
        super.tearDown()
    }

    /// The default theme with a 16 pt body and a line height multiple of 1, so expected positions are exact.
    private func theme(body spacing: CGFloat? = nil, heading: CGFloat? = nil, code: CGFloat? = nil) -> GlimmerTheme {
        var theme = GlimmerTheme.default
        theme.bodyFont = body
        theme.lineHeightMultiple = 1
        theme.lineSpacing = spacing
        theme.headingLineSpacing = heading
        theme.codeLineSpacing = code
        return theme
    }

    /// The 1.4 × point size pitch of SuperMe's previous renderer, as additive spacing.
    private var bodyPitchSpacing: CGFloat { 1.4 * 16 - body.lineHeight }

    private func settledView(_ markdown: String, theme: GlimmerTheme) -> GlimmerView {
        var configuration = GlimmerConfiguration(imageLoader: nil, reveal: .none)
        configuration.theme = theme
        let view = GlimmerView(configuration: configuration)
        view.update(markdown: markdown)
        windows.append(hostInWindow(view, width: width, height: view.sizeThatFits(CGSize(width: width, height: 10_000)).height))
        return view
    }

    /// The top of each line of the text view, in the text container's coordinates.
    private func lineTops(_ textView: UITextView) -> [CGFloat] {
        layoutFragments(textView).flatMap { fragment in
            fragment.textLineFragments.map { fragment.layoutFragmentFrame.minY + $0.typographicBounds.minY }
        }
    }

    /// The top of the line holding the first character of `text`.
    private func top(of text: String, in view: GlimmerView) throws -> CGFloat {
        let location = (view.textView.textStorage.string as NSString).range(of: text).location
        return try XCTUnwrap(view.textView.lineRect(atCharacter: location)).minY
    }

    // MARK: - Pitch

    func testTwoBodyLinesAreOnePointFourTimesThePointSizeApart() throws {
        let view = settledView(wrapping, theme: theme(body: bodyPitchSpacing))
        let tops = lineTops(view.textView)
        XCTAssertGreaterThanOrEqual(tops.count, 2)
        XCTAssertEqual(tops[0], 0, accuracy: 0.01)
        XCTAssertEqual(tops[1] - tops[0], 22.4, accuracy: 0.5)
    }

    func testAOneLineHeadingIsExactlyItsFontsLineHeight() throws {
        let theme = theme(heading: 2)
        let heading = theme.headingFont(level: 2).lineHeight
        let start = settledView("## Title\n\nBody", theme: theme)
        XCTAssertEqual(try top(of: "Title", in: start), 0, accuracy: 0.01)
        XCTAssertEqual(try top(of: "Body", in: start), heading + theme.paragraphSpacing, accuracy: 0.01)

        // After a paragraph: the collapsed block gap above, the paragraph spacing below, and nothing more.
        let middle = settledView("Intro\n\n## Title\n\nBody", theme: theme)
        let title = try top(of: "Title", in: middle)
        XCTAssertEqual(title, body.lineHeight + theme.blockSpacing, accuracy: 0.01)
        XCTAssertEqual(try top(of: "Body", in: middle) - title, heading + theme.paragraphSpacing, accuracy: 0.01)
    }

    func testATwoLineHeadingsPitchIsItsLineHeightPlusTheSpacing() {
        let theme = theme(heading: 2)
        let view = settledView("# A heading long enough to wrap onto a second line", theme: theme)
        let tops = lineTops(view.textView)
        XCTAssertGreaterThanOrEqual(tops.count, 2)
        XCTAssertEqual(tops[0], 0, accuracy: 0.01)
        XCTAssertEqual(tops[1] - tops[0], theme.headingFont(level: 1).lineHeight + 2, accuracy: 0.01)
    }

    func testCodeBlockLinePitchIsItsLineHeightPlusTheSpacing() {
        let theme = theme(code: 2)
        let code = GlimmerCodeBlockView(code: "a\nb\nc", language: nil, theme: theme, highlighter: GlimmerBasicHighlighter())
        let height = code.embedHeight(forWidth: width)
        windows.append(hostInWindow(code, width: width, height: height))
        let tops = lineTops(code.textView)
        let line = theme.codeFont.lineHeight
        XCTAssertEqual(tops.count, 3)
        XCTAssertEqual(tops[0], 0, accuracy: 0.01)
        XCTAssertEqual(tops[1] - tops[0], line + 2, accuracy: 0.01)
        XCTAssertEqual(tops[2] - tops[1], line + 2, accuracy: 0.01)
        // The box ends at the last line, with no spacing below it.
        let expected = GlimmerCodeBlockView.headerHeight + theme.embedPadding * 2 + ceil(3 * line + 4)
        XCTAssertEqual(height, expected, accuracy: 0.01)
    }

    func testAStreamedCodeBlockMeasuresAsOneBuiltWhole() {
        let theme = theme(code: 2)
        let highlighter = GlimmerBasicHighlighter()
        let lines = ["let a = 1", "let b = 2", "// done", "print(a + b)"]
        let streamed = GlimmerCodeBlockView(code: lines[0], language: "swift", theme: theme, highlighter: highlighter)
        for count in 2...lines.count {
            let code = lines.prefix(count).joined(separator: "\n")
            streamed.update(to: .codeBlock(language: "swift", code: code, highlighted: nil))
            let whole = GlimmerCodeBlockView(code: code, language: "swift", theme: theme, highlighter: highlighter)
            XCTAssertEqual(streamed.embedHeight(forWidth: width), whole.embedHeight(forWidth: width))
            let text = ceil(CGFloat(count) * theme.codeFont.lineHeight + CGFloat(count - 1) * 2)
            XCTAssertEqual(streamed.textSize.height, text, accuracy: 0.01)
        }
    }

    // MARK: - Gaps between blocks

    /// The space between the bottom of each block's last line and the top of the next block's first line.
    private func gaps(_ view: GlimmerView) -> [CGFloat] {
        let text = view.textView.textStorage.string as NSString
        var lasts: [Int] = []
        var firsts: [Int] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: .byParagraphs) { _, range, _, _ in
            guard range.length > 0 else { return }
            firsts.append(range.location)
            lasts.append(NSMaxRange(range) - 1)
        }
        return zip(lasts.dropLast(), firsts.dropFirst()).compactMap { last, first in
            guard let above = view.textView.lineRect(atCharacter: last),
                  let below = view.textView.lineRect(atCharacter: first) else { return nil }
            return below.minY - above.maxY
        }
    }

    func testTheGapsBetweenBlocksAreTheSameWithAndWithoutLineSpacing() {
        let markdown = """
        \(wrapping)

        ## Heading that wraps onto a second line here

        > A quote that also wraps onto a second line of text.

        - item one that wraps onto a second line of the list
        - item two

        ```
        code
        line
        ```

        After the code.
        """
        let plain = gaps(settledView(markdown, theme: theme()))
        let spaced = gaps(settledView(markdown, theme: theme(body: bodyPitchSpacing, heading: 2, code: 2)))
        XCTAssertGreaterThan(plain.count, 5)
        XCTAssertEqual(plain.count, spaced.count)
        for (plain, spaced) in zip(plain, spaced) {
            XCTAssertEqual(spaced, plain, accuracy: 0.01)
        }
    }

    // MARK: - Heights

    func testTheRevealedHeightNeverShrinksOrPassesTheSettledHeight() async {
        var configuration = GlimmerConfiguration(imageLoader: nil)
        configuration.theme = theme(body: 6, heading: 2)
        let view = GlimmerView(configuration: configuration)
        let clock = ManualRevealClock()
        view.clock = clock
        windows.append(hostInWindow(view, width: 240, height: 800))
        let answer = "## A heading that wraps\n\n" + wrapping + " " + wrapping
        var reported: [CGFloat] = []
        view.onHeightChange = { reported.append(view.intrinsicContentSize.height) }
        view.update(markdown: answer, isStreaming: true)
        await view.pendingDocument?.value
        var time = 0.0
        while view.engine != nil, time < 10 {
            time += 0.05
            if time > 1 {
                view.update(markdown: answer, isStreaming: false)
                await view.pendingDocument?.value
            }
            clock.advance(to: time)
        }
        let settled = view.textView.sizeThatFits(CGSize(width: 240, height: CGFloat.greatestFiniteMagnitude)).height
        XCTAssertGreaterThan(reported.count, 2, "the height grows line by line")
        XCTAssertEqual(reported, reported.sorted(), "the height never shrinks while revealing")
        XCTAssertLessThanOrEqual(reported.max() ?? 0, settled + 0.5)
        XCTAssertEqual(view.intrinsicContentSize.height, settled, accuracy: 0.5)
    }

    func testACappedHeightEndsAtTheBottomOfAWholeLine() {
        let view = settledView(wrapping + " " + wrapping, theme: theme(body: 6))
        let bottoms = layoutFragments(view.textView).flatMap { fragment in
            fragment.textLineFragments.map { ceil(fragment.layoutFragmentFrame.minY + $0.typographicBounds.maxY) }
        }
        XCTAssertGreaterThan(bottoms.count, 3)
        for maximum in [bottoms[1] + 3, bottoms[2] - 1, bottoms[2] + 5] {
            let capped = view.height(forWidth: width, notExceeding: maximum)
            XCTAssertTrue(bottoms.contains(capped), "\(capped) is not a line's bottom: \(bottoms)")
            XCTAssertEqual(capped, bottoms.last(where: { $0 <= maximum }))
        }
    }

    func testTheFittingWidthIgnoresLineSpacing() {
        let plain = settledView("Short line\n\nA longer line here", theme: theme()).fittingWidth(maximum: width)
        let spaced = settledView("Short line\n\nA longer line here", theme: theme(body: 6)).fittingWidth(maximum: width)
        XCTAssertEqual(spaced, plain)
    }

    // MARK: - GlimmerStaticText

    private func staticHeight(_ markdown: String, theme: GlimmerTheme, hostSpacing: CGFloat? = nil) -> CGFloat {
        var configuration = GlimmerConfiguration.default
        configuration.theme = theme
        let text = GlimmerStaticText(markdown, configuration: configuration)
            .frame(width: width)
            .transformEnvironment(\.lineSpacing) { if let hostSpacing { $0 = hostSpacing } }
        let host = UIHostingController(rootView: text.environment(\.dynamicTypeSize, .large))
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    func testStaticTextSpacesEachRolesLinesAndNothingAfterTheLast() {
        let plain = theme()
        let spaced = theme(body: 6, heading: 2, code: 2)
        // One line: no spacing above or below.
        XCTAssertEqual(staticHeight("One", theme: spaced), staticHeight("One", theme: plain), accuracy: 0.5)
        XCTAssertEqual(staticHeight("# One", theme: spaced), staticHeight("# One", theme: plain), accuracy: 0.5)
        // Lines that wrap: the role's spacing between each pair of lines.
        let scaled = plain.scaled(for: UITraitCollection(preferredContentSizeCategory: .large))
        func gaps(_ markdown: String, _ font: UIFont) -> CGFloat {
            (staticHeight(markdown, theme: plain) / font.lineHeight).rounded() - 1
        }
        let paragraphGaps = gaps(wrapping, scaled.bodyFont)
        XCTAssertGreaterThanOrEqual(paragraphGaps, 1)
        let paragraph = staticHeight(wrapping, theme: spaced) - staticHeight(wrapping, theme: plain)
        XCTAssertEqual(paragraph, 6 * paragraphGaps, accuracy: 1)
        let heading = "# A heading long enough to wrap onto a second line"
        let headingGaps = gaps(heading, scaled.headingFont(level: 1))
        XCTAssertGreaterThanOrEqual(headingGaps, 1)
        XCTAssertEqual(staticHeight(heading, theme: spaced) - staticHeight(heading, theme: plain), 2 * headingGaps, accuracy: 1)
        let code = "```\na\nb\nc\n```"
        XCTAssertEqual(staticHeight(code, theme: spaced) - staticHeight(code, theme: plain), 4, accuracy: 1)
    }

    func testStaticTextWithoutTheFieldsKeepsTheHostsLineSpacing() {
        let plain = theme()
        let base = staticHeight(wrapping, theme: plain)
        XCTAssertGreaterThan(staticHeight(wrapping, theme: plain, hostSpacing: 10), base + 15)
    }
}

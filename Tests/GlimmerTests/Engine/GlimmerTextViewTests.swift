import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerTextViewTests: XCTestCase {
    private let theme = GlimmerTheme.default

    private func attachment(_ embed: GlimmerEmbed) -> NSAttributedString {
        NSAttributedString(attachment: GlimmerBlockAttachment(
            embed: embed, theme: theme, highlighter: GlimmerBasicHighlighter(), imageLoader: nil
        ))
    }

    private func document(_ parts: [NSAttributedString]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, part) in parts.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n")) }
            result.append(part)
        }
        result.addAttribute(.font, value: theme.bodyFont, range: NSRange(location: 0, length: result.length))
        return result
    }

    func testStaysOnTextKit2() {
        let textView = GlimmerTextView()
        textView.attributedText = NSAttributedString(string: "Hello")
        XCTAssertNotNil(textView.textLayoutManager)
        XCTAssertFalse(textView.isScrollEnabled)
        XCTAssertFalse(textView.isEditable)
        XCTAssertTrue(textView.isSelectable)
    }

    func testEmptyTextAndZeroWidthMeasureZero() {
        let textView = GlimmerTextView()
        XCTAssertEqual(textView.sizeThatFits(CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)).height, 0)
        textView.attributedText = NSAttributedString(string: "Hello")
        XCTAssertEqual(textView.sizeThatFits(CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)).height, 0)
    }

    func testCodeBlockAttachmentHostsAFullWidthView() throws {
        let code = GlimmerEmbed.codeBlock(language: "swift", code: "let x = 1\nlet y = 2")
        let textView = GlimmerTextView()
        textView.attributedText = document([NSAttributedString(string: "Before"), attachment(code), NSAttributedString(string: "After")])
        let height = textView.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height
        let window = hostInWindow(textView, width: 390, height: height)

        let view = try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: textView))
        XCTAssertEqual(view.frame.width, 390, accuracy: 0.5)
        XCTAssertEqual(view.frame.height, view.embedHeight(forWidth: 390), accuracy: 0.5)
        XCTAssertGreaterThan(height, view.frame.height)
        _ = window
    }

    func testFactoryBuildsEveryEmbedKind() {
        let url = URL(string: "https://example.com/a.png")!  // test-only literal
        let embeds: [GlimmerEmbed] = [
            .codeBlock(language: nil, code: "x"),
            .table(header: [NSAttributedString(string: "h")], rows: [], alignments: [.none]),
            .image(source: url, alt: "a"),
            .thematicBreak,
        ]
        let kinds = embeds.map { embed in
            let attachment = GlimmerBlockAttachment(embed: embed, theme: theme, highlighter: GlimmerBasicHighlighter(), imageLoader: nil)
            return String(describing: type(of: GlimmerEmbedViewFactory.makeView(for: attachment)))
        }
        XCTAssertEqual(kinds, ["GlimmerCodeBlockView", "GlimmerTableView", "GlimmerImageEmbedView", "GlimmerRuleView"])
    }

    func testEmbedsResizeWhenWidthChanges() throws {
        let words = String(repeating: "wrap these words ", count: 30)
        let textView = GlimmerTextView()
        textView.attributedText = document([NSAttributedString(string: words), attachment(.thematicBreak)])
        let wide = textView.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height
        let window = hostInWindow(textView, width: 390, height: wide)
        let rule = try XCTUnwrap(findSubview(GlimmerRuleView.self, in: textView))
        XCTAssertEqual(rule.frame.width, 390, accuracy: 0.5)

        let narrow = textView.sizeThatFits(CGSize(width: 250, height: CGFloat.greatestFiniteMagnitude)).height
        XCTAssertGreaterThan(narrow, wide)
        textView.frame = CGRect(x: 0, y: 0, width: 250, height: narrow)
        settle(textView)
        let resized = try XCTUnwrap(findSubview(GlimmerRuleView.self, in: textView))
        XCTAssertTrue(resized === rule, "the same view resizes; it is not rebuilt")
        XCTAssertEqual(resized.frame.width, 250, accuracy: 0.5)
        _ = window
    }

    func testEmbedViewsSurviveHeightQueriesAndFrameChanges() async throws {
        let loader = CountingImageLoader()
        let url = URL(string: "https://example.com/a.png")!  // test-only literal
        let textView = GlimmerTextView()
        textView.attributedText = document([
            NSAttributedString(attachment: GlimmerBlockAttachment(
                embed: .codeBlock(language: "swift", code: "let x = 1"), theme: theme,
                highlighter: GlimmerBasicHighlighter(), imageLoader: nil)),
            NSAttributedString(attachment: GlimmerBlockAttachment(
                embed: .image(source: url, alt: "a"), theme: theme,
                highlighter: GlimmerBasicHighlighter(), imageLoader: loader)),
        ])
        let height = textView.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height
        let window = hostInWindow(textView, width: 390, height: height)
        let code = try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: textView))

        _ = textView.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude))
        _ = textView.intrinsicContentSize
        textView.frame.size.height += 40
        settle(textView)

        let after = try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: textView))
        XCTAssertTrue(after === code, "height queries and frame changes must not rebuild embed views")
        let loaded = await waitUntil { loader.count >= 1 }
        XCTAssertTrue(loaded)
        settle(textView)
        XCTAssertEqual(loader.count, 1, "the image is fetched once")
        _ = window
    }

    func testImageLoadIsCancelledWhenTheViewGoesAway() async throws {
        let loader = SuspendingImageLoader()
        let url = URL(string: "https://example.com/a.png")!  // test-only literal
        var view: GlimmerImageEmbedView? = GlimmerImageEmbedView(source: url, alt: "a", theme: theme, loader: loader)
        let started = await waitUntil { loader.didStart }
        XCTAssertTrue(started)
        XCTAssertNotNil(view)
        view = nil
        let cancelled = await waitUntil { loader.wasCancelled }
        XCTAssertTrue(cancelled, "a dropped image view must not keep fetching")
    }

    func testThemeSetsLinkAttributes() {
        var themed = theme
        themed.underlinesLinks = true
        let textView = GlimmerTextView()
        textView.apply(theme: themed)
        XCTAssertEqual(textView.linkTextAttributes[.foregroundColor] as? UIColor, themed.linkColor)
        XCTAssertEqual(textView.linkTextAttributes[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)
    }
}

/// Counts fetches; returns an empty image.
final class CountingImageLoader: GlimmerImageLoader, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    var count: Int { lock.withLock { calls } }

    func loadImage(from url: URL) async throws -> UIImage {
        lock.withLock { calls += 1 }
        return UIImage()
    }
}

/// Never finishes on its own; records whether its task was cancelled.
final class SuspendingImageLoader: GlimmerImageLoader, @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var cancelled = false
    var didStart: Bool { lock.withLock { started } }
    var wasCancelled: Bool { lock.withLock { cancelled } }

    func loadImage(from url: URL) async throws -> UIImage {
        lock.withLock { started = true }
        return try await withTaskCancellationHandler {
            try await Task.sleep(for: .seconds(30))
            return UIImage()
        } onCancel: {
            lock.withLock { cancelled = true }
        }
    }
}

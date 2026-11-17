import UIKit
import XCTest
@testable import Glimmer

/// Records the images it was asked for.
private final class RecordingImageLoader: GlimmerImageLoader, @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    var requested: [URL] { lock.withLock { urls } }
    func loadImage(from url: URL) async throws -> UIImage {
        lock.withLock { urls.append(url) }
        return UIImage()
    }
}

private struct ConfiguredCacheExtension: GlimmerExtension {
    let label: String
    func scan(_ text: String) -> [GlimmerInlineToken] {
        guard let range = text.range(of: "@person") else { return [] }
        return [GlimmerInlineToken(range: range, kind: "person", displayText: label,
                                  source: "@person", presentation: .text(tappable: false))]
    }
}

private struct ConfiguredCacheHighlighter: GlimmerHighlighter {
    let kind: GlimmerHighlightSpan.Kind
    func highlight(_ code: String, language: String?) -> [GlimmerHighlightSpan] {
        [GlimmerHighlightSpan(range: NSRange(location: 0, length: (code as NSString).length), kind: kind)]
    }
}

private struct Tagged: GlimmerExtension, Hashable {
    let tag: String
    func scan(_ text: String) -> [GlimmerInlineToken] {
        guard let range = text.range(of: "@person") else { return [] }
        return [GlimmerInlineToken(range: range, kind: "person", displayText: tag,
                                  source: "@person", presentation: .text(tappable: false))]
    }
}

private struct Untagged: GlimmerExtension {}

/// A tappable chip with a view, so each hosted view needs its own chip view.
private struct TappableChips: GlimmerExtension, Hashable {
    func scan(_ text: String) -> [GlimmerInlineToken] {
        text.ranges(of: #/\[\d+\]/#).map { range in
            var token = GlimmerInlineToken(range: range, kind: "citation", displayText: String(text[range]),
                                           source: String(text[range]))
            token.isTappable = true
            return token
        }
    }

    @MainActor func makeInlineView(for token: GlimmerInlineToken, theme: GlimmerTheme) -> UIView? {
        UILabel()
    }
}

private class BaseHighlighter: GlimmerHighlighter, Hashable, @unchecked Sendable {
    static func == (lhs: BaseHighlighter, rhs: BaseHighlighter) -> Bool { true }
    func hash(into hasher: inout Hasher) {}
    func highlight(_ code: String, language: String?) -> [GlimmerHighlightSpan] {
        [GlimmerHighlightSpan(range: NSRange(location: 0, length: (code as NSString).length), kind: .keyword)]
    }
}

private final class SubHighlighter: BaseHighlighter, @unchecked Sendable {
    override func highlight(_ code: String, language: String?) -> [GlimmerHighlightSpan] {
        [GlimmerHighlightSpan(range: NSRange(location: 0, length: (code as NSString).length), kind: .string)]
    }
}

private struct HashableLoader: GlimmerImageLoader, Hashable {
    func loadImage(from url: URL) async throws -> UIImage { UIImage() }
}

@MainActor
final class GlimmerDocumentCacheTests: XCTestCase {
    private let answer = "# Title\n\nSome **text**.\n\n```swift\nlet x = 1\n```"

    override func setUp() async throws {
        GlimmerDocumentCache.shared.removeAll()
    }

    private func hitsAfterTwoViews(_ configure: () -> (GlimmerConfiguration, GlimmerConfiguration), markdown: String = "Hello @person [1]") -> Int {
        let (a, b) = configure()
        let first = GlimmerView(configuration: a)
        first.update(markdown: markdown)
        let hits = GlimmerDocumentCache.shared.hits
        let second = GlimmerView(configuration: b)
        second.update(markdown: markdown)
        return GlimmerDocumentCache.shared.hits - hits
    }

    func testEqualHashableExtensionsShareComposedAnswers() {
        let gained = hitsAfterTwoViews {
            (.init(extensions: [Tagged(tag: "a")], imageLoader: nil), .init(extensions: [Tagged(tag: "a")], imageLoader: nil))
        }
        XCTAssertEqual(gained, 1)
    }

    func testDifferentHashableValuesDoNotShare() {
        let gained = hitsAfterTwoViews {
            (.init(extensions: [Tagged(tag: "a")], imageLoader: nil), .init(extensions: [Tagged(tag: "b")], imageLoader: nil))
        }
        XCTAssertEqual(gained, 0)
    }

    func testASubclassIsNotTheSameConfigurationAsItsBase() throws {
        let markdown = "```swift\nvalue\n```"
        let first = GlimmerView(configuration: .init(imageLoader: nil, highlighter: BaseHighlighter()))
        first.update(markdown: markdown)
        let hits = GlimmerDocumentCache.shared.hits
        let second = GlimmerView(configuration: .init(imageLoader: nil, highlighter: SubHighlighter()))
        second.update(markdown: markdown)
        XCTAssertEqual(GlimmerDocumentCache.shared.hits, hits)
        let attachment = try XCTUnwrap(blockAttachments(in: second.textView.textStorage).first)
        guard case .codeBlock(_, _, let highlighted) = attachment.embed else { return XCTFail("expected code") }
        XCTAssertEqual(highlighted?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor,
                       second.configuration.theme.syntaxStringColor)
    }

    func testIdentitiesOfABaseAndItsSubclassAreNotEqual() throws {
        let base = try XCTUnwrap(GlimmerCacheIdentity(highlighter: BaseHighlighter()))
        let sub = try XCTUnwrap(GlimmerCacheIdentity(highlighter: SubHighlighter()))
        XCTAssertNotEqual(base, sub)
        XCTAssertEqual(base, try XCTUnwrap(GlimmerCacheIdentity(highlighter: BaseHighlighter())))
    }

    func testANonHashableExtensionIsStillNotCached() {
        let gained = hitsAfterTwoViews {
            (.init(extensions: [Untagged()], imageLoader: nil), .init(extensions: [Untagged()], imageLoader: nil))
        }
        XCTAssertEqual(gained, 0)
    }

    func testAHashableLoaderIsCached() {
        let gained = hitsAfterTwoViews({
            (.init(imageLoader: HashableLoader()), .init(imageLoader: HashableLoader()))
        }, markdown: "Plain **text**.")
        XCTAssertEqual(gained, 1)
    }

    func testViewsSharingACachedAnswerGetTheirOwnChipViews() throws {
        let first = GlimmerView(configuration: .init(extensions: [TappableChips()], imageLoader: nil, reveal: .none))
        first.update(markdown: "See [1].")
        let firstWindow = hostInWindow(first, width: 320, height: 200)
        let hits = GlimmerDocumentCache.shared.hits
        let second = GlimmerView(configuration: .init(extensions: [TappableChips()], imageLoader: nil, reveal: .none))
        second.update(markdown: "See [1].")
        let secondWindow = hostInWindow(second, width: 320, height: 200)
        XCTAssertEqual(GlimmerDocumentCache.shared.hits, hits + 1)
        let firstChip = try XCTUnwrap(findSubview(GlimmerChipTapView.self, in: first))
        let secondChip = try XCTUnwrap(findSubview(GlimmerChipTapView.self, in: second))
        XCTAssertFalse(firstChip === secondChip)
        XCTAssertTrue(firstChip.isDescendant(of: first))
        XCTAssertTrue(secondChip.isDescendant(of: second))
        XCTAssertFalse(firstChip.isDescendant(of: second))
        _ = (firstWindow, secondWindow)
    }

    func testConfiguredExtensionsDoNotShareCachedOutput() {
        let first = GlimmerView(configuration: .init(extensions: [ConfiguredCacheExtension(label: "Alice")], imageLoader: nil))
        first.update(markdown: "Hello @person")
        let second = GlimmerView(configuration: .init(extensions: [ConfiguredCacheExtension(label: "Bob")], imageLoader: nil))
        second.update(markdown: "Hello @person")
        XCTAssertEqual(second.plainText(), "Hello Bob")
        first.configuration.extensions = [ConfiguredCacheExtension(label: "Carol")]
        XCTAssertEqual(first.plainText(), "Hello Carol")
    }

    func testCustomLoaderInstancesNeverShareCachedAttachments() throws {
        let firstLoader = RecordingImageLoader()
        let secondLoader = RecordingImageLoader()
        let first = GlimmerView(configuration: .init(imageLoader: firstLoader))
        first.update(markdown: "![Photo](https://example.com/photo.png)")
        let second = GlimmerView(configuration: .init(imageLoader: secondLoader))
        second.update(markdown: "![Photo](https://example.com/photo.png)")
        let attachment = try XCTUnwrap(blockAttachments(in: second.textView.textStorage).first)
        XCTAssertTrue((attachment.imageLoader as? RecordingImageLoader) === secondLoader)
    }

    func testConfiguredHighlightersDoNotShareCachedOutput() throws {
        let first = GlimmerView(configuration: .init(imageLoader: nil, highlighter: ConfiguredCacheHighlighter(kind: .keyword)))
        first.update(markdown: "```swift\nvalue\n```")
        let second = GlimmerView(configuration: .init(imageLoader: nil, highlighter: ConfiguredCacheHighlighter(kind: .string)))
        second.update(markdown: "```swift\nvalue\n```")
        let attachment = try XCTUnwrap(blockAttachments(in: second.textView.textStorage).first)
        guard case .codeBlock(_, _, let highlighted) = attachment.embed else { return XCTFail("expected code") }
        XCTAssertEqual(highlighted?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor,
                       second.configuration.theme.syntaxStringColor)
    }

    func testSecondConfigureOfTheSameAnswerComesFromTheCache() {
        let first = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let firstWindow = hostInWindow(first, width: 390, height: 800)
        first.update(markdown: answer)
        let hits = GlimmerDocumentCache.shared.hits
        let second = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let secondWindow = hostInWindow(second, width: 390, height: 800)
        second.update(markdown: answer)
        XCTAssertEqual(GlimmerDocumentCache.shared.hits, hits + 1)
        XCTAssertEqual(second.textView.textStorage.string, first.textView.textStorage.string)
        _ = (firstWindow, secondWindow)
    }

    func testTwoViewsOfOneAnswerNeverShareAnEmbedView() throws {
        let first = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let second = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let firstWindow = hostInWindow(first, width: 390, height: 800)
        let secondWindow = hostInWindow(second, width: 390, height: 800)
        first.update(markdown: answer)
        second.update(markdown: answer)
        settle(first)
        settle(second)
        let a = try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: first))
        let b = try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: second))
        XCTAssertFalse(a === b)
        XCTAssertTrue(a.isDescendant(of: first))
        _ = (firstWindow, secondWindow)
    }

    func testMemoryWarningEmptiesTheCache() throws {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: answer)
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        let highlighter = try XCTUnwrap(GlimmerCacheIdentity(highlighter: GlimmerBasicHighlighter()))
        let key = GlimmerDocumentCache.Key(source: answer, theme: view.configuration.theme.scaled(for: view.traitCollection),
                                           extensions: [], highlighter: highlighter, imageLoader: nil,
                                           imagePolicy: nil, linkPolicy: nil)
        XCTAssertNil(GlimmerDocumentCache.shared.text(for: key))
        _ = window
    }

    func testCachedHeightMatchesAMeasuredOne() {
        let first = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let firstWindow = hostInWindow(first, width: 390, height: 800)
        first.update(markdown: answer)
        let measured = first.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height
        let second = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let secondWindow = hostInWindow(second, width: 390, height: 800)
        second.update(markdown: answer)
        XCTAssertEqual(second.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height, measured, accuracy: 0.5)
        _ = (firstWindow, secondWindow)
    }

    func testStreamingOnNeverChangesWhatTheCacheHandsOut() async throws {
        let first = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let firstWindow = hostInWindow(first, width: 390, height: 800)
        first.update(markdown: "```swift\nlet a = 1")
        settle(first)
        // The same view streams on: its worker reuses the code block's attachment and grows it.
        first.update(markdown: "```swift\nlet a = 1\nlet b = 2", isStreaming: true)
        await first.pendingDocument?.value
        let second = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let secondWindow = hostInWindow(second, width: 390, height: 800)
        second.update(markdown: "```swift\nlet a = 1")
        settle(second)
        XCTAssertEqual(try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: second)).code, "let a = 1")
        _ = (firstWindow, secondWindow)
    }

    func testTheCacheKeepsNoEmbedViewAlive() {
        weak var codeView: GlimmerCodeBlockView?
        autoreleasepool {
            let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
            let window = hostInWindow(view, width: 390, height: 800)
            view.update(markdown: answer)
            settle(view)
            codeView = findSubview(GlimmerCodeBlockView.self, in: view)
            XCTAssertNotNil(codeView)
            window.isHidden = true
            view.removeFromSuperview()
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertNil(codeView, "the cached text must not hold the view that composed it")
    }

    func testAViewWithAnotherImageLoaderUsesItsOwn() async {
        let answer = "![Chart](https://example.com/chart.png)"
        let preview = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let previewWindow = hostInWindow(preview, width: 390, height: 800)
        preview.update(markdown: answer)
        settle(preview)
        let loader = RecordingImageLoader()
        let full = GlimmerView(configuration: GlimmerConfiguration(imageLoader: loader))
        let fullWindow = hostInWindow(full, width: 390, height: 800)
        full.update(markdown: answer)
        settle(full)
        let loaded = await waitUntil { !loader.requested.isEmpty }
        XCTAssertTrue(loaded, "the view's own loader fetches the image, not the cached text's")
        _ = (previewWindow, fullWindow)
    }
}

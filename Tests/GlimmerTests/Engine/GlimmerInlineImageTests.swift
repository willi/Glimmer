import UIKit
import XCTest
@testable import Glimmer

/// Counts loads, so a test can tell a kept image from one loaded again.
private final class CountingInlineLoader: GlimmerImageLoader, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.withLock { count } }
    func loadImage(from url: URL) async throws -> UIImage {
        lock.withLock { count += 1 }
        return UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }
    }
}

private struct InlineStubLoader: GlimmerImageLoader {
    let result: Result<UIImage, URLError>
    func loadImage(from url: URL) async throws -> UIImage { try result.get() }
}

/// An image inside a paragraph: a square as tall as the line, filled by the image loader, never resized by a load.
@MainActor
final class GlimmerInlineImageTests: XCTestCase {
    private let markdown = "A badge ![ci](https://example.com/b.png) in text."

    /// `tag` keeps each test's text apart in the settled-document cache.
    private func shown(
        loader: (any GlimmerImageLoader)?, shape: GlimmerInlineImageShape = .circle, tag: String = #function
    ) -> (GlimmerView, UIWindow) {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: loader, inlineImageShape: shape, reveal: .none))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: markdown + " " + tag)
        settle(view)
        return (view, window)
    }

    private func imageAttachment(in view: GlimmerView) throws -> GlimmerInlineImageAttachment {
        let text = view.textView.textStorage
        var found: GlimmerInlineImageAttachment?
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, stop in
            if let image = value as? GlimmerInlineImageAttachment { found = image; stop.pointee = true }
        }
        return try XCTUnwrap(found)
    }

    func testAnInlineImageIsALineHighSquare() throws {
        let (view, window) = shown(loader: nil)
        let attachment = try imageAttachment(in: view)
        let imageView = try XCTUnwrap(attachment.existingView)
        let side = ceil(GlimmerTheme.default.scaled(for: view.traitCollection).bodyFont.lineHeight)
        XCTAssertEqual(imageView.bounds.width, side, accuracy: 0.5)
        XCTAssertEqual(imageView.bounds.height, side, accuracy: 0.5)
        _ = window
    }

    func testAnInlineImageIsCircularByDefault() throws {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil, reveal: .none))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: markdown)
        settle(view)
        let imageView = try XCTUnwrap(imageAttachment(in: view).existingView)
        XCTAssertGreaterThan(imageView.bounds.height, 0)
        XCTAssertEqual(imageView.layer.cornerRadius, imageView.bounds.height / 2, accuracy: 0.5)
        XCTAssertEqual(imageView.layer.cornerCurve, .circular)
        XCTAssertTrue(imageView.clipsToBounds)
        XCTAssertEqual(imageView.contentMode, .scaleAspectFill)
        _ = window
    }

    func testRoundedInlineImagesUseTheConfiguredRadiusAndFitTheWholeImage() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 10)).image { _ in }
        for radius in [CGFloat(0), 3, 7] {
            let (view, window) = shown(loader: InlineStubLoader(result: .success(image)), shape: .roundedRectangle(cornerRadius: radius))
            let imageView = try XCTUnwrap(imageAttachment(in: view).existingView)
            let loaded = await waitUntil { imageView.image != nil }
            XCTAssertTrue(loaded)
            XCTAssertEqual(imageView.layer.cornerRadius, radius)
            XCTAssertEqual(imageView.layer.cornerCurve, .continuous)
            XCTAssertEqual(imageView.contentMode, .scaleAspectFit)
            _ = window
        }
    }

    func testAnInlineImageStaysCircularAtLargerTextSizes() throws {
        let (view, window) = shown(loader: nil)
        let originalSide = try XCTUnwrap(imageAttachment(in: view).existingView).bounds.height
        view.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        settle(view)
        let imageView = try XCTUnwrap(imageAttachment(in: view).existingView)
        XCTAssertGreaterThan(imageView.bounds.height, originalSide)
        XCTAssertEqual(imageView.bounds.width, imageView.bounds.height)
        XCTAssertEqual(imageView.layer.cornerRadius, imageView.bounds.height / 2, accuracy: 0.5)
        _ = window
    }

    func testChangingTheShapeUpdatesAnExistingView() throws {
        let (view, window) = shown(loader: nil)
        let originalBounds = try XCTUnwrap(imageAttachment(in: view).existingView).bounds
        view.configuration.inlineImageShape = .roundedRectangle(cornerRadius: 3)
        settle(view)
        let rounded = try XCTUnwrap(imageAttachment(in: view).existingView)
        XCTAssertEqual(rounded.layer.cornerRadius, 3)
        XCTAssertEqual(rounded.bounds, originalBounds)
        view.configuration.inlineImageShape = .circle
        settle(view)
        let circle = try XCTUnwrap(imageAttachment(in: view).existingView)
        XCTAssertEqual(circle.layer.cornerRadius, circle.bounds.height / 2, accuracy: 0.5)
        XCTAssertEqual(circle.bounds, originalBounds)
        _ = window
    }

    func testCachedInlineImagesKeepTheirShapeWithoutSharingViews() throws {
        GlimmerDocumentCache.shared.removeAll()
        let (rounded, roundedWindow) = shown(loader: nil, shape: .roundedRectangle(cornerRadius: 3), tag: "shape cache")
        let (circle, circleWindow) = shown(loader: nil, tag: "shape cache")
        let circleImage = try XCTUnwrap(imageAttachment(in: circle).existingView)
        XCTAssertEqual(circleImage.layer.cornerRadius, circleImage.bounds.height / 2, accuracy: 0.5)
        let hits = GlimmerDocumentCache.shared.hits
        let (cached, cachedWindow) = shown(loader: nil, shape: .roundedRectangle(cornerRadius: 3), tag: "shape cache")
        XCTAssertEqual(GlimmerDocumentCache.shared.hits, hits + 1)
        let cachedImage = try XCTUnwrap(imageAttachment(in: cached).existingView)
        XCTAssertEqual(cachedImage.layer.cornerRadius, 3)
        XCTAssertEqual(cachedImage.contentMode, .scaleAspectFit)
        XCTAssertFalse(cachedImage === (try imageAttachment(in: rounded)).existingView)
        _ = (roundedWindow, circleWindow, cachedWindow)
    }

    func testExtensionAndTableImagesUseTheConfiguredShape() throws {
        let shape = GlimmerInlineImageShape.roundedRectangle(cornerRadius: 5)
        let composer = GlimmerComposer(theme: .default, inlineImageShape: shape, extensions: [GlimmerEmojiShortcodes()])
        let text = composer.compose(GlimmerParser.parse(":octocat: inline"))
        let emoji = try XCTUnwrap(text.attribute(.attachment, at: 0, effectiveRange: nil) as? GlimmerInlineImageAttachment)
        XCTAssertEqual(emoji.shape, shape)
        let tableText = composer.compose(GlimmerParser.parse("| Badge |\n| --- |\n| ![ci](https://example.com/b.png) |"))
        let table = try XCTUnwrap(tableText.attribute(.attachment, at: 0, effectiveRange: nil) as? GlimmerBlockAttachment)
        guard case .table(_, let rows, _) = table.embed else { return XCTFail("expected a table") }
        let image = try XCTUnwrap(rows[0][0].attribute(.attachment, at: 0, effectiveRange: nil) as? GlimmerInlineImageAttachment)
        XCTAssertEqual(image.shape, shape)
    }

    func testAnInlineImageLoadsItsImage() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 10)).image { _ in }
        let (view, window) = shown(loader: InlineStubLoader(result: .success(image)))
        let imageView = try XCTUnwrap(imageAttachment(in: view).existingView)
        let loaded = await waitUntil { imageView.image != nil }
        XCTAssertTrue(loaded)
        XCTAssertEqual(imageView.contentMode, .scaleAspectFill)
        _ = window
    }

    func testAFailedInlineImageKeepsItsSquare() async throws {
        for (index, loader) in [InlineStubLoader(result: .failure(URLError(.badServerResponse))) as (any GlimmerImageLoader)?, nil].enumerated() {
            let (view, window) = shown(loader: loader, tag: "failed \(index)")
            let imageView = try XCTUnwrap(imageAttachment(in: view).existingView)
            let before = imageView.bounds
            try await Task.sleep(for: .milliseconds(100))
            view.layoutIfNeeded()
            XCTAssertNil(imageView.image)
            XCTAssertEqual(imageView.bounds, before)
            XCTAssertGreaterThan(imageView.bounds.width, 0)
            XCTAssertNotNil(imageView.backgroundColor, "the placeholder tint")
            _ = window
        }
    }

    func testAParagraphOfOnlyAnImageIsStillAnEmbed() {
        let text = GlimmerComposer(theme: .default).compose(GlimmerParser.parse("![Chart](https://example.com/c.png)"))
        XCTAssertTrue(text.attribute(.attachment, at: 0, effectiveRange: nil) is GlimmerBlockAttachment)
    }

    func testInlineImagesCopyTheirSourceAndAlt() {
        let text = GlimmerComposer(theme: .default).compose(GlimmerParser.parse(markdown))
        let all = NSRange(location: 0, length: text.length)
        XCTAssertEqual(GlimmerMarkdownSerializer.markdown(from: text, range: all), markdown)
        XCTAssertEqual(GlimmerMarkdownSerializer.plainText(from: text, range: all), "A badge ci in text.")
    }

    func testVoiceOverReadsAnInlineImagesAlt() {
        let text = GlimmerComposer(theme: .default).compose(GlimmerParser.parse(markdown))
        let spoken = GlimmerMarkdownSerializer.plainText(from: text, range: NSRange(location: 0, length: text.length), forAccessibility: true)
        XCTAssertEqual(spoken.components(separatedBy: "ci").count - 1, 1, spoken)
    }

    func testInlineImagesStreamWithoutMovingShownText() {
        assertStreamingKeepsShownTextInPlace(
            "Status ![build](https://example.com/b.png) and ![cov](https://example.com/c.png) badges.\n\nThe next paragraph keeps growing.",
            expectedPlainText: "Status build and cov badges.\nThe next paragraph keeps growing."
        )
    }

    func testAStreamingParagraphKeepsItsImage() throws {
        let loader = CountingInlineLoader()
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: loader, reveal: .none))
        let window = hostInWindow(view, width: 390, height: 800)
        let markdown = "Badge ![ci](https://example.com/keep.png) then words keep arriving, slowly, here."
        var seen = Set<ObjectIdentifier>()
        var end = markdown.startIndex
        while end < markdown.endIndex {
            end = markdown.index(end, offsetBy: 3, limitedBy: markdown.endIndex) ?? markdown.endIndex
            view.update(markdown: String(markdown[..<end]), isStreaming: true, revealID: "keep")
            let deadline = Date().addingTimeInterval(5)
            while view.pendingDocument != nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }
            view.layoutIfNeeded()
            let text = view.textView.textStorage
            text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
                if let image = value as? GlimmerInlineImageAttachment { seen.insert(ObjectIdentifier(image)) }
            }
        }
        XCTAssertEqual(seen.count, 1, "one attachment for the image while its paragraph streams")
        XCTAssertEqual(loader.calls, 1, "loaded once")
        _ = window
    }
}

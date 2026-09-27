import UIKit
import XCTest
@testable import Glimmer

private struct InlineStubLoader: GlimmerImageLoader {
    let result: Result<UIImage, URLError>
    func loadImage(from url: URL) async throws -> UIImage { try result.get() }
}

/// An image inside a paragraph: a square as tall as the line, filled by the image loader, never resized by a load.
@MainActor
final class GlimmerInlineImageTests: XCTestCase {
    private let markdown = "A badge ![ci](https://example.com/b.png) in text."

    /// `tag` keeps each test's text apart in the settled-document cache, which tells loaders apart by type only.
    private func shown(loader: (any GlimmerImageLoader)?, tag: String = #function) -> (GlimmerView, UIWindow) {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: loader, reveal: .none))
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

    func testAnInlineImageLoadsItsImage() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 10)).image { _ in }
        let (view, window) = shown(loader: InlineStubLoader(result: .success(image)))
        let imageView = try XCTUnwrap(imageAttachment(in: view).existingView)
        let loaded = await waitUntil { imageView.image != nil }
        XCTAssertTrue(loaded)
        XCTAssertEqual(imageView.contentMode, .scaleAspectFit)
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
        assertStreamingKeepsShownTextInPlace("Status ![build](https://example.com/b.png) and ![cov](https://example.com/c.png) badges, then more text.")
    }
}

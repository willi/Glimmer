import UIKit
import XCTest
@testable import Glimmer

private struct StubImageLoader: GlimmerImageLoader {
    let result: Result<UIImage, URLError>
    func loadImage(from url: URL) async throws -> UIImage { try result.get() }
}

@MainActor
final class GlimmerImageEmbedViewTests: XCTestCase {
    private let theme = GlimmerTheme.default
    private let url = URL(string: "https://example.com/a.png")!  // test-only literal

    private func tallImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 10, height: 40)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 40))
        }
    }

    func testImageLoadsWithoutChangingHeight() async {
        let view = GlimmerImageEmbedView(source: url, alt: "chart", theme: theme, loader: StubImageLoader(result: .success(tallImage())))
        let before = view.embedHeight(forWidth: 300)
        XCTAssertEqual(before, 300 / theme.imagePlaceholderAspect, accuracy: 0.5)
        let loaded = await waitUntil { view.imageView.image != nil }
        XCTAssertTrue(loaded)
        XCTAssertEqual(view.embedHeight(forWidth: 300), before, "a finished load must not change layout")
        XCTAssertTrue(view.altLabel.isHidden)
    }

    func testFailedLoadShowsAltText() async {
        let view = GlimmerImageEmbedView(source: url, alt: "chart", theme: theme, loader: StubImageLoader(result: .failure(URLError(.badServerResponse))))
        let shown = await waitUntil { !view.altLabel.isHidden }
        XCTAssertTrue(shown)
        XCTAssertEqual(view.altLabel.text, "chart")
        XCTAssertEqual(view.accessibilityLabel, "chart")
    }

    func testNoLoaderShowsAltTextImmediately() {
        let view = GlimmerImageEmbedView(source: url, alt: "chart", theme: theme, loader: nil)
        XCTAssertFalse(view.altLabel.isHidden)
    }

    func testHeightIsCappedByMaxImageHeight() {
        let view = GlimmerImageEmbedView(source: url, alt: "", theme: theme, loader: nil)
        XCTAssertEqual(view.embedHeight(forWidth: 2000), theme.maxImageHeight)
    }
}

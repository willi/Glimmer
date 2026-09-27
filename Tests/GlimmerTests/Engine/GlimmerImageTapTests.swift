import UIKit
import XCTest
@testable import Glimmer

/// `onImageTap`: a tap on a standalone image or an inline image square reports its URL and alt text.
@MainActor
final class GlimmerImageTapTests: XCTestCase {
    private func shown(_ markdown: String, handler: ((URL, String) -> Void)?) -> (GlimmerView, UIWindow) {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil, reveal: .none))
        view.onImageTap = handler
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: markdown)
        settle(view)
        return (view, window)
    }

    func testTappingAStandaloneImageCallsOnImageTap() throws {
        var tapped: (URL, String)?
        let (view, window) = shown("![Chart](https://example.com/chart.png)") { tapped = ($0, $1) }
        let image = try XCTUnwrap(findSubview(GlimmerImageEmbedView.self, in: view))
        XCTAssertTrue(image.accessibilityTraits.contains(.button))
        image.handleTap()
        XCTAssertEqual(tapped?.0, URL(string: "https://example.com/chart.png"))
        XCTAssertEqual(tapped?.1, "Chart")
        _ = window
    }

    func testTappingAnInlineImageCallsOnImageTap() throws {
        var tapped: (URL, String)?
        let (view, window) = shown("An icon ![octocat](https://example.com/o.png) inline.") { tapped = ($0, $1) }
        let image = try XCTUnwrap(findSubview(GlimmerInlineImageView.self, in: view))
        XCTAssertTrue(image.isUserInteractionEnabled)
        image.handleTap()
        XCTAssertEqual(tapped?.0, URL(string: "https://example.com/o.png"))
        XCTAssertEqual(tapped?.1, "octocat")
        _ = window
    }

    func testImagesAreNotTappableWithoutAHandler() throws {
        let (view, window) = shown("![Chart](https://example.com/chart.png)", handler: nil)
        let image = try XCTUnwrap(findSubview(GlimmerImageEmbedView.self, in: view))
        XCTAssertFalse(image.accessibilityTraits.contains(.button))
        XCTAssertFalse(image.acceptsTaps)
        _ = window
    }

    func testPlainTextOfTheWholeAnswer() {
        let (view, window) = shown("# Title\n\nSome **bold** text.", handler: nil)
        XCTAssertEqual(view.plainText(), "Title\nSome bold text.", "blocks end in one newline, as copy writes them")
        XCTAssertEqual(view.plainText(for: NSRange(location: 0, length: 5)), "Title")
        _ = window
    }
}

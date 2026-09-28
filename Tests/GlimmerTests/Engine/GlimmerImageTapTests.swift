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

    /// The spoken-only alt text after an inline image, as the text holds it.
    private func altRun(of alt: String, in view: GlimmerView) -> NSRange {
        (view.textView.textStorage.string as NSString).range(of: alt)
    }

    /// While the host takes image taps, VoiceOver reaches an inline image through its alt text, read once and in
    /// reading order: the alt text is an internal link whose action taps the image. The image view stays hidden.
    func testWithAHandlerAnInlineImagesAltTextIsALinkThatTapsIt() throws {
        var tapped: (URL, String)?
        let (view, window) = shown("An icon ![octocat](https://example.com/o.png) inline.") { tapped = ($0, $1) }
        let run = altRun(of: "octocat", in: view)
        let link = try XCTUnwrap(view.textView.textStorage.attribute(.link, at: run.location, effectiveRange: nil) as? URL)
        XCTAssertTrue(GlimmerTokenBox.isInternalLink(link))
        let image = try XCTUnwrap(findSubview(GlimmerInlineImageView.self, in: view))
        XCTAssertTrue(image.accessibilityElementsHidden, "no second announcement")
        view.tapImageLink(atCharacter: run.location)
        XCTAssertEqual(tapped?.0, URL(string: "https://example.com/o.png"))
        XCTAssertEqual(tapped?.1, "octocat")
        XCTAssertEqual(view.markdownSource(for: NSRange(location: 0, length: view.textView.textStorage.length)),
                       "An icon ![octocat](https://example.com/o.png) inline.", "the internal link is not copied")
        _ = window
    }

    /// Without a handler the alt text is plain spoken text; setting one later recomposes, and the link appears.
    func testWithoutAHandlerAnInlineImagesAltTextIsText() {
        let (view, window) = shown("An icon ![octocat](https://example.com/o.png) inline.", handler: nil)
        XCTAssertNil(view.textView.textStorage.attribute(.link, at: altRun(of: "octocat", in: view).location, effectiveRange: nil))
        view.onImageTap = { _, _ in }
        settle(view)
        XCTAssertNotNil(view.textView.textStorage.attribute(.link, at: altRun(of: "octocat", in: view).location, effectiveRange: nil))
        _ = window
    }

    /// An image inside a link follows the link, as on GitHub: it takes no tap of its own.
    func testALinkedImageLeavesTheTapToItsLink() throws {
        let (view, window) = shown("See [![octocat](https://example.com/o.png)](https://example.com/page) here.") { _, _ in }
        let image = try XCTUnwrap(findSubview(GlimmerInlineImageView.self, in: view))
        XCTAssertFalse(image.acceptsTaps, "the link takes the tap")
        XCTAssertFalse(image.isAccessibilityElement, "VoiceOver reaches the link, not a second button")
        _ = window
    }

    /// A token link is no web link: no menu, no preview of its internal URL.
    func testAMentionHasNoLinkMenu() {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        view.linkMenuActions = { _ in [UIAction(title: "Share") { _ in }] }
        XCTAssertNil(view.menuConfiguration(forLink: GlimmerTokenBox.link(kind: "mention"), defaultMenu: UIMenu(children: [])))
        XCTAssertNotNil(view.menuConfiguration(forLink: URL(string: "https://example.com")!, defaultMenu: UIMenu(children: [])))
    }

    /// Its traits are set, not computed, so reading them off the main thread (as UIKit's accessibility may) is safe,
    /// and they follow a handler set after the image is shown.
    func testAStandaloneImagesTraitsAreSafeOffTheMainThread() throws {
        let (view, window) = shown("![Chart](https://example.com/chart.png)", handler: nil)
        let image = try XCTUnwrap(findSubview(GlimmerImageEmbedView.self, in: view))
        view.onImageTap = { _, _ in }
        nonisolated(unsafe) let object: NSObject = image
        nonisolated(unsafe) var traits: UInt64?
        let read = expectation(description: "read off the main thread")
        DispatchQueue.global().async {
            traits = (object.value(forKey: "accessibilityTraits") as? NSNumber)?.uint64Value
            read.fulfill()
        }
        wait(for: [read], timeout: 5)
        XCTAssertEqual(traits.map { UIAccessibilityTraits(rawValue: $0) }, [.image, .button])
        _ = window
    }

    func testPlainTextOfTheWholeAnswer() {
        let (view, window) = shown("# Title\n\nSome **bold** text.", handler: nil)
        XCTAssertEqual(view.plainText(), "Title\nSome bold text.", "blocks end in one newline, as copy writes them")
        XCTAssertEqual(view.plainText(for: NSRange(location: 0, length: 5)), "Title")
        _ = window
    }
}

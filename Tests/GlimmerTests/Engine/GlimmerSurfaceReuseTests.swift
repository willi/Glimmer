import UIKit
import XCTest
@testable import Glimmer

/// iOS 27 asks the text view for a cached rendering surface for every fragment on every viewport pass; handing back
/// the view UIKit already drew skips its redraw. A redraw shows as a new `layer.contents` on UIKit's fragment view.
@MainActor
final class GlimmerSurfaceReuseTests: XCTestCase {
    private let long = Array(repeating: StreamingFixtures.all.map(\.markdown).joined(separator: "\n\n"), count: 29)
        .joined(separator: "\n\n")

    /// UIKit's fragment views under `textView`.
    private func fragmentViews(in textView: UITextView) -> [UIView] {
        var result: [UIView] = []
        func walk(_ view: UIView) {
            for sub in view.subviews {
                if NSStringFromClass(type(of: sub)).contains("TextLayoutFragmentView") { result.append(sub) }
                walk(sub)
            }
        }
        walk(textView)
        return result
    }

    /// How many fragment views are marked to redraw (UIKit marks each one it redraws; the commit then draws it).
    private func pendingRedraws(in textView: UITextView) -> Int {
        fragmentViews(in: textView).filter { $0.layer.needsDisplay() }.count
    }

    /// A long settled answer in an 800-pt window, its band rendered and drawn.
    private func shown(reuse: Bool = true) -> (GlimmerView, UIWindow) {
        let scrollView = UIScrollView()
        let window = hostInWindow(scrollView, width: 390, height: 800)
        var configuration = GlimmerConfiguration(imageLoader: nil)
        configuration.reusesDrawnText = reuse
        let view = GlimmerView(configuration: configuration)
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 100_000)
        scrollView.addSubview(view)
        scrollView.contentSize = view.frame.size
        view.update(markdown: long)
        view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        view.layoutIfNeeded()
        CATransaction.flush()
        return (view, window)
    }

    /// Runs a viewport pass without committing it, so its redraw marks are still visible.
    private func pass(_ view: GlimmerView) {
        view.textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
    }

    func testAnUnchangedPassRedrawsNothing() {
        let (view, window) = shown()
        XCTAssertGreaterThan(fragmentViews(in: view.textView).count, 10)
        XCTAssertEqual(pendingRedraws(in: view.textView), 0)
        pass(view)
        XCTAssertEqual(pendingRedraws(in: view.textView), 0, "every fragment kept its pixels")
        _ = window
    }

    /// A surface handed back from the cache is put back in the canvas by UIKit, even one moved elsewhere meanwhile, so
    /// a reused surface always renders in this text view (each text view caches only its own surfaces).
    func testAReusedSurfaceMovedOutOfTheCanvasRendersInItAgain() throws {
        let (view, window) = shown()
        let before = fragmentViews(in: view.textView).count
        let moved = try XCTUnwrap(fragmentViews(in: view.textView).first)
        let elsewhere = UIView()
        window.addSubview(elsewhere)
        elsewhere.addSubview(moved)
        XCTAssertEqual(fragmentViews(in: view.textView).count, before - 1)
        pass(view)
        view.layoutIfNeeded()
        XCTAssertEqual(fragmentViews(in: view.textView).count, before, "the fragment is rendered in the canvas again")
        XCTAssertTrue(moved.isDescendant(of: view.textView), "UIKit re-parents the surface it gets back")
        _ = window
    }

    /// A streamed edit inside a paragraph already drawn: TextKit makes a new fragment for it, so its old surface is
    /// never handed back and the new words are drawn. Checked on the drawn pixels where they land.
    func testAStreamedEditDrawsItsNewWordsWithReuseOn() async throws {
        let scrollView = UIScrollView()
        let window = hostInWindow(scrollView, width: 390, height: 800)
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil, reveal: .none))
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 2_000)
        scrollView.addSubview(view)
        view.update(markdown: "First paragraph, drawn.\n\nSecond paragraph starts", isStreaming: true)
        await view.pendingDocument?.value
        settle(view)
        view.update(markdown: "First paragraph, drawn.\n\nSecond paragraph starts and grows", isStreaming: true)
        await view.pendingDocument?.value
        settle(view)
        let textView = view.textView
        let offset = (textView.textStorage.string as NSString).range(of: "and grows").location
        let start = try XCTUnwrap(textView.position(from: textView.beginningOfDocument, offset: offset))
        let end = try XCTUnwrap(textView.position(from: start, offset: 9))
        let rect = textView.convert(textView.firstRect(for: try XCTUnwrap(textView.textRange(from: start, to: end))), to: window)
            .intersection(window.bounds).integral
        XCTAssertFalse(rect.isEmpty)
        XCTAssertGreaterThan(inkPixels(in: rect, of: window), 30, "the new words are drawn")
        let emptyRest = CGRect(x: rect.maxX + 20, y: rect.minY, width: max(0, window.bounds.maxX - rect.maxX - 30), height: rect.height)
        XCTAssertLessThan(inkPixels(in: emptyRest, of: window), 5, "the check sees where there is no text")
        _ = window
    }

    /// Dark pixels in `rect` of the window as drawn.
    private func inkPixels(in rect: CGRect, of window: UIWindow) -> Int {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { context in window.layer.render(in: context.cgContext) }
        guard let cgImage = image.cgImage, let data = cgImage.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return 0 }
        let scale = image.scale, perRow = cgImage.bytesPerRow, perPixel = cgImage.bitsPerPixel / 8
        var count = 0
        for y in max(0, Int(rect.minY * scale))..<min(cgImage.height, Int(rect.maxY * scale)) {
            for x in max(0, Int(rect.minX * scale))..<min(cgImage.width, Int(rect.maxX * scale)) {
                let pixel = bytes + y * perRow + x * perPixel
                if pixel[0] < 90, pixel[1] < 90, pixel[2] < 90 { count += 1 }
            }
        }
        return count
    }

    func testWithoutReuseAPassRedrawsTheBand() {
        let (view, window) = shown(reuse: false)
        let count = fragmentViews(in: view.textView).count
        XCTAssertGreaterThan(count, 10)
        pass(view)
        XCTAssertGreaterThan(pendingRedraws(in: view.textView), count / 2, "UIKit redraws the band on every pass")
        _ = window
    }

    func testADarkModeSwitchRedrawsReusedText() {
        let (view, window) = shown()
        let count = fragmentViews(in: view.textView).count
        window.overrideUserInterfaceStyle = .dark
        // UIKit applies trait changes in its next update cycle; a test applies them itself.
        window.updateTraitsIfNeeded()
        XCTAssertEqual(view.textView.traitCollection.userInterfaceStyle, .dark)
        view.layoutIfNeeded()
        pass(view)
        XCTAssertEqual(pendingRedraws(in: view.textView), count, "every visible fragment redraws in dark")
        _ = window
    }

    func testAnEmbedThatGrowsIsRedrawn() throws {
        let (view, window) = shown()
        let textView = view.textView
        let string = textView.textStorage.string as NSString
        var index: Int?
        for location in 0..<string.length where string.character(at: location) == 0xFFFC {
            if case .codeBlock = textView.blockAttachment(atCharacter: location)?.embed, textView.blockAttachment(atCharacter: location)?.existingView != nil {
                index = location
                break
            }
        }
        let location = try XCTUnwrap(index, "a code block on screen")
        let attachment = try XCTUnwrap(textView.blockAttachment(atCharacter: location))
        let embed = try XCTUnwrap(attachment.existingView as? UIView)
        let host = try XCTUnwrap(embed.superview)
        attachment.visibleUnitCount = 1
        textView.invalidateEmbedLayout(atCharacter: location)
        pass(view)
        let newHost = try XCTUnwrap(embed.superview)
        XCTAssertTrue(newHost !== host || newHost.layer.needsDisplay(), "the embed's fragment redraws at its new height")
        _ = window
    }

    func testTurningReuseOffOnALiveViewRedrawsOnEveryPass() {
        let (view, window) = shown()
        view.configuration.reusesDrawnText = false
        view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        view.layoutIfNeeded()
        CATransaction.flush()
        let count = fragmentViews(in: view.textView).count
        XCTAssertGreaterThan(count, 10)
        pass(view)
        XCTAssertGreaterThan(pendingRedraws(in: view.textView), count / 2, "the escape hatch works on a live view")
        _ = window
    }

    func testRevealingAnEmbedRedrawsOnlyItsFragment() throws {
        let (view, window) = shown()
        let textView = view.textView
        let string = textView.textStorage.string as NSString
        let location = try XCTUnwrap((0..<string.length).first {
            string.character(at: $0) == 0xFFFC && textView.blockAttachment(atCharacter: $0)?.existingView is GlimmerCodeBlockView
        }, "a code block on screen")
        let attachment = try XCTUnwrap(textView.blockAttachment(atCharacter: location))
        XCTAssertGreaterThan(fragmentViews(in: textView).count, 10)
        attachment.visibleUnitCount = 1
        textView.invalidateEmbedLayout(atCharacter: location)
        pass(view)
        XCTAssertLessThanOrEqual(pendingRedraws(in: textView), 2, "a revealed code line redraws its own fragment, not the band")
        _ = window
    }

    /// A rendering attribute (how UIKit tints a pressed link) must redraw its fragment with reuse on.
    func testARenderingAttributeRedrawsItsFragment() throws {
        let (view, window) = shown()
        let textView = view.textView
        var linkRange = NSRange(location: NSNotFound, length: 0)
        textView.textStorage.enumerateAttribute(.link, in: NSRange(location: 0, length: 4_000)) { value, range, stop in
            if value != nil { linkRange = range; stop.pointee = true }
        }
        let range = try XCTUnwrap(linkRange.location == NSNotFound ? nil : textView.textRange(for: linkRange), "a link near the top")
        textView.textLayoutManager?.setRenderingAttributes([.foregroundColor: UIColor.systemRed], for: range)
        pass(view)
        XCTAssertGreaterThan(pendingRedraws(in: textView), 0, "the link's fragment redraws")
        _ = window
    }
}

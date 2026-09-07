import XCTest
import UIKit
@testable import Glimmer

@MainActor
final class GlimmerTrailTextViewTests: XCTestCase {
    func testUsesTextKit2AndPreservesAttributedRunsAndLinks() {
        let view = GlimmerTrailTextView(now: { 10 })
        let font = UIFont.italicSystemFont(ofSize: 21)
        let color = UIColor.systemPurple.withAlphaComponent(0.6)
        let link = URL(string: "https://example.com")!
        let source = NSAttributedString(string: "linked", attributes: [
            .font: font,
            .foregroundColor: color,
            .link: link,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ])

        view.update(attributedText: source, isStreaming: true)

        XCTAssertNotNil(view.textLayoutManager)
        XCTAssertTrue(view.isSelectable)
        XCTAssertFalse(view.isEditable)
        XCTAssertTrue(view.attributedText.isEqual(to: source))
        XCTAssertEqual(view.trailOpacity(atUTF16Offset: 0), 0, accuracy: 0.001)

        view.advance(at: 10 + RevealSmoothTrail.duration / 2)
        let alpha = view.trailOpacity(atUTF16Offset: 0)
        XCTAssertGreaterThan(alpha, 0)
        XCTAssertLessThan(alpha, 1)
        XCTAssertTrue(view.attributedText.isEqual(to: source), "Drawing must not alter stored attributes.")
        XCTAssertEqual(view.attributedText.attribute(.link, at: 0, effectiveRange: nil) as? URL, link)
    }

    func testPauseSettlesLastWordWithoutAnotherProducerUpdate() {
        let view = GlimmerTrailTextView(now: { 0 })
        view.update(attributedText: NSAttributedString(string: "Hello"), isStreaming: true)
        XCTAssertTrue(view.isRevealing)
        XCTAssertTrue(view.isStreaming)

        view.advance(at: RevealSmoothTrail.duration + 0.01)

        XCTAssertFalse(view.isRevealing)
        XCTAssertTrue(view.isStreaming, "A settled trail must not end the producer stream.")
        XCTAssertEqual(view.text, "Hello")
        XCTAssertEqual(view.trailOpacity(atUTF16Offset: 0), 1)
        XCTAssertNil(view.layer.mask)
        XCTAssertFalse(view.isFrameUpdatesEnabled)
    }

    func testEndingStreamWaitsForLastWordFade() {
        var time = 0.0
        let view = GlimmerTrailTextView(now: { time })
        let source = NSAttributedString(string: "one two")
        view.update(attributedText: source, isStreaming: true)
        XCTAssertEqual(view.text, "one ")

        time = 0.1
        view.update(attributedText: source, isStreaming: false)
        XCTAssertEqual(view.text, source.string)
        XCTAssertTrue(view.isRevealing)

        view.advance(at: time + RevealSmoothTrail.duration + 0.01)
        XCTAssertFalse(view.isRevealing)
        XCTAssertFalse(view.isStreaming)
    }

    func testAppendAfterCompletionDoesNotReplayOldText() {
        var time = 0.0
        let view = GlimmerTrailTextView(now: { time })
        view.update(attributedText: NSAttributedString(string: "first"), isStreaming: false)
        view.finishImmediately()

        time = 2
        view.update(attributedText: NSAttributedString(string: "first second"), isStreaming: true)
        view.advance(at: 2.1)

        XCTAssertEqual(view.text, "first second")
        XCTAssertTrue(view.isRevealing)
        XCTAssertEqual(view.trailOpacity(atUTF16Offset: 0), 1)
        XCTAssertLessThan(view.trailOpacity(atUTF16Offset: 6), 1)
    }

    func testPartialWordAppendDoesNotRedimExistingCharacters() {
        var time = 0.0
        let view = GlimmerTrailTextView(now: { time })
        view.update(attributedText: NSAttributedString(string: "Hel"), isStreaming: true)
        view.finishImmediately()

        time = 1
        view.update(attributedText: NSAttributedString(string: "Hello"), isStreaming: true)

        XCTAssertEqual(view.text, "Hello")
        XCTAssertEqual(view.trailOpacity(atUTF16Offset: 0), 1)
        XCTAssertEqual(view.trailOpacity(atUTF16Offset: 3), 0, accuracy: 0.001)
    }

    func testAttributeOnlyUpdatePreservesProgressAndAdoptsNewStyle() {
        let view = GlimmerTrailTextView(now: { 0 })
        view.update(attributedText: NSAttributedString(string: "one two"), isStreaming: true)
        let replacement = NSAttributedString(string: "one two", attributes: [.foregroundColor: UIColor.systemRed])

        view.update(attributedText: replacement, isStreaming: true)

        XCTAssertEqual(view.text, "one ")
        XCTAssertEqual(view.attributedText.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor, .systemRed)
    }

    func testReplacementAndResetDiscardPreviousRanges() {
        let view = GlimmerTrailTextView(now: { 0 })
        view.update(attributedText: NSAttributedString(string: "a longer old message"), isStreaming: true)
        view.finishImmediately()
        view.update(attributedText: NSAttributedString(string: "new"), isStreaming: false)

        XCTAssertEqual(view.text, "new")
        XCTAssertTrue(view.isRevealing)
        view.reset()
        view.advance(at: 10)
        XCTAssertEqual(view.text, "")
        XCTAssertFalse(view.isStreaming)
        XCTAssertFalse(view.isRevealing)
        XCTAssertFalse(view.isFrameUpdatesEnabled)
    }

    func testUnicodeGraphemesRemainWholeAtEveryStep() {
        let view = GlimmerTrailTextView(now: { 0 })
        let words = ["👩🏽‍💻", "cafe\u{301}", "مرحبا", "你好"]
        view.update(attributedText: NSAttributedString(string: words.joined(separator: " ")), isStreaming: true)
        XCTAssertEqual(view.text, words[0] + " ")
        for index in 1..<words.count {
            view.advance(at: Double(index))
            let expected = words.prefix(index + 1).joined(separator: " ") + (index < words.count - 1 ? " " : "")
            XCTAssertEqual(view.text, expected)
        }
    }

    func testReduceMotionSettlesContentAndStopsFrameUpdates() {
        var reduced = false
        let view = GlimmerTrailTextView(now: { 0 }, reduceMotion: { reduced })
        let source = NSAttributedString(string: "one two three")
        view.update(attributedText: source, isStreaming: true)
        XCTAssertTrue(view.isRevealing)
        reduced = true

        view.advance(at: 0.1)

        XCTAssertTrue(view.attributedText.isEqual(to: source))
        XCTAssertFalse(view.isRevealing)
        XCTAssertFalse(view.isFrameUpdatesEnabled)
    }

    func testOffscreenViewDoesNotRequestContinuousUpdates() {
        let view = GlimmerTrailTextView(now: { 0 })
        view.update(attributedText: NSAttributedString(string: "one two three"), isStreaming: true)
        XCTAssertTrue(view.isRevealing)
        XCTAssertNil(view.window)
        XCTAssertFalse(view.isFrameUpdatesEnabled)
    }

    func testCanonicallyEquivalentReplacementDoesNotSplitUnicode() {
        let view = GlimmerTrailTextView(now: { 0 })
        view.update(attributedText: NSAttributedString(string: "é"), isStreaming: true)
        view.finishImmediately()
        let decomposed = "e\u{301}"

        view.update(attributedText: NSAttributedString(string: decomposed), isStreaming: true)

        XCTAssertEqual(Array(view.text.utf16), Array(decomposed.utf16))
        XCTAssertEqual(view.text.count, 1)
        view.advance(at: RevealSmoothTrail.duration + 0.01)
        XCTAssertFalse(view.isRevealing)
    }

    func testExtendedEmojiReplacementKeepsWholeGrapheme() {
        let view = GlimmerTrailTextView(now: { 0 })
        view.update(attributedText: NSAttributedString(string: "👩"), isStreaming: true)
        view.finishImmediately()
        view.update(attributedText: NSAttributedString(string: "👩‍💻"), isStreaming: true)

        XCTAssertEqual(Array(view.text.utf16), Array("👩‍💻".utf16))
        XCTAssertEqual(view.text.count, 1)
    }

    func testRepeatedBufferAndAppendPreserveSelection() {
        let view = GlimmerTrailTextView(now: { 0 })
        let source = NSAttributedString(string: "one")
        view.update(attributedText: source, isStreaming: true)
        view.finishImmediately()
        let selection = NSRange(location: 0, length: 2)
        view.selectedRange = selection

        view.update(attributedText: source, isStreaming: false)
        XCTAssertEqual(view.selectedRange, selection)
        view.update(attributedText: NSAttributedString(string: "one two"), isStreaming: true)
        XCTAssertEqual(view.selectedRange, selection)
    }

    func testNativeCadenceMatchesSmoothTrail() {
        let view = GlimmerTrailTextView(now: { 0 })
        view.update(attributedText: NSAttributedString(string: "one two three"), isStreaming: true)
        XCTAssertEqual(view.text, "one ")
        view.advance(at: 0.044)
        XCTAssertEqual(view.text, "one ")
        view.advance(at: 0.045)
        XCTAssertEqual(view.text, "one two ")
    }

    func testAttachedViewStopsFrameUpdatesAndReleasesOnRemoval() async {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let controller = UIViewController()
        window.rootViewController = controller
        window.isHidden = false
        var view: GlimmerTrailTextView? = GlimmerTrailTextView(now: { 0 })
        weak var releasedView = view
        view!.frame = CGRect(x: 0, y: 0, width: 300, height: 150)
        controller.view.addSubview(view!)
        view!.update(attributedText: NSAttributedString(string: "one two three"), isStreaming: true)
        XCTAssertTrue(view!.isFrameUpdatesEnabled)
        XCTAssertNotNil(view!.layer.mask)

        view!.removeFromSuperview()
        XCTAssertFalse(view!.isFrameUpdatesEnabled)
        XCTAssertNil(view!.layer.mask)
        view = nil

        // UIKit may retain a just-detached view until its pending layout/display
        // transaction and autorelease pool finish. Give the real main run loop a
        // bounded chance to drain; mask/link cleanup above must remain immediate.
        for _ in 0..<20 {
            if releasedView == nil { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertNil(releasedView, "The frame link must not retain a reused text view.")
        window.isHidden = true
    }

    func testUncoloredLinkDoesNotGainDrawingColorOverrides() {
        let view = GlimmerTrailTextView(now: { 0 })
        view.textColor = .systemOrange
        view.tintColor = .systemPurple
        let source = NSAttributedString(string: "link", attributes: [.link: URL(string: "https://example.com")!])
        view.update(attributedText: source, isStreaming: true)
        view.advance(at: RevealSmoothTrail.duration / 2)

        XCTAssertGreaterThan(view.trailOpacity(atUTF16Offset: 0), 0)
        XCTAssertLessThan(view.trailOpacity(atUTF16Offset: 0), 1)
        XCTAssertTrue(view.attributedText.isEqual(to: source))
        XCTAssertNil(renderingAttributes(in: view, at: 0)[.foregroundColor])
        view.finishImmediately()
        XCTAssertEqual(view.trailOpacity(atUTF16Offset: 0), 1)
        XCTAssertNil(view.layer.mask)
        XCTAssertNil(renderingAttributes(in: view, at: 0)[.foregroundColor])
        XCTAssertTrue(view.linkTextAttributes.isEmpty)
    }

    private func renderingAttributes(in view: GlimmerTrailTextView, at offset: Int) -> [NSAttributedString.Key: Any] {
        guard let manager = view.textLayoutManager,
              let content = manager.textContentManager,
              let location = content.location(content.documentRange.location, offsetBy: offset)
        else { return [:] }
        var result: [NSAttributedString.Key: Any] = [:]
        manager.enumerateRenderingAttributes(from: location, reverse: false) { _, attributes, range in
            if range.contains(location) { result = attributes }
            return false
        }
        return result
    }
}

import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerRevealMaskTests: XCTestCase {
    private let options = GlimmerRevealOptions()

    private func hosted(_ markdown: String, width: CGFloat = 390) -> (GlimmerTextView, UIWindow) {
        let textView = GlimmerTextView()
        textView.attributedText = GlimmerComposer(theme: .default).compose(GlimmerParser.parse(markdown))
        let height = textView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height
        return (textView, hostInWindow(textView, width: width, height: height))
    }

    private func engine(for textView: GlimmerTextView, streaming: Bool, advancedTo time: TimeInterval) -> GlimmerRevealEngine {
        var engine = GlimmerRevealEngine(options: options)
        engine.textChanged(NSString(string: textView.textStorage.string), isStreaming: streaming, now: 0)
        engine.advance(to: time)
        return engine
    }

    func testNothingRevealedCoversNothing() {
        let (textView, window) = hosted("Hidden until revealed.")
        let mask = GlimmerRevealMask()
        mask.update(in: textView, engine: GlimmerRevealEngine(options: options), now: 0)
        XCTAssertEqual(mask.settledRect.height, 0)
        XCTAssertEqual(mask.phraseLayerCount, 0)
        XCTAssertTrue(mask.settledLinePath?.isEmpty ?? true)
        _ = window
    }

    func testStartedPhraseFadesInOverItsGlyphs() throws {
        let (textView, window) = hosted("One two three four five six seven eight nine ten eleven")
        let engine = engine(for: textView, streaming: true, advancedTo: 0)
        let mask = GlimmerRevealMask()
        mask.update(in: textView, engine: engine, now: 0)
        let phrase = try XCTUnwrap(engine.phrases.first)
        let layer = try XCTUnwrap(mask.phraseLayer(startingAt: 0))
        let fade = try XCTUnwrap(layer.animation(forKey: "glimmer.fade") as? CABasicAnimation)
        XCTAssertEqual(fade.fromValue as? Double, 0)
        XCTAssertEqual(fade.toValue as? Double, 1)
        XCTAssertEqual(fade.duration, options.fadeDuration, accuracy: 1e-6)
        XCTAssertEqual(layer.opacity, 1, "the model value is opaque so the layer stays visible after the fade")
        let covered = try XCTUnwrap(layer.path?.boundingBox)
        for rect in textView.segmentRects(for: phrase.range) {
            XCTAssertTrue(covered.insetBy(dx: -0.5, dy: -0.5).contains(rect))
        }
        _ = window
    }

    func testSettledTextIsCoveredWithoutPhraseLayers() {
        let (textView, window) = hosted("Short settled line.")
        let engine = engine(for: textView, streaming: false, advancedTo: 5)
        let mask = GlimmerRevealMask()
        mask.update(in: textView, engine: engine, now: 5)
        XCTAssertEqual(mask.phraseLayerCount, 0)
        XCTAssertEqual(mask.settledRect.height, textView.bounds.height, accuracy: 0.5)
        _ = window
    }

    func testWidthChangeRebuildsPhraseGeometry() throws {
        let words = (1...40).map { "word\($0)" }.joined(separator: " ")
        let (textView, window) = hosted(words, width: 390)
        var engine = GlimmerRevealEngine(options: options)
        engine.textChanged(NSString(string: textView.textStorage.string), isStreaming: false, now: 0)
        engine.advance(to: 0)
        let mask = GlimmerRevealMask()
        mask.update(in: textView, engine: engine, now: 0)
        let before = try XCTUnwrap(mask.phraseLayer(startingAt: 0)?.path?.boundingBox)

        textView.frame.size.width = 180
        settle(textView)
        mask.update(in: textView, engine: engine, now: 0.3)
        let layer = try XCTUnwrap(mask.phraseLayer(startingAt: 0))
        XCTAssertNotEqual(layer.path?.boundingBox, before)
        let fade = try XCTUnwrap(layer.animation(forKey: "glimmer.fade") as? CABasicAnimation)
        XCTAssertEqual(fade.fromValue as? Double ?? 0, 0.5, accuracy: 0.01, "continues from the current opacity")
        XCTAssertEqual(fade.duration, 0.3, accuracy: 0.01)
        _ = window
    }
}

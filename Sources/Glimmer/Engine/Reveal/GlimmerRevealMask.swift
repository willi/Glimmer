import UIKit

/// Draws a reveal as a mask on the text view. Settled text sits under one opaque rect plus the settled part of the
/// current line; each fading phrase has its own layer whose opacity Core Animation runs from 0 to 1; text not yet
/// revealed is simply not covered. It changes only when a phrase starts or settles or the layout changes — never per
/// frame — and it does not depend on the background, so it works over glass and gradients.
@MainActor
final class GlimmerRevealMask {
    let layer = CALayer()

    private let settledLayer = CALayer()
    private let settledLineLayer = CAShapeLayer()
    private var phraseLayers: [Int: CAShapeLayer] = [:]
    private var geometryWidth: CGFloat = -1

    init() {
        settledLayer.backgroundColor = UIColor.black.cgColor
        settledLineLayer.fillColor = UIColor.black.cgColor
        layer.addSublayer(settledLayer)
        layer.addSublayer(settledLineLayer)
    }

    var settledRect: CGRect { settledLayer.frame }
    var settledLinePath: CGPath? { settledLineLayer.path }
    var phraseLayerCount: Int { phraseLayers.count }
    func phraseLayer(startingAt location: Int) -> CAShapeLayer? { phraseLayers[location] }

    /// Forces phrase geometry to be rebuilt on the next update (theme or text changes that move glyphs).
    func invalidateGeometry() {
        geometryWidth = -1
    }

    func update(in textView: GlimmerTextView, engine: GlimmerRevealEngine, now: TimeInterval) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let bounds = textView.bounds
        layer.frame = bounds
        let rebuild = bounds.width != geometryWidth
        geometryWidth = bounds.width

        // Settled: every line above the first unsettled character, plus that line's settled part.
        let firstUnsettled = engine.settledLength
        let lineTop = textView.lineRect(atCharacter: firstUnsettled)?.minY ?? bounds.height
        settledLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: lineTop)
        let lineStart = max(0, firstUnsettled - 512)
        let settledOnLine = textView.segmentRects(for: NSRange(location: lineStart, length: firstUnsettled - lineStart))
            .filter { $0.minY >= lineTop - 0.5 }
        settledLineLayer.path = Self.path(settledOnLine)

        // Fading: one layer per active phrase, keyed by its start offset.
        var live = Set<Int>()
        for phrase in engine.phrases {
            let key = phrase.range.location
            live.insert(key)
            let existing = phraseLayers[key]
            guard existing == nil || rebuild else { continue }
            let phraseLayer = existing ?? CAShapeLayer()
            phraseLayer.fillColor = UIColor.black.cgColor
            phraseLayer.path = Self.path(textView.segmentRects(for: phrase.range))
            phraseLayer.opacity = 1
            let elapsed = min(max(0, now - phrase.start), engine.options.fadeDuration)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = elapsed / engine.options.fadeDuration
            fade.toValue = 1.0
            fade.duration = max(0.001, engine.options.fadeDuration - elapsed)
            fade.timingFunction = CAMediaTimingFunction(name: .linear)
            fade.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
            phraseLayer.add(fade, forKey: "glimmer.fade")
            if existing == nil {
                layer.addSublayer(phraseLayer)
                phraseLayers[key] = phraseLayer
            }
        }
        for (key, stale) in phraseLayers where !live.contains(key) {
            stale.removeFromSuperlayer()
            phraseLayers[key] = nil
        }
    }

    private static func path(_ rects: [CGRect]) -> CGPath {
        let path = CGMutablePath()
        for rect in rects { path.addRect(rect.insetBy(dx: -1, dy: -2)) }
        return path
    }
}

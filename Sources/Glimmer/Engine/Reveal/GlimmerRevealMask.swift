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
    private var phraseLayers: [PhraseKey: CAShapeLayer] = [:]
    private var geometryWidth: CGFloat = -1
    /// Text from this offset on moved since the last update; geometry before it still stands.
    private var movedFrom = Int.max
    /// What the settled geometry was last computed for; segment queries cost time in proportion to the text length,
    /// so they run only when a phrase settles or the layout changes, not on every update or layout pass.
    private var settledKey: SettledKey?

    /// A text phrase by its start offset; a unit phrase by its embed's offset and unit index (all of an embed's
    /// units share its offset).
    private struct PhraseKey: Hashable {
        let location: Int
        let unit: Int?
    }

    private struct SettledKey: Equatable {
        let settledLength: Int
        /// Units of the embed at `settledLength` that have finished fading.
        let settledUnits: Int
        let width: CGFloat
        /// Everything is settled: the settled rect then reaches the bottom of the view, so its height matters.
        let allSettledHeight: CGFloat?
    }

    init() {
        settledLayer.backgroundColor = UIColor.black.cgColor
        settledLineLayer.fillColor = UIColor.black.cgColor
        layer.addSublayer(settledLayer)
        layer.addSublayer(settledLineLayer)
    }

    var settledRect: CGRect { settledLayer.frame }
    var settledLinePath: CGPath? { settledLineLayer.path }
    var phraseLayerCount: Int { phraseLayers.count }
    func phraseLayer(startingAt location: Int) -> CAShapeLayer? { phraseLayers[PhraseKey(location: location, unit: nil)] }
    func phraseLayer(forUnit unit: Int, at location: Int) -> CAShapeLayer? { phraseLayers[PhraseKey(location: location, unit: unit)] }

    /// Rebuilds the geometry of text from `location` on at the next update (an embed at the reveal's frontier grew),
    /// leaving earlier phrases' fades running untouched.
    func invalidateGeometry(from location: Int) {
        movedFrom = min(movedFrom, location)
    }

    /// Forces phrase geometry to be rebuilt on the next update (theme or text changes that move glyphs).
    func invalidateGeometry() {
        geometryWidth = -1
        settledKey = nil
    }

    func update(in textView: GlimmerTextView, engine: GlimmerRevealEngine, now: TimeInterval) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let bounds = textView.bounds
        layer.frame = bounds
        let rebuild = bounds.width != geometryWidth
        geometryWidth = bounds.width
        let moved = movedFrom
        movedFrom = .max

        // Settled: every line above the first unsettled character, plus that line's settled part.
        let firstUnsettled = engine.settledLength
        let settledUnits = engine.unitsSettled[firstUnsettled] ?? 0
        let key = SettledKey(
            settledLength: firstUnsettled, settledUnits: settledUnits, width: bounds.width,
            allSettledHeight: firstUnsettled < textView.textStorage.length ? nil : bounds.height
        )
        if key != settledKey || rebuild || moved <= firstUnsettled {
            settledKey = key
            let lineTop = textView.lineRect(atCharacter: firstUnsettled)?.minY ?? bounds.height
            settledLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: lineTop)
            let lineStart = max(0, firstUnsettled - 512)
            let settledOnLine = textView.segmentRects(for: NSRange(location: lineStart, length: firstUnsettled - lineStart))
                .filter { $0.minY >= lineTop - 0.5 }
            // The settled part of a line always starts the line, so it also uncovers the gutter (quote bars).
            var settledRects = settledOnLine.map(Self.extendedToLeadingEdge)
            // An embed revealing in units: the units that finished fading stay uncovered.
            if settledUnits > 0, let rects = textView.embedUnitRects(atCharacter: firstUnsettled) {
                settledRects += rects.prefix(settledUnits)
            }
            settledLineLayer.path = Self.path(settledRects)
        }

        // Fading: one layer per active phrase, keyed by its start offset.
        var live = Set<PhraseKey>()
        for phrase in engine.phrases {
            let key = PhraseKey(location: phrase.range.location, unit: phrase.unit)
            live.insert(key)
            let existing = phraseLayers[key]
            guard existing == nil || rebuild || key.location >= moved else { continue }
            let phraseLayer = existing ?? CAShapeLayer()
            phraseLayer.fillColor = UIColor.black.cgColor
            let segments: [CGRect]
            if let unit = phrase.unit, let rects = textView.embedUnitRects(atCharacter: phrase.range.location), unit < rects.count {
                segments = [rects[unit]]
            } else {
                // Segments that begin a visual line also uncover the gutter to their left (quote bars fade in with text).
                let startsLine = textView.isLineStart(atCharacter: phrase.range.location)
                segments = textView.segmentRects(for: phrase.range).enumerated().map { index, rect in
                    index > 0 || startsLine ? Self.extendedToLeadingEdge(rect) : rect
                }
            }
            phraseLayer.path = Self.path(segments)
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

    private static func extendedToLeadingEdge(_ rect: CGRect) -> CGRect {
        CGRect(x: 0, y: rect.minY, width: rect.maxX, height: rect.height)
    }

    private static func path(_ rects: [CGRect]) -> CGPath {
        let path = CGMutablePath()
        for rect in rects { path.addRect(rect.insetBy(dx: -1, dy: -2)) }
        return path
    }
}

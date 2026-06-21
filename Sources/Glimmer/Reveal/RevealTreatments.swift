import SwiftUI

// MARK: - Animatable effects (ported from TextStreaming)

/// Gradient sweep across a word as progress goes 0→1. Owns the foreground
/// style — do not bake a fixed foreground into shimmer atoms (spec 4.5).
struct ShimmerEffect: ViewModifier, Animatable {
    var progress: Double
    var color: Color

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let sweep = 1 - progress
        let halfWidth = 0.18
        let leftEdge = max(0, sweep - halfWidth)
        let rightEdge = min(1, sweep + halfWidth)
        let crest = min(1, max(0, sweep))
        let dim = color.opacity(0.15)
        let stops: [Gradient.Stop] = [
            .init(color: dim, location: 0),
            .init(color: dim, location: leftEdge),
            .init(color: color, location: crest),
            .init(color: color, location: rightEdge),
            .init(color: color, location: 1),
        ]
        return content
            .foregroundStyle(LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing))
            .opacity(progress > 0.001 ? 1 : 0)
    }
}

/// Opacity-in with a shadow pulse that rises then falls (wave-glow style).
struct WaveGlowEffect: ViewModifier, Animatable {
    var progress: Double
    var color: Color

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let opacity = min(1, progress / 0.35)
        let glow: Double = progress < 0.35
            ? progress / 0.35
            : max(0, (1 - progress) / 0.65)
        return content
            .opacity(opacity)
            .shadow(color: color.opacity(0.9 * glow), radius: 14 * glow)
    }
}

// MARK: - Entrance curves (tuned values from TextStreaming)

extension RevealTreatment {
    var entranceAnimation: Animation {
        switch self {
        case .plain, .caret, .scramble, .trailFade: .linear(duration: 0)
        case .fade: .easeOut(duration: 0.35)
        case .blur: .timingCurve(0.2, 0.7, 0.2, 1, duration: 0.5)
        case .slide: .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.45)
        case .dropIn: .timingCurve(0.3, 1.4, 0.4, 1, duration: 0.32)
        case .tracking: .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.5)
        case .shimmer: .easeOut(duration: 0.6)
        case .glow: .easeOut(duration: 0.6)
        }
    }

    func shouldRenderSettledBlock(isFullyRevealed: Bool) -> Bool {
        isFullyRevealed
    }
}

// MARK: - Single reveal unit

/// Renders one text atom and self-animates on appear: the atom is inserted
/// into the tree exactly when the driver unlocks it, so `onAppear` provides
/// the stagger — no per-index delay needed (spec 4.5).
struct RevealUnitView: View {
    let attributed: AttributedString
    let treatment: RevealTreatment
    /// False for resumed atoms (`revealIndex <= animateFrom`) — render settled.
    let animate: Bool

    @State private var p: Double = 0

    var body: some View {
        content
            .onAppear {
                if animate {
                    withAnimation(treatment.entranceAnimation) { p = 1 }
                } else {
                    p = 1
                }
            }
    }

    @ViewBuilder private var content: some View {
        let text = Text(attributed)
        switch treatment {
        case .plain, .caret, .scramble, .trailFade:
            // trailFade never routes here (it has a dedicated cursor-driven
            // path in RevealTrailTextView); plain text is the safe fallback.
            text
        case .fade:
            text.opacity(p)
        case .blur:
            text.opacity(p).blur(radius: (1 - p) * 6)
        case .slide:
            text.offset(y: (1 - p) * 14).opacity(p).clipped()
        case .dropIn:
            text.offset(y: (1 - p) * -8).opacity(p)
        case .tracking:
            text
                .scaleEffect(x: 1 + (1 - p) * 0.35, y: 1, anchor: .leading)
                .opacity(p)
                .offset(x: (1 - p) * -2)
        case .shimmer:
            text.modifier(ShimmerEffect(progress: p, color: .primary))
        case .glow:
            text.modifier(WaveGlowEffect(progress: p, color: .primary))
        }
    }
}

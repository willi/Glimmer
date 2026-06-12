import Foundation

/// Pure pacing math for the reveal driver (spec 4.3). Kept side-effect-free
/// so cadence, catch-up, and snapping are unit-testable without a clock.
enum RevealPacing {

    /// Style cadence with jitter in [0, 1] mapped across the style's range.
    static func nominalIntervalSeconds(style: RevealStyle, jitter: Double) -> Double {
        let range = style.nominalUnitIntervalMs
        return (range.lowerBound + (range.upperBound - range.lowerBound) * jitter) / 1000
    }

    /// The interval to sleep before unlocking the next unit(s). Adaptive
    /// catch-up shortens it (never below 0.25x) when `behind` exceeds the
    /// lag target, so units still animate individually while catching up.
    static func intervalSeconds(style: RevealStyle, behind: Int, catchUp: CatchUpPolicy, jitter: Double) -> Double {
        let base = nominalIntervalSeconds(style: style, jitter: jitter)
        guard case .adaptive(let maxLagSeconds) = catchUp else { return base }
        let target = targetLagUnits(style: style, maxLagSeconds: maxLagSeconds)
        guard target > 0 else { return base }
        let factor = min(1.0, max(0.25, target / Double(max(1, behind))))
        return base * factor
    }

    /// cappedSnap only: true when the backlog exceeds the lag cap and the
    /// driver should reveal everything at once.
    static func shouldSnap(style: RevealStyle, behind: Int, catchUp: CatchUpPolicy) -> Bool {
        guard case .cappedSnap(let maxLagSeconds) = catchUp else { return false }
        let target = targetLagUnits(style: style, maxLagSeconds: maxLagSeconds)
        guard target > 0 else { return false }
        return Double(behind) > target
    }

    /// Units to unlock this tick (LLM-token style unlocks 1–4 chars).
    static func step(style: RevealStyle, jitter: Double) -> Int {
        let range = style.unitsPerStep
        guard range.lowerBound < range.upperBound else { return range.lowerBound }
        let span = Double(range.upperBound - range.lowerBound + 1)
        return min(range.upperBound, range.lowerBound + Int(span * jitter))
    }

    /// `maxLagSeconds` expressed in reveal units at the style's mid cadence.
    private static func targetLagUnits(style: RevealStyle, maxLagSeconds: Double) -> Double {
        let range = style.nominalUnitIntervalMs
        let midMs = (range.lowerBound + range.upperBound) / 2
        guard midMs > 0 else { return 0 }
        return maxLagSeconds * 1000 / midMs
    }
}

/// Opacity ramp for the trail-fade style: instead of a binary reveal
/// boundary, the newest words sit near-invisible and brighten as the cursor
/// moves past them — a soft gradient sweeping in reading order.
enum RevealTrail {
    /// Number of countable units the fade ramp spans.
    static let length: Double = 12
    /// Opacity of the newest revealed word.
    static let floor: Double = 0.08

    /// Opacity for an atom at `revealIndex` given the current cursor.
    /// 1 for settled words, `floor` at the cursor, linear ramp between;
    /// everything snaps to 1 once the reveal completes.
    static func opacity(revealIndex: Int, revealedCount: Int, isComplete: Bool) -> Double {
        guard !isComplete else { return 1 }
        let distance = Double(revealedCount - revealIndex)
        guard distance >= 0 else { return 0 }
        return min(1, floor + (1 - floor) * (distance / length))
    }
}

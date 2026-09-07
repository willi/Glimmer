import Foundation

/// Shared temporal envelope for the SwiftUI and native UIKit renderers.
/// Drawing opacity changes; glyph positions, fonts, and source colors do not.
public enum RevealSmoothTrail {
    /// Time in seconds for a newly revealed unit to reach full opacity.
    public static let duration: Double = 0.5

    /// Opacity multiplier for elapsed seconds since a unit's reveal timestamp.
    /// Ages at or below zero produce zero; ages at or beyond `duration` produce one.
    /// With a `RevealDriver` snapshot, calculate age as
    /// `ProcessInfo.processInfo.systemUptime - start`.
    public static func opacity(age: Double) -> Double {
        let progress = min(1, max(0, age / duration))
        return 1 - pow(1 - progress, 3)
    }
}

/// A read-only snapshot of a driver's `.smoothTrail` timing, retaining only its active tail.
///
/// Restored units are already settled. While `RevealDriver.run()` is active, expired
/// timestamps are removed even when no new content arrives. A copied snapshot does
/// not advance on its own; observe `RevealDriver.smoothTrail` for subsequent changes.
public struct RevealSmoothTrailState: Equatable, Sendable {
    /// Number of leading countable units already fully opaque, including restored units.
    /// Countable reveal indices at or below this value are settled. It may decrease
    /// when the driver's content is truncated.
    public private(set) var settledCount = 0

    /// Reveal start times for units still in the active tail, keyed by their global,
    /// one-based `RevealAtom.revealIndex` (not atom IDs or block-local offsets).
    /// Non-countable atoms share the preceding countable unit's index, or zero if none.
    ///
    /// Times are seconds in the `ProcessInfo.processInfo.systemUptime` clock domain,
    /// not wall-clock dates. A revealed index with no entry renders at full opacity;
    /// indices beyond `RevealDriver.revealedCount` are still hidden.
    public private(set) var starts: [Int: Double] = [:]

    /// Whether the currently revealed tail is fully settled. This can be true during
    /// a producer pause or before any units reveal; it does not mean reveal is complete.
    /// A block can render settled once all its countable atoms are revealed and none
    /// of its atoms' reveal indices appear in `starts`, even if another block is fading.
    public var isSettled: Bool { starts.isEmpty }

    /// Earliest active unit's settlement time in system-uptime seconds, or `nil` when
    /// the tail is settled. This is not necessarily the time the entire tail settles.
    public var nextSettlement: Double? { starts.values.min().map { $0 + RevealSmoothTrail.duration } }

    mutating func reveal(through count: Int, from previous: Int, at time: Double) {
        settle(at: time)
        guard count > previous else { return }
        for index in (previous + 1)...count { starts[index] = time }
    }

    mutating func settle(at time: Double) {
        for (index, start) in starts where time >= start + RevealSmoothTrail.duration {
            settledCount = max(settledCount, index)
            starts[index] = nil
        }
    }

    mutating func settleImmediately(through count: Int) {
        settledCount = count
        starts.removeAll(keepingCapacity: true)
    }

    mutating func truncate(to count: Int) {
        settledCount = min(settledCount, count)
        starts = starts.filter { $0.key <= count }
    }
}

import Foundation

/// Shared temporal envelope for the SwiftUI and native UIKit renderers.
/// Drawing opacity changes; glyph positions, fonts, and source colors do not.
enum RevealSmoothTrail {
    static let duration: Double = 0.5

    static func opacity(age: Double) -> Double {
        let progress = min(1, max(0, age / duration))
        return 1 - pow(1 - progress, 3)
    }
}

/// Only retains the active tail. Restored units are already settled, and old
/// timestamps disappear as the clock advances, even when no words arrive.
struct RevealSmoothTrailState: Equatable {
    private(set) var settledCount = 0
    private(set) var starts: [Int: Double] = [:]

    var isSettled: Bool { starts.isEmpty }
    var nextSettlement: Double? { starts.values.min().map { $0 + RevealSmoothTrail.duration } }

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

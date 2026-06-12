import SwiftUI
import Observation

/// Paces `revealedCount` from a (possibly growing) buffer at the style's
/// cadence, with catch-up, completion, and resume-by-id (spec 4.3).
///
/// The driver is decoupled from text arrival (spec R3): `update` feeds it new
/// totals as the buffer grows; `run()` unlocks units on its own clock.
@MainActor
@Observable
public final class RevealDriver {
    /// Number of countable atoms currently revealed. Monotonic during a run.
    public private(set) var revealedCount: Int
    /// True once the buffer is drained AND the producer has stopped streaming.
    public private(set) var isComplete = false
    /// Atoms with `revealIndex <= animateFrom` were restored from a previous
    /// mount and render settled, with no entrance animation (spec R6).
    public let animateFrom: Int

    private var totalCountable = 0
    private var isStreaming: Bool
    private var hasReceivedUpdate = false
    private let style: RevealStyle
    private let catchUp: CatchUpPolicy
    private let revealID: String?
    private let demoDurationCap: Double?
    private let store: RevealProgressStore
    private let sleep: @MainActor (Double) async throws -> Void

    public convenience init(configuration: RevealConfiguration) {
        self.init(configuration: configuration, store: .shared) { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    }

    /// Internal initializer with injectable store and clock for tests.
    init(
        configuration: RevealConfiguration,
        store: RevealProgressStore,
        sleep: @escaping @MainActor (Double) async throws -> Void
    ) {
        self.style = configuration.style
        self.catchUp = configuration.catchUp
        self.isStreaming = configuration.isStreaming
        self.revealID = configuration.revealID
        self.demoDurationCap = configuration.demoDurationCap
        self.store = store
        self.sleep = sleep
        let resumed = store.resume(configuration.revealID)
        self.revealedCount = resumed
        self.animateFrom = resumed
    }

    /// Feeds the driver the current buffer state. Call on every parse.
    public func update(totalCountable: Int, isStreaming: Bool) {
        hasReceivedUpdate = true
        self.totalCountable = totalCountable
        self.isStreaming = isStreaming
        if revealedCount > totalCountable {
            // Buffer was replaced with shorter content (non-append change).
            revealedCount = totalCountable
        }
    }

    /// The pacing loop (spec 4.3 pseudocode). Runs until cancelled or until
    /// the buffer is drained and streaming has ended.
    public func run() async {
        while !Task.isCancelled {
            if revealedCount < totalCountable {
                let behind = totalCountable - revealedCount
                if RevealPacing.shouldSnap(style: style, behind: behind, catchUp: catchUp) {
                    revealedCount = totalCountable
                } else {
                    var interval = RevealPacing.intervalSeconds(
                        style: style, behind: behind, catchUp: catchUp, jitter: .random(in: 0..<1)
                    )
                    if let cap = demoDurationCap, totalCountable > 0 {
                        interval = min(interval, cap / Double(totalCountable))
                    }
                    do { try await sleep(interval) } catch { return }
                    guard !Task.isCancelled else { return }
                    let step = RevealPacing.step(style: style, jitter: .random(in: 0..<1))
                    revealedCount = min(totalCountable, revealedCount + step)
                }
                store.record(revealedCount, for: revealID)
            } else if hasReceivedUpdate && !isStreaming {
                // Never complete before the first buffer update — .task may start before the initial rebuild.
                isComplete = true
                return
            } else {
                // Buffer drained but producer still streaming: idle wait.
                do { try await sleep(0.016) } catch { return }
            }
        }
    }
}

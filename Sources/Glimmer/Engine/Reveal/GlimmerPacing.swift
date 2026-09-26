import Foundation

/// The reveal speed. It follows the backlog of arrived-but-unrevealed text smoothly, never drops below `baseRate`, and
/// empties the backlog by a deadline `drainDuration` after streaming ends (pacing against the time left, never slower). When the speed would need phrases closer together
/// than `minPhraseSpacing`, phrases get longer instead.
struct GlimmerPacing {
    let options: GlimmerRevealOptions
    /// Characters per second.
    private(set) var rate: Double
    private var lastUpdate: TimeInterval?
    /// When the backlog must be empty; set the first time the rate is updated after streaming ends.
    private var drainDeadline: TimeInterval?

    init(options: GlimmerRevealOptions) {
        self.options = options
        rate = options.baseRate
    }

    mutating func updateRate(backlog: Int, isStreaming: Bool, now: TimeInterval) {
        let target: Double
        if isStreaming {
            drainDeadline = nil
            target = max(options.baseRate, Double(backlog) / max(options.targetLag, 0.001))
        } else {
            let deadline = drainDeadline ?? now + options.drainDuration
            drainDeadline = deadline
            target = max(options.baseRate, Double(backlog) / max(deadline - now, options.minPhraseSpacing))
        }
        if let lastUpdate {
            let blend = min(1, max(0, now - lastUpdate) / max(options.rateSmoothing, 0.001))
            rate += (target - rate) * blend
            // Draining never runs slower than the deadline needs; smoothing only softens speed-ups while streaming.
            if !isStreaming { rate = max(rate, target) }
        } else {
            rate = target
        }
        lastUpdate = now
    }

    /// Characters a phrase should carry so phrase starts stay at least `minPhraseSpacing` apart at this rate.
    var minimumPhraseLength: Int {
        Int((rate * options.minPhraseSpacing).rounded(.up))
    }

    /// Seconds from one phrase starting to the next.
    func interval(forPhraseLength length: Int) -> TimeInterval {
        max(options.minPhraseSpacing, Double(length) / rate)
    }
}

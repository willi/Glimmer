import Foundation

/// The reveal speed. It follows the backlog of arrived-but-unrevealed text smoothly, never drops below `baseRate`, and
/// empties the backlog within `drainDuration` once streaming ends. When the speed would need phrases closer together
/// than `minPhraseSpacing`, phrases get longer instead.
struct GlimmerPacing {
    let options: GlimmerRevealOptions
    /// Characters per second.
    private(set) var rate: Double
    private var lastUpdate: TimeInterval?

    init(options: GlimmerRevealOptions) {
        self.options = options
        rate = options.baseRate
    }

    mutating func updateRate(backlog: Int, isStreaming: Bool, now: TimeInterval) {
        let window = max(isStreaming ? options.targetLag : options.drainDuration, 0.001)
        let target = max(options.baseRate, Double(backlog) / window)
        if let lastUpdate {
            let blend = min(1, max(0, now - lastUpdate) / max(options.rateSmoothing, 0.001))
            rate += (target - rate) * blend
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

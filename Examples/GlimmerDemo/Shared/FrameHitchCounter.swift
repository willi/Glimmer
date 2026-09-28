/// Counts hitches in a run of frame timestamps. A frame that arrives more than one and a half frame durations after
/// the one before it missed at least one refresh. The duration comes from the display link, so a 60 Hz screen (Low
/// Power Mode) is judged at 60 Hz, not against a 120 Hz budget.
struct FrameHitchCounter {
    private(set) var frames = 0
    private(set) var hitches = 0
    private(set) var worstInterval: Double = 0
    /// Seconds the late frames were late by, past the frame they were due in.
    private(set) var hitchTime: Double = 0
    private var first: Double?
    private var last: Double?

    /// Hitch time per second of the run, in milliseconds per second: Apple's hitch-time ratio. Under 5 is good.
    var hitchTimeRatio: Double {
        guard let first, let last, last > first else { return 0 }
        return hitchTime * 1000 / (last - first)
    }

    mutating func record(timestamp: Double, frameDuration: Double) {
        defer { last = timestamp }
        frames += 1
        if first == nil { first = timestamp }
        guard let last else { return }
        let interval = timestamp - last
        worstInterval = max(worstInterval, interval)
        if interval > frameDuration * 1.5 {
            hitches += 1
            hitchTime += interval - frameDuration
        }
    }
}

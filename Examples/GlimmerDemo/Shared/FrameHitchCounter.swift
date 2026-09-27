/// Counts hitches in a run of frame timestamps. A frame that arrives more than one and a half frame durations after
/// the one before it missed at least one refresh. The duration comes from the display link, so a 60 Hz screen (Low
/// Power Mode) is judged at 60 Hz, not against a 120 Hz budget.
struct FrameHitchCounter {
    private(set) var frames = 0
    private(set) var hitches = 0
    private(set) var worstInterval: Double = 0
    private var last: Double?

    mutating func record(timestamp: Double, frameDuration: Double) {
        defer { last = timestamp }
        frames += 1
        guard let last else { return }
        let interval = timestamp - last
        worstInterval = max(worstInterval, interval)
        if interval > frameDuration * 1.5 { hitches += 1 }
    }
}

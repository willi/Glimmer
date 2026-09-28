import QuartzCore
import UIKit

/// Asks for 120 Hz and counts the frames that arrive late while it runs.
@MainActor
final class FrameMonitor: NSObject {
    private var link: CADisplayLink?
    private(set) var counter = FrameHitchCounter()
    /// The frame duration in effect for the interval that ends at the next tick.
    private var dueDuration: Double?

    func start() {
        counter = FrameHitchCounter()
        dueDuration = nil
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        // Pinned: a panel dropping to 80 Hz between ticks would read as a hitch.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        // A frame is judged by the duration it was due in, the one the previous tick announced.
        let duration = link.targetTimestamp - link.timestamp
        counter.record(timestamp: link.timestamp, frameDuration: dueDuration ?? duration)
        dueDuration = duration
    }
}

import QuartzCore
import UIKit

/// Asks for 120 Hz and counts the frames that arrive late while it runs.
@MainActor
final class FrameMonitor: NSObject {
    private var link: CADisplayLink?
    private(set) var counter = FrameHitchCounter()

    func start() {
        counter = FrameHitchCounter()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        counter.record(timestamp: link.timestamp, frameDuration: link.targetTimestamp - link.timestamp)
    }
}

import UIKit

/// Calls `onScroll` whenever a scroll view above a view scrolls, so the view can move its rendered band. It observes
/// `contentOffset` with KVO; `stop()` tears the observations down when the view leaves its window.
@MainActor
final class GlimmerViewportTracker {
    var onScroll: (() -> Void)?
    private var observations: [NSKeyValueObservation] = []

    func track(ancestorsOf view: UIView) {
        observations.removeAll()
        var ancestor = view.superview
        while let current = ancestor {
            if let scrollView = current as? UIScrollView {
                observations.append(scrollView.observe(\.contentOffset, options: []) { [weak self] _, _ in
                    // Scroll views change their offset on the main thread.
                    MainActor.assumeIsolated { self?.onScroll?() }
                })
            }
            ancestor = current.superview
        }
    }

    func stop() {
        observations.removeAll()
    }
}

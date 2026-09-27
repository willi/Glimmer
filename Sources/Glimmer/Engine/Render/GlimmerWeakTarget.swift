import UIKit

/// A display link's target that doesn't keep the text view alive: a link retains its target until invalidated.
@MainActor
final class GlimmerWeakTarget: NSObject {
    private weak var textView: GlimmerTextView?

    init(_ textView: GlimmerTextView) {
        self.textView = textView
    }

    @objc func tick(_ link: CADisplayLink) {
        guard let textView else {
            link.invalidate()
            return
        }
        textView.preloadStep()
    }
}

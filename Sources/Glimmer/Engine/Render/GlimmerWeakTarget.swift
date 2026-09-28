import UIKit

/// A display link's target that doesn't keep the text view alive: a link retains its target until invalidated.
@MainActor
final class GlimmerWeakTarget: NSObject {
    private weak var textView: GlimmerTextView?
    private let step: (GlimmerTextView) -> Void

    init(_ textView: GlimmerTextView, step: @escaping (GlimmerTextView) -> Void) {
        self.textView = textView
        self.step = step
    }

    @objc func tick(_ link: CADisplayLink) {
        guard let textView else {
            link.invalidate()
            return
        }
        step(textView)
    }
}

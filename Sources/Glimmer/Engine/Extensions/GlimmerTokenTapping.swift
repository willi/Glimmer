import UIKit

extension UIView {
    /// The `GlimmerView` this view is inside, or nil.
    private var glimmerTokenHost: GlimmerView? {
        var ancestor = superview
        while let view = ancestor {
            if let glimmer = view as? GlimmerView { return glimmer }
            ancestor = view.superview
        }
        return nil
    }

    /// The host's `onTokenTap`, from the `GlimmerView` this view is inside, or nil.
    var glimmerTokenTapHandler: ((GlimmerInlineToken) -> Void)? { glimmerTokenHost?.onTokenTap }

    /// Whether the chip with this attachment is revealed in the `GlimmerView` this view is inside. A chip the host's
    /// text doesn't hold (inside a table cell) counts as revealed.
    func glimmerHostHasRevealed(_ attachment: NSTextAttachment) -> Bool {
        glimmerTokenHost?.hasRevealed(attachment) ?? true
    }
}

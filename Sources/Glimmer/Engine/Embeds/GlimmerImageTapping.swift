import UIKit

extension UIView {
    /// The host's `onImageTap`, from the `GlimmerView` this view is inside, or nil.
    var glimmerImageTapHandler: ((URL, String) -> Void)? {
        var ancestor = superview
        while let view = ancestor {
            if let glimmer = view as? GlimmerView { return glimmer.onImageTap }
            ancestor = view.superview
        }
        return nil
    }
}

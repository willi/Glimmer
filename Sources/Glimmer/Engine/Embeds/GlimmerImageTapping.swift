import UIKit

extension UIView {
    /// The `GlimmerView` this view is inside, or nil.
    private var glimmerHost: GlimmerView? {
        var ancestor = superview
        while let view = ancestor {
            if let glimmer = view as? GlimmerView { return glimmer }
            ancestor = view.superview
        }
        return nil
    }

    /// The host's `onImageTap`, from the `GlimmerView` this view is inside, or nil.
    var glimmerImageTapHandler: ((URL, String) -> Void)? { glimmerHost?.onImageTap }

    /// The image policy of the `GlimmerView` this view is inside, or nil.
    var glimmerHostImagePolicy: (any GlimmerImagePolicy)? { glimmerHost?.configuration.imagePolicy }
}

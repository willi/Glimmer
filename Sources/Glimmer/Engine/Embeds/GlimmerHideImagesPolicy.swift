import Foundation

/// A policy that hides every image. `GlimmerView.attributedString` composes with it: plain attributed text can't
/// show an image, and a hidden one also closes the space around it.
struct GlimmerHideImagesPolicy: GlimmerImagePolicy {
    func decision(for image: GlimmerImageCandidate) -> GlimmerImageDecision { .hide }
}

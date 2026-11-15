import Foundation

/// A policy bound to an image it allowed. The one place that loads images asks it again just before the request, so
/// an image that reaches a view by a path the composer did not decide is still not fetched.
struct GlimmerImageGate: Sendable {
    let policy: any GlimmerImagePolicy
    let candidate: GlimmerImageCandidate

    /// Whether the policy loads this image from `url`: its own URL, or one a server redirects it to.
    func permits(_ url: URL) -> Bool {
        var image = candidate
        image.url = url
        return policy.decision(for: image) == .load
    }
}

/// The image policy refused a load.
struct GlimmerImageRefused: Error {}

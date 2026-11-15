import Foundation

/// A policy bound to an image it allowed. The one place that loads images asks it again just before the request, and
/// passes it on for redirects. An image with no gate, shown inside a view that has a policy, is not loaded at all: it
/// reached the view by a path the composer did not decide.
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

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

/// Two gates are equal when they put the same image to equal policies. Only then is one's answer about a redirect
/// also the other's, which is what lets their requests share a download.
extension GlimmerImageGate: Hashable {
    static func == (lhs: GlimmerImageGate, rhs: GlimmerImageGate) -> Bool {
        lhs.candidate == rhs.candidate && lhs.policy.isEqual(to: rhs.policy)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(candidate)
        hasher.combine(GlimmerImagePolicyKey(policy: policy))
    }
}

/// The image policy refused a load.
struct GlimmerImageRefused: Error {}

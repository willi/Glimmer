import Foundation

extension GlimmerImagePolicy {
    /// Whether `other` is a policy of the same type that compares equal.
    func isEqual(to other: any GlimmerImagePolicy) -> Bool {
        (other as? Self) == self
    }
}

/// A policy as a key. Views whose policies are equal share composed answers and downloads; no others do, so a view
/// with a policy never receives what was composed or fetched without it.
struct GlimmerImagePolicyKey: Hashable, Sendable {
    let policy: any GlimmerImagePolicy

    static func == (lhs: GlimmerImagePolicyKey, rhs: GlimmerImagePolicyKey) -> Bool {
        lhs.policy.isEqual(to: rhs.policy)
    }

    func hash(into hasher: inout Hasher) {
        policy.hash(into: &hasher)
    }
}

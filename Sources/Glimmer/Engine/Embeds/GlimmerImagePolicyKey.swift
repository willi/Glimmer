import Foundation

extension GlimmerImagePolicy {
    /// Whether `other` is a policy of exactly this type that compares equal. A subclass is another policy: it can
    /// decide differently, and a cast alone would call the two equal from one side and not from the other.
    func isEqual(to other: any GlimmerImagePolicy) -> Bool {
        guard type(of: other) == type(of: self), let other = other as? Self else { return false }
        return other == self
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
        // Two policy types with the same stored values are different keys, so they should not share a hash either.
        hasher.combine(ObjectIdentifier(type(of: policy)))
        policy.hash(into: &hasher)
    }
}

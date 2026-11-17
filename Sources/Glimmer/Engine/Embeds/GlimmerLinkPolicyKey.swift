import Foundation

extension GlimmerLinkPolicy {
    /// Whether `other` is a policy of exactly this type that compares equal. A subclass is another policy: it can
    /// decide differently, and a cast alone would call the two equal from one side and not from the other.
    func isEqual(to other: any GlimmerLinkPolicy) -> Bool {
        guard type(of: other) == type(of: self), let other = other as? Self else { return false }
        return other == self
    }
}

/// A link policy as a key. Views whose policies are equal share composed answers; no others do, so a view with a
/// policy never shows a link that was composed without it.
struct GlimmerLinkPolicyKey: Hashable, Sendable {
    let policy: any GlimmerLinkPolicy

    static func == (lhs: GlimmerLinkPolicyKey, rhs: GlimmerLinkPolicyKey) -> Bool {
        lhs.policy.isEqual(to: rhs.policy)
    }

    func hash(into hasher: inout Hasher) {
        // Two policy types with the same stored values are different keys, so they should not share a hash either.
        hasher.combine(ObjectIdentifier(type(of: policy)))
        policy.hash(into: &hasher)
    }
}

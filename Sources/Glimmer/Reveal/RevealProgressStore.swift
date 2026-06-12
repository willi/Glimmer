import Foundation

/// Monotonic per-`revealID` reveal progress, so a re-mounted view (e.g. an
/// optimistic chat message replaced by the final one) resumes instead of
/// replaying the whole reveal (spec R6).
@MainActor
public final class RevealProgressStore {
    public static let shared = RevealProgressStore()

    private var progress: [String: Int] = [:]

    /// Internal so tests can use isolated instances; hosts use `.shared`.
    init() {}

    /// The last recorded count for `revealID`, or 0 if none / id is nil.
    public func resume(_ revealID: String?) -> Int {
        guard let revealID else { return 0 }
        return progress[revealID] ?? 0
    }

    /// Records progress; only ever increases the stored value.
    public func record(_ count: Int, for revealID: String?) {
        guard let revealID else { return }
        progress[revealID] = max(progress[revealID] ?? 0, count)
    }

    /// Forgets progress for `revealID` (e.g. when a chat turn is deleted).
    public func clear(_ revealID: String?) {
        guard let revealID else { return }
        progress.removeValue(forKey: revealID)
    }
}

import Foundation

/// How much of each message has been revealed, so a re-created or re-configured view resumes instead of replaying.
/// Keyed by the host's message id; bounded, least recently used out; lengths only grow.
@MainActor
final class GlimmerRevealStore {
    static let shared = GlimmerRevealStore()

    private let capacity: Int
    private var lengths: [String: Int] = [:]
    private var recent: [String] = []

    init(capacity: Int = 256) {
        self.capacity = capacity
    }

    func revealedLength(for id: String) -> Int? {
        lengths[id]
    }

    func record(_ length: Int, for id: String) {
        lengths[id] = max(lengths[id] ?? 0, length)
        recent.removeAll { $0 == id }
        recent.append(id)
        if recent.count > capacity { lengths[recent.removeFirst()] = nil }
    }

    func clear(_ id: String) {
        lengths[id] = nil
        recent.removeAll { $0 == id }
    }
}

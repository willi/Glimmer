import Foundation

/// How much of each message has been revealed, so a re-created or re-configured view resumes instead of replaying.
/// Keyed by the host's message id and fingerprinted by the answer's opening, so a regenerated answer under the same id
/// starts over; bounded, least recently used out; lengths only grow within one answer.
@MainActor
final class GlimmerRevealStore {
    static let shared = GlimmerRevealStore()

    private let capacity: Int
    private var entries: [String: (length: Int, prefixHash: Int)] = [:]
    private var recent: [String] = []

    init(capacity: Int = 256) {
        self.capacity = capacity
    }

    /// A fingerprint of an answer's opening: its first `min(length, 1_024)` characters.
    static func prefixHash(of text: NSString, length: Int) -> Int {
        text.substring(to: min(length, 1_024, text.length)).hashValue
    }

    /// The revealed length recorded for `id`, if `text` opens the way that answer did.
    func revealedLength(for id: String, text: NSString) -> Int? {
        guard let entry = entries[id], entry.prefixHash == Self.prefixHash(of: text, length: entry.length) else { return nil }
        return entry.length
    }

    /// Records `length` for `id`. It only grows while `text` is the same answer; a regenerated answer starts over.
    func record(_ length: Int, text: NSString, for id: String) {
        var stored = length
        if let entry = entries[id], entry.prefixHash == Self.prefixHash(of: text, length: entry.length) {
            stored = max(entry.length, length)
        }
        entries[id] = (stored, Self.prefixHash(of: text, length: stored))
        recent.removeAll { $0 == id }
        recent.append(id)
        if recent.count > capacity { entries[recent.removeFirst()] = nil }
    }

    func clear(_ id: String) {
        entries[id] = nil
        recent.removeAll { $0 == id }
    }
}

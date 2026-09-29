import Foundation

/// How much of each message has been revealed, so a re-created or re-configured view resumes instead of replaying.
/// Keyed by the host's message id and fingerprinted by the answer's opening, so a regenerated answer under the same id
/// starts over; bounded, least recently used out; lengths only grow within one answer.
@MainActor
final class GlimmerRevealStore {
    static let shared = GlimmerRevealStore()

    private let capacity: Int
    /// `version` is the text view's text version when the entry was recorded; `owner` is that text
    /// view's serial number, since a version identifies text only within its own view.
    private var entries: [String: (length: Int, prefixHash: Int, version: Int, owner: Int)] = [:]
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

    /// Records `length` for `id`, where `version` changes whenever `text` does. While it stays the same, the opening is
    /// hashed again only if the hashed part grew, so recording on every reveal step costs nothing on a long answer.
    func record(_ length: Int, text: NSString, version: Int, owner: Int, for id: String) {
        if let entry = entries[id], entry.version == version, entry.owner == owner {
            let stored = max(entry.length, length)
            let grew = min(stored, 1_024, text.length) != min(entry.length, 1_024, text.length)
            entries[id] = (stored, grew ? Self.prefixHash(of: text, length: stored) : entry.prefixHash, version, owner)
            touch(id)
            return
        }
        var stored = length
        if let entry = entries[id], entry.prefixHash == Self.prefixHash(of: text, length: entry.length) {
            stored = max(entry.length, length)
        }
        entries[id] = (stored, Self.prefixHash(of: text, length: stored), version, owner)
        touch(id)
    }

    private func touch(_ id: String) {
        guard recent.last != id else { return }
        recent.removeAll { $0 == id }
        recent.append(id)
        if recent.count > capacity { entries[recent.removeFirst()] = nil }
    }

    func clear(_ id: String) {
        entries[id] = nil
        recent.removeAll { $0 == id }
    }
}

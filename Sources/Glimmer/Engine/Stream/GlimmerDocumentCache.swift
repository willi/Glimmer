import UIKit

/// Composed text and heights of settled answers, so a cell showing an answer again skips parsing and composing and
/// knows its height before layout. Bounded (least recently used out), and emptied on a memory warning (spec §9).
@MainActor
final class GlimmerDocumentCache {
    static let shared = GlimmerDocumentCache()

    struct Key: Hashable {
        let source: String
        let theme: GlimmerTheme
        /// Only stateless built-in dependencies are shared, so their type names identify their behavior.
        let extensions: [String]
        let highlighter: String
        let imageLoader: String?
        /// Whether inline images' alt text links to them (the host takes image taps).
        var linksImagesForTaps = false
    }

    /// Custom dependencies may carry configuration or mutable state, and cached attachments retain their instances.
    /// Without an explicit equivalence contract, composing them afresh is the only safe way to use the current ones.
    static func supports(_ configuration: GlimmerConfiguration) -> Bool {
        configuration.extensions.allSatisfy { $0 is GlimmerMentions || $0 is GlimmerEmojiShortcodes }
            && configuration.highlighter is GlimmerBasicHighlighter
            && (configuration.imageLoader == nil || configuration.imageLoader is GlimmerURLSessionImageLoader)
    }

    private struct Entry {
        let text: NSAttributedString
        var heights: [CGFloat: CGFloat] = [:]
    }

    private let capacity: Int
    private var entries: [Key: Entry] = [:]
    private var recent: [Key] = []
    private(set) var hits = 0
    private var memoryWarning: NSObjectProtocol?

    init(capacity: Int = 64) {
        self.capacity = capacity
        memoryWarning = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.removeAll() }
        }
    }

    /// A copy of the cached text with fresh attachments, so no two views ever share an embed view.
    func text(for key: Key) -> NSAttributedString? {
        guard let entry = entries[key] else { return nil }
        hits += 1
        touch(key)
        return Self.detached(entry.text)
    }

    /// Stores a copy with fresh attachments: the view that composed `text` keeps using (and may grow) its own.
    func store(_ text: NSAttributedString, for key: Key) {
        entries[key] = Entry(text: Self.detached(text))
        touch(key)
    }

    /// `text` with every attachment replaced by a view-less copy of it.
    private static func detached(_ text: NSAttributedString) -> NSAttributedString {
        let copy = NSMutableAttributedString(attributedString: text)
        copy.enumerateAttribute(.attachment, in: NSRange(location: 0, length: copy.length)) { value, range, _ in
            if let block = value as? GlimmerBlockAttachment {
                copy.addAttribute(.attachment, value: block.freshCopy(), range: range)
            } else if let inline = value as? GlimmerInlineAttachment {
                copy.addAttribute(.attachment, value: inline.freshCopy(), range: range)
            } else if let image = value as? GlimmerInlineImageAttachment {
                copy.addAttribute(.attachment, value: image.freshCopy(), range: range)
            }
        }
        return copy
    }

    func height(for key: Key, width: CGFloat) -> CGFloat? {
        entries[key]?.heights[width]
    }

    func storeHeight(_ height: CGFloat, for key: Key, width: CGFloat) {
        entries[key]?.heights[width] = height
    }

    func removeAll() {
        entries.removeAll()
        recent.removeAll()
    }

    private func touch(_ key: Key) {
        recent.removeAll { $0 == key }
        recent.append(key)
        if recent.count > capacity { entries[recent.removeFirst()] = nil }
    }
}

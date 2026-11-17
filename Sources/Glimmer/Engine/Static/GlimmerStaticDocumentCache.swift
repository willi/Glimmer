import SwiftUI
import UIKit

/// Documents `GlimmerStaticText` built, shared by every view, so a feed cell and a separate sizing view showing the
/// same summary parse and compose it once, and a lazy container that drops a view's state doesn't build it again.
/// Bounded (least recently used out), and emptied on a memory warning, like `GlimmerDocumentCache`.
@MainActor
final class GlimmerStaticDocumentCache {
    static let shared = GlimmerStaticDocumentCache()

    /// What a document is built from. The theme is the configuration's, before scaling for the text size.
    struct Key: Hashable {
        let markdown: String
        let theme: GlimmerTheme
        let dynamicTypeSize: DynamicTypeSize
        /// The extensions' and the highlighter's identities, as `GlimmerDocumentCache` keys them; nil when one has
        /// none, and then the document is never shared.
        let dependencies: [GlimmerCacheIdentity]?

        init(markdown: String, configuration: GlimmerConfiguration, dynamicTypeSize: DynamicTypeSize) {
            self.markdown = markdown
            self.theme = configuration.theme
            self.dynamicTypeSize = dynamicTypeSize
            let extensions = configuration.extensions.compactMap { GlimmerCacheIdentity(extension: $0) }
            let highlighter = GlimmerCacheIdentity(highlighter: configuration.highlighter)
            if extensions.count == configuration.extensions.count, let highlighter {
                self.dependencies = extensions + [highlighter]
            } else {
                self.dependencies = nil
            }
        }
    }

    private let capacity: Int
    private var entries: [Key: GlimmerStaticDocument] = [:]
    private var recent: [Key] = []
    private var memoryWarning: NSObjectProtocol?
    /// How many documents this cache has built: for tests.
    private(set) var builds = 0

    init(capacity: Int = 64) {
        self.capacity = capacity
        memoryWarning = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.removeAll() }
        }
    }

    func document(
        markdown: String, configuration: GlimmerConfiguration, dynamicTypeSize: DynamicTypeSize
    ) -> GlimmerStaticDocument {
        document(for: Key(markdown: markdown, configuration: configuration, dynamicTypeSize: dynamicTypeSize),
                 configuration: configuration)
    }

    /// The document for `key`, built from `configuration` (which `key` was made from) when it isn't cached.
    func document(for key: Key, configuration: GlimmerConfiguration) -> GlimmerStaticDocument {
        if let cached = entries[key] {
            touch(key)
            return cached
        }
        builds += 1
        let document = GlimmerStaticDocument(
            markdown: key.markdown, configuration: configuration, dynamicTypeSize: key.dynamicTypeSize
        )
        guard key.dependencies != nil else { return document }
        entries[key] = document
        touch(key)
        return document
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

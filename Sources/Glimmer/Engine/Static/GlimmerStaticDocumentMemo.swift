import SwiftUI

/// The last document one `GlimmerStaticText` showed and its key, so a body evaluated again with the same inputs skips
/// even the shared cache's lookup, and a configuration the cache can't share still builds once per input.
@MainActor
final class GlimmerStaticDocumentMemo {
    private var last: (key: GlimmerStaticDocumentCache.Key, document: GlimmerStaticDocument)?

    nonisolated init() {}

    func document(
        markdown: String, configuration: GlimmerConfiguration, dynamicTypeSize: DynamicTypeSize,
        cache: GlimmerStaticDocumentCache
    ) -> GlimmerStaticDocument {
        let key = GlimmerStaticDocumentCache.Key(
            markdown: markdown, configuration: configuration, dynamicTypeSize: dynamicTypeSize
        )
        if let last, last.key == key { return last.document }
        let document = cache.document(for: key, configuration: configuration)
        last = (key, document)
        return document
    }
}

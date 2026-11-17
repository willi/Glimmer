import SwiftUI

/// Keeps the last document a `GlimmerStaticText` built, so a body re-evaluated with the same markdown and text size
/// reuses it. The configuration isn't part of the key (it isn't `Equatable`): the view is given a new identity when it
/// changes.
@MainActor
final class GlimmerStaticDocumentCache {
    private var markdown: String?
    private var dynamicTypeSize: DynamicTypeSize?
    private var cached: GlimmerStaticDocument?

    nonisolated init() {}

    func document(
        markdown: String, configuration: GlimmerConfiguration, dynamicTypeSize: DynamicTypeSize
    ) -> GlimmerStaticDocument {
        if let cached, markdown == self.markdown, dynamicTypeSize == self.dynamicTypeSize { return cached }
        let document = GlimmerStaticDocument(markdown: markdown, configuration: configuration, dynamicTypeSize: dynamicTypeSize)
        self.markdown = markdown
        self.dynamicTypeSize = dynamicTypeSize
        cached = document
        return document
    }
}

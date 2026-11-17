import SwiftUI
import UIKit

/// Markdown as the blocks `GlimmerStaticText` stacks, styled by a theme scaled for one Dynamic Type size.
///
/// Built once per input and kept by `GlimmerStaticDocumentCache`, since parsing and composing cost more than a SwiftUI
/// body should.
final class GlimmerStaticDocument {
    let blocks: [GlimmerStaticBlock]
    /// The configuration's theme, scaled for the document's Dynamic Type size.
    let theme: GlimmerTheme

    @MainActor
    init(markdown: String, configuration: GlimmerConfiguration, dynamicTypeSize: DynamicTypeSize) {
        let traits = UITraitCollection(preferredContentSizeCategory: dynamicTypeSize.contentSizeCategory)
        let theme = configuration.theme.scaled(for: traits)
        let source = configuration.extensions.prepared(markdown, isStreaming: false)
        var builder = GlimmerStaticDocumentBuilder(
            theme: theme, composer: GlimmerPlainText.composer(theme: theme, configuration: configuration)
        )
        self.blocks = builder.build(GlimmerParser.parse(source), context: GlimmerStaticDocumentBuilder.Context())
        self.theme = theme
    }
}

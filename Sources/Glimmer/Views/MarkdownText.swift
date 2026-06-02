import SwiftUI

/// A lightweight view for rendering a single paragraph of inline markdown content.
///
/// This view is optimized for performance when you only need to render a single line of text
/// with simple formatting, as it skips the block-level parsing.
public struct MarkdownText: View {
    private let attributedString: AttributedString

    /// Creates a `MarkdownText` view with the given markdown string and configuration.
    ///
    /// - Parameters:
    ///   - markdown: The markdown string to render.
    ///   - configuration: The configuration to use for rendering.
    public init(_ markdown: String, configuration: MarkdownConfiguration = .default) {
        let nodes = MarkdownParser.parseInlineOptimized(markdown, configuration: configuration)
        var renderer = MarkdownRenderer()
        
        // Wrap inline nodes in a paragraph block for rendering
        let paragraphBlock = MarkdownParser.BlockNode.paragraph(children: nodes)
        self.attributedString = renderer.render(blocks: [paragraphBlock], configuration: configuration)
    }

    public var body: some View {
        Text(attributedString)
    }
}

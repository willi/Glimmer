import SwiftUI

/// One block of a `GlimmerStaticDocument`, with the space above it.
struct GlimmerStaticBlock {
    /// What the block shows. The views switch on this.
    enum Content {
        /// A paragraph, a heading (with its level) or an HTML block, as one `Text`.
        case text(AttributedString, headingLevel: Int?)
        /// A code block's code, in the theme's code font.
        case code(AttributedString)
        /// A table, one line per row with its cells separated by tabs.
        case table([AttributedString])
        /// A thematic break.
        case rule
        /// A block quote's blocks, shown in the secondary text colour beside a bar.
        case quote([GlimmerStaticBlock])
        case list(GlimmerStaticList)
    }

    var content: Content
    /// The gap between this block and the one above it in the same stack; 0 for the first. A container's first block
    /// has 0 and the container carries the gap, so it sits outside a quote's bar or a list item's marker.
    var spacingAbove: CGFloat
}

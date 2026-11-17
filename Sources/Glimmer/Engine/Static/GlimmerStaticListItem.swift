import SwiftUI

/// One item of a `GlimmerStaticList`.
struct GlimmerStaticListItem {
    /// The bullet, number or task box, styled like the item's text.
    var marker: AttributedString
    /// The gap above the item; 0 for the first, whose gap the list carries.
    var spacingAbove: CGFloat
    /// The item's blocks, nested lists included. Empty for an empty item, which shows its marker alone.
    var blocks: [GlimmerStaticBlock]
}

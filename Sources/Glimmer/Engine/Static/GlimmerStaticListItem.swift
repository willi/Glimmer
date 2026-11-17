import SwiftUI

/// One item of a `GlimmerStaticList`.
struct GlimmerStaticListItem: Equatable {
    /// The bullet, number or task box, styled like the item's text.
    var marker: AttributedString
    /// What VoiceOver reads for the marker, when not its text: a task box's state.
    var markerAccessibilityLabel: String?
    /// The gap above the item; 0 for the first, whose gap the list carries.
    var spacingAbove: CGFloat
    /// The item's blocks, nested lists included. Empty for an empty item, which shows its marker alone.
    var blocks: [GlimmerStaticBlock]

    /// Whether VoiceOver reads the marker and the first block as one element, as `GlimmerView` reads the item's first
    /// line. Not when the first block is a list, whose items are elements of their own.
    var groupsMarkerWithFirstBlock: Bool {
        guard let first = blocks.first else { return false }
        if case .list = first.content { return false }
        return true
    }
}

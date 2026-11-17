import CoreGraphics

/// A list of a `GlimmerStaticDocument`: markers in a column, each item's blocks beside its marker.
struct GlimmerStaticList {
    /// Numbers end `markerGap` before the text, like a browser's list; bullets and boxes start the column.
    var isOrdered: Bool
    /// How far right of the list's leading edge every line of an item's text starts: at least the theme's
    /// `listIndent`, wider for wide markers, as the engine lays lists out.
    var markerColumnWidth: CGFloat
    /// The space between an ordered list's numbers and the text.
    var markerGap: CGFloat
    var items: [GlimmerStaticListItem]
}

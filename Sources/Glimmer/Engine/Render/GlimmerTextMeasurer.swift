import UIKit

/// Lays text out in a TextKit 2 stack of its own, apart from any view, so a host can ask how wide or how tall the text
/// is at a width without the shown text view re-wrapping. On iOS 27 only a band near the screen has layout in a view,
/// so measuring goes through the layout manager, not through views.
@MainActor
final class GlimmerTextMeasurer {
    /// The width of the longest line, including the insets and the line-fragment padding on both sides.
    private(set) var longestLineWidth: CGFloat = 0
    /// The bottom of each line fragment in order, including the top inset.
    private(set) var lineBottoms: [CGFloat] = []

    // The layout manager only weakly references its content manager, so the storage is kept here.
    private let contentStorage = NSTextContentStorage()

    /// Lays `text` out in a container `width` wide (the insets and padding come out of it) and records the result.
    init(text: NSAttributedString, width: CGFloat, insets: UIEdgeInsets, lineFragmentPadding: CGFloat) {
        let manager = NSTextLayoutManager()
        let container = NSTextContainer(size: CGSize(width: max(width - insets.left - insets.right, 0), height: 0))
        container.lineFragmentPadding = lineFragmentPadding
        manager.textContainer = container
        contentStorage.addTextLayoutManager(manager)
        contentStorage.attributedString = text

        var longest: CGFloat = 0
        var bottoms: [CGFloat] = []
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) { fragment in
            for line in fragment.textLineFragments {
                let frame = fragment.layoutFragmentFrame
                longest = max(longest, frame.minX + line.typographicBounds.maxX)
                bottoms.append(ceil(frame.minY + line.typographicBounds.maxY + insets.top))
            }
            return true
        }
        longestLineWidth = ceil(longest + lineFragmentPadding + insets.left + insets.right)
        lineBottoms = bottoms
    }
}

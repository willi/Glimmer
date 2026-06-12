import SwiftUI

/// Marks a subview as a forced line break inside `RevealFlowLayout`.
struct RevealLineBreakKey: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    func revealLineBreak(_ isBreak: Bool = true) -> some View {
        layoutValue(key: RevealLineBreakKey.self, value: isBreak)
    }
}

/// Left-to-right wrapping layout for reveal units. Words are laid out as
/// individual subviews so each can animate independently (spec §3 fact 1).
/// RTL layout is a documented later-phase limitation.
struct RevealFlowLayout: Layout {
    var lineSpacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .greatestFiniteMagnitude
        return computeFrames(in: width, subviews: subviews).totalSize
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = computeFrames(in: bounds.width, subviews: subviews).frames
        for (i, frame) in frames.enumerated() {
            subviews[i].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func computeFrames(in maxWidth: CGFloat, subviews: Subviews) -> (totalSize: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = Array(repeating: .zero, count: subviews.count)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for i in subviews.indices {
            if subviews[i][RevealLineBreakKey.self] {
                maxRowWidth = max(maxRowWidth, x)
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
                frames[i] = CGRect(x: 0, y: y, width: 0, height: 0)
                continue
            }
            let size = subviews[i].sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                maxRowWidth = max(maxRowWidth, x)
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            frames[i] = CGRect(x: x, y: y, width: size.width, height: size.height)
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }
        maxRowWidth = max(maxRowWidth, x)
        return (CGSize(width: maxRowWidth, height: y + rowHeight), frames)
    }
}

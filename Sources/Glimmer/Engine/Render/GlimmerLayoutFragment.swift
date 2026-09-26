import UIKit

/// Draws decorations that must not move glyphs: rounded pills behind inline code and one bar per blockquote level.
final class GlimmerLayoutFragment: NSTextLayoutFragment {
    var theme: GlimmerTheme?

    static let pillHorizontalInset: CGFloat = 3
    static let quoteBarWidth: CGFloat = 3

    override var renderingSurfaceBounds: CGRect {
        quoteBarRects().reduce(super.renderingSurfaceBounds.insetBy(dx: -(Self.pillHorizontalInset + 1), dy: -2)) {
            $0.union($1)
        }
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        if let theme {
            let traits = UITraitCollection.current
            context.saveGState()
            context.setFillColor(theme.quoteBarColor.resolvedColor(with: traits).cgColor)
            for rect in quoteBarRects() {
                context.fill(rect.offsetBy(dx: point.x, dy: point.y))
            }
            context.setFillColor(theme.inlineCodeBackground.resolvedColor(with: traits).cgColor)
            for rect in inlineCodePillRects() {
                context.addPath(UIBezierPath(roundedRect: rect.offsetBy(dx: point.x, dy: point.y), cornerRadius: 4).cgPath)
                context.fillPath()
            }
            context.restoreGState()
        }
        super.draw(at: point, in: context)
    }

    /// One bar per quote level, at `level × quoteIndent` from the container's leading edge. An indented
    /// paragraph's fragment frame starts at its indent, so these rects have negative x. Bars run the full fragment
    /// height (through the paragraph spacing) to join the next quoted paragraph, except the levels that close at
    /// this paragraph (`.glimmerQuoteContinues`), which stop at the bottom of the text.
    func quoteBarRects() -> [CGRect] {
        guard let theme,
              let paragraph = textElement as? NSTextParagraph,
              paragraph.attributedString.length > 0,
              let depth = paragraph.attributedString.attribute(.glimmerQuoteDepth, at: 0, effectiveRange: nil) as? Int,
              depth > 0 else { return [] }
        let height = layoutFragmentFrame.height
        let continuing = paragraph.attributedString.attribute(.glimmerQuoteContinues, at: 0, effectiveRange: nil) as? Int
        let textBottom = textLineFragments.last?.typographicBounds.maxY ?? height
        return (0..<depth).map { level in
            let closesHere = continuing.map { level >= $0 } ?? false
            return CGRect(
                x: CGFloat(level) * theme.quoteIndent - layoutFragmentFrame.minX, y: 0,
                width: Self.quoteBarWidth, height: closesHere ? min(textBottom, height) : height
            )
        }
    }

    /// A rounded background behind each inline-code run, split per line.
    func inlineCodePillRects() -> [CGRect] {
        var rects: [CGRect] = []
        for line in textLineFragments {
            let text = line.attributedString
            let lineRange = line.characterRange
            guard lineRange.length > 0, NSMaxRange(lineRange) <= text.length else { continue }
            text.enumerateAttribute(.glimmerInlineCode, in: lineRange) { value, range, _ in
                guard value != nil,
                      let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont else { return }
                let startX = line.locationForCharacter(at: range.location).x
                let endX = line.locationForCharacter(at: NSMaxRange(range)).x
                let baseline = line.typographicBounds.minY + line.glyphOrigin.y
                rects.append(CGRect(
                    x: line.typographicBounds.minX + startX - Self.pillHorizontalInset,
                    y: baseline - font.ascender - 1,
                    width: endX - startX + Self.pillHorizontalInset * 2,
                    height: font.ascender - font.descender + 2
                ))
            }
        }
        return rects
    }
}

/// Hands TextKit a `GlimmerLayoutFragment` for every paragraph.
final class GlimmerLayoutFragmentProvider: NSObject, NSTextLayoutManagerDelegate {
    var theme: GlimmerTheme

    init(theme: GlimmerTheme) {
        self.theme = theme
    }

    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation, in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        let fragment = GlimmerLayoutFragment(textElement: textElement, range: textElement.elementRange)
        fragment.theme = theme
        return fragment
    }
}

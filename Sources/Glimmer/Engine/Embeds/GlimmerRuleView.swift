import UIKit

/// A thematic break: a hairline centered in `blockSpacing` of space.
@MainActor
final class GlimmerRuleView: UIView, GlimmerEmbedView {
    private let line = UIView()
    private let spacing: CGFloat

    init(theme: GlimmerTheme) {
        spacing = theme.blockSpacing
        super.init(frame: .zero)
        line.backgroundColor = theme.tableBorderColor
        addSubview(line)
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(to embed: GlimmerEmbed) {}

    func embedHeight(forWidth width: CGFloat) -> CGFloat { spacing + 1 }

    override func layoutSubviews() {
        super.layoutSubviews()
        let thickness = 1 / max(traitCollection.displayScale, 1)
        line.frame = CGRect(x: 0, y: (bounds.height - thickness) / 2, width: bounds.width, height: thickness)
    }
}

import UIKit

/// The TextKit 2 surface for a composed markdown document: non-scrolling, selectable, not editable.
/// Never read `layoutManager` here — it silently switches the view to TextKit 1.
@MainActor
final class GlimmerTextView: UITextView {
    private(set) var theme: GlimmerTheme = .default
    private var lastLayoutWidth: CGFloat = 0
    /// Strongly held: the text layout manager's delegate is weak.
    private let fragmentProvider = GlimmerLayoutFragmentProvider(theme: .default)

    init() {
        // On iOS 16+, a nil text container gives a TextKit 2 text view.
        super.init(frame: .zero, textContainer: nil)
        backgroundColor = .clear
        isEditable = false
        isSelectable = true
        isScrollEnabled = false
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        dataDetectorTypes = []
        textLayoutManager?.delegate = fragmentProvider
        apply(theme: .default)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func apply(theme: GlimmerTheme) {
        self.theme = theme
        fragmentProvider.theme = theme
        var link: [NSAttributedString.Key: Any] = [.foregroundColor: theme.linkColor]
        if theme.underlinesLinks { link[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        linkTextAttributes = link
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard size.width > 0, attributedText.length > 0 else { return CGSize(width: max(size.width, 0), height: 0) }
        let fitted = super.sizeThatFits(CGSize(width: size.width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: size.width, height: ceil(fitted.height))
    }

    override var intrinsicContentSize: CGSize {
        let height = bounds.width > 0 ? sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height : 0
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width != lastLayoutWidth else { return }
        lastLayoutWidth = bounds.width
        invalidateIntrinsicContentSize()
    }
}

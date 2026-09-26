import UIKit

/// Renders markdown natively with TextKit 2.
///
/// Size it with Auto Layout (a width constraint gives an intrinsic height) or call `sizeThatFits(_:)` with a finite
/// width. `onHeightChange` fires whenever the height may have changed.
@MainActor
public final class GlimmerView: UIView {
    public var configuration: GlimmerConfiguration {
        didSet { render() }
    }
    public var onLinkTap: ((URL) -> Void)?
    public var onHeightChange: (() -> Void)?

    let textView = GlimmerTextView()
    private(set) var markdown = ""
    private var lastWidth: CGFloat = 0

    public init(configuration: GlimmerConfiguration = .default) {
        self.configuration = configuration
        super.init(frame: .zero)
        textView.delegate = self
        addSubview(textView)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: GlimmerView, _: UITraitCollection) in
            view.render()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Replaces the rendered markdown. Rendering the same string twice does nothing.
    public func update(markdown: String) {
        guard markdown != self.markdown else { return }
        self.markdown = markdown
        render()
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        textView.sizeThatFits(size)
    }

    public override var intrinsicContentSize: CGSize {
        let height = bounds.width > 0 ? sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height : 0
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = bounds
        guard bounds.width != lastWidth else { return }
        lastWidth = bounds.width
        invalidateIntrinsicContentSize()
        onHeightChange?()
    }

    func linkAction(for url: URL) -> UIAction? {
        guard let onLinkTap else { return nil }
        return UIAction { _ in onLinkTap(url) }
    }

    private func render() {
        let theme = configuration.theme.scaled(for: traitCollection)
        textView.apply(theme: theme)
        let source = configuration.extensions.reduce(markdown) { $1.preprocess($0) }
        let composer = GlimmerComposer(
            theme: theme,
            highlighter: configuration.highlighter,
            imageLoader: configuration.imageLoader,
            extensions: configuration.extensions
        )
        textView.attributedText = composer.compose(GlimmerParser.parse(source))
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        onHeightChange?()
    }
}

extension GlimmerView: UITextViewDelegate {
    public func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
        guard case .link(let url) = textItem.content else { return defaultAction }
        return linkAction(for: url) ?? defaultAction
    }
}

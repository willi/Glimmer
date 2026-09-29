import UIKit

/// An inline image and its placeholder share the configured shape without changing the reserved text space.
@MainActor
final class GlimmerInlineImageView: UIImageView {
    private let source: URL
    private let alt: String
    private let isLinked: Bool
    private let shape: GlimmerInlineImageShape
    private let imageLoader: GlimmerImageViewLoader?
    private lazy var tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))

    init(
        source: URL, alt: String, isLinked: Bool = false, theme: GlimmerTheme, loader: (any GlimmerImageLoader)?,
        shape: GlimmerInlineImageShape = .circle
    ) {
        self.source = source
        self.alt = alt
        self.isLinked = isLinked
        self.shape = shape
        imageLoader = loader.map {
            GlimmerImageViewLoader(source: source, loader: $0, contentMode: shape == .circle ? .aspectFill : .aspectFit)
        }
        super.init(frame: .zero)
        contentMode = shape == .circle ? .scaleAspectFill : .scaleAspectFit
        clipsToBounds = true
        layer.cornerCurve = shape == .circle ? .circular : .continuous
        backgroundColor = theme.codeBlockBackground
        // The spoken-only alt text after it reads the image (and, while the host takes image taps, links to it), so the
        // view itself stays out of VoiceOver's way.
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        isUserInteractionEnabled = true
        addGestureRecognizer(tapRecognizer)
        registerForTraitChanges([UITraitDisplayScale.self]) { (view: GlimmerInlineImageView, _: UITraitCollection) in
            view.setNeedsLayout()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // TextKit supplies the bounds after creating the view, and line heights vary with font and Dynamic Type.
        let maximumRadius = min(bounds.width, bounds.height) / 2
        switch shape {
        case .circle:
            layer.cornerRadius = maximumRadius
        case .roundedRectangle(let cornerRadius):
            layer.cornerRadius = cornerRadius.isFinite ? min(max(0, cornerRadius), maximumRadius) : 0
        }
        imageLoader?.load(size: bounds.size, scale: traitCollection.displayScale) { [weak self] result in
            if case .success(let image) = result { self?.image = image }
        }
    }

    /// Whether a tap reaches the host: only while it sets `onImageTap`, and not inside a link, which takes the tap as
    /// on GitHub. Otherwise the tap falls through to the text.
    var acceptsTaps: Bool { !isLinked && glimmerImageTapHandler != nil }

    @objc func handleTap() {
        glimmerImageTapHandler?(source, alt)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === tapRecognizer ? acceptsTaps : super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

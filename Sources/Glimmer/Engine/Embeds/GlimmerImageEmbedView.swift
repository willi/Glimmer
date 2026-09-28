import UIKit

/// A standalone markdown image. The box is sized before loading (placeholder aspect, capped height) and never
/// resizes, so a finished load cannot shift the text below it; the image is aspect-fit inside the box.
@MainActor
final class GlimmerImageEmbedView: UIView, GlimmerEmbedView {
    let imageView = UIImageView()
    let altLabel = UILabel()

    private let theme: GlimmerTheme
    private let source: URL
    private let alt: String
    private var loadTask: Task<Void, Never>?
    private lazy var tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))

    init(source: URL, alt: String, theme: GlimmerTheme, loader: (any GlimmerImageLoader)?) {
        self.theme = theme
        self.source = source
        self.alt = alt
        super.init(frame: .zero)
        backgroundColor = theme.codeBlockBackground
        layer.cornerRadius = theme.embedCornerRadius
        layer.cornerCurve = .continuous
        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityTraits = .image
        accessibilityLabel = alt

        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        altLabel.text = alt
        altLabel.font = theme.captionFont
        altLabel.textColor = theme.secondaryTextColor
        altLabel.textAlignment = .center
        altLabel.numberOfLines = 0
        altLabel.isHidden = true
        addSubview(altLabel)
        addGestureRecognizer(tapRecognizer)

        guard let loader else {
            altLabel.isHidden = false
            return
        }
        loadTask = Task { [weak self] in
            do {
                let image = try await loader.loadImage(from: source)
                self?.imageView.image = image
            } catch {
                self?.altLabel.isHidden = false
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Whether a tap reaches the host: only while it sets `onImageTap`.
    var acceptsTaps: Bool { glimmerImageTapHandler != nil }

    @objc func handleTap() {
        glimmerImageTapHandler?(source, alt)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === tapRecognizer ? acceptsTaps : super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    /// A button while the host takes image taps. Set, not computed: UIKit's accessibility may read a view off the main
    /// thread, where a Swift override traps.
    func updateAccessibility() {
        accessibilityTraits = acceptsTaps ? [.image, .button] : .image
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateAccessibility()
    }

    /// An image embed continues only an identical one (`GlimmerEmbed.continues`), so there is nothing to update.
    func update(to embed: GlimmerEmbed) {}

    /// Reveals as one phrase: no units.
    var visibleUnitCount: Int?

    func revealUnitRects(in box: CGRect) -> [CGRect] { [box] }

    isolated deinit {
        loadTask?.cancel()
    }

    func embedHeight(forWidth width: CGFloat) -> CGFloat {
        min(width / theme.imagePlaceholderAspect, theme.maxImageHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        altLabel.frame = bounds.insetBy(dx: theme.embedPadding, dy: theme.embedPadding)
    }
}

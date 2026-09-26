import UIKit

/// A standalone markdown image. The box is sized before loading (placeholder aspect, capped height) and never
/// resizes, so a finished load cannot shift the text below it; the image is aspect-fit inside the box.
@MainActor
final class GlimmerImageEmbedView: UIView, GlimmerEmbedView {
    let imageView = UIImageView()
    let altLabel = UILabel()

    private let theme: GlimmerTheme
    private var loadTask: Task<Void, Never>?

    init(source: URL, alt: String, theme: GlimmerTheme, loader: (any GlimmerImageLoader)?) {
        self.theme = theme
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

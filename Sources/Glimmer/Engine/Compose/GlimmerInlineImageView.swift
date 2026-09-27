import UIKit

/// The view of an inline image: the placeholder tint until the loader delivers, then the image, aspect-fitted.
@MainActor
final class GlimmerInlineImageView: UIImageView {
    private var loadTask: Task<Void, Never>?

    init(source: URL, theme: GlimmerTheme, loader: (any GlimmerImageLoader)?) {
        super.init(frame: .zero)
        contentMode = .scaleAspectFit
        clipsToBounds = true
        layer.cornerRadius = 3
        layer.cornerCurve = .continuous
        backgroundColor = theme.codeBlockBackground
        // The spoken-only alt text after it reads the image; the view itself stays out of VoiceOver's way.
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        guard let loader else { return }
        loadTask = Task { [weak self] in
            guard let image = try? await loader.loadImage(from: source) else { return }
            self?.image = image
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    isolated deinit {
        loadTask?.cancel()
    }
}

import UIKit

/// The view of an inline image: the placeholder tint until the loader delivers, then the image, aspect-fitted.
@MainActor
final class GlimmerInlineImageView: UIImageView {
    private let source: URL
    private let alt: String
    private var loadTask: Task<Void, Never>?
    private lazy var tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))

    init(source: URL, alt: String, theme: GlimmerTheme, loader: (any GlimmerImageLoader)?) {
        self.source = source
        self.alt = alt
        super.init(frame: .zero)
        contentMode = .scaleAspectFit
        clipsToBounds = true
        layer.cornerRadius = 3
        layer.cornerCurve = .continuous
        backgroundColor = theme.codeBlockBackground
        // The spoken-only alt text after it reads the image; the view itself stays out of VoiceOver's way.
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        isUserInteractionEnabled = true
        addGestureRecognizer(tapRecognizer)
        guard let loader else { return }
        loadTask = Task { [weak self] in
            guard let image = try? await loader.loadImage(from: source) else { return }
            self?.image = image
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Whether a tap reaches the host: only while it sets `onImageTap`. Otherwise the tap falls through to the text.
    var acceptsTaps: Bool { glimmerImageTapHandler != nil }

    @objc func handleTap() {
        glimmerImageTapHandler?(source, alt)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === tapRecognizer ? acceptsTaps : super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    isolated deinit {
        loadTask?.cancel()
    }
}

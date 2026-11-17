import UIKit

/// Hosts a tappable chip's view and reports a tap on it as the token, through the `GlimmerView`'s `onTokenTap`.
@MainActor
final class GlimmerChipTapView: UIView {
    private let content: UIView
    private let token: GlimmerInlineToken
    private weak var attachment: GlimmerInlineAttachment?
    private lazy var tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))

    init(content: UIView, token: GlimmerInlineToken, attachment: GlimmerInlineAttachment) {
        self.content = content
        self.token = token
        self.attachment = attachment
        super.init(frame: .zero)
        // The spoken-only link after the chip reads it and takes VoiceOver's activation.
        isAccessibilityElement = false
        isUserInteractionEnabled = true
        content.isUserInteractionEnabled = false
        addSubview(content)
        addGestureRecognizer(tapRecognizer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func sizeThatFits(_ size: CGSize) -> CGSize { content.sizeThatFits(size) }

    override func layoutSubviews() {
        super.layoutSubviews()
        content.frame = bounds
    }

    /// Whether a tap reaches the host: only while it sets `onTokenTap` and the chip is revealed. Otherwise the tap
    /// falls through to the text.
    var acceptsTaps: Bool {
        guard glimmerTokenTapHandler != nil else { return false }
        return attachment.map(glimmerHostHasRevealed) ?? true
    }

    @objc func handleTap() {
        glimmerTokenTapHandler?(token)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === tapRecognizer ? acceptsTaps : super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

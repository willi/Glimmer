import UIKit

/// An inline chip for an extension token. It is laid out at the line height, on the baseline.
final class GlimmerInlineAttachment: NSTextAttachment {
    let token: GlimmerInlineToken
    let glimmerExtension: any GlimmerExtension
    let theme: GlimmerTheme

    init(token: GlimmerInlineToken, glimmerExtension: any GlimmerExtension, theme: GlimmerTheme) {
        self.token = token
        self.glimmerExtension = glimmerExtension
        self.theme = theme
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewProvider(
        for parentView: UIView?, location: any NSTextLocation, textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider? {
        let provider = GlimmerInlineViewProvider(
            textAttachment: self, parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager, location: location
        )
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }
}

/// Creates the chip view and sizes it to the surrounding font's line height.
///
/// Like `GlimmerEmbedViewProvider`, its overrides are nonisolated in the SDK but run on the main thread during
/// `UITextView` layout, so they assume main-actor isolation to build and measure the view.
final class GlimmerInlineViewProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        // The attachment is immutable after init and this callback runs on the main thread during layout.
        nonisolated(unsafe) let attachment = textAttachment as? GlimmerInlineAttachment
        guard attachment != nil else { return }
        view = MainActor.assumeIsolated { () -> UIView? in
            guard let attachment else { return nil }
            if let custom = attachment.glimmerExtension.makeInlineView(for: attachment.token, theme: attachment.theme) {
                return custom
            }
            let label = UILabel()
            label.text = attachment.token.displayText
            label.font = attachment.theme.bodyFont
            label.textColor = attachment.theme.linkColor
            return label
        }
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation, textContainer: NSTextContainer?,
        proposedLineFragment: CGRect, position: CGPoint
    ) -> CGRect {
        let font = attributes[.font] as? UIFont ?? UIFont.preferredFont(forTextStyle: .body)
        let height = ceil(font.lineHeight)
        let available = proposedLineFragment.width
        let chip = view
        let fitted = MainActor.assumeIsolated { chip?.sizeThatFits(CGSize(width: available, height: height)).width ?? 0 }
        return CGRect(x: 0, y: font.descender, width: min(ceil(fitted), available), height: height)
    }
}

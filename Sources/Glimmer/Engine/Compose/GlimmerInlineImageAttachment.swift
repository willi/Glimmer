import UIKit

/// An image inside a paragraph: a square as tall as the line, the image aspect-fitted inside. The square never changes
/// size, so a load never moves text (the spec's promise for images); until it loads, or if it fails, it shows the
/// placeholder tint. VoiceOver reads the alt text, which follows it as spoken-only text.
final class GlimmerInlineImageAttachment: NSTextAttachment {
    let source: URL
    let alt: String
    let theme: GlimmerTheme
    let loader: (any GlimmerImageLoader)?
    /// Built once and reused when TextKit asks for a fresh provider.
    private var cachedView: GlimmerInlineImageView?

    init(source: URL, alt: String, theme: GlimmerTheme, loader: (any GlimmerImageLoader)?) {
        self.source = source
        self.alt = alt
        self.theme = theme
        self.loader = loader
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// A new attachment for the same image, without a view: for a cached text shown by another view.
    func freshCopy() -> GlimmerInlineImageAttachment {
        GlimmerInlineImageAttachment(source: source, alt: alt, theme: theme, loader: loader)
    }

    @MainActor
    var existingView: UIImageView? { cachedView }

    @MainActor
    func imageView() -> UIImageView {
        if let cachedView { return cachedView }
        let view = GlimmerInlineImageView(source: source, alt: alt, theme: theme, loader: loader)
        cachedView = view
        return view
    }

    override func viewProvider(
        for parentView: UIView?, location: any NSTextLocation, textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider? {
        let provider = GlimmerInlineImageViewProvider(
            textAttachment: self, parentView: parentView, textLayoutManager: textContainer?.textLayoutManager, location: location
        )
        // As for chips: TextKit then sizes the view from `attachmentBounds`, not from the attachment's image.
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }
}

/// Sizes the image to a line-height square on the baseline, like a chip.
final class GlimmerInlineImageViewProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        nonisolated(unsafe) let attachment = textAttachment as? GlimmerInlineImageAttachment
        guard attachment != nil else { return }
        view = MainActor.assumeIsolated { attachment?.imageView() }
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation, textContainer: NSTextContainer?,
        proposedLineFragment: CGRect, position: CGPoint
    ) -> CGRect {
        let font = attributes[.font] as? UIFont ?? UIFont.preferredFont(forTextStyle: .body)
        let side = ceil(font.lineHeight)
        return CGRect(x: 0, y: font.descender, width: side, height: side)
    }
}

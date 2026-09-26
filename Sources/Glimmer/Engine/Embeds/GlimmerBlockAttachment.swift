import UIKit

/// A full-width attachment whose view comes from `GlimmerEmbedViewFactory`.
/// Put it in its own paragraph (`\n` before and after).
final class GlimmerBlockAttachment: NSTextAttachment {
    private(set) var embed: GlimmerEmbed
    let theme: GlimmerTheme
    let highlighter: any GlimmerHighlighter
    let imageLoader: (any GlimmerImageLoader)?
    /// Built once. TextKit asks for a fresh provider on every height query and frame change; rebuilding the view each
    /// time would re-highlight code and re-fetch images.
    private var cachedView: (any GlimmerEmbedView)?

    init(embed: GlimmerEmbed, theme: GlimmerTheme, highlighter: any GlimmerHighlighter, imageLoader: (any GlimmerImageLoader)?) {
        self.embed = embed
        self.theme = theme
        self.highlighter = highlighter
        self.imageLoader = imageLoader
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewProvider(
        for parentView: UIView?, location: any NSTextLocation, textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider? {
        let provider = GlimmerEmbedViewProvider(
            textAttachment: self, parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager, location: location
        )
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }

    /// Moves the attachment to a grown embed and updates its view, if one was made. Main thread: it touches the view,
    /// and TextKit reads `embed` when it asks for a view.
    @MainActor
    func update(to embed: GlimmerEmbed) {
        self.embed = embed
        cachedView?.update(to: embed)
    }

    /// The units the view shows while a reveal runs; nil shows all. Kept here, so a view made later starts right.
    @MainActor
    var visibleUnitCount: Int? {
        get { visibleUnits }
        set {
            visibleUnits = newValue
            cachedView?.visibleUnitCount = newValue
        }
    }
    @MainActor private var visibleUnits: Int?

    /// The view, if one was made.
    @MainActor
    var existingView: (any GlimmerEmbedView)? { cachedView }

    /// The embed's view, created on first use and reused for the attachment's lifetime.
    @MainActor
    func embedView() -> any GlimmerEmbedView {
        if let cachedView { return cachedView }
        var view = GlimmerEmbedViewFactory.makeView(for: self)
        view.visibleUnitCount = visibleUnits
        cachedView = view
        return view
    }
}

/// Creates the embed view and sizes the attachment to the full available width.
///
/// The provider's overrides are nonisolated in the SDK, but a `UITextView` lays out on the main thread, so they
/// assume main-actor isolation to reach the (main-actor) embed views.
final class GlimmerEmbedViewProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        // UITextView calls this on the main thread during layout; the attachment's only mutable state (its cached view) is main-actor.
        nonisolated(unsafe) let attachment = textAttachment as? GlimmerBlockAttachment
        guard attachment != nil else { return }
        view = MainActor.assumeIsolated { attachment.map { $0.embedView() } }
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation, textContainer: NSTextContainer?,
        proposedLineFragment: CGRect, position: CGPoint
    ) -> CGRect {
        let width = max(0, proposedLineFragment.width - position.x)
        let embed = view as? any GlimmerEmbedView
        let height = MainActor.assumeIsolated { embed?.embedHeight(forWidth: width) ?? 0 }
        return CGRect(x: 0, y: 0, width: width, height: height)
    }
}

@MainActor
enum GlimmerEmbedViewFactory {
    static func makeView(for attachment: GlimmerBlockAttachment) -> any GlimmerEmbedView {
        switch attachment.embed {
        case .codeBlock(let language, let code):
            return GlimmerCodeBlockView(code: code, language: language, theme: attachment.theme, highlighter: attachment.highlighter)
        case .table(let header, let rows, let alignments):
            return GlimmerTableView(header: header, rows: rows, alignments: alignments, theme: attachment.theme)
        case .image(let source, let alt):
            return GlimmerImageEmbedView(source: source, alt: alt, theme: attachment.theme, loader: attachment.imageLoader)
        case .thematicBreak:
            return GlimmerRuleView(theme: attachment.theme)
        }
    }
}

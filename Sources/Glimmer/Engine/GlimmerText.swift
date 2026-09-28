import SwiftUI

/// SwiftUI wrapper for `GlimmerView`. Markdown, `onLinkTap`, `onTokenTap` and `onImageTap` update in place; the configuration is read once, when
/// the view is created. To apply a different configuration (theme, extensions, image loader), give the view a new
/// identity, for example `.id(themeVersion)`.
public struct GlimmerText: UIViewRepresentable {
    public var markdown: String
    public var isStreaming: Bool
    public var revealID: String?
    public var configuration: GlimmerConfiguration
    public var onLinkTap: ((URL) -> Void)?
    /// Called with a tapped extension token, such as a mention. See `GlimmerView.onTokenTap`.
    public var onTokenTap: ((GlimmerInlineToken) -> Void)?
    /// Called with a tapped image's URL and alt text. See `GlimmerView.onImageTap`.
    public var onImageTap: ((URL, String) -> Void)?
    /// Items appended to the edit menu for a selection. See `GlimmerView.editMenuActions`.
    public var editMenuActions: ((GlimmerSelection) -> [UIMenuElement])?
    /// Items appended to a link's menu. See `GlimmerView.linkMenuActions`.
    public var linkMenuActions: ((URL) -> [UIMenuElement])?

    public init(
        _ markdown: String,
        isStreaming: Bool = false,
        revealID: String? = nil,
        configuration: GlimmerConfiguration = .default,
        onLinkTap: ((URL) -> Void)? = nil,
        onTokenTap: ((GlimmerInlineToken) -> Void)? = nil,
        onImageTap: ((URL, String) -> Void)? = nil,
        editMenuActions: ((GlimmerSelection) -> [UIMenuElement])? = nil,
        linkMenuActions: ((URL) -> [UIMenuElement])? = nil
    ) {
        self.markdown = markdown
        self.isStreaming = isStreaming
        self.revealID = revealID
        self.configuration = configuration
        self.onLinkTap = onLinkTap
        self.onTokenTap = onTokenTap
        self.onImageTap = onImageTap
        self.editMenuActions = editMenuActions
        self.linkMenuActions = linkMenuActions
    }

    public func makeUIView(context: Context) -> GlimmerView {
        let view = GlimmerView(configuration: configuration)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    public func updateUIView(_ view: GlimmerView, context: Context) {
        view.onLinkTap = onLinkTap
        view.onTokenTap = onTokenTap
        view.onImageTap = onImageTap
        view.editMenuActions = editMenuActions
        view.linkMenuActions = linkMenuActions
        view.update(markdown: markdown, isStreaming: isStreaming, revealID: revealID)
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: GlimmerView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}

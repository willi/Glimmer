import SwiftUI

/// SwiftUI wrapper for `GlimmerView`. Markdown and `onLinkTap` update in place; the configuration is read once, when
/// the view is created. To apply a different configuration (theme, extensions, image loader), give the view a new
/// identity, for example `.id(themeVersion)`.
public struct GlimmerText: UIViewRepresentable {
    public var markdown: String
    public var isStreaming: Bool
    public var revealID: String?
    public var configuration: GlimmerConfiguration
    public var onLinkTap: ((URL) -> Void)?

    public init(
        _ markdown: String,
        isStreaming: Bool = false,
        revealID: String? = nil,
        configuration: GlimmerConfiguration = .default,
        onLinkTap: ((URL) -> Void)? = nil
    ) {
        self.markdown = markdown
        self.isStreaming = isStreaming
        self.revealID = revealID
        self.configuration = configuration
        self.onLinkTap = onLinkTap
    }

    public func makeUIView(context: Context) -> GlimmerView {
        let view = GlimmerView(configuration: configuration)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    public func updateUIView(_ view: GlimmerView, context: Context) {
        view.onLinkTap = onLinkTap
        view.update(markdown: markdown, isStreaming: isStreaming, revealID: revealID)
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: GlimmerView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}

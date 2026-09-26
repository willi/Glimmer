import SwiftUI

/// SwiftUI wrapper for `GlimmerView`. The configuration is read once, when the view is created. Markdown and
/// `onLinkTap` update in place.
public struct GlimmerText: UIViewRepresentable {
    public var markdown: String
    public var configuration: GlimmerConfiguration
    public var onLinkTap: ((URL) -> Void)?

    public init(_ markdown: String, configuration: GlimmerConfiguration = .default, onLinkTap: ((URL) -> Void)? = nil) {
        self.markdown = markdown
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
        view.update(markdown: markdown)
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: GlimmerView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}

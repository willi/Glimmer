import SwiftUI
import UIKit

/// A UIKit controller that hosts Glimmer's complete SwiftUI markdown reveal.
///
/// Embed it using normal child-view-controller containment and constrain its
/// view's width. The hosted content participates in Auto Layout self-sizing.
/// Retain the controller while appending text so parsing and reveal progress
/// survive each update. For a native attributed-text surface, use
/// `GlimmerTrailTextView` instead.
@MainActor
public final class GlimmerRevealViewController: UIViewController {
    private let content: RevealHostingState
    private let containerView: RevealHostingContainerView
    private let hostingController: UIHostingController<RevealHostingContent>

    public init(
        markdown: String = "",
        reveal: RevealConfiguration = .init(style: .smoothTrail, isStreaming: true),
        configuration: MarkdownConfiguration = .default,
        onLinkTap: ((URL) -> Void)? = nil,
        onComplete: (() -> Void)? = nil
    ) {
        let content = RevealHostingState(markdown: markdown, reveal: reveal)
        let containerView = RevealHostingContainerView()
        self.content = content
        self.containerView = containerView
        self.hostingController = UIHostingController(rootView: RevealHostingContent(
            content: content,
            configuration: configuration,
            onLinkTap: onLinkTap,
            onComplete: onComplete,
            onSizeChange: { [weak containerView] size in
                containerView?.updateContentSize(size)
            }
        ))
        super.init(nibName: nil, bundle: nil)
        hostingController.sizingOptions = .intrinsicContentSize
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("Use init(markdown:reveal:configuration:onLinkTap:onComplete:)")
    }

    public override func loadView() {
        view = containerView
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        addChild(hostingController)
        let hostedView = hostingController.view!
        hostedView.backgroundColor = .clear
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: view.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
    }

    /// Updates the current message without replacing its reveal session.
    /// Pass the complete accumulated buffer on each call, then set
    /// `isStreaming` to `false` when the producer finishes.
    public func update(markdown: String, isStreaming: Bool) {
        // Representables may send the same input again during sizing. In
        // particular, mutating a nested @Observable struct property always
        // invalidates its observers, even when the Boolean did not change.
        // A no-op update must not schedule another host/representable pass.
        guard content.markdown != markdown || content.reveal.isStreaming != isStreaming else { return }
        if content.markdown != markdown {
            content.markdown = markdown
        }
        if content.reveal.isStreaming != isStreaming {
            var reveal = content.reveal
            reveal.isStreaming = isStreaming
            content.reveal = reveal
        }
        containerView.invalidateIntrinsicContentSize()
    }

    /// Reuses this controller for a message or style with a new view identity.
    ///
    /// A supplied `revealID` retains the normal cross-remount resume behavior.
    /// Use a new message ID for a new message; to replay an existing ID, first
    /// call `RevealProgressStore.shared.clear(id)`. Pass a configuration without
    /// a `revealID` to start fresh without shared progress.
    public func reset(markdown: String = "", reveal: RevealConfiguration) {
        content.markdown = markdown
        content.reveal = reveal
        content.generation += 1
        containerView.invalidateIntrinsicContentSize()
    }

    /// Measures the markdown at the proposed width for custom UIKit layouts.
    /// Use a finite width and a generous height for a vertically growing chat
    /// message; Auto Layout hosts can use `systemLayoutSizeFitting` instead.
    public func sizeThatFits(in size: CGSize) -> CGSize {
        loadViewIfNeeded()
        return hostingController.sizeThatFits(in: size)
    }
}

/// The public controller's root must publish the SwiftUI content height. A
/// plain UIView swallows the hosting child's intrinsic-size invalidations,
/// leaving a self-sized representable stuck at its initially empty height.
private final class RevealHostingContainerView: UIView {
    private var contentHeight: CGFloat = 0

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: contentHeight)
    }

    func updateContentSize(_ size: CGSize) {
        guard size.height.isFinite, abs(size.height - contentHeight) > 0.1 else { return }
        contentHeight = size.height
        invalidateIntrinsicContentSize()
        superview?.setNeedsLayout()
    }
}

@MainActor
@Observable
private final class RevealHostingState {
    var markdown: String
    var reveal: RevealConfiguration
    var generation = 0

    init(markdown: String, reveal: RevealConfiguration) {
        self.markdown = markdown
        self.reveal = reveal
    }
}

private struct RevealHostingContent: View {
    let content: RevealHostingState
    let configuration: MarkdownConfiguration
    let onLinkTap: ((URL) -> Void)?
    let onComplete: (() -> Void)?
    let onSizeChange: (CGSize) -> Void

    var body: some View {
        GlimmerRevealView(
            markdown: content.markdown,
            reveal: content.reveal,
            configuration: configuration,
            onLinkTap: onLinkTap,
            onComplete: onComplete
        )
        .id(content.generation)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            onSizeChange(size)
        }
    }
}

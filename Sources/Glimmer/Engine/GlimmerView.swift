import UIKit

/// Renders markdown natively with TextKit 2, and reveals a streaming answer phrase by phrase.
///
/// Size it with Auto Layout (a width constraint gives an intrinsic height) or call `sizeThatFits(_:)` with a finite
/// width. While a reveal runs, the height ends at the last revealed line. `onHeightChange` fires whenever the height
/// may have changed.
@MainActor
public final class GlimmerView: UIView {
    public var configuration: GlimmerConfiguration {
        didSet { rebuildDocument() }
    }
    public var onLinkTap: ((URL) -> Void)?
    public var onHeightChange: (() -> Void)?

    let textView = GlimmerTextView()
    let revealMask = GlimmerRevealMask()
    /// The reveal's time source; tests substitute a manual clock.
    var clock: any GlimmerRevealClock = GlimmerSystemRevealClock()
    private(set) var markdown = ""
    private(set) var isStreaming = false
    private(set) var revealID: String?
    private(set) var engine: GlimmerRevealEngine?

    private var document: GlimmerStreamingDocument
    private var lastWidth: CGFloat = 0
    private var lastReportedHeight: CGFloat = -1

    public init(configuration: GlimmerConfiguration = .default) {
        self.configuration = configuration
        document = GlimmerStreamingDocument(composer: GlimmerComposer(theme: configuration.theme))
        super.init(frame: .zero)
        // While revealing, this view is shorter than the text and clips the rest (see `fitTextViewToContent`).
        clipsToBounds = true
        textView.delegate = self
        addSubview(textView)
        rebuildDocument()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: GlimmerView, _: UITraitCollection) in
            view.rebuildDocument()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows a finished document immediately.
    public func update(markdown: String) {
        update(markdown: markdown, isStreaming: false)
    }

    /// Shows `markdown`, the accumulated text so far. While `isStreaming` is true — and until the reveal it started
    /// finishes — new text is revealed per `configuration.reveal`. Pass the same `revealID` for the same message so a
    /// re-created view resumes instead of replaying.
    public func update(markdown: String, isStreaming: Bool, revealID: String? = nil) {
        guard markdown != self.markdown || isStreaming != self.isStreaming || revealID != self.revealID else { return }
        if revealID != self.revealID { endReveal() }
        self.markdown = markdown
        self.isStreaming = isStreaming
        self.revealID = revealID
        if let edit = document.update(markdown: preprocessed(markdown), isStreaming: isStreaming) {
            textView.apply(edit)
            fitTextViewToContent()
        }
        startRevealIfNeeded()
        engine?.textChanged(NSString(string: textView.textStorage.string), isStreaming: isStreaming, now: clock.now)
        advanceReveal()
        reportHeightIfChanged()
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: height(forWidth: size.width))
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: height(forWidth: bounds.width))
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        fitTextViewToContent()
        if let engine { revealMask.update(in: textView, engine: engine, now: clock.now) }
        guard bounds.width != lastWidth else { return }
        lastWidth = bounds.width
        reportHeightIfChanged()
    }

    func linkAction(for url: URL) -> UIAction? {
        guard let onLinkTap else { return nil }
        return UIAction { _ in onLinkTap(url) }
    }

    // MARK: - Reveal

    /// Starts due phrases, settles finished fades, redraws the mask and schedules the next wake-up.
    func advanceReveal() {
        guard var current = engine else { return }
        let now = clock.now
        current.advance(to: now)
        if let revealID { GlimmerRevealStore.shared.record(current.revealedLength, for: revealID) }
        if current.isComplete {
            endReveal()
            reportHeightIfChanged()
            return
        }
        engine = current
        revealMask.update(in: textView, engine: current, now: now)
        reportHeightIfChanged()
        if let wake = current.nextWake {
            clock.wake(at: wake) { [weak self] in self?.advanceReveal() }
        } else {
            clock.cancel()
        }
    }

    private var revealOptions: GlimmerRevealOptions? {
        guard case .smooth(let options) = configuration.reveal, !UIAccessibility.isReduceMotionEnabled else { return nil }
        return options
    }

    private func startRevealIfNeeded() {
        guard engine == nil, isStreaming, let options = revealOptions else { return }
        let resumed = revealID.flatMap { GlimmerRevealStore.shared.revealedLength(for: $0) } ?? 0
        engine = GlimmerRevealEngine(options: options, alreadyRevealed: min(resumed, textView.textStorage.length))
        revealMask.invalidateGeometry()
        textView.layer.mask = revealMask.layer
    }

    private func endReveal() {
        engine = nil
        clock.cancel()
        textView.layer.mask = nil
    }

    // MARK: - Document

    private func preprocessed(_ markdown: String) -> String {
        configuration.extensions.reduce(markdown) { $1.preprocess($0) }
    }

    /// Re-composes everything (theme, configuration or text size changed).
    private func rebuildDocument() {
        let theme = configuration.theme.scaled(for: traitCollection)
        textView.apply(theme: theme)
        document = GlimmerStreamingDocument(composer: GlimmerComposer(
            theme: theme,
            highlighter: configuration.highlighter,
            imageLoader: configuration.imageLoader,
            extensions: configuration.extensions
        ))
        _ = document.update(markdown: preprocessed(markdown), isStreaming: isStreaming)
        textView.attributedText = document.text
        fitTextViewToContent()
        if revealOptions == nil { endReveal() }
        revealMask.invalidateGeometry()
        engine?.textChanged(NSString(string: textView.textStorage.string), isStreaming: isStreaming, now: clock.now)
        advanceReveal()
        reportHeightIfChanged()
    }

    // MARK: - Height

    /// The full document's height at `width` or, while revealing, the bottom of the last revealed line.
    private func height(forWidth width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        if let engine, engine.revealedLength < textView.textStorage.length {
            guard engine.revealedLength > 0 else { return 0 }
            if textView.bounds.width != width {
                let fullHeight = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
                textView.frame = CGRect(x: 0, y: 0, width: width, height: fullHeight)
            }
            return ceil(textView.lineRect(atCharacter: engine.revealedLength - 1)?.maxY ?? 0)
        }
        return textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    /// Keeps the text view as tall as the whole document. TextKit 2 inside a text view lays out only what its viewport
    /// covers (verified in Plan 1's review fix), and the mask needs geometry for text below the revealed line.
    private func fitTextViewToContent() {
        guard bounds.width > 0 else { return }
        let fullHeight = textView.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height
        textView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(bounds.height, fullHeight))
    }

    private func reportHeightIfChanged() {
        let height = height(forWidth: bounds.width)
        guard height != lastReportedHeight else { return }
        lastReportedHeight = height
        invalidateIntrinsicContentSize()
        onHeightChange?()
    }
}

extension GlimmerView: UITextViewDelegate {
    public func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
        guard case .link(let url) = textItem.content else { return defaultAction }
        return linkAction(for: url) ?? defaultAction
    }
}

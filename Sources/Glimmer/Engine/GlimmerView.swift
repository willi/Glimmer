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
    private let viewportTracker = GlimmerViewportTracker()
    /// The reveal's time source; tests substitute a manual clock.
    var clock: any GlimmerRevealClock = GlimmerSystemRevealClock()
    private(set) var markdown = ""
    private(set) var isStreaming = false
    private(set) var revealID: String?
    private(set) var engine: GlimmerRevealEngine?
    /// The worker update in flight, if any. Tests await it.
    private(set) var pendingDocument: Task<Void, Never>?
    /// Main-thread time spent applying the last document change: the spec's "applying one network update" metric.
    private(set) var lastApplyDuration: Duration = .zero

    /// Parses and composes streaming updates off the main thread. Replaced (with its document) on every synchronous
    /// compose, which also drops any result still in flight from the old one.
    private var worker: GlimmerDocumentWorker
    private var requestedUpdate = 0
    private var appliedUpdate = 0
    private var lastWidth: CGFloat = 0
    private var lastReportedHeight: CGFloat = -1
    /// The text's height at the text view's width, as of a text version (see `fitTextViewToContent`).
    private var contentHeight: (version: Int, height: CGFloat)?
    /// The bottom of the last revealed line, for a revealed length and width. Appends after the revealed text do not
    /// move it; edits that reach into the revealed text clear it.
    private var revealedHeight: (revealed: Int, width: CGFloat, height: CGFloat)?
    /// The first character whose layout may have changed since the text view was last measured.
    private var layoutChangedFrom = 0
    /// Embeds that reveal in units (code lines, table rows): document offset → each unit's length.
    private var embedUnits: [Int: [Int]] = [:]

    public init(configuration: GlimmerConfiguration = .default) {
        self.configuration = configuration
        worker = GlimmerDocumentWorker(
            document: GlimmerStreamingDocument(composer: GlimmerComposer(theme: configuration.theme)),
            extensions: configuration.extensions
        )
        super.init(frame: .zero)
        // While revealing, this view is shorter than the text and clips the rest (see `fitTextViewToContent`).
        clipsToBounds = true
        textView.delegate = self
        addSubview(textView)
        rebuildDocument()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: GlimmerView, _: UITraitCollection) in
            view.rebuildDocument()
        }
        viewportTracker.onScroll = { [weak self] in self?.textView.refreshVisibleBandIfNeeded() }
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
        if !isStreaming, engine == nil, pendingDocument == nil {
            // A settled answer: compose now, so the host can size it in this layout pass.
            composeSynchronously()
            return
        }
        requestedUpdate += 1
        if pendingDocument == nil {
            pendingDocument = Task { [weak self] in await self?.drainDocumentUpdates() }
        }
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
        textView.refreshVisibleBandIfNeeded()
        if let engine { revealMask.update(in: textView, engine: engine, now: clock.now) }
        guard bounds.width != lastWidth else { return }
        lastWidth = bounds.width
        reportHeightIfChanged()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        trackScrollViews()
    }

    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        trackScrollViews()
    }

    /// Follows the scroll views above this view while it is in a window.
    private func trackScrollViews() {
        if window == nil { viewportTracker.stop() } else { viewportTracker.track(ancestorsOf: self) }
        textView.setNeedsLayout()
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
        syncEmbedUnits()
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

    private func startRevealIfNeeded(isStreaming: Bool) {
        guard engine == nil, isStreaming, let options = revealOptions else { return }
        let resumed = revealID.flatMap { GlimmerRevealStore.shared.revealedLength(for: $0) } ?? 0
        engine = GlimmerRevealEngine(options: options, alreadyRevealed: min(resumed, textView.textStorage.length))
        revealMask.invalidateGeometry()
        revealedHeight = nil
        textView.layer.mask = revealMask.layer
    }

    /// Shows the frontier embed's started units, one more line or row per unit phrase. Embeds already passed, or not
    /// reached yet, show everything.
    private func syncEmbedUnits() {
        var changedFrom = Int.max
        for offset in embedUnits.keys {
            guard let attachment = textView.blockAttachment(atCharacter: offset) else { continue }
            let visible: Int? = engine.flatMap { engine in
                offset == engine.revealedLength ? max(1, engine.unitsRevealed[offset] ?? 0) : nil
            }
            guard attachment.visibleUnitCount != visible else { continue }
            attachment.visibleUnitCount = visible
            textView.invalidateEmbedLayout(atCharacter: offset)
            layoutChangedFrom = min(layoutChangedFrom, offset)
            changedFrom = min(changedFrom, offset)
        }
        guard changedFrom < .max else { return }
        fitTextViewToContent()
        revealMask.invalidateGeometry(from: changedFrom)
        revealedHeight = nil
    }

    private func endReveal() {
        engine = nil
        syncEmbedUnits()
        clock.cancel()
        textView.layer.mask = nil
    }

    // MARK: - Document

    private func preprocessed(_ markdown: String) -> String {
        configuration.extensions.reduce(markdown) { $1.preprocess($0) }
    }

    /// Re-composes everything (theme, configuration or text size changed).
    private func rebuildDocument() {
        textView.apply(theme: configuration.theme.scaled(for: traitCollection))
        if revealOptions == nil { endReveal() }
        composeSynchronously()
    }

    private func makeDocument() -> GlimmerStreamingDocument {
        GlimmerStreamingDocument(composer: GlimmerComposer(
            theme: configuration.theme.scaled(for: traitCollection),
            highlighter: configuration.highlighter,
            imageLoader: configuration.imageLoader,
            extensions: configuration.extensions
        ))
    }

    /// Composes the whole current markdown on the main thread and restarts the worker from that document.
    private func composeSynchronously() {
        let document = makeDocument()
        _ = document.update(markdown: preprocessed(markdown), isStreaming: isStreaming)
        worker = GlimmerDocumentWorker(document: document, extensions: configuration.extensions)
        appliedUpdate = requestedUpdate
        textView.attributedText = document.text
        apply(GlimmerDocumentResult(edit: nil, embedUnits: document.embedUnits, isStreaming: isStreaming), replacedText: true)
    }

    /// Applies worker results in request order. When one lands, only the latest request is computed next.
    private func drainDocumentUpdates() async {
        while appliedUpdate < requestedUpdate {
            let request = requestedUpdate
            let worker = self.worker
            let result = await worker.update(markdown: markdown, isStreaming: isStreaming)
            // A synchronous compose replaced the worker meanwhile, and already showed this text.
            guard worker === self.worker else { continue }
            apply(result, replacedText: false)
            appliedUpdate = request
        }
        pendingDocument = nil
    }

    /// Everything after the document changed: embed updates, the text edit, fitting, the reveal and the height.
    private func apply(_ result: GlimmerDocumentResult, replacedText: Bool) {
        let started = ContinuousClock.now
        embedUnits = result.embedUnits
        if let edit = result.edit {
            // Grown code blocks and tables update their views in place; the edit then re-lays them out.
            for update in edit.embedUpdates { update.attachment.update(to: update.embed) }
            textView.apply(edit)
            layoutChangedFrom = min(layoutChangedFrom, edit.range.location)
            // Revealed text changed or reflowed (a list turned loose, a header became a table): fading phrases move.
            if let engine, edit.range.location < engine.revealedLength {
                revealMask.invalidateGeometry()
                revealedHeight = nil
            }
        }
        if replacedText {
            layoutChangedFrom = 0
            revealedHeight = nil
            revealMask.invalidateGeometry()
        }
        if replacedText || result.edit != nil { fitTextViewToContent() }
        startRevealIfNeeded(isStreaming: result.isStreaming)
        engine?.textChanged(NSString(string: textView.textStorage.string), isStreaming: result.isStreaming,
                            now: clock.now, embedUnits: embedUnits)
        advanceReveal()
        reportHeightIfChanged()
        lastApplyDuration = ContinuousClock.now - started
    }

    // MARK: - Height

    /// The full document's height at `width` or, while revealing, the bottom of the last revealed line.
    private func height(forWidth width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        if let engine, engine.revealedLength < textView.textStorage.length {
            // An embed at the frontier with units started: its box, as tall as those units, ends the height.
            let frontierEmbed = (engine.unitsRevealed[engine.revealedLength] ?? 0) > 0
            guard engine.revealedLength > 0 || frontierEmbed else { return 0 }
            if textView.bounds.width != width {
                let fullHeight = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
                textView.frame = CGRect(x: 0, y: 0, width: width, height: fullHeight + slack(forContentHeight: fullHeight))
            }
            if let revealedHeight, revealedHeight.revealed == engine.revealedLength, revealedHeight.width == width {
                return revealedHeight.height
            }
            let last = frontierEmbed ? engine.revealedLength : engine.revealedLength - 1
            let height = ceil(textView.lineRect(atCharacter: last)?.maxY ?? 0)
            revealedHeight = (engine.revealedLength, width, height)
            return height
        }
        if width == textView.bounds.width, width == bounds.width {
            if contentHeight?.version != textView.textVersion { fitTextViewToContent() }
            if let contentHeight { return contentHeight.height }
        }
        return textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    /// Keeps the text view at least as tall as the document, with a slack band below it. The text container is
    /// unbounded, so `laidOutHeight()` is exact whatever the frame; the band exists only because resizing a tall text
    /// view costs about as much as laying it out (8–10 ms at 5,000 words), so the frame should change rarely. The band
    /// grows with the text.
    private func fitTextViewToContent() {
        guard bounds.width > 0 else { return }
        if textView.bounds.width != bounds.width {
            // A new width re-wraps everything: measure it in full once.
            let fullHeight = textView.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height
            textView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: fullHeight + slack(forContentHeight: fullHeight))
            layoutChangedFrom = 0
        } else if contentHeight?.version == textView.textVersion {
            return
        }
        let height = textView.laidOutHeight(from: layoutChangedFrom)
        layoutChangedFrom = Int.max
        let slack = slack(forContentHeight: height)
        if textView.bounds.height < height || textView.bounds.height > height + 2 * slack {
            textView.frame.size.height = height + slack
        }
        if textView.bounds.height < bounds.height { textView.frame.size.height = bounds.height }
        contentHeight = (textView.textVersion, height)
    }

    private func slack(forContentHeight height: CGFloat) -> CGFloat {
        max(1_000, height / 4)
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

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
    /// Items appended to the edit menu for a selection (for example "Ask about this").
    public var editMenuActions: ((GlimmerSelection) -> [UIMenuElement])?
    /// Items appended to a link's menu.
    public var linkMenuActions: ((URL) -> [UIMenuElement])?
    /// The text's Find interaction when `configuration.allowsFind` is on. Hosts present it from a toolbar or menu:
    /// `findInteraction?.presentFindNavigator(showingReplace: false)`.
    public var findInteraction: UIFindInteraction? { configuration.allowsFind ? textView.findInteraction : nil }

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
    /// False while the view shows a cached text its worker never composed: the worker's first result then replaces the
    /// whole text instead of applying an edit to it.
    private var viewHoldsWorkerText = true
    /// The cache key of the settled text on screen, or nil (streaming, or edited since it was shown).
    private var cacheKey: GlimmerDocumentCache.Key?
    private var lastWidth: CGFloat = 0
    private var lastReportedHeight: CGFloat = -1
    /// The text's height at the text view's width, as of a text version (see `fitTextViewToContent`).
    private var contentHeight: (version: Int, width: CGFloat, height: CGFloat)?
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
        textView.reusesDrawnText = configuration.reusesDrawnText
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
        if isStreaming, window != nil {
            GlimmerEmbedViewPool.shared.prepareCodeBlockView(
                theme: configuration.theme.scaled(for: traitCollection), highlighter: configuration.highlighter, in: self
            )
        }
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

    /// A host that moves the view without resizing it (content above grew) gives it no layout pass, so the rendered
    /// band would stay where it was: refresh it here.
    public override var frame: CGRect {
        // Outside any animation the host is running: fragment views appear in place, they don't fly in.
        didSet { if frame.origin != oldValue.origin { UIView.performWithoutAnimation { textView.refreshVisibleBandIfNeeded() } } }
    }

    public override var center: CGPoint {
        didSet { if center != oldValue { UIView.performWithoutAnimation { textView.refreshVisibleBandIfNeeded() } } }
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

    /// The markdown for `range` of the shown text (UTF-16 offsets, as in `UITextView.selectedRange`), or — for nil —
    /// the whole answer exactly as last given to `update`. Backs "Copy answer" buttons.
    public func markdownSource(for range: NSRange? = nil) -> String {
        guard let range else { return markdown }
        return GlimmerMarkdownSerializer.markdown(from: textView.textStorage, range: range)
    }

    // MARK: - Accessibility

    /// While a reveal runs the view is one element that reads what is revealed so far. The text view underneath is
    /// hidden, because its unrevealed text is laid out but invisible. At settle the text view takes over, with
    /// line and word navigation and the links rotor. A host may group a settled answer into one element too.
    public override var isAccessibilityElement: Bool {
        get { engine != nil || hostGroupsAnswer == true }
        set { hostGroupsAnswer = newValue }
    }

    /// A host's own choice to group the answer into one element; nil lets the view decide.
    private var hostGroupsAnswer: Bool?

    /// While revealing, the revealed text; for a host-grouped answer without a label of its own, the whole text.
    public override var accessibilityLabel: String? {
        get {
            if let engine {
                let revealed = min(engine.revealedLength, textView.textStorage.length)
                return GlimmerMarkdownSerializer.plainText(
                    from: textView.textStorage, range: NSRange(location: 0, length: revealed), forAccessibility: true
                )
            }
            if hostGroupsAnswer == true, super.accessibilityLabel == nil {
                return GlimmerMarkdownSerializer.plainText(
                    from: textView.textStorage, range: NSRange(location: 0, length: textView.textStorage.length),
                    forAccessibility: true
                )
            }
            return super.accessibilityLabel
        }
        set { super.accessibilityLabel = newValue }
    }

    public override var accessibilityTraits: UIAccessibilityTraits {
        get { engine != nil ? [.staticText, .updatesFrequently] : super.accessibilityTraits }
        set { super.accessibilityTraits = newValue }
    }

    /// The link's default menu plus the host's items.
    func linkMenu(for url: URL, defaultMenu: UIMenu) -> UIMenu {
        guard let linkMenuActions else { return defaultMenu }
        return defaultMenu.replacingChildren(defaultMenu.children + linkMenuActions(url))
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
        if let revealID {
            GlimmerRevealStore.shared.record(
                current.revealedLength, text: textView.textStorage.string as NSString, version: textView.textVersion, for: revealID
            )
        }
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
        let resumed = revealID.flatMap {
            GlimmerRevealStore.shared.revealedLength(for: $0, text: textView.textStorage.string as NSString)
        } ?? 0
        engine = GlimmerRevealEngine(options: options, alreadyRevealed: min(resumed, textView.textStorage.length))
        revealMask.invalidateGeometry()
        revealedHeight = nil
        textView.layer.mask = revealMask.layer
        // VoiceOver reads this view's label (the revealed text) instead: the text view's unrevealed text is laid out.
        textView.accessibilityElementsHidden = true
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
        // Read before `engine` clears: while revealing, this view is the element VoiceOver focuses.
        let hadFocus = engine != nil && accessibilityElementIsFocused()
        engine = nil
        syncEmbedUnits()
        clock.cancel()
        textView.layer.mask = nil
        textView.accessibilityElementsHidden = false
        // Move VoiceOver to the text only when it was on this answer; moving it from elsewhere would yank the reader.
        if hadFocus { UIAccessibility.post(notification: .layoutChanged, argument: textView) }
    }

    // MARK: - Document

    private func preprocessed(_ markdown: String) -> String {
        configuration.extensions.reduce(markdown) { $1.preprocess($0) }
    }

    /// Re-composes everything (theme, configuration or text size changed).
    private func rebuildDocument() {
        textView.reusesDrawnText = configuration.reusesDrawnText
        textView.apply(theme: configuration.theme.scaled(for: traitCollection))
        textView.dataDetectorTypes = configuration.dataDetectors
        textView.isFindInteractionEnabled = configuration.allowsFind
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

    /// Composes the whole current markdown on the main thread and restarts the worker from that document. A settled
    /// answer shown before (same source, theme and extensions) comes from `GlimmerDocumentCache` instead.
    private func composeSynchronously() {
        let theme = configuration.theme.scaled(for: traitCollection)
        let source = preprocessed(markdown)
        let key = GlimmerDocumentCache.Key(
            source: source, theme: theme,
            extensions: configuration.extensions.map { String(reflecting: type(of: $0)) },
            highlighter: String(reflecting: type(of: configuration.highlighter)),
            imageLoader: configuration.imageLoader.map { String(reflecting: type(of: $0)) }
        )
        // An empty answer (every new view starts with one) costs nothing to compose; keep it out of the cache.
        let cacheable = !isStreaming && !source.isEmpty
        if cacheable, let cached = GlimmerDocumentCache.shared.text(for: key) {
            // The worker starts empty; its first result replaces the whole text (see `drainDocumentUpdates`).
            worker = GlimmerDocumentWorker(document: makeDocument(), extensions: configuration.extensions)
            viewHoldsWorkerText = false
            cacheKey = key
            appliedUpdate = requestedUpdate
            textView.renderScreenFirst()
            textView.replaceText(with: cached)
            apply(GlimmerDocumentResult(edit: nil, embedUnits: [:], isStreaming: false), replacedText: true)
            return
        }
        let document = makeDocument()
        _ = document.update(markdown: source, isStreaming: isStreaming)
        if cacheable { GlimmerDocumentCache.shared.store(document.text, for: key) }
        cacheKey = cacheable ? key : nil
        worker = GlimmerDocumentWorker(document: document, extensions: configuration.extensions)
        viewHoldsWorkerText = true
        appliedUpdate = requestedUpdate
        textView.renderScreenFirst()
        textView.replaceText(with: document.text)
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
            if viewHoldsWorkerText {
                apply(result, replacedText: false)
            } else {
                // The view shows a cached text the worker never composed: take its whole text instead of an edit.
                let full = await worker.text().text
                guard worker === self.worker else { continue }
                textView.replaceText(with: full)
                viewHoldsWorkerText = true
                cacheKey = nil
                apply(GlimmerDocumentResult(edit: nil, embedUnits: result.embedUnits, isStreaming: result.isStreaming),
                      replacedText: true)
            }
            appliedUpdate = request
        }
        pendingDocument = nil
    }

    /// Everything after the document changed: embed updates, the text edit, fitting, the reveal and the height.
    private func apply(_ result: GlimmerDocumentResult, replacedText: Bool) {
        let started = ContinuousClock.now
        embedUnits = result.embedUnits
        if let edit = result.edit {
            cacheKey = nil
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
                sizeTextView(width: width, contentHeight: fullHeight)
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
            if contentHeight?.version != textView.textVersion || contentHeight?.width != width { fitTextViewToContent() }
            if let contentHeight { return contentHeight.height }
        }
        if let cacheKey, let cached = GlimmerDocumentCache.shared.height(for: cacheKey, width: width) { return cached }
        let measured = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        if let cacheKey, engine == nil { GlimmerDocumentCache.shared.storeHeight(measured, for: cacheKey, width: width) }
        return measured
    }

    /// The text view's height. Tall enough that an answer never outgrows it, so streaming never resizes the text view:
    /// on an iPhone 16 Pro Max a resize cost up to 9 ms plus the commit after it, the main cause of dropped frames.
    /// The view reports and clips to the content's height; the text container is unbounded and TextKit renders only
    /// the band near the screen, so the extra height costs nothing. Text taller than this doubles it.
    static var textViewHeight: CGFloat = 1_000_000

    /// Sizes the text view for `width`, as tall as `textViewHeight` or twice the content if that is taller.
    private func sizeTextView(width: CGFloat, contentHeight: CGFloat) {
        var height = max(Self.textViewHeight, textView.bounds.height)
        while height < contentHeight { height *= 2 }
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        if textView.frame != frame { textView.frame = frame }
    }

    /// Keeps the text view tall enough for the document and records the document's height. The frame changes only
    /// for a new width, or for text taller than the text view (see `textViewHeight`).
    private func fitTextViewToContent() {
        guard bounds.width > 0 else { return }
        // The text view may already have this width (a size query during a reveal resized it) while the height on
        // record is for another width: that is a width change too.
        let widthChanged = textView.bounds.width != bounds.width || contentHeight?.width != bounds.width
        guard widthChanged || contentHeight?.version != textView.textVersion else { return }
        // A settled answer shown before, whole (a new width, or a replaced text): its height is known.
        if widthChanged || layoutChangedFrom == 0,
           let cached = cacheKey.flatMap({ GlimmerDocumentCache.shared.height(for: $0, width: bounds.width) }) {
            sizeTextView(width: bounds.width, contentHeight: cached)
            layoutChangedFrom = 0
            contentHeight = (textView.textVersion, bounds.width, cached)
            textView.contentHeight = cached
            return
        }
        if widthChanged {
            // A new width re-wraps everything: measure it in full once.
            let fullHeight = textView.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height
            sizeTextView(width: bounds.width, contentHeight: fullHeight)
            layoutChangedFrom = 0
        }
        let height = textView.laidOutHeight(from: layoutChangedFrom)
        layoutChangedFrom = Int.max
        sizeTextView(width: textView.bounds.width, contentHeight: height)
        contentHeight = (textView.textVersion, textView.bounds.width, height)
        textView.contentHeight = height
        if let cacheKey, engine == nil { GlimmerDocumentCache.shared.storeHeight(height, for: cacheKey, width: textView.bounds.width) }
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

    public func textView(
        _ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu
    ) -> UITextItem.MenuConfiguration? {
        guard case .link(let url) = textItem.content, linkMenuActions != nil else { return nil }
        return UITextItem.MenuConfiguration(menu: linkMenu(for: url, defaultMenu: defaultMenu))
    }

    /// While a reveal runs, the selection stops at the revealed text: nobody can select or copy words not shown yet.
    public func textViewDidChangeSelection(_ textView: UITextView) {
        guard let engine else { return }
        let limit = min(engine.revealedLength, textView.textStorage.length)
        let selected = textView.selectedRange
        guard NSMaxRange(selected) > limit else { return }
        let start = min(selected.location, limit)
        textView.selectedRange = NSRange(location: start, length: limit - start)
    }

    public func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let editMenuActions, range.length > 0 else { return nil }
        let selection = GlimmerSelection(
            range: range,
            plainText: GlimmerMarkdownSerializer.plainText(from: textView.textStorage, range: range),
            markdown: GlimmerMarkdownSerializer.markdown(from: textView.textStorage, range: range)
        )
        return UIMenu(children: suggestedActions + editMenuActions(selection))
    }
}

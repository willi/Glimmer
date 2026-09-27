import UIKit
import UniformTypeIdentifiers

/// The TextKit 2 surface for a composed markdown document: selectable, not editable, and never scrolled (the host scrolls).
/// Never read `layoutManager` here — it silently switches the view to TextKit 1.
@MainActor
final class GlimmerTextView: UITextView {
    private(set) var theme: GlimmerTheme = .default
    /// Bumped on every change to the text or its styling; keys measurement caches.
    private(set) var textVersion = 0
    private var lastLayoutWidth: CGFloat = 0
    private var fittedSize: (version: Int, width: CGFloat, height: CGFloat)?
    /// Strongly held: the text layout manager's delegate is weak.
    private let fragmentProvider = GlimmerLayoutFragmentProvider(theme: .default)
    /// The laid-out text's height, set by `GlimmerView`; the frame is much taller (see `GlimmerView.textViewHeight`).
    var contentHeight: CGFloat = 0

    /// VoiceOver frames the text, not the tall frame it is laid out in.
    override var accessibilityFrame: CGRect {
        get {
            let height = contentHeight > 0 ? min(contentHeight, bounds.height) : bounds.height
            return UIAccessibility.convertToScreenCoordinates(CGRect(x: 0, y: 0, width: bounds.width, height: height), in: self)
        }
        set {}
    }

    /// Where Copy writes. The general pasteboard unless a host (or a test) redirects it.
    var pasteboard: UIPasteboard = .general
    /// False for a code block's text, which copies as the code itself.
    var copiesMarkdown = true
    /// Whether a viewport pass hands UIKit back the fragment views it already drew (iOS 27). UIKit otherwise redraws
    /// every fragment in the band on every pass: each scroll step and each streamed edit.
    var reusesDrawnText = true {
        didSet { if !reusesDrawnText { forgetDrawnSurfaces() } }
    }
    private let drawnSurfaces = NSMapTable<NSTextLayoutFragment, UIView>.weakToWeakObjects()
    /// What each drawn surface showed: its size and its rendering attributes (link and find highlights, …).
    private var drawnStates: [ObjectIdentifier: DrawnState] = [:]

    private struct DrawnState: Equatable {
        let size: CGSize
        let rendering: Int
    }

    init() {
        // On iOS 16+, a nil text container gives a TextKit 2 text view.
        super.init(frame: .zero, textContainer: nil)
        backgroundColor = .clear
        isEditable = false
        isSelectable = true
        // Scrolling stays on only so TextKit keeps the text container unbounded. A non-scrolling text view pins the
        // container to its frame height, and with any finite height TextKit finds late text in linear time (about
        // 2 ms per lookup at 5,000 words, against 25 µs). The frame always covers the text, so there is nothing to
        // scroll, and the pan gesture is off so the host's scroll view keeps every drag.
        isScrollEnabled = true
        panGestureRecognizer.isEnabled = false
        bounces = false
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        scrollsToTop = false
        contentInsetAdjustmentBehavior = .never
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        dataDetectorTypes = []
        textLayoutManager?.delegate = fragmentProvider
        apply(theme: .default)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Always zero: the text view never scrolls itself (selection autoscroll, `scrollRangeToVisible`); the host does.
    override var contentOffset: CGPoint {
        get { super.contentOffset }
        set { super.contentOffset = .zero }
    }

    /// Copies the selection as plain text and as markdown (`net.daringfireball.markdown`), so a paste into a
    /// markdown-aware app keeps lists, code and emphasis.
    override func copy(_ sender: Any?) {
        let range = selectedRange
        guard range.length > 0 else { return }
        guard copiesMarkdown else {
            pasteboard.string = (textStorage.string as NSString).substring(with: range)
            return
        }
        let plain = GlimmerMarkdownSerializer.plainText(from: textStorage, range: range)
        let markdown = GlimmerMarkdownSerializer.markdown(from: textStorage, range: range)
        pasteboard.setItems([[
            UTType.utf8PlainText.identifier: plain,
            "net.daringfireball.markdown": Data(markdown.utf8),
        ]])
    }

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        super.setContentOffset(.zero, animated: false)
    }

    /// The pan never begins, so every drag reaches the host's scroll view. (Disabling the recognizer is not enough:
    /// UIKit turns it back on while laying the text view out.)
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === panGestureRecognizer ? false : super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    override var attributedText: NSAttributedString! {
        didSet {
            textVersion &+= 1
            forgetDrawnSurfaces()
        }
    }

    func apply(theme: GlimmerTheme) {
        self.theme = theme
        textVersion &+= 1
        forgetDrawnSurfaces()
        fragmentProvider.theme = theme
        var link: [NSAttributedString.Key: Any] = [.foregroundColor: theme.linkColor]
        if theme.underlinesLinks { link[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        linkTextAttributes = link
    }

    /// Measured by `UITextView`: a full layout at `size.width`, so it is cached per text version and width. Use it only
    /// for a width the view is not laid out at; at the current width `laidOutHeight()` is exact and incremental. The
    /// attachments cache their views, so the provider churn this measurement causes rebuilds nothing.
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard size.width > 0, textStorage.length > 0 else { return CGSize(width: max(size.width, 0), height: 0) }
        if let fittedSize, fittedSize.version == textVersion, fittedSize.width == size.width {
            return CGSize(width: size.width, height: fittedSize.height)
        }
        let fitted = super.sizeThatFits(CGSize(width: size.width, height: CGFloat.greatestFiniteMagnitude))
        fittedSize = (textVersion, size.width, ceil(fitted.height))
        return CGSize(width: size.width, height: ceil(fitted.height))
    }

    /// The height of the laid-out text at the current width, exact at any frame height because the text container is
    /// unbounded (see `init`). Layout is ensured from `index` on: pass the first character that changed since the
    /// last measure, because ensuring the whole document walks every paragraph (about 0.9 ms at 5,000 words) even
    /// when nothing needs layout.
    func laidOutHeight(from index: Int = 0) -> CGFloat {
        guard textStorage.length > 0, let manager = textLayoutManager, let content = manager.textContentManager else { return 0 }
        let start = min(max(0, index), textStorage.length - 1)
        if start == 0 {
            manager.ensureLayout(for: manager.documentRange)
        } else if let location = content.location(content.documentRange.location, offsetBy: start),
                  let range = NSTextRange(location: location, end: content.documentRange.endLocation) {
            manager.ensureLayout(for: range)
        }
        return ceil(manager.usageBoundsForTextContainer.maxY + textContainerInset.top + textContainerInset.bottom)
    }

    override var intrinsicContentSize: CGSize {
        let height = bounds.width > 0 ? sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height : 0
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width != lastLayoutWidth else { return }
        lastLayoutWidth = bounds.width
        invalidateIntrinsicContentSize()
    }

    // MARK: - Streaming edits

    /// Applies a document edit in one TextKit 2 editing transaction, so only the changed paragraphs lay out again.
    /// Replaces the whole text. After a whole-text change, UIKit's first viewport layout asks for the text
    /// container's used rect, which lays out every paragraph inside the view's bounds; in a view as tall as
    /// `GlimmerView.textViewHeight` that is the whole answer (13 ms more for 1,200 words on the simulator). So the swap
    /// happens at 1 pt: `GlimmerView` makes the view tall again right after, before any viewport pass, and TextKit then
    /// renders only the band (31 of 168 paragraphs, against all of them). Not the host's height: a reused cell is
    /// still as tall as its previous answer.
    func replaceText(with text: NSAttributedString) {
        frame.size.height = 1
        attributedText = text
    }

    func apply(_ edit: GlimmerDocumentEdit) {
        if let content = textLayoutManager?.textContentManager as? NSTextContentStorage {
            content.performEditingTransaction {
                textStorage.replaceCharacters(in: edit.range, with: edit.replacement)
            }
        } else {
            textStorage.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        textVersion &+= 1
        invalidateIntrinsicContentSize()
    }

    // MARK: - Reveal geometry

    func textRange(for range: NSRange) -> NSTextRange? {
        guard let content = textLayoutManager?.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length) else { return nil }
        return NSTextRange(location: start, end: end)
    }

    /// Rects covering the glyphs of `range`, one per line segment, in the text view's coordinates.
    func segmentRects(for range: NSRange) -> [CGRect] {
        guard range.length > 0, NSMaxRange(range) <= textStorage.length,
              let manager = textLayoutManager, let textRange = textRange(for: range) else { return [] }
        manager.ensureLayout(for: textRange)
        var rects: [CGRect] = []
        manager.enumerateTextSegments(in: textRange, type: .standard, options: [.rangeNotRequired]) { _, frame, _, _ in
            rects.append(frame)
            return true
        }
        return rects
    }

    /// The line box holding the character at `index`, or nil past the end of the text.
    func lineRect(atCharacter index: Int) -> CGRect? {
        guard index >= 0, index < textStorage.length else { return nil }
        return segmentRects(for: NSRange(location: index, length: 1)).first
    }

    /// The top of the line holding the character at `index`, and the segment rects of that line's text before it.
    /// Lays out and asks about one line, so a phrase start costs the same at the end of a long answer as at its start.
    func settledLine(upTo index: Int) -> (top: CGFloat, rects: [CGRect])? {
        guard index >= 0, index < textStorage.length, let manager = textLayoutManager, let content = manager.textContentManager,
              let location = content.location(content.documentRange.location, offsetBy: index),
              let characterRange = textRange(for: NSRange(location: index, length: 1)) else { return nil }
        manager.ensureLayout(for: characterRange)
        guard let fragment = manager.textLayoutFragment(for: location) else { return nil }
        let paragraphStart = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        let offset = index - paragraphStart
        guard let line = fragment.textLineFragments.first(where: { NSLocationInRange(offset, $0.characterRange) }) else { return nil }
        let top = fragment.layoutFragmentFrame.minY + line.typographicBounds.minY + textContainerInset.top
        let lineStart = paragraphStart + line.characterRange.location
        return (top, index > lineStart ? segmentRects(for: NSRange(location: lineStart, length: index - lineStart)) : [])
    }

    /// Whether the character at `index` begins a visual line: a paragraph start or a wrap point.
    func isLineStart(atCharacter index: Int) -> Bool {
        guard index > 0 else { return true }
        guard let manager = textLayoutManager, let content = manager.textContentManager,
              let location = content.location(content.documentRange.location, offsetBy: index) else { return false }
        // Text appended a moment ago has no line fragments until laid out.
        manager.ensureLayout(for: NSTextRange(location: location))
        guard let fragment = manager.textLayoutFragment(for: location) else { return false }
        let paragraphStart = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        let offsetInParagraph = index - paragraphStart
        return fragment.textLineFragments.contains { $0.characterRange.location == offsetInParagraph }
    }

    // MARK: - Embeds

    /// The block attachment at `index`, or nil.
    func blockAttachment(atCharacter index: Int) -> GlimmerBlockAttachment? {
        guard index >= 0, index < textStorage.length else { return nil }
        return textStorage.attribute(.attachment, at: index, effectiveRange: nil) as? GlimmerBlockAttachment
    }

    /// The reveal-unit rects of the embed at `index`, in this view's coordinates, or nil before its view exists.
    /// Placed from TextKit's attachment frame, not the view's: an invalidated attachment's view is detached, and its
    /// frame lags, until the next viewport pass.
    func embedUnitRects(atCharacter index: Int) -> [CGRect]? {
        guard let view = blockAttachment(atCharacter: index)?.existingView, let manager = textLayoutManager,
              let range = textRange(for: NSRange(location: index, length: 1)) else { return nil }
        manager.ensureLayout(for: range)
        guard let fragment = manager.textLayoutFragment(for: range.location) else { return nil }
        let frame = fragment.frameForTextAttachment(at: range.location)
        guard frame.width > 0, frame.height > 0 else { return nil }
        let origin = CGPoint(x: fragment.layoutFragmentFrame.minX + frame.minX + textContainerInset.left,
                             y: fragment.layoutFragmentFrame.minY + frame.minY + textContainerInset.top)
        return view.revealUnitRects(in: CGRect(origin: .zero, size: frame.size)).map { $0.offsetBy(dx: origin.x, dy: origin.y) }
    }

    /// Lays the embed at `index` out again after its height changed (its visible units).
    func invalidateEmbedLayout(atCharacter index: Int) {
        guard let manager = textLayoutManager, let range = textRange(for: NSRange(location: index, length: 1)) else { return }
        // The fragment keeps its instance through an invalidation; its old pixels must not come back.
        forgetDrawnSurfaces()
        manager.invalidateLayout(for: range)
        manager.ensureLayout(for: range)
        textVersion &+= 1
    }

    // MARK: - Drawn surfaces

    /// Forgets every drawn surface, so the next pass redraws: after changes that keep a fragment but change its pixels.
    func forgetDrawnSurfaces() {
        drawnSurfaces.removeAllObjects()
        drawnStates.removeAll()
    }

    private func drawnState(of fragment: NSTextLayoutFragment) -> DrawnState {
        DrawnState(size: fragment.renderingSurfaceBounds.size, rendering: renderingSignature(of: fragment))
    }

    /// A hash of the rendering attributes over `fragment`'s text: UIKit tints pressed links and find results with them.
    private func renderingSignature(of fragment: NSTextLayoutFragment) -> Int {
        guard let manager = textLayoutManager else { return 0 }
        let range = fragment.rangeInElement
        var hasher = Hasher()
        manager.enumerateRenderingAttributes(from: range.location, reverse: false) { manager, attributes, attributeRange in
            guard attributeRange.location.compare(range.endLocation) == .orderedAscending else { return false }
            hasher.combine(manager.offset(from: range.location, to: attributeRange.location))
            for (key, value) in attributes {
                hasher.combine(key)
                hasher.combine((value as? NSObject)?.hash ?? 0)
            }
            return true
        }
        return hasher.finalize()
    }

    // The iOS 27 SDK's rendering-surface cache hooks (WWDC26: key rendering surfaces by NSTextLayoutFragment), declared
    // by selector so they compile at the iOS 26 floor; iOS 26 never calls them. UITextView implements both, and its
    // implementations are always called: UIKit asserts if the surface it made isn't stored.
    @objc(textViewportLayoutController:retrieveCachedRenderingSurfaceForKey:)
    func retrieveDrawnSurface(_ controller: NSTextViewportLayoutController, key: AnyObject) -> AnyObject? {
        if reusesDrawnText, let fragment = key as? NSTextLayoutFragment, let view = drawnSurfaces.object(forKey: fragment),
           view.superview != nil, !view.isHidden, drawnStates[ObjectIdentifier(fragment)] == drawnState(of: fragment) {
            return view
        }
        let selector = #selector(retrieveDrawnSurface(_:key:))
        guard UITextView.instancesRespond(to: selector), let implementation = class_getMethodImplementation(UITextView.self, selector) else {
            return nil
        }
        typealias Retrieve = @convention(c) (AnyObject, Selector, AnyObject, AnyObject) -> AnyObject?
        return unsafeBitCast(implementation, to: Retrieve.self)(self, selector, controller, key)
    }

    @objc(textViewportLayoutController:cacheRenderingSurface:forKey:)
    func cacheDrawnSurface(_ controller: NSTextViewportLayoutController, surface: AnyObject, key: AnyObject) {
        if canvasView == nil { canvasView = (surface as? UIView)?.superview }
        if reusesDrawnText, let fragment = key as? NSTextLayoutFragment, let view = surface as? UIView {
            drawnSurfaces.setObject(view, forKey: fragment)
            drawnStates[ObjectIdentifier(fragment)] = drawnState(of: fragment)
            if drawnStates.count > 1_024 { pruneDrawnStates() }
        }
        let selector = #selector(cacheDrawnSurface(_:surface:key:))
        guard UITextView.instancesRespond(to: selector), let implementation = class_getMethodImplementation(UITextView.self, selector) else {
            return
        }
        typealias Cache = @convention(c) (AnyObject, Selector, AnyObject, AnyObject, AnyObject) -> Void
        unsafeBitCast(implementation, to: Cache.self)(self, selector, controller, surface, key)
    }

    /// Drops the states of fragments that no longer have a drawn surface.
    private func pruneDrawnStates() {
        var live = Set<ObjectIdentifier>()
        let fragments = drawnSurfaces.keyEnumerator()
        while let fragment = fragments.nextObject() as? NSTextLayoutFragment { live.insert(ObjectIdentifier(fragment)) }
        drawnStates = drawnStates.filter { live.contains($0.key) }
    }

    /// The view UIKit renders fragments into: the superview of the surfaces it hands over. Marking it for layout runs
    /// exactly one viewport pass, in the commit; calling `layoutViewport()` runs one now and UIKit another then.
    private weak var canvasView: UIView?

    /// Re-renders the band: one pass in the next commit through the canvas, or now before the canvas is known.
    private func relayoutViewport() {
        if let canvasView {
            canvasView.setNeedsLayout()
        } else {
            textLayoutManager?.textViewportLayoutController.layoutViewport()
        }
    }

    /// Viewport passes run so far: diagnostics for tests and the benchmark.
    private(set) var viewportPasses = 0

    @available(iOS 27.0, *)
    override func textViewportLayoutControllerWillLayout(_ controller: NSTextViewportLayoutController) {
        viewportPasses += 1
        super.textViewportLayoutControllerWillLayout(controller)
    }

    @available(iOS 27.0, *)
    override func textViewportLayoutControllerDidLayout(_ controller: NSTextViewportLayoutController) {
        super.textViewportLayoutControllerDidLayout(controller)
        schedulePreload()
    }

    // MARK: - Preload

    /// How far past the band, in screen heights, idle frames lay text out: ahead in the scroll direction, and behind.
    /// A band move then renders text that is already laid out (Texture's preload range does the same).
    static let preloadAhead: CGFloat = 1.5
    static let preloadBehind: CGFloat = 0.5
    /// Main-thread time one idle frame spends laying text out ahead.
    static let preloadBudget: Duration = .milliseconds(2)

    /// What TextKit has laid out around the band, in this view's coordinates, or nil before any preload.
    private(set) var preloadedRange: ClosedRange<CGFloat>?
    private var preloading: CADisplayLink?
    /// +1 while the text moves up the screen (reading down), -1 the other way.
    private var scrollDirection: CGFloat = 1
    private var lastScreenMidY: CGFloat?

    /// Starts laying text out ahead in idle frames, if the band's surroundings aren't laid out yet.
    private func schedulePreload() {
        guard preloading == nil, window != nil, !rendersScreenOnly, renderedBand != nil else { return }
        let link = CADisplayLink(target: GlimmerWeakTarget(self), selector: #selector(GlimmerWeakTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        preloading = link
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopPreloading() }
    }

    private func stopPreloading() {
        preloading?.invalidate()
        preloading = nil
    }

    /// Lays out fragments beyond the band for up to `preloadBudget`; stops the display link once the preload range
    /// covers `preloadAhead` screens ahead and `preloadBehind` behind.
    func preloadStep() {
        guard let manager = textLayoutManager, let band = renderedBand, let window, !rendersScreenOnly, band.height > 0 else {
            stopPreloading()
            return
        }
        let screen = window.bounds.height
        let below = band.maxY + screen * (scrollDirection > 0 ? Self.preloadAhead : Self.preloadBehind)
        let above = band.minY - screen * (scrollDirection > 0 ? Self.preloadBehind : Self.preloadAhead)
        let clock = ContinuousClock()
        let deadline = clock.now + Self.preloadBudget
        var lowest = band.maxY
        var highest = band.minY
        var done = true
        // Ahead first, then behind: each walks from the band's edge; laid-out fragments are passed over cheaply.
        for reverse in scrollDirection > 0 ? [false, true] : [true, false] {
            let edge = CGPoint(x: 0, y: reverse ? max(band.minY, 0) : max(band.maxY - 1, 0))
            guard let start = manager.textLayoutFragment(for: edge)?.rangeInElement.location else { continue }
            var options: NSTextLayoutFragment.EnumerationOptions = [.ensuresLayout]
            if reverse { options.insert(.reverse) }
            var finished = false
            manager.enumerateTextLayoutFragments(from: start, options: options) { fragment in
                let frame = fragment.layoutFragmentFrame
                if reverse { highest = min(highest, frame.minY) } else { lowest = max(lowest, frame.maxY) }
                if reverse ? frame.minY <= above : frame.maxY >= below {
                    finished = true
                    return false
                }
                return clock.now < deadline
            }
            // Reaching the text's start or end also finishes a direction.
            if !finished, clock.now < deadline { finished = true }
            if !finished { done = false }
            if clock.now >= deadline { done = false; break }
        }
        preloadedRange = min(highest, band.minY)...max(lowest, band.maxY)
        if done { stopPreloading() }
    }

    // MARK: - Visible band

    /// How far past the screen, in screen heights, TextKit still renders. Enough that a fling lands on rendered text
    /// before the next band update.
    static let bandOverscan: CGFloat = 1
    /// How far, in screen heights, the screen may travel from where the band was centred before it re-renders.
    /// Smaller steps bring in less new text each time: on an iPhone 16 Pro Max a half-screen step cost up to 6.7 ms.
    static let bandRefreshStep: CGFloat = 0.25

    /// The rect TextKit rendered last, in this view's coordinates, or nil while it renders its own viewport.
    private(set) var renderedBand: CGRect?
    /// After a configure, TextKit renders only the screen until the first frame is on screen, then the whole band:
    /// the first frame's layout and drawing are a third of a full band's.
    private(set) var rendersScreenOnly = false
    private var bandWidening: CADisplayLink?

    /// Renders only the screen until the next frame has been presented, then the whole band.
    func renderScreenFirst() {
        rendersScreenOnly = true
        guard bandWidening == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(widenBand))
        link.add(to: .main, forMode: .common)
        bandWidening = link
    }

    @objc private func widenBand() {
        bandWidening?.invalidate()
        bandWidening = nil
        guard rendersScreenOnly else { return }
        rendersScreenOnly = false
        relayoutViewport()
    }

    private var overscan: CGFloat { rendersScreenOnly ? 0 : Self.bandOverscan }

    /// This view's part within `overscan` screens of its window's bounds, full width. It is zero-height off screen
    /// or outside a window (a cell sized before it is shown renders nothing), and nil before the view has a width.
    func visibleBand() -> CGRect? {
        guard bounds.width > 0 else { return nil }
        guard let window else { return CGRect(x: 0, y: 0, width: bounds.width, height: 0) }
        let screen = convert(window.bounds, from: window)
        let band = screen.insetBy(dx: 0, dy: -window.bounds.height * overscan).intersection(bounds)
        guard !band.isNull else { return CGRect(x: 0, y: 0, width: bounds.width, height: 0) }
        return CGRect(x: 0, y: band.minY, width: bounds.width, height: band.height)
    }

    /// Re-renders once the screen has travelled `bandRefreshStep` screens from where the band was centred, or, while
    /// only the screen is rendered, as soon as any of the screen is not.
    func refreshVisibleBandIfNeeded() {
        guard let window, let rendered = renderedBand else { return }
        let screen = convert(window.bounds, from: window).intersection(bounds)
        guard !screen.isNull else { return }
        if let lastScreenMidY, screen.midY != lastScreenMidY { scrollDirection = screen.midY > lastScreenMidY ? 1 : -1 }
        lastScreenMidY = screen.midY
        let margin = max(0, overscan - Self.bandRefreshStep)
        let needed = screen.insetBy(dx: 0, dy: -window.bounds.height * margin).intersection(bounds)
        if !rendered.contains(needed) { relayoutViewport() }
    }

    /// TextKit renders whatever this returns. Public from iOS 27, where it is the band around the screen: without it,
    /// TextKit renders the whole bounds of this full-height view — every paragraph of a long answer, on every change.
    @available(iOS 27.0, *)
    override func viewportBounds(for textViewportLayoutController: NSTextViewportLayoutController) -> CGRect {
        // UIKit calls this on older systems too (the text view has always been its viewport's delegate), where it is
        // untested: keep TextKit's own viewport there.
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)),
              let band = visibleBand() else {
            renderedBand = nil
            return super.viewportBounds(for: textViewportLayoutController)
        }
        renderedBand = band
        return band
    }
}

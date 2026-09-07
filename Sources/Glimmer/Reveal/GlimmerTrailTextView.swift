import UIKit
import os

/// A native TextKit 2 text view that reveals an attributed stream with a soft,
/// continuously settling trail. Supply UIKit attributes (`UIFont`, `UIColor`,
/// paragraph styles and links); this view does not parse markdown.
///
/// Use `update(attributedText:isStreaming:)` to replace or append the producer's
/// full buffer. Existing text keeps its progress when the buffer grows. The
/// inherited `attributedText` contains the currently revealed prefix. Configure
/// links and selection through the standard `UITextView` APIs and delegate.
/// Do not access `layoutManager`: UIKit switches to TextKit 1 when it is read.
/// This view owns `layer.mask` while revealing; apply other masks to a wrapper.
@MainActor
public final class GlimmerTrailTextView: UITextView {
    public private(set) var isStreaming = false

    /// Whether buffered words or the last word's fade still need to finish.
    /// This becomes false during a producer pause once the visible trail settles.
    public var isRevealing: Bool { visibleLength < buffer.length || !activeWords.isEmpty }

    private struct ActiveWord {
        let range: NSRange
        let startedAt: Double
    }

    private struct FadingWord {
        let range: NSRange
        let opacity: Double
    }

    private var buffer = NSAttributedString(string: "")
    private var boundaries: [Int] = []
    private var nextBoundary = 0
    private var visibleLength = 0
    private var activeWords: [ActiveWord] = []
    private var nextRevealAt: Double?
    private var updateLink: UIUpdateLink?
    private var trailMask: TrailOpacityMaskLayer?
    private var fadingWords: [FadingWord] = []
    private var wordRectangles: [NSRange: [CGRect]] = [:]
    private var geometryBounds: CGRect = .null
    private var isUpdatingMask = false
    private var now: () -> Double = { CACurrentMediaTime() }
    private var reduceMotion: () -> Bool = { UIAccessibility.isReduceMotionEnabled }

    public init(frame: CGRect = .zero) {
        // A nil container uses TextKit 2. Never touch NSLayoutManager, including
        // for measuring or hit testing; UITextView handles both natively.
        super.init(frame: frame, textContainer: nil)
        configure()
    }

    @available(*, unavailable, message: "Create GlimmerTrailTextView programmatically to ensure TextKit 2.")
    public required init?(coder: NSCoder) {
        fatalError("Create GlimmerTrailTextView programmatically to ensure TextKit 2.")
    }

    /// Deterministic clock/accessibility injection; no production per-word timers.
    init(now: @escaping () -> Double, reduceMotion: @escaping () -> Bool = { false }) {
        self.now = now
        self.reduceMotion = reduceMotion
        super.init(frame: .zero, textContainer: nil)
        configure()
    }

    private func configure() {
        isEditable = false
        isSelectable = true
        isScrollEnabled = false
        backgroundColor = .clear
        textColor = .label
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        // Preserve the producer's link font/color while keeping native link
        // interaction. Uncolored links use textColor, like other uncolored text;
        // supply UIColor.link in the attributed buffer for the system link color.
        linkTextAttributes = [:]
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reduceMotionDidChange),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
    }

    /// Updates the full attributed buffer. Attribute-only updates preserve reveal
    /// progress. A replacement starts a fresh reveal; an append continues it.
    /// Ending streaming lets the remaining words and their fade finish naturally.
    public func update(attributedText: NSAttributedString, isStreaming: Bool) {
        let time = now()
        self.isStreaming = isStreaming
        let sameText = buffer.string.utf16.elementsEqual(attributedText.string.utf16)
        if sameText && buffer.isEqual(to: attributedText) {
            // Producer completion toggles and repeated packets must not replace
            // text storage, disturb selection, or tokenize the buffer again.
            advance(at: time)
            refreshUpdateLink()
            return
        }
        let appended = isAppend(attributedText.string)
        let visibleRange = NSRange(location: 0, length: visibleLength)
        let prefixChanged = !appended || !buffer.attributedSubstring(from: visibleRange).isEqual(
            to: attributedText.attributedSubstring(from: visibleRange)
        )
        if !appended {
            removeTrailMask()
            visibleLength = 0
            activeWords.removeAll(keepingCapacity: true)
            fadingWords.removeAll(keepingCapacity: true)
            nextRevealAt = nil
        }
        // Take a copy so a producer's mutable attributed string cannot change
        // ranges underneath the frame callback.
        buffer = NSAttributedString(attributedString: attributedText)
        if !sameText { boundaries = Self.wordBoundaries(in: buffer.string) }
        nextBoundary = boundaries.firstIndex(where: { $0 > visibleLength }) ?? boundaries.count
        setVisiblePrefix(length: visibleLength, replacing: prefixChanged)
        if reduceMotion() || textLayoutManager == nil {
            finishImmediately()
            return
        }
        if visibleLength < buffer.length, nextRevealAt == nil {
            nextRevealAt = time
        }
        advance(at: time)
        refreshUpdateLink()
    }

    /// Reveals and settles the current buffer without animation. Future appends
    /// still animate; this does not change the producer's streaming flag.
    public func finishImmediately() {
        removeTrailMask()
        activeWords.removeAll(keepingCapacity: true)
        fadingWords.removeAll(keepingCapacity: true)
        nextRevealAt = nil
        nextBoundary = boundaries.count
        setVisiblePrefix(length: buffer.length)
        refreshUpdateLink()
    }

    /// Clears both text and reveal progress for reuse with a different message.
    public func reset() {
        buffer = NSAttributedString(string: "")
        boundaries.removeAll(keepingCapacity: true)
        activeWords.removeAll(keepingCapacity: true)
        fadingWords.removeAll(keepingCapacity: true)
        nextBoundary = 0
        nextRevealAt = nil
        isStreaming = false
        removeTrailMask()
        setVisiblePrefix(length: 0)
        refreshUpdateLink()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            // Resume pending words at normal cadence instead of treating the
            // time spent in a reused/offscreen cell as a giant animation frame.
            if visibleLength < buffer.length { nextRevealAt = now() }
            advance(at: now())
        } else {
            removeTrailMask()
        }
        refreshUpdateLink()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateMaskPresentation()
    }

    @objc private func reduceMotionDidChange() {
        if reduceMotion() { finishImmediately() }
    }

    private func refreshUpdateLink() {
        let shouldRun = window != nil && isRevealing && !reduceMotion()
        if shouldRun, updateLink == nil {
            updateLink = UIUpdateLink(view: self) { [weak self] _, _ in
                guard let self else { return }
                self.advance(at: self.now())
                self.refreshUpdateLink()
            }
        }
        updateLink?.requiresContinuousUpdates = shouldRun
        updateLink?.isEnabled = shouldRun
        if !shouldRun { updateLink = nil }
    }

    /// Advances drawing using elapsed time. Testable without sleeping or a window.
    func advance(at time: Double) {
        if reduceMotion() || textLayoutManager == nil {
            finishImmediately()
            return
        }
        if let due = nextRevealAt, time >= due, nextBoundary < boundaries.count {
            let end = boundaries[nextBoundary]
            let range = NSRange(location: visibleLength, length: end - visibleLength)
            nextBoundary += 1
            setVisiblePrefix(length: end)
            if range.length > 0 { activeWords.append(ActiveWord(range: range, startedAt: time)) }
            let remaining = boundaries.count - nextBoundary
            // Keep bursty streams responsive without skipping words. At most one
            // word unlocks per display update; the fade itself is frame independent.
            let cadence = RevealPacing.intervalSeconds(
                style: .smoothTrail,
                behind: remaining,
                catchUp: .adaptive(maxLagSeconds: 1.5),
                jitter: 0.5
            )
            nextRevealAt = remaining > 0 ? time + cadence : nil
        }
        applyTrail(at: time)
    }

    private func setVisiblePrefix(length: Int, replacing: Bool = false) {
        let previousLength = visibleLength
        visibleLength = min(max(0, length), buffer.length)
        guard replacing || visibleLength != previousLength || textStorage.length != previousLength else { return }
        // Only producer updates and word unlocks touch the text storage. Display
        // frames update a compositing mask over cached native text geometry.
        if replacing || visibleLength < previousLength || textStorage.length != previousLength {
            super.attributedText = buffer.attributedSubstring(from: NSRange(location: 0, length: visibleLength))
        } else if visibleLength > previousLength {
            textStorage.append(buffer.attributedSubstring(from: NSRange(
                location: previousLength,
                length: visibleLength - previousLength
            )))
        }
        wordRectangles.removeAll(keepingCapacity: true)
        invalidateIntrinsicContentSize()
    }

    private func applyTrail(at time: Double) {
        activeWords.removeAll { time - $0.startedAt >= RevealSmoothTrail.duration }
        fadingWords = activeWords.map { word in
            FadingWord(range: word.range, opacity: RevealSmoothTrail.opacity(age: time - word.startedAt))
        }
        if activeWords.isEmpty {
            // Removing the compositor entirely guarantees the final pixels use
            // the original text, even when TextKit retains its drawing cache.
            removeTrailMask()
        } else {
            updateMaskPresentation()
        }
    }

    private func updateMaskPresentation() {
        guard !isUpdatingMask else { return }
        guard window != nil, !fadingWords.isEmpty, bounds.width > 0, bounds.height > 0 else {
            removeTrailMask()
            return
        }
        isUpdatingMask = true
        defer { isUpdatingMask = false }

        if geometryBounds != bounds {
            geometryBounds = bounds
            wordRectangles.removeAll(keepingCapacity: true)
        }
        var regions: [TrailMaskRegion] = []
        for word in fadingWords {
            let rectangles: [CGRect]
            if let cached = wordRectangles[word.range] {
                rectangles = cached
            } else {
                rectangles = nativeRectangles(for: word.range)
                wordRectangles[word.range] = rectangles
            }
            regions.append(contentsOf: rectangles.map { TrailMaskRegion(rect: $0, opacity: word.opacity) })
        }
        let activeRanges = Set(fadingWords.map(\.range))
        wordRectangles = wordRectangles.filter { activeRanges.contains($0.key) }

        let mask = trailMask ?? TrailOpacityMaskLayer()
        trailMask = mask
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.frame = bounds
        mask.contentsScale = traitCollection.displayScale
        mask.update(bounds: CGRect(origin: .zero, size: bounds.size), regions: regions)
        if layer.mask !== mask { layer.mask = mask }
        CATransaction.commit()
    }

    private func nativeRectangles(for range: NSRange) -> [CGRect] {
        guard let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length),
              let range = textRange(from: start, to: end)
        else { return [] }
        return selectionRects(for: range).compactMap { selection in
            let rect = selection.rect
            guard !rect.isNull, !rect.isInfinite, rect.width > 0, rect.height > 0 else { return nil }
            return rect.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
        }
    }

    private func removeTrailMask() {
        if let trailMask, layer.mask === trailMask {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.mask = nil
            CATransaction.commit()
        }
        trailMask = nil
        wordRectangles.removeAll(keepingCapacity: true)
    }

    private func isAppend(_ newString: String) -> Bool {
        let old = buffer.string
        // Both checks matter: exact UTF-16 rejects canonically equivalent
        // re-encoding; Character comparison rejects an arriving combining/ZWJ
        // suffix that would extend the old final grapheme across its boundary.
        return newString.utf16.starts(with: old.utf16) && newString.prefix(old.count) == old
    }

    private static func wordBoundaries(in string: String) -> [Int] {
        var result: [Int] = []
        var offset = 0
        var previousWasWhitespace = true
        for character in string {
            let whitespace = character.isWhitespace
            if !whitespace && previousWasWhitespace && offset > 0 { result.append(offset) }
            offset += character.utf16.count
            previousWasWhitespace = whitespace
        }
        if offset > 0 { result.append(offset) }
        return result
    }

    var isFrameUpdatesEnabled: Bool { updateLink?.isEnabled == true }

    /// Temporal mask input, available without a window for deterministic tests.
    func trailOpacity(atUTF16Offset offset: Int) -> Double {
        fadingWords.first(where: { NSLocationInRange(offset, $0.range) })?.opacity ?? 1
    }
}

private struct TrailMaskRegion: Sendable, Equatable {
    let rect: CGRect
    let opacity: Double
}

/// A drawing-only layer; immutable snapshots cross the Core Animation drawing
/// boundary under a lock, without accessing the main-actor text view.
private final class TrailOpacityMaskLayer: CALayer, @unchecked Sendable {
    private struct Snapshot: Sendable, Equatable {
        var bounds: CGRect = .zero
        var regions: [TrailMaskRegion] = []
    }

    private let drawingState = OSAllocatedUnfairLock(initialState: Snapshot())

    override init() {
        super.init()
        actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
    }

    override init(layer: Any) {
        super.init(layer: layer)
        if let source = layer as? TrailOpacityMaskLayer {
            let snapshot = source.drawingState.withLock { $0 }
            drawingState.withLock { $0 = snapshot }
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func update(bounds: CGRect, regions: [TrailMaskRegion]) {
        let snapshot = Snapshot(bounds: bounds, regions: regions)
        let changed = drawingState.withLock { state in
            guard state != snapshot else { return false }
            state = snapshot
            return true
        }
        if changed { setNeedsDisplay() }
    }

    override func draw(in context: CGContext) {
        let snapshot = drawingState.withLock { $0 }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(snapshot.bounds)
        context.setBlendMode(.copy)
        for region in snapshot.regions {
            context.setFillColor(gray: 1, alpha: region.opacity)
            context.fill(region.rect)
        }
    }
}

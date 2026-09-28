import UIKit

/// A fenced code block: a header (language + Copy) above selectable, syntax-colored code that scrolls
/// horizontally instead of wrapping. Its height does not depend on width.
@MainActor
final class GlimmerCodeBlockView: UIView, GlimmerEmbedView, UITextViewDelegate {
    static let headerHeight: CGFloat = 44

    private(set) var code: String
    private(set) var language: String?
    /// Scrolls the unwrapped code horizontally. A TextKit 2 `UITextView` resets its container to its own width, so
    /// the text view itself never scrolls; it is sized to the full line width inside this scroll view instead.
    let scrollView = UIScrollView()
    /// The document text view's configuration suits code too: an unbounded container (a taller frame as lines stream
    /// in re-lays out nothing) and rendering only the band near the screen.
    let textView = GlimmerTextView()
    let copyButton = UIButton(type: .system)
    let languageLabel = UILabel()
    /// Where Copy writes — the button and a selection's Copy alike. The general pasteboard unless a host redirects it.
    var pasteboard: UIPasteboard = .general {
        didSet { textView.pasteboard = pasteboard }
    }

    /// Moves the text view's band as scroll views above scroll: the answer's own tracker moves only the answer's band.
    private let viewportTracker = GlimmerViewportTracker()

    private let theme: GlimmerTheme
    /// Settable so a prepared view (`GlimmerEmbedViewPool`) takes the highlighter of the block it shows.
    var highlighter: any GlimmerHighlighter
    private var highlighted: NSAttributedString
    /// A standalone TextKit 2 layout of the unwrapped code, its container unbounded both ways so each code line is one
    /// fragment. Kept across streaming updates, so only the lines that changed are measured again.
    private let metricsStorage = NSTextContentStorage()
    private let metricsManager = NSTextLayoutManager()
    /// The highlighted code's colour runs, from the last update.
    private var runs: [ColorRun] = []
    /// Bottom of each code line, cumulative, and each line's width.
    private var lineBottoms: [CGFloat] = []
    private var lineWidths: [CGFloat] = []

    var visibleUnitCount: Int? {
        didSet {
            guard visibleUnitCount != oldValue else { return }
            textViewDidChangeSelection(textView)
            setNeedsLayout()
        }
    }

    /// `highlighted` is the code as the composer styled it on the worker; nil highlights it here.
    init(
        code: String, language: String?, theme: GlimmerTheme, highlighter: any GlimmerHighlighter,
        highlighted: NSAttributedString? = nil
    ) {
        self.code = code
        self.language = language
        self.theme = theme
        self.highlighter = highlighter
        self.highlighted = highlighted
            ?? GlimmerCodeHighlighting.highlightedCode(code, language: language, theme: theme, highlighter: highlighter)
        super.init(frame: .zero)

        backgroundColor = theme.codeBlockBackground
        layer.cornerRadius = theme.embedCornerRadius
        layer.cornerCurve = .continuous
        clipsToBounds = true

        let padding = theme.embedPadding
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: padding, left: padding, bottom: padding, right: padding)
        textView.setText(self.highlighted)
        textView.copiesMarkdown = false
        textView.delegate = self
        let container = NSTextContainer(size: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 0))
        container.lineFragmentPadding = 0
        metricsManager.textContainer = container
        metricsStorage.addTextLayoutManager(metricsManager)
        // Backed by a text storage, so streaming edits can replace just the changed lines.
        metricsStorage.textStorage = NSTextStorage(attributedString: self.highlighted)
        measureLines(fromLine: 0, at: 0)
        runs = Self.colorRuns(of: self.highlighted)
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.addSubview(textView)
        addSubview(scrollView)

        languageLabel.text = language?.lowercased() ?? "code"
        languageLabel.font = theme.captionFont
        languageLabel.textColor = theme.secondaryTextColor
        copyButton.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
        copyButton.tintColor = theme.secondaryTextColor
        copyButton.accessibilityLabel = GlimmerStrings.copyCode
        copyButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            pasteboard.string = (self.code as NSString).substring(to: self.revealedCodeLength)
        }, for: .primaryActionTriggered)
        if theme.showsCodeBlockHeader {
            addSubview(languageLabel)
            addSubview(copyButton)
        }
        // VoiceOver: "Code, swift", then the code, then the Copy button. The header label would repeat the language.
        textView.accessibilityLabel = language.map(GlimmerStrings.code(language:)) ?? GlimmerStrings.code
        languageLabel.isAccessibilityElement = false
        accessibilityElements = theme.showsCodeBlockHeader ? [textView, copyButton] : [textView]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The clipped lines remain in TextKit for layout, but selection and Copy must not expose them yet.
    private var revealedCodeLength: Int {
        guard let visibleUnitCount else { return (code as NSString).length }
        guard visibleUnitCount > 0 else { return 0 }
        var lines = 0
        for (offset, unit) in code.utf16.enumerated() where unit == 0x0A {
            lines += 1
            if lines == visibleUnitCount { return offset + 1 }
        }
        return (code as NSString).length
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        let selected = textView.selectedRange
        guard visibleUnitCount != nil, NSMaxRange(selected) > 0 else { return }
        let limit = revealedCodeLength
        guard NSMaxRange(selected) > limit else { return }
        let start = min(selected.location, limit)
        textView.selectedRange = NSRange(location: start, length: limit - start)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return viewportTracker.stop() }
        viewportTracker.onScroll = { [weak self] in self?.textView.refreshVisibleBandIfNeeded() }
        viewportTracker.track(ancestorsOf: self)
        textView.refreshVisibleBandIfNeeded()
    }

    /// The answer moves the block when text above it changes; the band follows, as for `GlimmerView`.
    override var frame: CGRect {
        didSet { if frame.origin != oldValue.origin { UIView.performWithoutAnimation { textView.refreshVisibleBandIfNeeded() } } }
    }

    override var center: CGPoint {
        didSet { if center != oldValue { UIView.performWithoutAnimation { textView.refreshVisibleBandIfNeeded() } } }
    }

    /// Unwrapped size of the highlighted code.
    var textSize: CGSize {
        CGSize(width: lineWidths.max() ?? 0, height: bottoms.last ?? 0)
    }

    private var bottoms: [CGFloat] {
        lineBottoms.isEmpty ? [ceil(theme.codeFont.lineHeight)] : lineBottoms
    }

    /// Measures the lines from `line` (which starts at UTF-16 offset `location`) to the end; earlier lines keep theirs.
    private func measureLines(fromLine line: Int, at location: Int) {
        lineBottoms.removeSubrange(min(line, lineBottoms.count)...)
        lineWidths.removeSubrange(min(line, lineWidths.count)...)
        guard let content = metricsManager.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: location) else { return }
        metricsManager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            lineBottoms.append(ceil(fragment.layoutFragmentFrame.maxY))
            lineWidths.append(fragment.textLineFragments.map { ceil($0.typographicBounds.width) }.max() ?? 0)
            return true
        }
    }

    /// The height of the lines shown: all of them, or the first `visibleUnitCount` while a reveal runs.
    private var visibleTextHeight: CGFloat {
        let bottoms = bottoms
        let count = visibleUnitCount.map { min(max($0, 1), bottoms.count) } ?? bottoms.count
        return bottoms[count - 1]
    }

    func embedHeight(forWidth width: CGFloat) -> CGFloat {
        (theme.showsCodeBlockHeader ? Self.headerHeight : 0) + theme.embedPadding * 2 + visibleTextHeight
    }

    func revealUnitRects(in box: CGRect) -> [CGRect] {
        let top = (theme.showsCodeBlockHeader ? Self.headerHeight : 0) + theme.embedPadding
        var rects: [CGRect] = []
        var previous: CGFloat = 0
        for (index, bottom) in bottoms.enumerated() {
            // The first line also covers the header and top padding.
            let minY = index == 0 ? 0 : top + previous
            rects.append(CGRect(x: 0, y: minY, width: box.width, height: top + bottom - minY))
            previous = bottom
        }
        return extendingLastVisibleUnit(rects, in: box)
    }

    /// A span of one colour in highlighted code.
    struct ColorRun: Equatable {
        let range: NSRange
        let color: UIColor?
    }

    static func colorRuns(of text: NSAttributedString) -> [ColorRun] {
        var runs: [ColorRun] = []
        text.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            runs.append(ColorRun(range: range, color: value as? UIColor))
        }
        return runs
    }

    /// Streams in place. The composer highlights the whole code on the worker (a closing `*/` can recolor earlier
    /// lines, and hosts bring their own highlighters); only the lines from the first one whose text or colours changed
    /// reach TextKit and are measured.
    func update(to embed: GlimmerEmbed) {
        guard case .codeBlock(let language, let code, let highlighted) = embed,
              code != self.code || language != self.language else { return }
        self.code = code
        if language != self.language {
            languageLabel.text = language?.lowercased() ?? "code"
            textView.accessibilityLabel = language.map(GlimmerStrings.code(language:)) ?? GlimmerStrings.code
        }
        self.language = language
        let old = self.highlighted
        self.highlighted = highlighted
            ?? GlimmerCodeHighlighting.highlightedCode(code, language: language, theme: theme, highlighter: highlighter)
        let newString = self.highlighted.string as NSString
        let newRuns = Self.colorRuns(of: self.highlighted)
        // The first change: where the text first differs, or where the colours first do (a closing `*/` recolours
        // earlier lines). Colour is the only attribute that varies inside code, and comparing runs is much cheaper
        // than comparing attributed strings.
        let textChange = (old.string as NSString).commonPrefix(with: newString as String, options: .literal).utf16.count
        let colorChange = (0..<min(runs.count, newRuns.count)).first { runs[$0] != newRuns[$0] }.map { index in
            // Runs before it match, so both start here: a new colour changes from the start, a longer or shorter run
            // from where the shorter one ends (plain code is one run that grows with every update).
            runs[index].color == newRuns[index].color
                ? min(NSMaxRange(runs[index].range), NSMaxRange(newRuns[index].range))
                : runs[index].range.location
        } ?? min(runs.last.map { NSMaxRange($0.range) } ?? 0, newRuns.last.map { NSMaxRange($0.range) } ?? 0)
        runs = newRuns
        let change = min(textChange, colorChange)
        // Replace from the start of the line holding the change to the end.
        let before = NSRange(location: 0, length: min(change, newString.length))
        let newline = newString.range(of: "\n", options: .backwards, range: before)
        let lineStart = newline.location == NSNotFound ? 0 : NSMaxRange(newline)
        let edit = GlimmerDocumentEdit(
            range: NSRange(location: lineStart, length: old.length - lineStart),
            replacement: self.highlighted.attributedSubstring(from: NSRange(location: lineStart, length: newString.length - lineStart))
        )
        textView.apply(edit)
        metricsStorage.performEditingTransaction {
            metricsStorage.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        // UTF-16 units, not Characters: this runs on main for every streamed chunk.
        let unchangedLines = old.string.utf16.prefix(lineStart).reduce(0) { $0 + ($1 == 0x0A ? 1 : 0) }
        measureLines(fromLine: unchangedLines, at: lineStart)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let headerHeight = theme.showsCodeBlockHeader ? Self.headerHeight : 0
        if theme.showsCodeBlockHeader {
            copyButton.frame = CGRect(x: bounds.width - headerHeight, y: 0, width: headerHeight, height: headerHeight)
            languageLabel.frame = CGRect(
                x: theme.embedPadding, y: 0,
                width: max(0, copyButton.frame.minX - theme.embedPadding), height: headerHeight
            )
        }
        // While revealing, glyphs stop at the last shown line, so the next line never peeks into the bottom padding.
        let glyphHeight = visibleUnitCount == nil ? bounds.height - headerHeight : theme.embedPadding + visibleTextHeight
        scrollView.frame = CGRect(x: 0, y: headerHeight, width: bounds.width, height: max(0, min(glyphHeight, bounds.height - headerHeight)))
        // +2 absorbs rounding between measurement and layout so the last glyph never wraps.
        let contentWidth = max(bounds.width, textSize.width + theme.embedPadding * 2 + 2)
        // The text view's width steps in 256 pt, so a streamed line that is a little longer does not change its
        // container (which would re-lay out every line); the scroll view scrolls only to the real width.
        let textWidth = max(bounds.width, ceil(contentWidth / 256) * 256)
        // Every line stays laid out; while revealing, this view is shorter and the scroll view clips the rest. The
        // content size keeps the visible height, so the code never scrolls vertically.
        textView.frame = CGRect(x: 0, y: 0, width: textWidth, height: textSize.height + theme.embedPadding * 2)
        scrollView.contentSize = CGSize(width: contentWidth, height: scrollView.bounds.height)
    }
}

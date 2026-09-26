import UIKit

/// A fenced code block: a header (language + Copy) above selectable, syntax-colored code that scrolls
/// horizontally instead of wrapping. Its height does not depend on width.
@MainActor
final class GlimmerCodeBlockView: UIView, GlimmerEmbedView {
    static let headerHeight: CGFloat = 44

    private(set) var code: String
    private(set) var language: String?
    /// Scrolls the unwrapped code horizontally. A TextKit 2 `UITextView` resets its container to its own width, so
    /// the text view itself never scrolls; it is sized to the full line width inside this scroll view instead.
    let scrollView = UIScrollView()
    let textView = UITextView(usingTextLayoutManager: true)
    let copyButton = UIButton(type: .system)
    let languageLabel = UILabel()
    /// Where Copy writes. The general pasteboard unless a host redirects it.
    var pasteboard: UIPasteboard = .general

    private let theme: GlimmerTheme
    private let highlighter: any GlimmerHighlighter
    private var highlighted: NSAttributedString
    /// Bottom of each code line in the unwrapped text, cumulative, and the widest line: TextKit 2, measured once.
    private var lineMetrics: (bottoms: [CGFloat], width: CGFloat)?

    var visibleUnitCount: Int? {
        didSet { if visibleUnitCount != oldValue { setNeedsLayout() } }
    }

    init(code: String, language: String?, theme: GlimmerTheme, highlighter: any GlimmerHighlighter) {
        self.code = code
        self.language = language
        self.theme = theme
        self.highlighter = highlighter
        highlighted = Self.highlightedCode(code, language: language, theme: theme, highlighter: highlighter)
        super.init(frame: .zero)

        backgroundColor = theme.codeBlockBackground
        layer.cornerRadius = theme.embedCornerRadius
        layer.cornerCurve = .continuous
        clipsToBounds = true

        let padding = theme.embedPadding
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: padding, left: padding, bottom: padding, right: padding)
        textView.textContainer.lineFragmentPadding = 0
        textView.attributedText = highlighted
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.addSubview(textView)
        addSubview(scrollView)

        languageLabel.text = language?.lowercased() ?? "code"
        languageLabel.font = theme.captionFont
        languageLabel.textColor = theme.secondaryTextColor
        copyButton.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
        copyButton.tintColor = theme.secondaryTextColor
        copyButton.accessibilityLabel = "Copy code"
        copyButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            pasteboard.string = self.code
        }, for: .primaryActionTriggered)
        if theme.showsCodeBlockHeader {
            addSubview(languageLabel)
            addSubview(copyButton)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Unwrapped size of the highlighted code.
    var textSize: CGSize {
        CGSize(width: lines.width, height: lines.bottoms.last ?? 0)
    }

    /// Measured with a standalone TextKit 2 layout manager whose container is unbounded both ways, so each code line
    /// is one layout fragment.
    private var lines: (bottoms: [CGFloat], width: CGFloat) {
        if let lineMetrics { return lineMetrics }
        let storage = NSTextContentStorage()
        let manager = NSTextLayoutManager()
        let container = NSTextContainer(size: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 0))
        container.lineFragmentPadding = 0
        manager.textContainer = container
        storage.addTextLayoutManager(manager)
        storage.attributedString = highlighted
        manager.ensureLayout(for: manager.documentRange)
        var bottoms: [CGFloat] = []
        var width: CGFloat = 0
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) { fragment in
            bottoms.append(ceil(fragment.layoutFragmentFrame.maxY))
            for line in fragment.textLineFragments { width = max(width, ceil(line.typographicBounds.width)) }
            return true
        }
        if bottoms.isEmpty { bottoms = [ceil(theme.codeFont.lineHeight)] }
        let metrics = (bottoms, width)
        lineMetrics = metrics
        return metrics
    }

    /// The height of the lines shown: all of them, or the first `visibleUnitCount` while a reveal runs.
    private var visibleTextHeight: CGFloat {
        let bottoms = lines.bottoms
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
        for (index, bottom) in lines.bottoms.enumerated() {
            // The first line also covers the header and top padding.
            let minY = index == 0 ? 0 : top + previous
            rects.append(CGRect(x: 0, y: minY, width: box.width, height: top + bottom - minY))
            previous = bottom
        }
        return extendingLastVisibleUnit(rects, in: box)
    }

    func update(to embed: GlimmerEmbed) {
        guard case .codeBlock(let language, let code) = embed, code != self.code || language != self.language else { return }
        self.code = code
        self.language = language
        highlighted = Self.highlightedCode(code, language: language, theme: theme, highlighter: highlighter)
        textView.attributedText = highlighted
        languageLabel.text = language?.lowercased() ?? "code"
        lineMetrics = nil
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
        // +2 absorbs rounding between boundingRect and TextKit so the last glyph never wraps.
        let contentWidth = max(bounds.width, textSize.width + theme.embedPadding * 2 + 2)
        // Every line stays laid out; while revealing, this view is shorter and the scroll view clips the rest. The
        // content size keeps the visible height, so the code never scrolls vertically.
        textView.frame = CGRect(x: 0, y: 0, width: contentWidth, height: textSize.height + theme.embedPadding * 2)
        scrollView.contentSize = CGSize(width: contentWidth, height: scrollView.bounds.height)
    }

    static func highlightedCode(
        _ code: String, language: String?, theme: GlimmerTheme, highlighter: any GlimmerHighlighter
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = theme.lineHeightMultiple
        let result = NSMutableAttributedString(string: code, attributes: [
            .font: theme.codeFont,
            .foregroundColor: theme.textColor,
            .paragraphStyle: paragraph,
        ])
        for span in highlighter.highlight(code, language: language) where NSMaxRange(span.range) <= result.length {
            result.addAttribute(.foregroundColor, value: color(for: span.kind, theme: theme), range: span.range)
        }
        return result
    }

    private static func color(for kind: GlimmerHighlightSpan.Kind, theme: GlimmerTheme) -> UIColor {
        switch kind {
        case .keyword: theme.syntaxKeywordColor
        case .string: theme.syntaxStringColor
        case .comment: theme.syntaxCommentColor
        case .number: theme.syntaxNumberColor
        }
    }
}

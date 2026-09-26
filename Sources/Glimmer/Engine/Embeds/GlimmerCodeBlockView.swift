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
    private var cachedTextSize: CGSize?

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
        if let cachedTextSize { return cachedTextSize }
        let bounds = highlighted.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let size = CGSize(width: ceil(bounds.width), height: ceil(bounds.height))
        cachedTextSize = size
        return size
    }

    func embedHeight(forWidth width: CGFloat) -> CGFloat {
        (theme.showsCodeBlockHeader ? Self.headerHeight : 0) + theme.embedPadding * 2 + textSize.height
    }

    func update(to embed: GlimmerEmbed) {
        guard case .codeBlock(let language, let code) = embed, code != self.code || language != self.language else { return }
        self.code = code
        self.language = language
        highlighted = Self.highlightedCode(code, language: language, theme: theme, highlighter: highlighter)
        textView.attributedText = highlighted
        languageLabel.text = language?.lowercased() ?? "code"
        cachedTextSize = nil
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
        scrollView.frame = CGRect(x: 0, y: headerHeight, width: bounds.width, height: max(0, bounds.height - headerHeight))
        // +2 absorbs rounding between boundingRect and TextKit so the last glyph never wraps.
        let contentWidth = max(bounds.width, textSize.width + theme.embedPadding * 2 + 2)
        textView.frame = CGRect(x: 0, y: 0, width: contentWidth, height: scrollView.bounds.height)
        scrollView.contentSize = textView.frame.size
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

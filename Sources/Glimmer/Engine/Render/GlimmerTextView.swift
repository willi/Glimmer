import UIKit

/// The TextKit 2 surface for a composed markdown document: non-scrolling, selectable, not editable.
/// Never read `layoutManager` here — it silently switches the view to TextKit 1.
@MainActor
final class GlimmerTextView: UITextView {
    private(set) var theme: GlimmerTheme = .default
    private var lastLayoutWidth: CGFloat = 0
    /// Strongly held: the text layout manager's delegate is weak.
    private let fragmentProvider = GlimmerLayoutFragmentProvider(theme: .default)

    init() {
        // On iOS 16+, a nil text container gives a TextKit 2 text view.
        super.init(frame: .zero, textContainer: nil)
        backgroundColor = .clear
        isEditable = false
        isSelectable = true
        isScrollEnabled = false
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        dataDetectorTypes = []
        textLayoutManager?.delegate = fragmentProvider
        apply(theme: .default)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func apply(theme: GlimmerTheme) {
        self.theme = theme
        fragmentProvider.theme = theme
        var link: [NSAttributedString.Key: Any] = [.foregroundColor: theme.linkColor]
        if theme.underlinesLinks { link[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        linkTextAttributes = link
    }

    /// Measured by `UITextView`. TextKit 2 inside a text view lays out only what its viewport covers — even after
    /// `ensureLayout(for: documentRange)` — so usage bounds under-report a view shorter than its content. The
    /// attachments cache their views, so the provider churn this measurement causes rebuilds nothing.
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard size.width > 0, attributedText.length > 0 else { return CGSize(width: max(size.width, 0), height: 0) }
        let fitted = super.sizeThatFits(CGSize(width: size.width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: size.width, height: ceil(fitted.height))
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
    func apply(_ edit: GlimmerDocumentEdit) {
        if let content = textLayoutManager?.textContentManager as? NSTextContentStorage {
            content.performEditingTransaction {
                textStorage.replaceCharacters(in: edit.range, with: edit.replacement)
            }
        } else {
            textStorage.replaceCharacters(in: edit.range, with: edit.replacement)
        }
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
}

import UIKit

/// A linked table cell. UIKit handles hit testing, selection and native URL actions; its table keeps the row and
/// column accessibility semantics. Plain cells use UILabel so ordinary tables incur no extra TextKit work.
@MainActor
final class GlimmerTableCellTextView: UITextView, UITextViewDelegate {
    init() {
        super.init(frame: .zero, textContainer: nil)
        backgroundColor = .clear
        isEditable = false
        isSelectable = true
        isScrollEnabled = false
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        linkTextAttributes = [:]
        dataDetectorTypes = []
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static func hasLinks(in text: NSAttributedString) -> Bool {
        var found = false
        text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, _, stop in
            if value != nil { found = true; stop.pointee = true }
        }
        return found
    }

    var linkRanges: [NSRange] {
        var ranges: [NSRange] = []
        textStorage.enumerateAttribute(.link, in: NSRange(location: 0, length: textStorage.length)) { value, range, _ in
            if value != nil { ranges.append(range) }
        }
        return ranges
    }

    /// Accessibility's default activation point is the frame's center. A full cell can put it past a short link,
    /// so use its first glyph segment, which also stays inside the target when a link wraps over several lines.
    func frameForLink(_ range: NSRange) -> CGRect? {
        guard bounds.width > 0, range.length > 0, NSMaxRange(range) <= textStorage.length else { return nil }
        layoutIfNeeded()
        guard let manager = textLayoutManager, let content = manager.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end) else { return nil }
        manager.ensureLayout(for: textRange)
        var result: CGRect?
        manager.enumerateTextSegments(in: textRange, type: .standard, options: [.rangeNotRequired]) { _, frame, _, _ in
            guard frame.width > 0, frame.height > 0 else { return true }
            result = frame.offsetBy(dx: textContainerInset.left - contentOffset.x, dy: textContainerInset.top - contentOffset.y)
            return false
        }
        return result
    }

    private var host: GlimmerView? {
        var ancestor = superview
        while let view = ancestor {
            if let host = view as? GlimmerView { return host }
            ancestor = view.superview
        }
        return nil
    }

    /// Cell offsets belong to this storage, not the outer document's single table attachment character.
    private func hostHandler(for url: URL, atCharacter index: Int) -> (() -> Void)? {
        if GlimmerTokenBox.isTokenLink(url) {
            guard index >= 0, index < textStorage.length,
                  let token = (textStorage.attribute(.glimmerToken, at: index, effectiveRange: nil) as? GlimmerTokenBox)?.token,
                  let handler = host?.onTokenTap else { return nil }
            return { handler(token) }
        }
        if GlimmerTokenBox.isImageLink(url) {
            guard index > 0, index <= textStorage.length,
                  let image = textStorage.attribute(.attachment, at: index - 1, effectiveRange: nil) as? GlimmerInlineImageAttachment,
                  let handler = host?.onImageTap else { return nil }
            return { handler(image.source, image.alt) }
        }
        guard let handler = host?.onLinkTap else { return nil }
        return { handler(url) }
    }

    func linkAction(for url: URL, atCharacter index: Int, defaultAction: UIAction) -> UIAction? {
        if let handler = hostHandler(for: url, atCharacter: index) { return UIAction { _ in handler() } }
        return GlimmerTokenBox.isInternalLink(url) ? nil : defaultAction
    }

    func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
        guard case .link(let url) = textItem.content else { return defaultAction }
        return linkAction(for: url, atCharacter: textItem.range.location, defaultAction: defaultAction)
    }

    func textView(
        _ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu
    ) -> UITextItem.MenuConfiguration? {
        guard case .link(let url) = textItem.content else { return nil }
        return host?.menuConfiguration(forLink: url, defaultMenu: defaultMenu)
    }

    /// Accessibility activates the same action as a touch; UIKit supplies the default action for touch itself.
    @discardableResult
    func activateLink(atCharacter index: Int) -> Bool {
        guard index >= 0, index < textStorage.length,
              let url = textStorage.attribute(.link, at: index, effectiveRange: nil) as? URL else { return false }
        if let handler = hostHandler(for: url, atCharacter: index) {
            handler()
        } else {
            guard !GlimmerTokenBox.isInternalLink(url) else { return false }
            UIApplication.shared.open(url)
        }
        return true
    }
}

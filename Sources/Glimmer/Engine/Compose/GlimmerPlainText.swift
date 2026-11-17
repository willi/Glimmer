import SwiftUI
import UIKit

/// Turns composed text, which leans on attachments and internal links that only a `GlimmerView` understands, into text
/// that stands alone.
enum GlimmerPlainText {
    /// Replaces attachments with text, drops spoken-only text, and rewrites links: internal ones go, and a token with a
    /// URL links to it.
    static func flatten(_ text: NSMutableAttributedString, theme: GlimmerTheme) {
        removeSpokenOnly(from: text)
        replaceAttachments(in: text, theme: theme)
        fixLinks(in: text)
    }

    /// The text as an `AttributedString` whose runs carry the SwiftUI attributes beside the UIKit ones.
    static func attributedString(from text: NSAttributedString) -> AttributedString {
        guard var result = try? AttributedString(text, including: AttributeScopes.UIKitAttributes.self) else {
            return AttributedString(text.string)
        }
        for run in result.runs {
            let range = run.range
            if let font = run.uiKit.font { result[range].swiftUI.font = Font(font) }
            if let color = run.uiKit.foregroundColor { result[range].swiftUI.foregroundColor = Color(uiColor: color) }
            if let style = run.uiKit.strikethroughStyle, style != [] {
                result[range].swiftUI.strikethroughStyle = Text.LineStyle(nsUnderlineStyle: style)
            }
            if let style = run.uiKit.underlineStyle, style != [] {
                result[range].swiftUI.underlineStyle = Text.LineStyle(nsUnderlineStyle: style)
            }
        }
        return result
    }

    private static func removeSpokenOnly(from text: NSMutableAttributedString) {
        var ranges: [NSRange] = []
        text.enumerateAttribute(.glimmerSpokenOnly, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if value != nil { ranges.append(range) }
        }
        for range in ranges.reversed() { text.deleteCharacters(in: range) }
    }

    private static func replaceAttachments(in text: NSMutableAttributedString, theme: GlimmerTheme) {
        var found: [(range: NSRange, attachment: NSTextAttachment)] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let attachment = value as? NSTextAttachment { found.append((range, attachment)) }
        }
        // Back to front, so the ranges still ahead stay valid.
        for (range, attachment) in found.reversed() {
            var attributes = text.attributes(at: range.location, effectiveRange: nil)
            attributes[.attachment] = nil
            if let block = attachment as? GlimmerBlockAttachment {
                replace(block, at: range, in: text, attributes: attributes, theme: theme)
            } else if let chip = attachment as? GlimmerInlineAttachment {
                // The chip's run carries the token only as the attachment, so its URL is linked here.
                if let url = chip.token.url { attributes[.link] = url }
                text.replaceCharacters(in: range, with: NSAttributedString(string: chip.token.displayText, attributes: attributes))
            } else {
                text.deleteCharacters(in: range)
            }
        }
    }

    private static func replace(
        _ block: GlimmerBlockAttachment, at range: NSRange, in text: NSMutableAttributedString,
        attributes: [NSAttributedString.Key: Any], theme: GlimmerTheme
    ) {
        switch block.embed {
        case .codeBlock(_, let code, _):
            var codeAttributes = attributes
            codeAttributes[.font] = theme.codeFont
            codeAttributes[.foregroundColor] = theme.textColor
            let trimmed = code.hasSuffix("\n") ? String(code.dropLast()) : code
            text.replaceCharacters(in: range, with: NSAttributedString(string: trimmed, attributes: codeAttributes))
        case .table(let header, let rows, _):
            let lines = ([header] + rows).map { row in
                row.map { $0.string.replacingOccurrences(of: "\n", with: " ") }.joined(separator: "\t")
            }
            text.replaceCharacters(in: range, with: NSAttributedString(string: lines.joined(separator: "\n"), attributes: attributes))
        case .image, .thematicBreak:
            // The break's own line ends in "\n". Take it too, or the line it leaves would be a blank paragraph.
            var removal = range
            let end = range.location + range.length
            if end < text.length, (text.string as NSString).character(at: end) == 0x0A {
                removal.length += 1
            } else if range.location > 0, (text.string as NSString).character(at: range.location - 1) == 0x0A {
                removal = NSRange(location: range.location - 1, length: range.length + 1)
            }
            text.deleteCharacters(in: removal)
        }
    }

    private static func fixLinks(in text: NSMutableAttributedString) {
        let whole = NSRange(location: 0, length: text.length)
        var internalLinks: [NSRange] = []
        text.enumerateAttribute(.link, in: whole) { value, range, _ in
            let url = (value as? URL) ?? (value as? String).flatMap { URL(string: $0) }
            if let url, GlimmerTokenBox.isInternalLink(url) { internalLinks.append(range) }
        }
        for range in internalLinks { text.removeAttribute(.link, range: range) }
        text.enumerateAttribute(.glimmerToken, in: whole) { value, range, _ in
            if let url = (value as? GlimmerTokenBox)?.token.url { text.addAttribute(.link, value: url, range: range) }
        }
    }
}

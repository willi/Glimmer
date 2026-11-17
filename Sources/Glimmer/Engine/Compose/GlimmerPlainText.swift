import SwiftUI
import UIKit

/// Turns composed text, which leans on attachments and internal links that only a `GlimmerView` understands, into text
/// that stands alone.
enum GlimmerPlainText {
    /// The composer for text that stands alone: images are hidden, since nothing here can load them, and the hidden
    /// ones close the space around them. The configuration's link policy applies, as it does in a `GlimmerView`.
    static func composer(theme: GlimmerTheme, configuration: GlimmerConfiguration) -> GlimmerComposer {
        GlimmerComposer(
            theme: theme, highlighter: configuration.highlighter, imageLoader: nil,
            imagePolicy: GlimmerHideImagesPolicy(), linkPolicy: configuration.linkPolicy,
            extensions: configuration.extensions
        )
    }

    /// Composed text flattened (see `flatten`) and converted (see `attributedString(from:)`), leaving `composed` as it was.
    static func standalone(_ composed: NSAttributedString, theme: GlimmerTheme) -> AttributedString {
        let text = NSMutableAttributedString(attributedString: composed)
        flatten(text, theme: theme)
        return attributedString(from: text)
    }

    /// Replaces attachments with text, drops spoken-only text, and rewrites links: internal ones go, and a token with a
    /// URL links to it.
    static func flatten(_ text: NSMutableAttributedString, theme: GlimmerTheme) {
        // Attachments first: a task checkbox's state is the spoken-only text after it.
        replaceAttachments(in: text, theme: theme)
        removeSpokenOnly(from: text)
        fixLinks(in: text, theme: theme)
        fillMissingFontAndColor(in: text, theme: theme)
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

    /// The composer styles a list marker's tab and a task checkbox with a paragraph style alone; plain text needs a font
    /// and colour on every run, so the body's are filled in, dimmed inside a quote.
    private static func fillMissingFontAndColor(in text: NSMutableAttributedString, theme: GlimmerTheme) {
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            if attributes[.font] == nil { text.addAttribute(.font, value: theme.bodyFont, range: range) }
            if attributes[.foregroundColor] == nil {
                let color = attributes[.glimmerQuoteDepth] == nil ? theme.textColor : theme.secondaryTextColor
                text.addAttribute(.foregroundColor, value: color, range: range)
            }
        }
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
            // Prose colour for text that replaces an attachment, dimmed inside a quote like the text around it.
            if attributes[.foregroundColor] == nil {
                attributes[.foregroundColor] = attributes[.glimmerQuoteDepth] == nil ? theme.textColor : theme.secondaryTextColor
            }
            if let block = attachment as? GlimmerBlockAttachment {
                replace(block, at: range, in: text, attributes: attributes, theme: theme)
            } else if let chip = attachment as? GlimmerInlineAttachment {
                // A tappable chip's run carries its token, and `fixLinks` links its URL; this covers a chip that isn't
                // tappable, whose run carries the token only as the attachment.
                if let url = chip.token.url {
                    attributes[.link] = url
                    attributes[.foregroundColor] = theme.linkColor
                }
                text.replaceCharacters(in: range, with: NSAttributedString(string: chip.token.displayText, attributes: attributes))
            } else if attachment.image != nil {
                // A task-list checkbox. Its state is in the spoken-only text that follows.
                let next = range.location + range.length
                var spoken = NSRange()
                let isChecked = next < text.length
                    && text.attribute(.glimmerSpokenOnly, at: next, effectiveRange: &spoken) != nil
                    && (text.string as NSString).substring(with: spoken).hasPrefix(GlimmerStrings.checked)
                text.replaceCharacters(in: range, with: NSAttributedString(string: GlimmerTaskBox.character(isChecked: isChecked), attributes: attributes))
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
            codeAttributes[.foregroundColor] = attributes[.foregroundColor]
            let trimmed = code.hasSuffix("\n") ? String(code.dropLast()) : code
            text.replaceCharacters(in: range, with: NSAttributedString(string: trimmed, attributes: codeAttributes))
        case .table(let header, let rows, _):
            // Each cell is flattened like the text around it, so a chip, a link or bold text survives. Cells are
            // styled by the composer, not by the paragraph, so they get the surrounding text colour when they have none.
            let table = NSMutableAttributedString()
            for (rowIndex, row) in ([header] + rows).enumerated() {
                if rowIndex > 0 { table.append(NSAttributedString(string: "\n", attributes: attributes)) }
                for (cellIndex, cell) in row.enumerated() {
                    if cellIndex > 0 { table.append(NSAttributedString(string: "\t", attributes: attributes)) }
                    let flat = NSMutableAttributedString(attributedString: cell)
                    flatten(flat, theme: theme)
                    flat.mutableString.replaceOccurrences(
                        of: "\n", with: " ", range: NSRange(location: 0, length: flat.length))
                    for key in [NSAttributedString.Key.font, .foregroundColor] {
                        guard let fallback = attributes[key] else { continue }
                        flat.enumerateAttribute(key, in: NSRange(location: 0, length: flat.length)) { value, range, _ in
                            if value == nil { flat.addAttribute(key, value: fallback, range: range) }
                        }
                    }
                    table.append(flat)
                }
            }
            text.replaceCharacters(in: range, with: table)
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

    private static func fixLinks(in text: NSMutableAttributedString, theme: GlimmerTheme) {
        let whole = NSRange(location: 0, length: text.length)
        var internalLinks: [NSRange] = []
        text.enumerateAttribute(.link, in: whole) { value, range, _ in
            let url = (value as? URL) ?? (value as? String).flatMap { URL(string: $0) }
            if let url, GlimmerTokenBox.isInternalLink(url) { internalLinks.append(range) }
        }
        for range in internalLinks { text.removeAttribute(.link, range: range) }
        text.enumerateAttribute(.glimmerToken, in: whole) { value, range, _ in
            guard let url = (value as? GlimmerTokenBox)?.token.url else { return }
            text.addAttribute(.link, value: url, range: range)
            text.addAttribute(.foregroundColor, value: theme.linkColor, range: range)
        }
    }
}

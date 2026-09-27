import UIKit

extension GlimmerComposer {
    func appendInlines(_ inlines: [GlimmerInline], attributes: [NSAttributedString.Key: Any], to output: NSMutableAttributedString) {
        for inline in inlines {
            switch inline {
            case .text(let text):
                appendText(text, attributes: attributes, to: output)
            case .code(let code):
                var codeAttributes = attributes
                let size = (attributes[.font] as? UIFont ?? theme.bodyFont).pointSize
                codeAttributes[.font] = theme.codeFont.withSize(size * 0.9)
                codeAttributes[.glimmerInlineCode] = true
                output.append(NSAttributedString(string: code, attributes: codeAttributes))
            case .emphasis(let children):
                var emphasized = adding(.traitItalic, to: attributes)
                emphasized[.glimmerEmphasis] = true
                appendInlines(children, attributes: emphasized, to: output)
            case .strong(let children):
                var strong = adding(.traitBold, to: attributes)
                strong[.glimmerStrong] = true
                appendInlines(children, attributes: strong, to: output)
            case .strikethrough(let children):
                var struck = attributes
                struck[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                appendInlines(children, attributes: struck, to: output)
            case .link(let destination, _, let children):
                var linked = attributes
                if let url = URL(string: destination) { linked[.link] = url }
                appendInlines(children, attributes: linked, to: output)
            case .image(let source, _, let alt):
                var faded = attributes
                faded[.foregroundColor] = theme.secondaryTextColor
                faded[.glimmerSource] = "![\(alt)](\(source))"
                output.append(NSAttributedString(string: alt, attributes: faded))
            case .softBreak:
                output.append(NSAttributedString(string: " ", attributes: attributes))
            case .lineBreak:
                output.append(NSAttributedString(string: "\u{2028}", attributes: attributes))
            case .html(let html):
                output.append(NSAttributedString(string: html, attributes: attributes))
            case .footnoteReference(let label):
                // A superscript number in the link colour; copy writes the original `[^label]`.
                var marker = attributes
                let font = attributes[.font] as? UIFont ?? theme.bodyFont
                marker[.font] = theme.footnoteFont
                marker[.baselineOffset] = max(1, font.capHeight - theme.footnoteFont.capHeight)
                marker[.foregroundColor] = theme.linkColor
                marker[.glimmerSource] = "[^\(label)]"
                output.append(NSAttributedString(string: "\(footnotes.number(for: label))", attributes: marker))
            }
        }
    }

    /// Appends plain text, turning extension tokens into inline chips.
    func appendText(_ text: String, attributes: [NSAttributedString.Key: Any], to output: NSMutableAttributedString) {
        let tokens = extensions.flatMap { glimmerExtension in
            glimmerExtension.scan(text)
                .filter { $0.range.lowerBound >= text.startIndex && $0.range.upperBound <= text.endIndex }
                .map { (glimmerExtension: glimmerExtension, token: $0) }
        }.sorted { $0.token.range.lowerBound < $1.token.range.lowerBound }

        var cursor = text.startIndex
        for match in tokens where match.token.range.lowerBound >= cursor {
            if cursor < match.token.range.lowerBound {
                output.append(NSAttributedString(string: String(text[cursor..<match.token.range.lowerBound]), attributes: attributes))
            }
            var chip = attributes
            chip[.attachment] = GlimmerInlineAttachment(token: match.token, glimmerExtension: match.glimmerExtension, theme: theme)
            chip[.glimmerSource] = match.token.source
            output.append(NSAttributedString(string: "\u{FFFC}", attributes: chip))
            cursor = match.token.range.upperBound
        }
        if cursor < text.endIndex {
            output.append(NSAttributedString(string: String(text[cursor...]), attributes: attributes))
        }
    }

    private func adding(_ trait: UIFontDescriptor.SymbolicTraits, to attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        guard let font = attributes[.font] as? UIFont,
              let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait)) else {
            return attributes
        }
        var updated = attributes
        updated[.font] = UIFont(descriptor: descriptor, size: font.pointSize)
        return updated
    }
}

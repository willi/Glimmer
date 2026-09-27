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
                appendInlineImage(source: source, alt: alt, markdown: "![\(alt)](\(source))", attributes: attributes, to: output)
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

    /// An image inside a paragraph: a line-height square, then its alt text for VoiceOver only. An unusable URL shows
    /// the alt text, dimmed, as before.
    func appendInlineImage(
        source: String, alt: String, markdown: String, spoken: String? = nil, attributes: [NSAttributedString.Key: Any],
        to output: NSMutableAttributedString
    ) {
        guard let url = URL(string: source) else {
            var faded = attributes
            faded[.foregroundColor] = theme.secondaryTextColor
            faded[.glimmerSource] = markdown
            output.append(NSAttributedString(string: alt, attributes: faded))
            return
        }
        var image = attributes
        image[.attachment] = GlimmerInlineImageAttachment(source: url, alt: alt, theme: theme, loader: imageLoader)
        image[.glimmerSource] = markdown
        output.append(NSAttributedString(string: "\u{FFFC}", attributes: image))
        let label = spoken ?? alt
        guard !label.isEmpty else { return }
        var spokenAttributes = attributes
        spokenAttributes[.font] = (attributes[.font] as? UIFont ?? theme.bodyFont).withSize(0.01)
        spokenAttributes[.foregroundColor] = UIColor.clear
        spokenAttributes[.glimmerSpokenOnly] = true
        output.append(NSAttributedString(string: label, attributes: spokenAttributes))
    }

    /// Appends plain text, turning extension tokens into chips, text or inline images.
    func appendText(_ text: String, attributes: [NSAttributedString.Key: Any], to output: NSMutableAttributedString) {
        let inLink = attributes[.link] != nil
        let tokens = extensions.filter { !inLink || $0.appliesInsideLinks }.flatMap { glimmerExtension in
            glimmerExtension.scan(text)
                .filter { $0.range.lowerBound >= text.startIndex && $0.range.upperBound <= text.endIndex }
                .map { (glimmerExtension: glimmerExtension, token: $0) }
        }.sorted { $0.token.range.lowerBound < $1.token.range.lowerBound }

        var cursor = text.startIndex
        for match in tokens where match.token.range.lowerBound >= cursor {
            if cursor < match.token.range.lowerBound {
                output.append(NSAttributedString(string: String(text[cursor..<match.token.range.lowerBound]), attributes: attributes))
            }
            appendToken(match.token, glimmerExtension: match.glimmerExtension, attributes: attributes, to: output)
            cursor = match.token.range.upperBound
        }
        if cursor < text.endIndex {
            output.append(NSAttributedString(string: String(text[cursor...]), attributes: attributes))
        }
    }

    private func appendToken(
        _ token: GlimmerInlineToken, glimmerExtension: any GlimmerExtension, attributes: [NSAttributedString.Key: Any],
        to output: NSMutableAttributedString
    ) {
        switch token.presentation {
        case .chip:
            var chip = attributes
            chip[.attachment] = GlimmerInlineAttachment(token: token, glimmerExtension: glimmerExtension, theme: theme)
            chip[.glimmerSource] = token.source
            output.append(NSAttributedString(string: "\u{FFFC}", attributes: chip))
        case .text(let tappable):
            // Text like any other: it wraps and selects as words do. Copy writes the source; a tap reports the token.
            var run = attributes
            run[.glimmerSource] = token.source
            run[.glimmerToken] = GlimmerTokenBox(token)
            if tappable {
                run[.foregroundColor] = theme.mentionColor
                run[.textItemTag] = token.kind
            }
            output.append(NSAttributedString(string: token.displayText, attributes: run))
        case .image(let url):
            var run = attributes
            run[.glimmerToken] = GlimmerTokenBox(token)
            appendInlineImage(source: url.absoluteString, alt: token.displayText, markdown: token.source,
                              spoken: token.accessibilityLabel, attributes: run, to: output)
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

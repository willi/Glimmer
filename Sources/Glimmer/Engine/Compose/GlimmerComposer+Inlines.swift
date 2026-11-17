import UIKit

extension GlimmerComposer {
    /// `reuse` offers back a re-composed block's inline images, so a streaming paragraph keeps its image.
    /// `soleImageDecision` is the policy's answer for the only image of a paragraph, when the caller already asked.
    /// Returns whether the image policy kept an image from showing.
    @discardableResult
    func appendInlines(
        _ inlines: [GlimmerInline], attributes: [NSAttributedString.Key: Any], reuse: GlimmerAttachmentReuse? = nil,
        soleImageDecision: GlimmerImageDecision? = nil, to output: NSMutableAttributedString
    ) -> Bool {
        let start = output.length
        let keptAnImageFromShowing = appendRun(
            inlines, attributes: attributes, reuse: reuse, decided: soleImageDecision, to: output
        )
        if keptAnImageFromShowing { Self.closeImageGaps(in: output, from: start) }
        return keptAnImageFromShowing
    }

    /// One level of inlines. `decided` answers for an image at this level only, never for one nested inside.
    private func appendRun(
        _ inlines: [GlimmerInline], attributes: [NSAttributedString.Key: Any], reuse: GlimmerAttachmentReuse?,
        decided: GlimmerImageDecision? = nil, to output: NSMutableAttributedString
    ) -> Bool {
        var keptAnImageFromShowing = false
        // As in a browser, spaces around a `<br>` don't start or end a line.
        var afterBreakTag = false
        for inline in inlines {
            let isBreakTag = if case .html(let html) = inline { Self.isBreakTag(html) } else { false }
            defer { afterBreakTag = isBreakTag || (afterBreakTag && inline == .softBreak) }
            switch inline {
            case .text(let text):
                let shown = afterBreakTag ? String(text.drop { $0 == " " || $0 == "\t" }) : text
                if !shown.isEmpty, appendText(shown, attributes: attributes, reuse: reuse, to: output) {
                    keptAnImageFromShowing = true
                }
            case .softBreak where afterBreakTag:
                break
            case .code(let code):
                var codeAttributes = attributes
                let size = (attributes[.font] as? UIFont ?? theme.bodyFont).pointSize
                codeAttributes[.font] = theme.codeFont.withSize(size * 0.9)
                codeAttributes[.glimmerInlineCode] = true
                output.append(NSAttributedString(string: code, attributes: codeAttributes))
            case .emphasis(let children):
                var emphasized = adding(.traitItalic, to: attributes)
                emphasized[.glimmerEmphasis] = true
                if appendRun(children, attributes: emphasized, reuse: reuse, to: output) { keptAnImageFromShowing = true }
            case .strong(let children):
                var strong = adding(.traitBold, to: attributes)
                strong[.glimmerStrong] = true
                if appendRun(children, attributes: strong, reuse: reuse, to: output) { keptAnImageFromShowing = true }
            case .strikethrough(let children):
                var struck = attributes
                struck[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                if appendRun(children, attributes: struck, reuse: reuse, to: output) { keptAnImageFromShowing = true }
            case .link(let destination, _, let children):
                var linked = attributes
                if let url = URL(string: destination) {
                    // The text carries the link style: the text view's link attributes would restyle token links too.
                    linked[.link] = url
                    linked[.foregroundColor] = theme.linkColor
                    if theme.underlinesLinks { linked[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                }
                if appendRun(children, attributes: linked, reuse: reuse, to: output) { keptAnImageFromShowing = true }
            case .image(let source, let title, let alt):
                let decision = appendInlineImage(
                    source: source, alt: alt, title: title, origin: .markdown, decided: decided,
                    markdown: GlimmerMarkdownSerializer.imageSource(source: source, alt: alt), attributes: attributes,
                    reuse: reuse, to: output
                )
                guard decision != .load else { break }
                keptAnImageFromShowing = true
                if decision == .showAltText, !alt.isEmpty {
                    // Ordinary text in the style around it. It copies as what is shown, not as the image the host refused.
                    output.append(NSAttributedString(string: alt, attributes: attributes))
                } else {
                    Self.markImageGap(in: output)
                }
            case .softBreak:
                output.append(NSAttributedString(string: " ", attributes: attributes))
            case .lineBreak:
                output.append(NSAttributedString(string: "\u{2028}", attributes: attributes))
            case .html(let html) where isBreakTag:
                // The one tag with a plain meaning, and a common way to break a line in a table cell. Copies as itself.
                // Spaces before it go, but not a code span's own.
                while output.length > 0, (output.string as NSString).character(at: output.length - 1) == 0x20,
                      output.attribute(.glimmerInlineCode, at: output.length - 1, effectiveRange: nil) == nil {
                    output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1))
                }
                var lineBreak = attributes
                lineBreak[.glimmerSource] = html
                output.append(NSAttributedString(string: "\u{2028}", attributes: lineBreak))
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
        return keptAnImageFromShowing
    }

    /// An image inside a paragraph: a line-height square, then its alt text for VoiceOver only. An unusable URL shows
    /// the alt text, dimmed, as before.
    ///
    /// Returns the image policy's decision. Anything but `.load` appends nothing: the caller puts its own text in the
    /// image's place, the alt text for a markdown image and the token's text for an extension's. `decided` is that
    /// decision when the caller already has it, so the policy is not asked a second time.
    func appendInlineImage(
        source: String, alt: String, title: String? = nil, origin: GlimmerImageCandidate.Origin,
        decided: GlimmerImageDecision? = nil, markdown: String, spoken: String? = nil,
        attributes: [NSAttributedString.Key: Any], reuse: GlimmerAttachmentReuse? = nil,
        to output: NSMutableAttributedString
    ) -> GlimmerImageDecision {
        let parsed = URL(string: source)
        let decision = decided ?? imageDecision(url: parsed, alt: alt, title: title, origin: origin)
        guard decision == .load else { return decision }
        guard let url = parsed else {
            var faded = attributes
            faded[.foregroundColor] = theme.secondaryTextColor
            faded[.glimmerSource] = markdown
            output.append(NSAttributedString(string: alt, attributes: faded))
            return .load
        }
        var image = attributes
        let isLinked = attributes[.link] != nil
        let attachment = reuse?.inlineImage(source: url, alt: alt, isLinked: isLinked)
            ?? GlimmerInlineImageAttachment(
                source: url, alt: alt, isLinked: isLinked, theme: theme, loader: imageLoader, shape: inlineImageShape,
                gate: imageGate(url: url, alt: alt, title: title, origin: origin)
            )
        reuse?.record(inlineImage: attachment)
        image[.attachment] = attachment
        image[.glimmerSource] = markdown
        output.append(NSAttributedString(string: "\u{FFFC}", attributes: image))
        let label = spoken ?? alt
        guard !label.isEmpty else { return .load }
        var spokenAttributes = attributes
        spokenAttributes[.font] = (attributes[.font] as? UIFont ?? theme.bodyFont).withSize(0.01)
        spokenAttributes[.foregroundColor] = UIColor.clear
        spokenAttributes[.glimmerSpokenOnly] = true
        // Inside a link the alt text reads as part of it, and the link takes the tap.
        if linksImagesForTaps, !isLinked { spokenAttributes[.link] = GlimmerTokenBox.imageLink(at: output.length) }
        output.append(NSAttributedString(string: label, attributes: spokenAttributes))
        return .load
    }

    static func isBreakTag(_ html: String) -> Bool {
        html.wholeMatch(of: #/<br\s*/?>/#.ignoresCase()) != nil
    }

    // MARK: - The space around an image that is not shown

    /// Marks the place of an image the policy kept from showing, where nothing was put instead. The white space
    /// around it can only be judged once the text after it is composed, so `closeImageGaps` does that.
    private static func markImageGap(in output: NSMutableAttributedString) {
        output.append(NSAttributedString(string: "\u{200B}", attributes: [.glimmerImageGap: true]))
    }

    /// Removes every mark from `start` on, and with each the white space that stood only around its image: the
    /// spaces at the start or the end of its line, one of two spaces it stood between, and the break of a line that
    /// held nothing else. Without this a hidden image above its caption leaves a blank line above the caption.
    private static func closeImageGaps(in output: NSMutableAttributedString, from start: Int) {
        var location = start
        while location < output.length {
            if output.attribute(.glimmerImageGap, at: location, effectiveRange: nil) == nil {
                location += 1
            } else {
                output.deleteCharacters(in: NSRange(location: location, length: 1))
                location = closeImageGap(at: location, in: output, from: start)
            }
        }
    }

    /// Returns where the gap is once the white space before it is gone. Marks further on are still in the text and
    /// count as text here; each is closed in its turn.
    private static func closeImageGap(at location: Int, in output: NSMutableAttributedString, from start: Int) -> Int {
        let text = output.mutableString
        var gap = location
        func isLineBreak(_ index: Int) -> Bool { text.character(at: index) == 0x2028 }
        // A code span's own spaces stay, as they do beside a `<br>`.
        func isSpace(_ index: Int) -> Bool {
            let character = text.character(at: index)
            return (character == 0x20 || character == 0x09)
                && output.attribute(.glimmerInlineCode, at: index, effectiveRange: nil) == nil
        }
        func startsLine() -> Bool { gap == start || isLineBreak(gap - 1) }
        func endsLine() -> Bool { gap == output.length || isLineBreak(gap) }
        func delete(_ index: Int) { output.deleteCharacters(in: NSRange(location: index, length: 1)) }

        if startsLine() || isSpace(gap - 1) {
            while gap < output.length, isSpace(gap) { delete(gap) }
        }
        if endsLine() {
            while gap > start, isSpace(gap - 1) {
                gap -= 1
                delete(gap)
            }
        }
        // The image was alone on its line, so the line goes with it: its own break, or on the last line the one above.
        if startsLine(), endsLine() {
            if gap < output.length {
                delete(gap)
            } else if gap > start {
                gap -= 1
                delete(gap)
            }
        }
        return gap
    }

    /// Appends plain text, turning extension tokens into chips, text or inline images. Returns whether the image
    /// policy kept a token's image from showing.
    @discardableResult
    func appendText(
        _ text: String, attributes: [NSAttributedString.Key: Any], reuse: GlimmerAttachmentReuse? = nil,
        to output: NSMutableAttributedString
    ) -> Bool {
        let inLink = attributes[.link] != nil
        let tokens = extensions.filter { !inLink || $0.appliesInsideLinks }.flatMap { glimmerExtension in
            glimmerExtension.scan(text)
                .filter { $0.range.lowerBound >= text.startIndex && $0.range.upperBound <= text.endIndex }
                .map { (glimmerExtension: glimmerExtension, token: $0) }
        }.sorted { $0.token.range.lowerBound < $1.token.range.lowerBound }

        var keptAnImageFromShowing = false
        var cursor = text.startIndex
        for match in tokens where match.token.range.lowerBound >= cursor {
            if cursor < match.token.range.lowerBound {
                output.append(NSAttributedString(string: String(text[cursor..<match.token.range.lowerBound]), attributes: attributes))
            }
            if appendToken(match.token, glimmerExtension: match.glimmerExtension, attributes: attributes, reuse: reuse, to: output) {
                keptAnImageFromShowing = true
            }
            cursor = match.token.range.upperBound
        }
        if cursor < text.endIndex {
            output.append(NSAttributedString(string: String(text[cursor...]), attributes: attributes))
        }
        return keptAnImageFromShowing
    }

    /// Returns whether the image policy kept the token's image from showing.
    private func appendToken(
        _ token: GlimmerInlineToken, glimmerExtension: any GlimmerExtension, attributes: [NSAttributedString.Key: Any],
        reuse: GlimmerAttachmentReuse?, to output: NSMutableAttributedString
    ) -> Bool {
        switch token.presentation {
        case .chip:
            var chip = attributes
            chip[.attachment] = GlimmerInlineAttachment(token: token, glimmerExtension: glimmerExtension, theme: theme)
            chip[.glimmerSource] = token.source
            output.append(NSAttributedString(string: "\u{FFFC}", attributes: chip))
            if token.isTappable { appendSpokenLink(for: token, attributes: attributes, to: output) }
            return false
        case .text(let tappable):
            appendTokenText(token, tappable: tappable, attributes: attributes, to: output)
            return false
        case .image(let url):
            var run = attributes
            run[.glimmerToken] = GlimmerTokenBox(token)
            let decision = appendInlineImage(
                source: url.absoluteString, alt: token.displayText, origin: .extensionToken(kind: token.kind),
                markdown: token.source, spoken: token.accessibilityLabel, attributes: run, reuse: reuse, to: output
            )
            guard decision != .load else { return false }
            let end = output.length
            // Without its image the token is its text, as if the extension had presented it that way.
            if decision == .showAltText { appendTokenText(token, tappable: false, attributes: attributes, to: output) }
            if output.length == end { Self.markImageGap(in: output) }
            return true
        }
    }

    /// The chip's spoken-only text, a link: VoiceOver and the links rotor reach the chip through it, and activating it
    /// reports the token. The chip view itself stays hidden from VoiceOver. Copy skips it.
    private func appendSpokenLink(
        for token: GlimmerInlineToken, attributes: [NSAttributedString.Key: Any], to output: NSMutableAttributedString
    ) {
        var spoken = attributes
        spoken[.font] = (attributes[.font] as? UIFont ?? theme.bodyFont).withSize(0.01)
        spoken[.foregroundColor] = UIColor.clear
        spoken[.glimmerSpokenOnly] = true
        spoken[.glimmerToken] = GlimmerTokenBox(token)
        spoken[.link] = GlimmerTokenBox.link(kind: token.kind, at: output.length)
        output.append(NSAttributedString(string: token.accessibilityLabel ?? token.displayText, attributes: spoken))
    }

    /// Text like any other: it wraps and selects as words do. Copy writes the source; a tap reports the token.
    private func appendTokenText(
        _ token: GlimmerInlineToken, tappable: Bool, attributes: [NSAttributedString.Key: Any], to output: NSMutableAttributedString
    ) {
        var run = attributes
        run[.glimmerSource] = token.source
        run[.glimmerToken] = GlimmerTokenBox(token)
        if tappable {
            run[.foregroundColor] = theme.mentionColor
            run[.link] = GlimmerTokenBox.link(kind: token.kind, at: output.length)
        }
        output.append(NSAttributedString(string: token.displayText, attributes: run))
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

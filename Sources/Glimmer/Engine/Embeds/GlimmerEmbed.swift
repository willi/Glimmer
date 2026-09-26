import Foundation

/// A block rendered as its own view inside the text flow. Table cells arrive already styled by the composer.
enum GlimmerEmbed {
    case codeBlock(language: String?, code: String)
    case table(header: [NSAttributedString], rows: [[NSAttributedString]], alignments: [GlimmerTable.Alignment])
    case image(source: URL, alt: String)
    case thematicBreak
}

extension GlimmerEmbed {
    /// Whether this embed is `previous` grown by streaming: more code under the same fence, more rows under the same
    /// header, or the same image or rule. Such an embed keeps its attachment and view.
    func continues(_ previous: GlimmerEmbed) -> Bool {
        switch (self, previous) {
        case let (.codeBlock(language, code), .codeBlock(oldLanguage, oldCode)):
            language == oldLanguage && code.hasPrefix(oldCode)
        case let (.table(header, _, alignments), .table(oldHeader, _, oldAlignments)):
            alignments == oldAlignments && header.map(\.string) == oldHeader.map(\.string)
        case let (.image(source, _), .image(oldSource, _)):
            source == oldSource
        case (.thematicBreak, .thematicBreak):
            true
        default:
            false
        }
    }
}

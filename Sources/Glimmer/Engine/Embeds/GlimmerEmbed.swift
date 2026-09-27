import Foundation

/// A block rendered as its own view inside the text flow. Table cells arrive already styled by the composer.
enum GlimmerEmbed {
    /// `highlighted` is the code styled by the composer on the worker; nil makes the view highlight it.
    case codeBlock(language: String?, code: String, highlighted: NSAttributedString? = nil)
    case table(header: [NSAttributedString], rows: [[NSAttributedString]], alignments: [GlimmerTable.Alignment])
    case image(source: URL, alt: String)
    case thematicBreak
}

extension GlimmerEmbed {
    /// Whether this embed is `previous` grown by streaming: more code under the same fence, more rows under the same
    /// header, or the same image or rule. Such an embed keeps its attachment and view.
    func continues(_ previous: GlimmerEmbed) -> Bool {
        switch (self, previous) {
        case let (.codeBlock(language, code, _), .codeBlock(oldLanguage, oldCode, _)):
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

extension GlimmerEmbed {
    /// The UTF-16 length of each reveal unit: code lines, or the header row and each body row. Images and rules have
    /// none; each reveals as one phrase.
    var revealUnitLengths: [Int] {
        switch self {
        case .codeBlock(_, let code, _):
            code.split(separator: "\n", omittingEmptySubsequences: false).map { max(1, $0.utf16.count) }
        case .table(let header, let rows, _):
            ([header] + rows).map { row in max(1, row.reduce(0) { $0 + $1.length }) }
        case .image, .thematicBreak:
            []
        }
    }
}

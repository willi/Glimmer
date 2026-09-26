import Foundation

/// A block rendered as its own view inside the text flow. Table cells arrive already styled by the composer.
enum GlimmerEmbed {
    case codeBlock(language: String?, code: String)
    case table(header: [NSAttributedString], rows: [[NSAttributedString]], alignments: [GlimmerTable.Alignment])
    case image(source: URL, alt: String)
    case thematicBreak
}

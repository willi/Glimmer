import Foundation

/// A block-level markdown element. Produced by `GlimmerParser`, consumed by `GlimmerComposer`.
public enum GlimmerBlock: Equatable, Sendable {
    case paragraph([GlimmerInline])
    case heading(level: Int, [GlimmerInline])
    case blockQuote([GlimmerBlock])
    case list(GlimmerList)
    case codeBlock(language: String?, code: String)
    case table(GlimmerTable)
    case thematicBreak
    case htmlBlock(String)
    /// The answer's footnote definitions, which cmark gathers after its last block.
    case footnoteDefinitions([GlimmerFootnote])
}

public struct GlimmerFootnote: Equatable, Sendable {
    public var label: String
    public var blocks: [GlimmerBlock]

    public init(label: String, blocks: [GlimmerBlock]) {
        self.label = label
        self.blocks = blocks
    }
}

public struct GlimmerList: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case bullet
        case ordered(start: Int)
    }

    public var kind: Kind
    public var isTight: Bool
    public var items: [GlimmerListItem]

    public init(kind: Kind, isTight: Bool, items: [GlimmerListItem]) {
        self.kind = kind
        self.isTight = isTight
        self.items = items
    }
}

public struct GlimmerListItem: Equatable, Sendable {
    /// `nil` for a plain item; `true`/`false` for a checked/unchecked task item.
    public var checkbox: Bool?
    public var blocks: [GlimmerBlock]

    public init(checkbox: Bool? = nil, blocks: [GlimmerBlock]) {
        self.checkbox = checkbox
        self.blocks = blocks
    }
}

public struct GlimmerTable: Equatable, Sendable {
    public enum Alignment: Equatable, Sendable {
        case none, left, center, right
    }

    public var alignments: [Alignment]
    public var header: [[GlimmerInline]]
    public var rows: [[[GlimmerInline]]]

    public init(alignments: [Alignment], header: [[GlimmerInline]], rows: [[[GlimmerInline]]]) {
        self.alignments = alignments
        self.header = header
        self.rows = rows
    }
}

/// An inline markdown element.
public indirect enum GlimmerInline: Equatable, Sendable {
    case text(String)
    case code(String)
    case emphasis([GlimmerInline])
    case strong([GlimmerInline])
    case strikethrough([GlimmerInline])
    case link(destination: String, title: String?, [GlimmerInline])
    case image(source: String, title: String?, alt: String)
    case softBreak
    case lineBreak
    case html(String)
    /// `[^label]`, with or without a definition.
    case footnoteReference(label: String)
}

extension GlimmerInline {
    /// The visible text of a run of inlines with markup removed. Breaks become spaces.
    public static func plainText(_ inlines: [GlimmerInline]) -> String {
        inlines.map { inline in
            switch inline {
            case .text(let text), .code(let text), .html(let text):
                text
            case .emphasis(let children), .strong(let children), .strikethrough(let children), .link(_, _, let children):
                plainText(children)
            case .image(_, _, let alt):
                alt
            case .softBreak, .lineBreak:
                " "
            case .footnoteReference:
                ""
            }
        }.joined()
    }
}

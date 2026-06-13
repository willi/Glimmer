import Foundation

/// A host-provided Markdown extension identified by a stable namespace.
///
/// Glimmer treats extensions as opaque parser/rendering hooks. Product-specific
/// syntax should live in the host app or a separate package, not in Glimmer core.
public struct MarkdownExtension: Hashable, Sendable {
    public typealias Preprocessor = @Sendable (String) -> String
    public typealias InlineParser = @Sendable (MarkdownExtensionInlineContext) -> MarkdownExtensionInlineMatch?
    public typealias InlineRenderer = @Sendable (MarkdownParser.ExtensionNode) -> AttributedString?

    public let id: String
    public let version: Int
    public let triggerCharacters: Set<Character>

    private let preprocessHandler: Preprocessor?
    private let parseInlineHandler: InlineParser?
    private let renderInlineHandler: InlineRenderer?

    public init(
        id: String,
        version: Int,
        triggerCharacters: Set<Character> = [],
        preprocess: Preprocessor? = nil,
        parseInline: InlineParser? = nil,
        renderInline: InlineRenderer? = nil
    ) {
        self.id = id
        self.version = version
        self.triggerCharacters = triggerCharacters
        self.preprocessHandler = preprocess
        self.parseInlineHandler = parseInline
        self.renderInlineHandler = renderInline
    }

    func shouldAttemptInlineParse(for character: Character) -> Bool {
        triggerCharacters.isEmpty || triggerCharacters.contains(character)
    }

    func preprocess(_ source: String) -> String {
        preprocessHandler?(source) ?? source
    }

    func parseInline(_ context: MarkdownExtensionInlineContext) -> MarkdownExtensionInlineMatch? {
        parseInlineHandler?(context)
    }

    func renderInline(_ node: MarkdownParser.ExtensionNode) -> AttributedString? {
        renderInlineHandler?(node)
    }

    public static func == (lhs: MarkdownExtension, rhs: MarkdownExtension) -> Bool {
        lhs.id == rhs.id && lhs.version == rhs.version
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(version)
    }
}

public struct MarkdownExtensionInlineContext: Sendable {
    public let source: String
    public let startIndex: String.Index

    public var remaining: Substring {
        source[startIndex...]
    }

    public func index(offsetBy distance: Int) -> String.Index {
        precondition(distance >= 0, "Inline extension offsets must move forward")
        return source.index(startIndex, offsetBy: distance, limitedBy: source.endIndex) ?? source.endIndex
    }
}

public struct MarkdownExtensionInlineMatch: Sendable {
    public let name: String
    public let literal: String
    public let fields: [String: String]
    public let endIndex: String.Index

    public init(name: String, literal: String, fields: [String: String], endIndex: String.Index) {
        self.name = name
        self.literal = literal
        self.fields = fields
        self.endIndex = endIndex
    }
}

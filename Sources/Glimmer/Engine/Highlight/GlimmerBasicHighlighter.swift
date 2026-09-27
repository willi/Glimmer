import Foundation

/// A small regex tokenizer for common languages: keywords, numbers, strings, comments.
/// Good enough for chat answers; supply your own `GlimmerHighlighter` for full grammars.
public struct GlimmerBasicHighlighter: GlimmerHighlighter {
    public init() {}

    public func highlight(_ code: String, language: String?) -> [GlimmerHighlightSpan] {
        guard let regex = Self.expression(for: language) else { return [] }
        let whole = NSRange(location: 0, length: (code as NSString).length)
        return regex.matches(in: code, range: whole).compactMap { match in
            for entry in Self.kinds {
                let range = match.range(withName: entry.name)
                if range.location != NSNotFound { return GlimmerHighlightSpan(range: range, kind: entry.kind) }
            }
            return nil
        }
    }

    /// The named groups each family's expression has, in match priority.
    private static let kinds: [(name: String, kind: GlimmerHighlightSpan.Kind)] = [
        ("comment", .comment), ("leading", .keyword), ("string", .string), ("number", .number), ("keyword", .keyword),
    ]

    /// Each family's expression, built once: highlighting runs on every streamed update of a code block.
    /// `NSRegularExpression` is safe to match from several threads.
    nonisolated(unsafe) private static let expressions: [String: NSRegularExpression] = Dictionary(
        uniqueKeysWithValues: Family.all.compactMap { family in
            (try? NSRegularExpression(pattern: family.pattern)).map { (family.name, $0) }
        }
    )

    /// The compiled expression for `language`, or nil for a language no family covers.
    static func expression(for language: String?) -> NSRegularExpression? {
        Family.name(for: language).flatMap { expressions[$0] }
    }
}

extension GlimmerBasicHighlighter {
    struct Family {
        let name: String
        let keywords: [String]
        let commentPatterns: [String]
        /// Keyword-coloured tokens matched before strings: JSON and YAML keys, HTML tags and attributes, CSS at-rules.
        var leadingPatterns: [String] = []
        var caseInsensitiveKeywords = false

        private static let lineComment = "//[^\\n]*"
        private static let blockComment = "/\\*[\\s\\S]*?\\*/"
        private static let hashComment = "#[^\\n]*"
        /// Matches nothing: a family without that kind of token still has the group.
        private static let never = "(?!)"

        /// One alternation scanned left to right: whichever token starts first wins, so `//` inside a string stays
        /// string and a quote inside a comment stays comment.
        var pattern: String {
            let comment = commentPatterns.isEmpty ? Self.never : commentPatterns.joined(separator: "|")
            let leading = leadingPatterns.isEmpty ? Self.never : leadingPatterns.joined(separator: "|")
            let keywordList = keywords.isEmpty ? Self.never : keywords.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
            let keyword = caseInsensitiveKeywords ? "(?i:\(keywordList))" : "(?:\(keywordList))"
            return [
                "(?<comment>\(comment))",
                "(?<leading>\(leading))",
                #"(?<string>"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')"#,
                "(?<number>\\b\\d+(?:\\.\\d+)?\\b)",
                "(?<keyword>(?<![\\w-])\(keyword)(?![\\w-]))",
            ].joined(separator: "|")
        }

        /// The family for a code fence's language, by name or alias.
        static func name(for language: String?) -> String? {
            switch language?.lowercased() {
            case "swift": "swift"
            case "python", "py": "python"
            case "javascript", "js", "jsx", "typescript", "ts", "tsx": "javascript"
            case "ruby", "rb": "ruby"
            case "go", "golang": "go"
            case "java", "kotlin", "kt": "java"
            case "c", "h", "cpp", "c++", "objc", "objective-c": "c"
            case "rust", "rs": "rust"
            case "bash", "sh", "shell", "zsh": "shell"
            case "json": "json"
            case "sql": "sql"
            case "yaml", "yml": "yaml"
            case "html", "xml", "svg": "html"
            case "css", "scss": "css"
            case "csharp", "cs", "c#": "csharp"
            case "php": "php"
            default: nil
            }
        }

        static let all: [Family] = [
            Family(name: "swift", keywords: [
                "let", "var", "func", "return", "if", "else", "guard", "for", "in", "while", "struct", "class", "enum", "protocol",
                "extension", "import", "switch", "case", "default", "break", "continue", "true", "false", "nil", "self", "Self",
                "init", "throws", "throw", "try", "async", "await", "some", "any", "public", "private", "internal", "fileprivate",
                "static", "where",
            ], commentPatterns: [lineComment, blockComment]),
            Family(name: "python", keywords: [
                "def", "return", "if", "elif", "else", "for", "in", "while", "class", "import", "from", "as", "with", "try",
                "except", "finally", "raise", "True", "False", "None", "and", "or", "not", "lambda", "yield", "async", "await",
                "pass", "break", "continue",
            ], commentPatterns: [hashComment]),
            Family(name: "javascript", keywords: [
                "const", "let", "var", "function", "return", "if", "else", "for", "of", "in", "while", "class", "import", "from",
                "export", "default", "new", "this", "true", "false", "null", "undefined", "async", "await", "try", "catch",
                "finally", "throw", "typeof", "interface", "type", "extends", "implements",
            ], commentPatterns: [lineComment, blockComment]),
            Family(name: "ruby", keywords: [
                "def", "end", "return", "if", "elsif", "else", "unless", "for", "in", "while", "class", "module", "require", "do",
                "true", "false", "nil", "self", "yield", "begin", "rescue", "ensure",
            ], commentPatterns: [hashComment]),
            Family(name: "go", keywords: [
                "func", "return", "if", "else", "for", "range", "package", "import", "var", "const", "type", "struct",
                "interface", "map", "chan", "go", "defer", "select", "switch", "case", "default", "true", "false", "nil",
            ], commentPatterns: [lineComment, blockComment]),
            Family(name: "java", keywords: [
                "class", "interface", "fun", "val", "var", "public", "private", "protected", "static", "final", "void", "return",
                "if", "else", "for", "while", "new", "this", "true", "false", "null", "import", "package", "extends",
                "implements", "when", "object", "override",
            ], commentPatterns: [lineComment, blockComment]),
            Family(name: "c", keywords: [
                "int", "char", "float", "double", "void", "return", "if", "else", "for", "while", "struct", "typedef", "enum",
                "static", "const", "unsigned", "signed", "sizeof", "switch", "case", "default", "break", "continue", "NULL",
                "true", "false",
            ], commentPatterns: [lineComment, blockComment]),
            Family(name: "rust", keywords: [
                "fn", "let", "mut", "return", "if", "else", "for", "in", "while", "loop", "match", "struct", "enum", "impl",
                "trait", "use", "pub", "mod", "crate", "self", "Self", "true", "false", "None", "Some", "Ok", "Err", "async",
                "await", "where",
            ], commentPatterns: [lineComment, blockComment]),
            Family(name: "shell", keywords: [
                "if", "then", "else", "fi", "for", "in", "do", "done", "while", "case", "esac", "function", "return", "export",
                "local", "echo",
            ], commentPatterns: [hashComment]),
            // Keys before strings, so a key reads as a key and its value as a string.
            Family(name: "json", keywords: ["true", "false", "null"], commentPatterns: [],
                   leadingPatterns: [#""(?:\\.|[^"\\\n])*"(?=\s*:)"#]),
            Family(name: "sql", keywords: [
                "add", "all", "alter", "and", "any", "as", "asc", "between", "by", "case", "check", "column", "constraint",
                "create", "database", "default", "delete", "desc", "distinct", "drop", "else", "end", "exists", "foreign", "from",
                "full", "group", "having", "in", "index", "inner", "insert", "into", "is", "join", "key", "left", "like", "limit",
                "not", "null", "on", "or", "order", "outer", "primary", "references", "right", "select", "set", "table", "then",
                "top", "truncate", "union", "unique", "update", "values", "view", "when", "where", "with",
                "bigint", "boolean", "char", "date", "datetime", "decimal", "float", "int", "integer", "numeric", "real",
                "smallint", "text", "time", "timestamp", "varchar",
            ], commentPatterns: ["--[^\\n]*", blockComment], caseInsensitiveKeywords: true),
            Family(name: "yaml", keywords: ["true", "false", "null", "yes", "no", "on", "off"], commentPatterns: [hashComment],
                   leadingPatterns: [#"(?m)^[ \t-]*[A-Za-z_][\w.-]*(?=[ \t]*:)"#]),
            Family(name: "html", keywords: [], commentPatterns: ["<!--[\\s\\S]*?-->"],
                   leadingPatterns: [#"</?[A-Za-z][\w:-]*"#, #"(?<=\s)[A-Za-z_:][\w:.-]*(?==)"#]),
            Family(name: "css", keywords: [
                "align-content", "align-items", "align-self", "animation", "background", "border", "border-radius", "bottom",
                "box-shadow", "box-sizing", "color", "content", "cursor", "display", "flex", "float", "font", "font-size",
                "font-weight", "gap", "grid", "height", "justify-content", "left", "line-height", "margin", "max-height",
                "max-width", "min-height", "min-width", "opacity", "overflow", "padding", "position", "right", "text-align",
                "text-decoration", "top", "transform", "transition", "visibility", "width", "z-index",
            ], commentPatterns: [blockComment], leadingPatterns: [#"@[\w-]+"#]),
            Family(name: "csharp", keywords: [
                "abstract", "as", "async", "await", "base", "bool", "break", "byte", "case", "catch", "char", "class", "const",
                "continue", "decimal", "default", "delegate", "do", "double", "else", "enum", "event", "false", "finally", "float",
                "for", "foreach", "if", "in", "int", "interface", "internal", "is", "lock", "long", "namespace", "new", "null",
                "object", "out", "override", "private", "protected", "public", "readonly", "record", "ref", "return", "sealed",
                "static", "string", "struct", "switch", "this", "throw", "true", "try", "typeof", "using", "var", "virtual",
                "void", "while", "yield",
            ], commentPatterns: [lineComment, blockComment]),
            Family(name: "php", keywords: [
                "abstract", "and", "array", "as", "break", "case", "catch", "class", "clone", "const", "continue", "default", "do",
                "echo", "else", "elseif", "extends", "false", "final", "finally", "fn", "for", "foreach", "function", "global",
                "if", "implements", "include", "instanceof", "interface", "match", "namespace", "new", "null", "or", "print",
                "private", "protected", "public", "require", "require_once", "return", "static", "switch", "throw", "trait",
                "true", "try", "use", "var", "while", "yield",
            ], commentPatterns: [lineComment, blockComment, hashComment]),
        ]
    }
}

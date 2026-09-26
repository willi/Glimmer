import Foundation

/// A small regex tokenizer for common languages: keywords, numbers, strings, comments.
/// Good enough for chat answers; supply your own `GlimmerHighlighter` for full grammars.
public struct GlimmerBasicHighlighter: GlimmerHighlighter {
    public init() {}

    public func highlight(_ code: String, language: String?) -> [GlimmerHighlightSpan] {
        guard let family = Family(language) else { return [] }
        let whole = NSRange(location: 0, length: (code as NSString).length)
        var spans: [GlimmerHighlightSpan] = []
        func collect(_ pattern: String, _ kind: GlimmerHighlightSpan.Kind) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            for match in regex.matches(in: code, range: whole) {
                spans.append(GlimmerHighlightSpan(range: match.range, kind: kind))
            }
        }
        collect("\\b(?:" + family.keywords.joined(separator: "|") + ")\\b", .keyword)
        collect("\\b\\d+(?:\\.\\d+)?\\b", .number)
        collect(#""(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'"#, .string)
        for pattern in family.commentPatterns { collect(pattern, .comment) }
        return spans
    }
}

extension GlimmerBasicHighlighter {
    struct Family {
        let keywords: [String]
        let commentPatterns: [String]

        private static let lineComment = "//[^\\n]*"
        private static let blockComment = "/\\*[\\s\\S]*?\\*/"
        private static let hashComment = "#[^\\n]*"

        init?(_ language: String?) {
            switch language?.lowercased() {
            case "swift":
                keywords = ["let", "var", "func", "return", "if", "else", "guard", "for", "in", "while", "struct", "class",
                            "enum", "protocol", "extension", "import", "switch", "case", "default", "break", "continue",
                            "true", "false", "nil", "self", "Self", "init", "throws", "throw", "try", "async", "await",
                            "some", "any", "public", "private", "internal", "fileprivate", "static", "where"]
                commentPatterns = [Self.lineComment, Self.blockComment]
            case "python", "py":
                keywords = ["def", "return", "if", "elif", "else", "for", "in", "while", "class", "import", "from", "as",
                            "with", "try", "except", "finally", "raise", "True", "False", "None", "and", "or", "not",
                            "lambda", "yield", "async", "await", "pass", "break", "continue"]
                commentPatterns = [Self.hashComment]
            case "javascript", "js", "jsx", "typescript", "ts", "tsx":
                keywords = ["const", "let", "var", "function", "return", "if", "else", "for", "of", "in", "while", "class",
                            "import", "from", "export", "default", "new", "this", "true", "false", "null", "undefined",
                            "async", "await", "try", "catch", "finally", "throw", "typeof", "interface", "type",
                            "extends", "implements"]
                commentPatterns = [Self.lineComment, Self.blockComment]
            case "ruby", "rb":
                keywords = ["def", "end", "return", "if", "elsif", "else", "unless", "for", "in", "while", "class",
                            "module", "require", "do", "true", "false", "nil", "self", "yield", "begin", "rescue", "ensure"]
                commentPatterns = [Self.hashComment]
            case "go", "golang":
                keywords = ["func", "return", "if", "else", "for", "range", "package", "import", "var", "const", "type",
                            "struct", "interface", "map", "chan", "go", "defer", "select", "switch", "case", "default",
                            "true", "false", "nil"]
                commentPatterns = [Self.lineComment, Self.blockComment]
            case "java", "kotlin", "kt":
                keywords = ["class", "interface", "fun", "val", "var", "public", "private", "protected", "static", "final",
                            "void", "return", "if", "else", "for", "while", "new", "this", "true", "false", "null",
                            "import", "package", "extends", "implements", "when", "object", "override"]
                commentPatterns = [Self.lineComment, Self.blockComment]
            case "c", "h", "cpp", "c++", "objc", "objective-c":
                keywords = ["int", "char", "float", "double", "void", "return", "if", "else", "for", "while", "struct",
                            "typedef", "enum", "static", "const", "unsigned", "signed", "sizeof", "switch", "case",
                            "default", "break", "continue", "NULL", "true", "false"]
                commentPatterns = [Self.lineComment, Self.blockComment]
            case "rust", "rs":
                keywords = ["fn", "let", "mut", "return", "if", "else", "for", "in", "while", "loop", "match", "struct",
                            "enum", "impl", "trait", "use", "pub", "mod", "crate", "self", "Self", "true", "false",
                            "None", "Some", "Ok", "Err", "async", "await", "where"]
                commentPatterns = [Self.lineComment, Self.blockComment]
            case "bash", "sh", "shell", "zsh":
                keywords = ["if", "then", "else", "fi", "for", "in", "do", "done", "while", "case", "esac", "function",
                            "return", "export", "local", "echo"]
                commentPatterns = [Self.hashComment]
            default:
                return nil
            }
        }
    }
}

import SwiftUI
import Foundation
import os

struct SyntaxHighlighter {
    private let theme: CodeHighlightingTheme
    // Cache highlighted output for repeated code blocks (LRU)
    private struct HighlightState: @unchecked Sendable { var dict: [String: AttributedString] = [:]; var order: [String] = [] }
    private static let highlightCache = OSAllocatedUnfairLock(initialState: HighlightState())
    private static let highlightCapacity = 128

    init(theme: CodeHighlightingTheme) {
        self.theme = theme
    }

    func highlight(code: String, language: String?) -> AttributedString {
        let lang = language?.lowercased() ?? "swift"
        // Cache by (lang, theme, content)
        var th = Hasher(); theme.hash(into: &th)
        var ch = Hasher(); code.hash(into: &ch)
        let key = "hl|\(lang)|\(th.finalize())|\(ch.finalize())"
        if let cached = Self.highlightCache.withLock({ $0.dict[key] }) {
            // touch LRU
            Self.highlightCache.withLock { state in
                if let i = state.order.firstIndex(of: key) { state.order.remove(at: i); state.order.append(key) }
            }
            return cached
        }
        var attributedString = AttributedString(code)
        attributedString.font = .system(.callout, design: .monospaced)

        // Use synchronous version for now, as highlight is called from non-async context
        let compiled = Self.compiledPatternsSync(for: lang, theme: theme)
        let searchRange = NSRange(code.startIndex..., in: code)

        for (regex, color) in compiled {
            regex.enumerateMatches(in: code, range: searchRange) { match, _, _ in
                guard let matchRange = match?.range,
                      let attrRange = Range(matchRange, in: attributedString) else { return }
                attributedString[attrRange].foregroundColor = color
            }
        }

        let rendered = attributedString
        Self.highlightCache.withLock { state in
            if state.dict[key] == nil { state.order.append(key) }
            state.dict[key] = rendered
            while state.order.count > max(1, Self.highlightCapacity) {
                let k = state.order.removeFirst(); state.dict.removeValue(forKey: k)
            }
        }
        return rendered
    }

    // Synchronous wrapper that blocks to get patterns (with a small in-process cache)
    private struct CompiledPatternState: @unchecked Sendable {
        var dict: [String: [(NSRegularExpression, Color)]] = [:]
    }

    private static let compiledCache = OSAllocatedUnfairLock(initialState: CompiledPatternState())

    private static func compiledPatternsSync(for language: String, theme: CodeHighlightingTheme) -> [(NSRegularExpression, Color)] {
        var hasher = Hasher(); theme.hash(into: &hasher)
        let key = language + "#" + String(hasher.finalize())
        if let cached = compiledCache.withLock({ $0.dict[key] }) { return cached }

        let patterns: [(String, Color)]
        switch language {
        case "swift": patterns = swiftPatterns(theme)
        case "javascript", "js": patterns = javascriptPatterns(theme)
        case "typescript", "ts": patterns = typescriptPatterns(theme)
        case "python", "py": patterns = pythonPatterns(theme)
        case "ruby", "rb": patterns = rubyPatterns(theme)
        case "go", "golang": patterns = goPatterns(theme)
        case "rust", "rs": patterns = rustPatterns(theme)
        case "java": patterns = javaPatterns(theme)
        case "c", "cpp", "c++": patterns = cppPatterns(theme)
        case "csharp", "cs": patterns = csharpPatterns(theme)
        case "php": patterns = phpPatterns(theme)
        case "kotlin", "kt": patterns = kotlinPatterns(theme)
        case "shell", "bash", "sh": patterns = shellPatterns(theme)
        case "sql": patterns = sqlPatterns(theme)
        case "html", "xml": patterns = htmlPatterns(theme)
        case "css", "scss": patterns = cssPatterns(theme)
        case "json": patterns = jsonPatterns(theme)
        case "yaml", "yml": patterns = yamlPatterns(theme)
        default: patterns = []
        }
        let compiled: [(NSRegularExpression, Color)] = patterns.compactMap { pat, color in
            do {
                let regex = try NSRegularExpression(pattern: pat)
                return (regex, color)
            } catch {
                #if DEBUG
                print("[SyntaxHighlighter] ERROR: Failed to compile regex pattern '\(pat)' - \(error)")
                #endif
                return nil
            }
        }
        compiledCache.withLock { $0.dict[key] = compiled }
        return compiled
    }

    // Removed deprecated syntaxPatterns() compatibility shim.

    private static func swiftPatterns(_ theme: CodeHighlightingTheme) -> [(String, Color)] {
        [
            (#"//.*|/\*[\s\S]*?\*/"#, theme.comment),
            (#"\"(?:\\.|[^\"])*\""#, theme.string),
            (#"\b[0-9]+(\.[0-9]+)?\b"#, theme.number),
            (#"\b(actor|associatedtype|async|await|break|case|catch|class|continue|default|defer|deinit|do|else|enum|extension|fallthrough|false|fileprivate|for|func|guard|if|import|in|init|inout|internal|is|let|nil|operator|private|protocol|public|repeat|rethrows|return|self|static|struct|subscript|super|switch|throw|throws|true|try|typealias|var|where|while)\b"#, theme.keyword),
            (#"\b(Any|AnyObject|Array|Bool|Character|Color|CGFloat|Date|Dictionary|Double|Error|Float|Font|Int|Image|Never|String|View|URL|UUID)\b"#, theme.type)
        ]
    }

    private static func javascriptPatterns(_ theme: CodeHighlightingTheme) -> [(String, Color)] {
        [
            (#"//.*|/\*[\s\S]*?\*/"#, theme.comment),
            (#"'(?:\\.|[^'])*'|\"(?:\\.|[^\"])*\""#, theme.string),
            (#"\b[0-9]+(\.[0-9]+)?\b"#, theme.number),
            (#"\b(async|await|break|case|catch|class|const|continue|debugger|default|delete|do|else|enum|export|extends|false|finally|for|function|if|implements|import|in|instanceof|interface|let|new|null|package|private|protected|public|return|super|switch|static|this|throw|try|true|typeof|var|void|while|with|yield)\b"#, theme.keyword)
        ]
    }

    private static func pythonPatterns(_ theme: CodeHighlightingTheme) -> [(String, Color)] {
        [
            (#"#.*"#, theme.comment),
            (#"'''[\s\S]*?'''|\"\"\"[\s\S]*?\"\"\"|'(?:\\.|[^'])*'|\"(?:\\.|[^\"])*\""#, theme.string),
            (#"\b[0-9]+(\.[0-9]+)?\b"#, theme.number),
            (#"\b(and|as|assert|break|class|continue|def|del|elif|else|except|False|finally|for|from|global|if|import|in|is|lambda|None|nonlocal|not|or|pass|raise|return|True|try|while|with|yield)\b"#, theme.keyword)
        ]
    }

    private static func rubyPatterns(_ theme: CodeHighlightingTheme) -> [(String, Color)] {
        [
            (#"#.*"#, theme.comment),
            (#"'(?:\\.|[^'])*'|\"(?:\\.|[^\"])*\""#, theme.string),
            (#"\b[0-9]+(\.[0-9]+)?\b"#, theme.number),
            (#"\b(BEGIN|END|alias|and|begin|break|case|class|def|defined\?|do|else|elsif|end|ensure|false|for|if|in|module|next|nil|not|or|redo|rescue|retry|return|self|super|then|true|undef|unless|until|when|while|yield)\b"#, theme.keyword)
        ]
    }
    
    private static func typescriptPatterns(_ theme: CodeHighlightingTheme) -> [(String, Color)] {
        [
            (#"//.*|/\*[\s\S]*?\*/"#, theme.comment),
            (#"'(?:\\.|[^'])*'|\"(?:\\.|[^\"])*\"|`(?:\\.|[^`])*`"#, theme.string),
            (#"\b[0-9]+(\.[0-9]+)?\b"#, theme.number),
            (#"\b(abstract|any|as|async|await|boolean|break|case|catch|class|const|constructor|continue|debugger|declare|default|delete|do|else|enum|export|extends|false|finally|for|from|function|get|if|implements|import|in|instanceof|interface|is|keyof|let|module|namespace|never|new|null|number|of|package|private|protected|public|readonly|require|return|set|static|string|super|switch|symbol|this|throw|true|try|type|typeof|undefined|union|unknown|var|void|while|with|yield)\b"#, theme.keyword),
            (#"\b(Array|Boolean|Date|Error|Function|Map|Number|Object|Promise|RegExp|Set|String|Symbol|WeakMap|WeakSet)\b"#, theme.type)
        ]
    }
    
    private static func goPatterns(_ theme: CodeHighlightingTheme) -> [(String, Color)] {
        [
            (#"//.*|/\*[\s\S]*?\*/"#, theme.comment),
            (#"\"(?:\\.|[^\"])*\"|`[^`]*`"#, theme.string),
            (#"\b[0-9]+(\.[0-9]+)?\b"#, theme.number),
            (#"\b(break|case|chan|const|continue|default|defer|else|fallthrough|for|func|go|goto|if|import|interface|map|package|range|return|select|struct|switch|type|var)\b"#, theme.keyword),
            (#"\b(bool|byte|complex64|complex128|error|float32|float64|int|int8|int16|int32|int64|rune|string|uint|uint8|uint16|uint32|uint64|uintptr|true|false|nil)\b"#, theme.type)
        ]
    }
    
    private static func rustPatterns(_ theme: CodeHighlightingTheme) -> [(String, Color)] {
        [
            (#"//.*|/\*[\s\S]*?\*/"#, theme.comment),
            (#"\"(?:\\.|[^\"])*\""#, theme.string),  // Simplified to avoid raw string literal issues
            (#"\b[0-9]+(\.[0-9]+)?\b"#, theme.number),
            (#"\b(as|async|await|break|const|continue|crate|dyn|else|enum|extern|false|fn|for|if|impl|in|let|loop|match|mod|move|mut|pub|ref|return|self|Self|static|struct|super|trait|true|type|unsafe|use|where|while)\b"#, theme.keyword),
            (#"\b(bool|char|f32|f64|i8|i16|i32|i64|i128|isize|str|u8|u16|u32|u64|u128|usize|Option|Result|Vec|String|Box)\b"#, theme.type),
            (#"'[a-zA-Z_][a-zA-Z0-9_]*"#, theme.keyword)
        ]
    }
    
    private static func javaPatterns(_ theme: CodeHighlightingTheme) -> [(String, Color)] {
        [
            (#"//.*|/\*[\s\S]*?\*/"#, theme.comment),
            (#"\"(?:\\.|[^\"])*\""#, theme.string),
            (#"\b[0-9]+(\.[0-9]+)?[fFdDlL]?\b"#, theme.number),
            (#"\b(abstract|assert|boolean|break|byte|case|catch|char|class|const|continue|default|do|double|else|enum|extends|final|finally|float|for|goto|if|implements|import|instanceof|int|interface|long|native|new|null|package|private|protected|public|return|short|static|strictfp|super|switch|synchronized|this|throw|throws|transient|try|void|volatile|while)\b"#, theme.keyword),
            (#"\b(Boolean|Byte|Character|Class|Double|Float|Integer|Long|Object|Short|String|Thread|Void)\b"#, theme.type),
            (#"@\w+"#, theme.keyword)
        ]
    }
    
    private static func cppPatterns(_ theme: CodeHighlightingTheme) -> [(String, Color)] {
        [
            (#"//.*|/\*[\s\S]*?\*/"#, theme.comment),
            (#"\"(?:\\.|[^\"])*\"|'(?:\\.|[^'])*'"#, theme.string),
            (#"\b[0-9]+(\.[0-9]+)?[fFdDlLuU]?\b"#, theme.number),
            (#"\b(alignas|alignof|and|and_eq|asm|auto|bitand|bitor|bool|break|case|catch|char|class|compl|const|constexpr|continue|decltype|default|delete|do|double|dynamic_cast|else|enum|explicit|export|extern|false|float|for|friend|goto|if|inline|int|long|mutable|namespace|new|noexcept|not|not_eq|nullptr|operator|or|or_eq|private|protected|public|register|reinterpret_cast|return|short|signed|sizeof|static|static_assert|static_cast|struct|switch|template|this|throw|true|try|typedef|typeid|typename|union|unsigned|using|virtual|void|volatile|wchar_t|while|xor|xor_eq)\b"#, theme.keyword),
            (#"#\s*\w+"#, theme.keyword)
        ]
    }
    
    private static func csharpPatterns(_ theme: CodeHighlightingTheme) -> [(String, Color)] {
        [
            (#"//.*|/\*[\s\S]*?\*/"#, theme.comment),
            (#"@?\"(?:\\.|[^\"])*\"|'(?:\\.|[^'])*'"#, theme.string),
            (#"\b[0-9]+(\.[0-9]+)?[fFdDmMlLuU]?\b"#, theme.number),
            (#"\b(abstract|as|async|await|base|bool|break|byte|case|catch|char|checked|class|const|continue|decimal|default|delegate|do|double|else|enum|event|explicit|extern|false|finally|fixed|float|for|foreach|goto|if|implicit|in|int|interface|internal|is|lock|long|namespace|new|null|object|operator|out|override|params|private|protected|public|readonly|ref|return|sbyte|sealed|short|sizeof|stackalloc|static|string|struct|switch|this|throw|true|try|typeof|uint|ulong|unchecked|unsafe|ushort|using|var|virtual|void|volatile|while|yield)\b"#, theme.keyword),
            (#"\b(Boolean|Byte|Char|DateTime|Decimal|Double|Int16|Int32|Int64|Object|SByte|Single|String|UInt16|UInt32|UInt64|Void)\b"#, theme.type)
        ]
    }
    
    private static func phpPatterns(_ theme: CodeHighlightingTheme) -> [(String, Color)] {
        [
            (#"//.*|/\*[\s\S]*?\*/|#.*"#, theme.comment),
            (#"'(?:\\.|[^'])*'|\"(?:\\.|[^\"])*\""#, theme.string),
            (#"\b[0-9]+(\.[0-9]+)?\b"#, theme.number),
            (#"\b(abstract|and|array|as|break|callable|case|catch|class|clone|const|continue|declare|default|die|do|echo|else|elseif|empty|enddeclare|endfor|endforeach|endif|endswitch|endwhile|eval|exit|extends|final|finally|fn|for|foreach|function|global|goto|if|implements|include|include_once|instanceof|insteadof|interface|isset|list|match|namespace|new|or|print|private|protected|public|require|require_once|return|static|switch|throw|trait|try|unset|use|var|while|xor|yield)\b"#, theme.keyword),
            (#"\$\w+"#, theme.type)
        ]
    }
    
    private static func kotlinPatterns(_ theme: CodeHighlightingTheme) -> [(String, Color)] {
        [
            (#"//.*|/\*[\s\S]*?\*/"#, theme.comment),
            (#"\"(?:\\.|[^\"])*\"|\"\"\"[\s\S]*?\"\"\""#, theme.string),
            (#"\b[0-9]+(\.[0-9]+)?[fFdDlL]?\b"#, theme.number),
            (#"\b(abstract|actual|annotation|as|break|by|catch|class|companion|const|constructor|continue|crossinline|data|do|dynamic|else|enum|expect|external|false|final|finally|for|fun|get|if|import|in|infix|init|inline|inner|interface|internal|is|lateinit|noinline|null|object|open|operator|out|override|package|private|protected|public|reified|return|sealed|set|super|suspend|tailrec|this|throw|true|try|typealias|typeof|val|var|vararg|when|where|while)\b"#, theme.keyword),
            (#"\b(Boolean|Byte|Char|Double|Float|Int|Long|Short|String|Unit|Any|Nothing)\b"#, theme.type),
            (#"@\w+"#, theme.keyword)
        ]
    }
    
    private static func shellPatterns(_ theme: CodeHighlightingTheme) -> [(String, Color)] {
        [
            (#"#.*"#, theme.comment),
            (#"'(?:\\.|[^'])*'|\"(?:\\.|[^\"])*\""#, theme.string),
            (#"\b[0-9]+\b"#, theme.number),
            (#"\b(alias|bg|bind|break|builtin|case|cd|command|compgen|complete|continue|declare|dirs|disown|do|done|echo|elif|else|enable|esac|eval|exec|exit|export|false|fc|fg|fi|for|function|getopts|hash|help|history|if|in|jobs|kill|let|local|logout|popd|printf|pushd|pwd|read|readonly|return|select|set|shift|shopt|source|suspend|test|then|time|times|trap|true|type|typeset|ulimit|umask|unalias|unset|until|wait|while)\b"#, theme.keyword),
            (#"\$\w+|\$\{[^}]+\}"#, theme.type)
        ]
    }
    
    private static func sqlPatterns(_ theme: CodeHighlightingTheme) -> [(String, Color)] {
        [
            (#"--.*|/\*[\s\S]*?\*/"#, theme.comment),
            (#"'(?:''|[^'])*'"#, theme.string),
            (#"\b[0-9]+(\.[0-9]+)?\b"#, theme.number),
            (#"\b(?i)(ADD|ALL|ALTER|AND|ANY|AS|ASC|BACKUP|BETWEEN|CASE|CHECK|COLUMN|CONSTRAINT|CREATE|DATABASE|DEFAULT|DELETE|DESC|DISTINCT|DROP|EXEC|EXISTS|FOREIGN|FROM|FULL|GROUP|HAVING|IN|INDEX|INNER|INSERT|INTO|IS|JOIN|KEY|LEFT|LIKE|LIMIT|NOT|NULL|OR|ORDER|OUTER|PRIMARY|PROCEDURE|RIGHT|ROWNUM|SELECT|SET|TABLE|TOP|TRUNCATE|UNION|UNIQUE|UPDATE|VALUES|VIEW|WHERE)\b"#, theme.keyword),
            (#"\b(?i)(bigint|bit|date|datetime|decimal|float|int|money|nchar|ntext|numeric|nvarchar|real|smallint|text|time|timestamp|tinyint|uniqueidentifier|varchar)\b"#, theme.type)
        ]
    }
    
    private static func htmlPatterns(_ theme: CodeHighlightingTheme) -> [(String, Color)] {
        [
            (#"<!--[\s\S]*?-->"#, theme.comment),
            (#"</?[a-zA-Z][^>]*>"#, theme.keyword),
            (#"\"[^\"]*\"|'[^']*'"#, theme.string),
            (#"&[a-zA-Z]+;"#, theme.type)
        ]
    }
    
    private static func cssPatterns(_ theme: CodeHighlightingTheme) -> [(String, Color)] {
        [
            (#"/\*[\s\S]*?\*/"#, theme.comment),
            (#"\"[^\"]*\"|'[^']*'"#, theme.string),
            (#"#[0-9a-fA-F]{3,8}\b"#, theme.number),
            (#"\b[0-9]+(\.[0-9]+)?(px|em|rem|%|vh|vw|deg|s|ms)?\b"#, theme.number),
            (#"\.[a-zA-Z][\w-]*"#, theme.type),
            (#"#[a-zA-Z][\w-]*"#, theme.type),
            (#"\b(align-content|align-items|align-self|animation|background|border|bottom|box-shadow|box-sizing|clear|color|content|cursor|display|flex|float|font|grid|height|justify-content|left|line-height|margin|max-height|max-width|min-height|min-width|opacity|overflow|padding|position|right|text-align|text-decoration|text-transform|top|transform|transition|vertical-align|visibility|width|z-index)\b"#, theme.keyword)
        ]
    }
    
    private static func jsonPatterns(_ theme: CodeHighlightingTheme) -> [(String, Color)] {
        [
            (#"\"[^\"]*\"\s*:"#, theme.keyword),
            (#"\"[^\"]*\""#, theme.string),
            (#"\b(true|false|null)\b"#, theme.keyword),
            (#"\b-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?\b"#, theme.number)
        ]
    }
    
    private static func yamlPatterns(_ theme: CodeHighlightingTheme) -> [(String, Color)] {
        [
            (#"#.*"#, theme.comment),
            (#"^[a-zA-Z_][\w]*:"#, theme.keyword),
            (#"'[^']*'|\"[^\"]*\""#, theme.string),
            (#"\b(true|false|null|yes|no|on|off)\b"#, theme.keyword),
            (#"\b-?[0-9]+(\.[0-9]+)?\b"#, theme.number),
            (#"^-\s+"#, theme.keyword)
        ]
    }
}

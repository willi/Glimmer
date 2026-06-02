import Foundation

/// Markdown linter for checking document quality and consistency
public struct MarkdownLinter {
    
    // MARK: - Lint Rules
    
    /// Lint rule severity levels
    public enum Severity: String, CaseIterable {
        case error
        case warning
        case info
        case style
    }
    
    /// Lint issue found in markdown
    public struct LintIssue: Identifiable {
        public let id: UUID = UUID()
        public let rule: String
        public let severity: Severity
        public let message: String
        public let line: Int
        public let column: Int
        public let suggestion: String?
        
        public init(rule: String, severity: Severity, message: String, line: Int, column: Int, suggestion: String? = nil) {
            self.rule = rule
            self.severity = severity
            self.message = message
            self.line = line
            self.column = column
            self.suggestion = suggestion
        }
    }
    
    /// Linter configuration
    public struct LintConfiguration {
        // Document structure
        public var requireTitleHeading: Bool = true
        public var maxHeadingLength: Int = 60
        public var incrementalHeadings: Bool = true
        public var consistentHeadingStyle: Bool = true
        
        // Lists
        public var consistentListMarkers: Bool = true
        public var indentSize: Int = 2
        public var orderedListStyle: OrderedListStyle = .period
        
        // Line length
        public var maxLineLength: Int = 100
        public var ignoreCodeBlocks: Bool = true
        public var ignoreTables: Bool = true
        
        // Whitespace
        public var noTrailingSpaces: Bool = true
        public var noMultipleBlankLines: Bool = true
        public var blankLineAroundHeadings: Bool = true
        public var blankLineAroundCodeBlocks: Bool = true
        
        // Links
        public var noEmptyLinks: Bool = true
        public var noBrokenLocalLinks: Bool = true
        public var preferReferenceLinks: Bool = false
        
        // Code
        public var fencedCodeLanguage: Bool = true
        public var consistentCodeFence: Bool = true
        
        // Emphasis
        public var consistentEmphasisStyle: Bool = true
        public var noMultipleSpaces: Bool = true
        
        public init() {}
        
        public static let `default` = LintConfiguration()
        public static let strict: LintConfiguration = {
            var config = LintConfiguration()
            config.requireTitleHeading = true
            config.maxHeadingLength = 50
            config.incrementalHeadings = true
            config.maxLineLength = 80
            config.preferReferenceLinks = true
            config.fencedCodeLanguage = true
            return config
        }()
    }
    
    public enum OrderedListStyle {
        case period  // 1.
        case parenthesis  // 1)
    }
    
    // MARK: - Public API
    
    /// Lint markdown content and return issues
    public static func lint(_ markdown: String, configuration: LintConfiguration = .default) -> [LintIssue] {
        var issues: [LintIssue] = []
        
        // Parse markdown to AST with source line locations
        let locatedBlocks = MarkdownParser.parseWithLocations(markdown, configuration: .default)
        let blocks = locatedBlocks.map { $0.node }
        let startLines = locatedBlocks.map { $0.startLine }
        
        // Line-based checks
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        issues.append(contentsOf: checkLineIssues(lines, configuration: configuration))
        
        // Structure checks
        issues.append(contentsOf: checkDocumentStructure(blocks, lines: lines, configuration: configuration, startLines: startLines))
        
        // Heading checks
        issues.append(contentsOf: checkHeadings(blocks, lines: lines, configuration: configuration, startLines: startLines))
        
        // List checks
        issues.append(contentsOf: checkLists(blocks, lines: lines, configuration: configuration, startLines: startLines))
        
        // Link checks
        issues.append(contentsOf: checkLinks(blocks, configuration: configuration, startLines: startLines))
        
        // Code block checks
        issues.append(contentsOf: checkCodeBlocks(blocks, lines: lines, configuration: configuration, startLines: startLines))
        
        // Sort issues by line number
        issues.sort { $0.line < $1.line }
        
        return issues
    }
    
    // MARK: - Line-based Checks
    
    private static func checkLineIssues(_ lines: [String], configuration: LintConfiguration) -> [LintIssue] {
        var issues: [LintIssue] = []
        var previousWasBlank = false
        var blankLineCount = 0
        
        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1
            let inCodeBlock = isInCodeBlock(at: index, lines: lines)
            let tableLine = isTableLine(line)
            
            // Check line length
            if configuration.maxLineLength > 0 && line.count > configuration.maxLineLength {
                let shouldIgnore = (configuration.ignoreCodeBlocks && inCodeBlock) ||
                    (configuration.ignoreTables && tableLine)
                if !shouldIgnore {
                    issues.append(LintIssue(
                        rule: "line-length",
                        severity: .warning,
                        message: "Line exceeds maximum length of \(configuration.maxLineLength) characters",
                        line: lineNumber,
                        column: configuration.maxLineLength + 1,
                        suggestion: "Consider breaking this line into multiple lines"
                    ))
                }
            }
            
            // Check trailing spaces (ensure proper precedence)
            if configuration.noTrailingSpaces && (line.hasSuffix(" ") || line.hasSuffix("\t")) {
                // Allow two spaces for line breaks
                if !line.hasSuffix("  ") || line.hasSuffix("   ") {
                    issues.append(LintIssue(
                        rule: "no-trailing-spaces",
                        severity: .style,
                        message: "Line has trailing whitespace",
                        line: lineNumber,
                        column: line.count,
                        suggestion: "Remove trailing whitespace"
                    ))
                }
            }
            
            // Check multiple blank lines
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank {
                blankLineCount += 1
                if configuration.noMultipleBlankLines && previousWasBlank {
                    issues.append(LintIssue(
                        rule: "no-multiple-blank-lines",
                        severity: .style,
                        message: "Multiple consecutive blank lines",
                        line: lineNumber,
                        column: 1,
                        suggestion: "Remove extra blank lines"
                    ))
                }
                previousWasBlank = true
            } else {
                blankLineCount = 0
                previousWasBlank = false
            }
            
            // Check multiple spaces
            if configuration.noMultipleSpaces && line.contains("  ") {
                let shouldIgnore = (configuration.ignoreCodeBlocks && inCodeBlock) ||
                    (configuration.ignoreTables && tableLine)
                if shouldIgnore {
                    continue
                }
                // Allow double spaces at end for line breaks
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("  ") {
                    issues.append(LintIssue(
                        rule: "no-multiple-spaces",
                        severity: .style,
                        message: "Multiple consecutive spaces",
                        line: lineNumber,
                        column: line.firstIndex(of: " ")?.utf16Offset(in: line) ?? 1,
                        suggestion: "Use single spaces between words"
                    ))
                }
            }
        }
        
        return issues
    }
    
    // MARK: - Structure Checks
    
    private static func checkDocumentStructure(_ blocks: [MarkdownParser.BlockNode], lines: [String], configuration: LintConfiguration, startLines: [Int]) -> [LintIssue] {
        var issues: [LintIssue] = []
        
        // Check for title heading
        if configuration.requireTitleHeading {
            let hasH1 = blocks.contains { block in
                if case .heading(let level, _, _) = block {
                    return level == 1
                }
                return false
            }
            
            if !hasH1 {
                issues.append(LintIssue(
                    rule: "require-title-heading",
                    severity: .warning,
                    message: "Document should start with a level 1 heading",
                    line: 1,
                    column: 1,
                    suggestion: "Add a # Title at the beginning of the document"
                ))
            }
        }
        
        // Check blank lines around headings
        if configuration.blankLineAroundHeadings {
            for (index, block) in blocks.enumerated() {
                if case .heading = block {
                    let lineNum = (index < startLines.count ? max(1, startLines[index]) : lineNumber(forIndex: index, in: blocks))
                    
                    // Check blank line before (except first heading)
                    if index > 0 && lineNum > 1 {
                        if (lineNum - 2) >= 0 && (lineNum - 2) < lines.count && !lines[lineNum - 2].isEmpty {
                            issues.append(LintIssue(
                                rule: "blank-line-around-headings",
                                severity: .style,
                                message: "Heading should be preceded by a blank line",
                                line: lineNum,
                                column: 1,
                                suggestion: "Add a blank line before the heading"
                            ))
                        }
                    }
                }
            }
        }
        
        return issues
    }
    
    // MARK: - Heading Checks
    
    private static func checkHeadings(_ blocks: [MarkdownParser.BlockNode], lines: [String], configuration: LintConfiguration, startLines: [Int]) -> [LintIssue] {
        var issues: [LintIssue] = []
        var previousLevel = 0
        var headingStyles: Set<HeadingStyle> = []
        
        enum HeadingStyle {
            case atx
            case setext
        }
        
        for (idx, block) in blocks.enumerated() {
            if case .heading(let level, let content, _) = block {
                let lineNum = (idx < startLines.count ? max(1, startLines[idx]) : lineNumber(forIndex: idx, in: blocks))

                if (lineNum - 1) >= 0 && (lineNum - 1) < lines.count {
                    let headingLine = lines[lineNum - 1].trimmingCharacters(in: .whitespaces)
                    if headingLine.hasPrefix("#") {
                        headingStyles.insert(.atx)
                    } else if lineNum < lines.count {
                        let underlineLine = lines[lineNum].trimmingCharacters(in: .whitespaces)
                        if !underlineLine.isEmpty && underlineLine.allSatisfy({ $0 == "=" || $0 == "-" }) {
                            headingStyles.insert(.setext)
                        }
                    }
                }
                
                // Check heading length
                let headingText = extractText(from: content)
                if configuration.maxHeadingLength > 0 && headingText.count > configuration.maxHeadingLength {
                    issues.append(LintIssue(
                        rule: "heading-length",
                        severity: .warning,
                        message: "Heading exceeds maximum length of \(configuration.maxHeadingLength) characters",
                        line: lineNum,
                        column: 1,
                        suggestion: "Consider shortening the heading"
                    ))
                }
                
                // Check incremental headings
                if configuration.incrementalHeadings && previousLevel > 0 {
                    if level > previousLevel + 1 {
                        issues.append(LintIssue(
                            rule: "incremental-headings",
                            severity: .warning,
                            message: "Heading level skipped (from h\(previousLevel) to h\(level))",
                            line: lineNum,
                            column: 1,
                            suggestion: "Use h\(previousLevel + 1) instead"
                        ))
                    }
                }
                previousLevel = level
            }
        }
        
        // Check consistent heading style
        if configuration.consistentHeadingStyle && headingStyles.count > 1 {
            issues.append(LintIssue(
                rule: "consistent-heading-style",
                severity: .style,
                message: "Inconsistent heading styles (mix of ATX and Setext)",
                line: 1,
                column: 1,
                suggestion: "Use consistent heading style throughout the document"
            ))
        }
        
        return issues
    }
    
    // MARK: - List Checks
    
    private static func checkLists(_ blocks: [MarkdownParser.BlockNode], lines: [String], configuration: LintConfiguration, startLines: [Int]) -> [LintIssue] {
        var issues: [LintIssue] = []
        var listMarkers: Set<String> = []

        for (idx, block) in blocks.enumerated() {
            if case .list(let ordered, _, let items) = block {
                let lineNum = (idx < startLines.count ? max(1, startLines[idx]) : lineNumber(forIndex: idx, in: blocks))
                
                if !ordered {
                    // Track unordered list markers from source for consistency checks.
                    if (lineNum - 1) >= 0 && (lineNum - 1) < lines.count {
                        let listLine = lines[lineNum - 1].trimmingCharacters(in: .whitespaces)
                        if let marker = listLine.first, marker == "-" || marker == "*" || marker == "+" {
                            listMarkers.insert(String(marker))
                        }
                    }
                }
                
                // Check for empty list items
                for (index, item) in items.enumerated() {
                    if item.content.isEmpty {
                        issues.append(LintIssue(
                            rule: "no-empty-list-items",
                            severity: .warning,
                            message: "Empty list item",
                            line: lineNum + index,
                            column: 1,
                            suggestion: "Add content to the list item or remove it"
                        ))
                    }
                }
            }
        }
        
        // Check consistent list markers
        if configuration.consistentListMarkers && listMarkers.count > 1 {
            issues.append(LintIssue(
                rule: "consistent-list-markers",
                severity: .style,
                message: "Inconsistent list markers",
                line: 1,
                column: 1,
                suggestion: "Use consistent list markers (-, *, or +) throughout the document"
            ))
        }
        
        return issues
    }
    
    // MARK: - Link Checks
    
    private static func checkLinks(_ blocks: [MarkdownParser.BlockNode], configuration: LintConfiguration, startLines: [Int]) -> [LintIssue] {
        var issues: [LintIssue] = []
        
        func checkInlines(_ inlines: [MarkdownParser.InlineNode], lineNum: Int) {
            for inline in inlines {
                switch inline {
                case .link(let url, _, let children):
                    // Check for empty link text
                    if configuration.noEmptyLinks && extractText(from: children).isEmpty {
                        issues.append(LintIssue(
                            rule: "no-empty-links",
                            severity: .warning,
                            message: "Empty link text",
                            line: lineNum,
                            column: 1,
                            suggestion: "Add descriptive text to the link"
                        ))
                    }
                    
                    // Check for broken local links
                    if configuration.noBrokenLocalLinks && url.scheme == "file" {
                        if !FileManager.default.fileExists(atPath: url.path) {
                            issues.append(LintIssue(
                                rule: "no-broken-local-links",
                                severity: .error,
                                message: "Broken local link: \(url.path)",
                                line: lineNum,
                                column: 1,
                                suggestion: "Fix the link path or remove the link"
                            ))
                        }
                    }
                    
                case .emphasis(let children), .strong(let children), .strikethrough(let children):
                    checkInlines(children, lineNum: lineNum)
                    
                default:
                    break
                }
            }
        }
        
        // Check all blocks for links
        for (idx, block) in blocks.enumerated() {
            let lineNum = (idx < startLines.count ? max(1, startLines[idx]) : lineNumber(forIndex: idx, in: blocks))
            
            switch block {
            case .paragraph(let content):
                checkInlines(content, lineNum: lineNum)
            case .heading(_, let content, _):
                checkInlines(content, lineNum: lineNum)
            case .list(_, _, let items):
                for item in items {
                    for subBlock in item.content {
                        if case .paragraph(let content) = subBlock {
                            checkInlines(content, lineNum: lineNum)
                        }
                    }
                }
            default:
                break
            }
        }
        
        return issues
    }
    
    // MARK: - Code Block Checks
    
    private static func checkCodeBlocks(_ blocks: [MarkdownParser.BlockNode], lines: [String], configuration: LintConfiguration, startLines: [Int]) -> [LintIssue] {
        var issues: [LintIssue] = []
        var fenceStyles: Set<String> = []
        
        for (idx, block) in blocks.enumerated() {
            if case .codeBlock(let language, let content) = block {
                let lineNum = (idx < startLines.count ? max(1, startLines[idx]) : lineNumber(forIndex: idx, in: blocks))
                
                // Check for language specification
                if configuration.fencedCodeLanguage && language == nil {
                    issues.append(LintIssue(
                        rule: "fenced-code-language",
                        severity: .info,
                        message: "Code block is missing language specification",
                        line: lineNum,
                        column: 1,
                        suggestion: "Add a language identifier after the opening fence"
                    ))
                }
                
                // Check for empty code blocks
                if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(LintIssue(
                        rule: "no-empty-code-blocks",
                        severity: .warning,
                        message: "Empty code block",
                        line: lineNum,
                        column: 1,
                        suggestion: "Add code or remove the empty block"
                    ))
                }
                
                // Track fence style from source line.
                if (lineNum - 1) >= 0 && (lineNum - 1) < lines.count {
                    let sourceLine = lines[lineNum - 1].trimmingCharacters(in: .whitespaces)
                    if sourceLine.hasPrefix("```") {
                        fenceStyles.insert("```")
                    } else if sourceLine.hasPrefix("~~~") {
                        fenceStyles.insert("~~~")
                    }
                }
            }
        }
        
        // Check consistent code fence style
        if configuration.consistentCodeFence && fenceStyles.count > 1 {
            issues.append(LintIssue(
                rule: "consistent-code-fence",
                severity: .style,
                message: "Inconsistent code fence styles",
                line: 1,
                column: 1,
                suggestion: "Use consistent code fence style (``` or ~~~) throughout the document"
            ))
        }
        
        return issues
    }
    
    // MARK: - Helper Methods
    
    private static func isInCodeBlock(at lineIndex: Int, lines: [String]) -> Bool {
        var inCodeBlock = false
        var fence: String?
        
        for i in 0..<lineIndex {
            let line = lines[i]
            if line.starts(with: "```") || line.starts(with: "~~~") {
                if fence == nil {
                    fence = String(line.prefix(3))
                    inCodeBlock = true
                } else if line.starts(with: fence!) {
                    fence = nil
                    inCodeBlock = false
                }
            }
        }
        
        return inCodeBlock
    }
    
    private static func isTableLine(_ line: String) -> Bool {
        return line.contains("|") && (line.contains("-") || line.trimmingCharacters(in: .whitespaces).starts(with: "|"))
    }
    
    private static func lineNumber(forIndex index: Int, in blocks: [MarkdownParser.BlockNode]) -> Int {
        // Estimate the starting line of the block at `index` by summing prior blocks.
        // This is heuristic, but avoids out-of-bounds and gives stable ordering.
        var lineNum = 1
        if index <= 0 { return lineNum }
        for i in 0..<min(index, blocks.count) {
            lineNum += estimateBlockLines(blocks[i])
        }
        return max(1, lineNum)
    }
    
    private static func estimateBlockLines(_ block: MarkdownParser.BlockNode) -> Int {
        switch block {
        case .heading:
            return 2  // Heading + blank line
        case .paragraph:
            return 2  // Paragraph + blank line
        case .codeBlock(_, let content):
            return content.split(separator: "\n").count + 3  // Fences + content + blank line
        case .list(_, _, let items):
            return items.count + 1
        case .table(_, let rows):
            return rows.count + 3  // Header + separator + rows + blank line
        default:
            return 1
        }
    }
    
    private static func extractText(from inlines: [MarkdownParser.InlineNode]) -> String {
        var text = ""
        for inline in inlines {
            switch inline {
            case .text(let t):
                text += t
            case .emphasis(let children), .strong(let children), .strikethrough(let children):
                text += extractText(from: children)
            case .code(let c):
                text += c
            case .link(_, _, let children):
                text += extractText(from: children)
            default:
                break
            }
        }
        return text
    }
}

// MARK: - Convenience Extensions

public extension MarkdownLinter.LintIssue {
    /// Format issue as a string for display
    var formatted: String {
        let severityIcon: String
        switch severity {
        case .error: severityIcon = "❌"
        case .warning: severityIcon = "⚠️"
        case .info: severityIcon = "ℹ️"
        case .style: severityIcon = "💅"
        }
        
        var result = "\(severityIcon) [\(rule)] Line \(line):\(column) - \(message)"
        if let suggestion = suggestion {
            result += "\n    💡 \(suggestion)"
        }
        return result
    }
}

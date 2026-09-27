import SwiftUI
import Glimmer

struct LinterDemoView: View {
    @State private var markdown = """
    # Markdown Linter Demo
    
    This demo shows the new **Markdown Linting** capabilities added to Glimmer.
    
    ## Sample Markdown with Issues
    
    Below is markdown with various linting issues that can be detected:
    
    ###Heading without space after ###
    
    - List item 1
    *  List item with inconsistent marker
    +  Another inconsistent marker
    
    [Empty link text]()
    
    ```
    Code block without language specification
    ```
    
    This line is way too long and exceeds the recommended maximum line length of 100 characters which will trigger a linting warning.
    
    Multiple  spaces  between  words  
    
    Trailing spaces at the end of this line   
    
    
    
    Multiple blank lines above
    
    ## Try It Yourself
    
    Edit the markdown above and click "Lint" to see the issues!
    """
    
    @State private var lintResults: [MarkdownLinter.LintIssue] = []
    @State private var showingLintResults = false
    @State private var selectedConfigType = ConfigType.default
    @State private var jumpTarget: EditorTextView.JumpTarget? = nil
    
    enum ConfigType: String, CaseIterable {
        case `default` = "Default"
        case strict = "Strict"
        
        var configuration: MarkdownLinter.LintConfiguration {
            switch self {
            case .default: return .default
            case .strict: return .strict
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Controls
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Text("Markdown Editor")
                            .font(.headline)
                        Spacer(minLength: 12)
                        Picker("Lint Config", selection: $selectedConfigType) {
                            ForEach(ConfigType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 260)
                    }
                    HStack(spacing: 12) {
                        Button("Lint") { lintMarkdown() }
                            .buttonStyle(.borderedProminent)
                        Button("Fix Simple Issues") {
                            fixSimpleIssues(); lintMarkdown()
                        }
                        .buttonStyle(.bordered)
                        Button("Clear") {
                            showingLintResults = false; lintResults = []
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal)

                // Editor
                EditorTextView(text: $markdown, jumpTarget: $jumpTarget)
                    .frame(minHeight: 240)
                    .padding(.horizontal)

                // Preview
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.headline)
                        .padding(.horizontal)
                    MarkdownView(markdown: markdown)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal)
                }

                // Results
                if showingLintResults {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Lint Results")
                                .font(.headline)
                            Spacer()
                            if !lintResults.isEmpty {
                                Text("\(lintResults.count)")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            }
                        }
                        .padding(.horizontal)

                        if lintResults.isEmpty {
                            Text("No issues found")
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(lintResults) { issue in
                                    LintIssueRow(
                                        issue: issue,
                                        linePreview: previewLine(for: issue.line),
                                        caretColumn: issue.column
                                    ) {
                                        jumpTarget = .init(line: issue.line, column: issue.column)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Markdown Linter")
    }
    
    func lintMarkdown() {
        lintResults = MarkdownLinter.lint(markdown, configuration: selectedConfigType.configuration)
        showingLintResults = true
    }

    private func previewLine(for line: Int) -> String? {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard line > 0 && line <= lines.count else { return nil }
        return lines[line - 1]
    }
}

struct LintIssueRow: View {
    let issue: MarkdownLinter.LintIssue
    let linePreview: String?
    let caretColumn: Int?
    var onTap: (() -> Void)? = nil
    
    var severityIcon: String {
        switch issue.severity {
        case .error: return "❌"
        case .warning: return "⚠️"
        case .info: return "ℹ️"
        case .style: return "💅"
        }
    }
    
    var severityColor: Color {
        switch issue.severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        case .style: return .purple
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(severityIcon)
                .font(.system(size: 14))
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("[\(issue.rule)]")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(severityColor)
                    
                    Text("Line \(issue.line):\(issue.column)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Text(issue.message)
                    .font(.system(size: 13))

                if let preview = linePreview {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preview)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        if let col = caretColumn, col > 0 {
                            let spaces = String(repeating: " ", count: max(0, min(preview.count, col - 1)))
                            Text(spaces + "^")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 2)
                }
                
                if let suggestion = issue.suggestion {
                    Text("💡 \(suggestion)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(severityColor.opacity(0.1))
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}

// MARK: - Simple Auto-fixes
extension LinterDemoView {
    private func fixSimpleIssues() {
        let rawLines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var lines: [String] = []
        lines.reserveCapacity(rawLines.count)
        var inCode = false
        var fence: String? = nil

        for var line in rawLines {
            // Toggle code fences
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                if let f = fence {
                    if line.hasPrefix(f) { fence = nil; inCode = false }
                } else {
                    fence = String(line.prefix(3)); inCode = true
                }
                lines.append(line)
                continue
            }

            if inCode { lines.append(line); continue }

            // 1) Insert space after ATX heading hashes if missing: ###Heading -> ### Heading
            if let first = line.first, first == "#" {
                var i = 0
                for ch in line { if ch == "#" && i < 6 { i += 1 } else { break } }
                if i > 0 {
                    let afterHashesIndex = line.index(line.startIndex, offsetBy: i)
                    if afterHashesIndex < line.endIndex {
                        let next = line[afterHashesIndex]
                        if next != " " && next != "#" && next != "\n" { // insert a space
                            line.insert(" ", at: afterHashesIndex)
                        }
                    }
                }
            }

            // 2) Collapse internal runs of 3+ spaces to single space (avoid trimming EOL)
            line = collapseInternalSpaces(line)

            // 3) Trim trailing spaces if more than two (preserve markdown linebreak "  ")
            var trailing = 0
            while trailing < line.count, line[line.index(line.endIndex, offsetBy: -(trailing + 1))] == " " { trailing += 1 }
            if trailing > 2 {
                let newEnd = line.index(line.endIndex, offsetBy: -(trailing - 2))
                line = String(line[..<newEnd])
            }

            lines.append(line)
        }

        markdown = lines.joined(separator: "\n")
    }

    private func collapseInternalSpaces(_ input: String) -> String {
        // Replace sequences of 3+ spaces between non-space characters with a single space
        // (simple pass without regex)
        var out = ""
        out.reserveCapacity(input.count)
        let chars = Array(input)
        var i = 0
        while i < chars.count {
            if chars[i] == " " {
                var j = i
                while j < chars.count && chars[j] == " " { j += 1 }
                let runLen = j - i
                let prevIsNonSpace = i > 0 ? (chars[i-1] != " ") : false
                let nextIsNonSpace = j < chars.count ? (chars[j] != " ") : false
                if runLen >= 3 && prevIsNonSpace && nextIsNonSpace {
                    out.append(" ")
                } else {
                    out += String(repeating: " ", count: runLen)
                }
                i = j
            } else {
                out.append(chars[i])
                i += 1
            }
        }
        return out
    }
}


#Preview {
    NavigationView {
        LinterDemoView()
    }
}

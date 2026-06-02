import Foundation

/// GitHub Flavored Markdown extensions parser
public struct GFMExtensions {
    
    // MARK: - Task Lists
    
    /// Parse task list markers in list items
    public static func parseTaskMarker(_ text: String) -> (isTask: Bool, isChecked: Bool, content: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        
        if trimmed.hasPrefix("[ ] ") {
            return (true, false, String(trimmed.dropFirst(4)))
        } else if trimmed.hasPrefix("[x] ") || trimmed.hasPrefix("[X] ") {
            return (true, true, String(trimmed.dropFirst(4)))
        }
        
        return (false, false, text)
    }
    
    // MARK: - Tables
    
    /// Parse a complete table from lines
    public static func parseTable(lines: [String], configuration: MarkdownConfiguration) -> (headers: [MarkdownParser.TableCell], rows: [[MarkdownParser.TableCell]], alignments: [MarkdownParser.TableAlignment])? {
        guard lines.count >= 2 else { return nil }
        
        // Parse separator line for alignments
        let alignments = parseTableAlignments(lines[1])
        guard !alignments.isEmpty else { return nil }
        
        // Parse header
        let headers = parseTableRow(lines[0], alignments: alignments, configuration: configuration)
        
        // Parse body rows
        var rows: [[MarkdownParser.TableCell]] = []
        for i in 2..<lines.count {
            let row = parseTableRow(lines[i], alignments: alignments, configuration: configuration)
            rows.append(row)
        }
        
        return (headers, rows, alignments)
    }
    
    /// Parse table row into cells
    public static func parseTableRow(_ line: String, alignments: [MarkdownParser.TableAlignment]? = nil, configuration: MarkdownConfiguration) -> [MarkdownParser.TableCell] {
        let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        
        var cells: [MarkdownParser.TableCell] = []
        for (index, part) in parts.enumerated() {
            // Skip leading and trailing empty cells from pipe characters
            if index == 0 && part.isEmpty { continue }
            if index == parts.count - 1 && part.isEmpty { continue }
            
            // Parse inline content for the cell
            let content = InlineParser.parseInlineOptimized(part, configuration: configuration)
            let alignment = alignments?[safe: cells.count] ?? .left
            cells.append(MarkdownParser.TableCell(content: content, alignment: alignment))
        }
        
        return cells
    }
    
    /// Parse table alignment row
    public static func parseTableAlignments(_ line: String) -> [MarkdownParser.TableAlignment] {
        let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        
        var alignments: [MarkdownParser.TableAlignment] = []
        
        for part in parts {
            if part.isEmpty { continue }
            
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            
            // Must contain at least one dash
            guard trimmed.contains("-") else { continue }
            
            // Check for colons indicating alignment
            let startsWithColon = trimmed.first == ":"
            let endsWithColon = trimmed.last == ":"
            
            if startsWithColon && endsWithColon {
                alignments.append(.center)
            } else if endsWithColon {
                alignments.append(.right)
            } else {
                alignments.append(.left)
            }
        }
        
        return alignments
    }
    
    // MARK: - Autolinks
    
    /// Detect and parse autolinks in text
    public static func parseAutolink(text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        
        // Standard URLs
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || 
           trimmed.hasPrefix("ftp://") || trimmed.hasPrefix("mailto:") {
            return URL(string: trimmed)
        }
        
        // www URLs
        if trimmed.hasPrefix("www.") {
            return URL(string: "http://\(trimmed)")
        }
        
        // Email addresses
        if isValidEmail(trimmed) {
            return URL(string: "mailto:\(trimmed)")
        }
        
        return nil
    }
    
    /// Check if string is a valid email address
    public static func isValidEmail(_ text: String) -> Bool {
        // Simple email validation
        let parts = text.split(separator: "@")
        guard parts.count == 2 else { return false }
        
        let localPart = parts[0]
        let domainPart = parts[1]
        
        // Basic checks
        guard !localPart.isEmpty && !domainPart.isEmpty else { return false }
        guard domainPart.contains(".") else { return false }
        
        // Check for valid characters
        let validChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_+"))
        let textChars = CharacterSet(charactersIn: text)
        
        return validChars.isSuperset(of: textChars.subtracting(CharacterSet(charactersIn: "@")))
    }
    
    // MARK: - GitHub-Specific References
    
    /// Parse GitHub mention (@username)
    public static func parseMention(_ text: String) -> String? {
        guard text.hasPrefix("@") else { return nil }
        
        let username = String(text.dropFirst())
        
        // Username validation (GitHub rules)
        guard !username.isEmpty else { return nil }
        guard username.count <= 39 else { return nil }
        
        // Must contain only alphanumeric, dash, or underscore
        for char in username {
            if !char.isLetter && !char.isNumber && char != "-" && char != "_" {
                return nil
            }
        }
        
        // Cannot start or end with dash
        if username.first == "-" || username.last == "-" {
            return nil
        }
        
        // Cannot have consecutive dashes
        if username.contains("--") {
            return nil
        }
        
        return username
    }
    
    /// Parse GitHub issue reference (#123)
    public static func parseIssueReference(_ text: String) -> Int? {
        guard text.hasPrefix("#") else { return nil }
        
        let numberStr = String(text.dropFirst())
        return Int(numberStr)
    }
    
    /// Parse GitHub commit SHA
    public static func parseCommitSHA(_ text: String) -> String? {
        // Must be 7-40 hex characters
        guard text.count >= 7 && text.count <= 40 else { return nil }
        
        // Check all characters are hex
        for char in text {
            if !ParsingHelpers.isHexChar(char) {
                return nil
            }
        }
        
        return text
    }
    
    /// Parse GitHub repository reference (owner/repo)
    public static func parseRepositoryReference(_ text: String) -> (owner: String, repo: String)? {
        let parts = text.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        
        let owner = String(parts[0])
        let repo = String(parts[1])
        
        // Validate owner
        guard isValidGitHubUsername(owner) else { return nil }
        
        // Validate repo name
        guard isValidGitHubRepoName(repo) else { return nil }
        
        return (owner, repo)
    }
    
    /// Parse GitHub pull request reference (owner/repo#123)
    public static func parsePullRequestReference(_ text: String) -> (owner: String, repo: String, number: Int)? {
        let parts = text.split(separator: "#", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        
        guard let repoRef = parseRepositoryReference(String(parts[0])) else { return nil }
        guard let number = Int(parts[1]) else { return nil }
        
        return (repoRef.owner, repoRef.repo, number)
    }
    
    // MARK: - Strikethrough
    
    /// Parse strikethrough text (~~text~~)
    public static func parseStrikethrough(_ text: String) -> String? {
        guard text.hasPrefix("~~") && text.hasSuffix("~~") else { return nil }
        guard text.count > 4 else { return nil }
        
        let content = String(text.dropFirst(2).dropLast(2))
        return content.isEmpty ? nil : content
    }
    
    // MARK: - Helper Methods
    
    private static func isValidGitHubUsername(_ username: String) -> Bool {
        guard !username.isEmpty && username.count <= 39 else { return false }
        
        for char in username {
            if !char.isLetter && !char.isNumber && char != "-" && char != "_" {
                return false
            }
        }
        
        // Cannot start or end with dash
        if username.first == "-" || username.last == "-" {
            return false
        }
        
        // Cannot have consecutive dashes
        if username.contains("--") {
            return false
        }
        
        return true
    }
    
    private static func isValidGitHubRepoName(_ repo: String) -> Bool {
        guard !repo.isEmpty && repo.count <= 100 else { return false }
        
        for char in repo {
            if !char.isLetter && !char.isNumber && char != "-" && char != "_" && char != "." {
                return false
            }
        }
        
        // Cannot be just "." or ".."
        if repo == "." || repo == ".." {
            return false
        }
        
        return true
    }
}

// MARK: - Array Extension

private extension Array {
    subscript(safe index: Int) -> Element? {
        return index >= 0 && index < count ? self[index] : nil
    }
}

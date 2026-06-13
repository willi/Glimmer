import SwiftUI

/// AST Types for Markdown Parser
extension MarkdownParser {
    
    // MARK: - AST Nodes
    
    public enum AutolinkType: Sendable, Equatable {
        case url, www, email
    }

    public indirect enum BlockNode: Sendable {
        case heading(level: Int, children: [InlineNode], id: String?)
        case paragraph(children: [InlineNode])
        case blockquote(children: [BlockNode])
        case codeBlock(language: String?, content: String)
        case list(ordered: Bool, tight: Bool, items: [ListItem])
        case taskList(items: [TaskListItem])
        case table(header: [TableCell], rows: [[TableCell]])
        case horizontalRule
        case html(content: String)
        case footnoteDefinition(label: String, children: [BlockNode])
    }

    // MARK: - Source Locations
    /// Block node with its starting source line (1-based), for tools like linters.
    public struct LocatedBlock: Sendable {
        public let node: BlockNode
        public let startLine: Int
        
        public init(node: BlockNode, startLine: Int) {
            self.node = node
            self.startLine = startLine
        }
    }
    
    public indirect enum InlineNode: Sendable, Equatable {
        case text(String)
        case emphasis(children: [InlineNode])
        case strong(children: [InlineNode])
        case strikethrough(children: [InlineNode])
        case code(String)
        case link(url: URL, title: String?, children: [InlineNode])
        case image(url: URL, alt: String, title: String?)
        case autolink(URL, AutolinkType, originalText: String)
        case mention(username: String)
        case issueReference(number: Int)
        case commitSHA(sha: String, short: String)
        case repositoryReference(owner: String, repo: String)
        case pullRequestReference(owner: String, repo: String, number: Int)
        case lineBreak
        case softBreak
        case html(String)
        case footnoteReference(label: String)
        case extensionInline(ExtensionNode)
    }

    public struct ExtensionNode: Sendable, Equatable, Hashable {
        public let namespace: String
        public let name: String
        public let literal: String
        public let fields: [String: String]

        public init(namespace: String, name: String, literal: String, fields: [String: String]) {
            self.namespace = namespace
            self.name = name
            self.literal = literal
            self.fields = fields
        }
    }
    
    public struct ListItem: Sendable {
        public let marker: String
        public let content: [BlockNode]
        public let isTask: Bool
        public let isChecked: Bool?
        
        public init(marker: String, content: [BlockNode], isTask: Bool = false, isChecked: Bool? = nil) {
            self.marker = marker
            self.content = content
            self.isTask = isTask
            self.isChecked = isChecked
        }
    }
    
    public struct TaskListItem: Sendable {
        public let isChecked: Bool
        public let content: [InlineNode]
    }
    
    public struct TableCell: Sendable, Equatable {
        public let content: [InlineNode]
        public let alignment: TableAlignment
        
        public init(content: [InlineNode], alignment: TableAlignment) {
            self.content = content
            self.alignment = alignment
        }
    }
    
    public enum TableAlignment: Sendable, Equatable {
        case left, center, right, none
    }
    
    // MARK: - Rendering
    
    public static func parseToAttributedString(_ markdown: String, configuration: MarkdownConfiguration = .default) -> AttributedString {
        let blocks = parse(markdown, configuration: configuration)
        var renderer = MarkdownRenderer()
        return renderer.render(blocks: blocks, configuration: configuration)
    }
    
    static func renderBlocks(_ blocks: [BlockNode], configuration: MarkdownConfiguration) -> AttributedString {
        var renderer = MarkdownRenderer()
        return renderer.render(blocks: blocks, configuration: configuration)
    }
}

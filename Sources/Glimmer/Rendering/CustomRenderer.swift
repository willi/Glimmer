import SwiftUI

/// Protocol for custom markdown renderers
public protocol MarkdownRendererProtocol {
    associatedtype Output
    
    /// Render a complete markdown document
    func render(blocks: [MarkdownParser.BlockNode], configuration: MarkdownConfiguration) -> Output
    
    /// Render a single block node
    func renderBlock(_ block: MarkdownParser.BlockNode, configuration: MarkdownConfiguration) -> Output
    
    /// Render inline nodes
    func renderInlines(_ inlines: [MarkdownParser.InlineNode], configuration: MarkdownConfiguration) -> Output
}

/// Default implementation helpers
public extension MarkdownRendererProtocol {
    func render(blocks: [MarkdownParser.BlockNode], configuration: MarkdownConfiguration) -> Output {
        // Default implementation would need to combine outputs
        // This is a placeholder - actual implementation depends on Output type
        fatalError("Must implement render(blocks:configuration:)")
    }
}

// MARK: - HTML Renderer

/// Custom HTML renderer for markdown
public struct HTMLMarkdownRenderer: MarkdownRendererProtocol {
    public typealias Output = String
    
    private let options: HTMLRenderOptions
    
    public struct HTMLRenderOptions {
        public var includeCSS: Bool = true
        public var cssClasses: CSSClasses = .defaultClasses
        public var syntaxHighlightTheme: String = "github"
        public var wrapInHTML: Bool = false
        
        public struct CSSClasses {
            public var heading: String = "md-heading"
            public var paragraph: String = "md-paragraph"
            public var blockquote: String = "md-blockquote"
            public var codeBlock: String = "md-code-block"
            public var inlineCode: String = "md-inline-code"
            public var list: String = "md-list"
            public var table: String = "md-table"
            public var link: String = "md-link"
            public var image: String = "md-image"
            
            public static let defaultClasses = CSSClasses()
        }
        
        public init() {}
    }
    
    public init(options: HTMLRenderOptions = HTMLRenderOptions()) {
        self.options = options
    }
    
    public func render(blocks: [MarkdownParser.BlockNode], configuration: MarkdownConfiguration) -> String {
        let content = blocks.map { renderBlock($0, configuration: configuration) }.joined(separator: "\n")
        
        if options.wrapInHTML {
            return """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <title>Markdown Document</title>
                \(options.includeCSS ? generateCSS() : "")
            </head>
            <body>
                <div class="markdown-content">
                    \(content)
                </div>
            </body>
            </html>
            """
        }
        
        return content
    }
    
    public func renderBlock(_ block: MarkdownParser.BlockNode, configuration: MarkdownConfiguration) -> String {
        switch block {
        case .heading(let level, let children, let id):
            let content = renderInlines(children, configuration: configuration)
            let idAttr = id.map { " id=\"\($0)\"" } ?? ""
            return "<h\(level) class=\"\(options.cssClasses.heading) \(options.cssClasses.heading)-\(level)\"\(idAttr)>\(content)</h\(level)>"
            
        case .paragraph(let children):
            let content = renderInlines(children, configuration: configuration)
            return "<p class=\"\(options.cssClasses.paragraph)\">\(content)</p>"
            
        case .blockquote(let children):
            let content = children.map { renderBlock($0, configuration: configuration) }.joined(separator: "\n")
            return "<blockquote class=\"\(options.cssClasses.blockquote)\">\n\(content)\n</blockquote>"
            
        case .codeBlock(let language, let content):
            let langAttr = language.map { " data-language=\"\($0)\"" } ?? ""
            let highlightedContent = language.flatMap { lang in
                highlightCode(content, language: lang)
            } ?? escapeHTML(content)
            return "<pre class=\"\(options.cssClasses.codeBlock)\"\(langAttr)><code>\(highlightedContent)</code></pre>"
            
        case .list(let ordered, let tight, let items):
            let tag = ordered ? "ol" : "ul"
            let itemsHTML = items.map { renderListItem($0, configuration: configuration) }.joined(separator: "\n")
            let tightClass = tight ? "tight" : "loose"
            return "<\(tag) class=\"\(options.cssClasses.list) \(options.cssClasses.list)-\(tightClass)\">\n\(itemsHTML)\n</\(tag)>"
            
        case .table(let header, let rows):
            let headerHTML = "<tr>" + header.map { renderTableCell($0, isHeader: true) }.joined() + "</tr>"
            let rowsHTML = rows.map { row in
                "<tr>" + row.map { renderTableCell($0, isHeader: false) }.joined() + "</tr>"
            }.joined(separator: "\n")
            
            return """
            <table class="\(options.cssClasses.table)">
                <thead>\(headerHTML)</thead>
                <tbody>\(rowsHTML)</tbody>
            </table>
            """
            
        case .horizontalRule:
            return "<hr class=\"md-hr\">"
            
        case .html(let content):
            return content  // Pass through raw HTML
            
        case .footnoteDefinition(let label, let children):
            let content = children.map { renderBlock($0, configuration: configuration) }.joined(separator: "\n")
            return "<div class=\"footnote\" id=\"fn-\(label)\">\n<sup>\(label)</sup>\n\(content)\n</div>"
            
        case .taskList(let items):
            let itemsHTML = items.map { item in
                let checkbox = item.isChecked ? "☑" : "☐"
                let content = renderInlines(item.content, configuration: configuration)
                return "<li class=\"task-list-item\">\(checkbox) \(content)</li>"
            }.joined(separator: "\n")
            return "<ul class=\"task-list\">\n\(itemsHTML)\n</ul>"
        }
    }
    
    public func renderInlines(_ inlines: [MarkdownParser.InlineNode], configuration: MarkdownConfiguration) -> String {
        inlines.map { renderInline($0, configuration: configuration) }.joined()
    }
    
    private func renderInline(_ inline: MarkdownParser.InlineNode, configuration: MarkdownConfiguration) -> String {
        switch inline {
        case .text(let text):
            return escapeHTML(text)
            
        case .emphasis(let children):
            let content = renderInlines(children, configuration: configuration)
            return "<em>\(content)</em>"
            
        case .strong(let children):
            let content = renderInlines(children, configuration: configuration)
            return "<strong>\(content)</strong>"
            
        case .strikethrough(let children):
            let content = renderInlines(children, configuration: configuration)
            return "<del>\(content)</del>"
            
        case .code(let text):
            return "<code class=\"\(options.cssClasses.inlineCode)\">\(escapeHTML(text))</code>"
            
        case .link(let url, let title, let children):
            let content = renderInlines(children, configuration: configuration)
            let titleAttr = title.map { " title=\"\(escapeHTML($0))\"" } ?? ""
            return "<a href=\"\(url.absoluteString)\" class=\"\(options.cssClasses.link)\"\(titleAttr)>\(content)</a>"
            
        case .image(let url, let alt, let title):
            let titleAttr = title.map { " title=\"\(escapeHTML($0))\"" } ?? ""
            return "<img src=\"\(url.absoluteString)\" alt=\"\(escapeHTML(alt))\" class=\"\(options.cssClasses.image)\"\(titleAttr)>"
            
        case .lineBreak:
            return "<br>"
            
        case .softBreak:
            return " "
            
        case .html(let content):
            return content
            
        case .autolink(let url, _, let originalText):
            return "<a href=\"\(url.absoluteString)\" class=\"autolink\">\(escapeHTML(originalText))</a>"
            
        case .mention(let username):
            return "<a href=\"https://github.com/\(username)\" class=\"mention\">@\(username)</a>"
            
        case .issueReference(let number):
            return "<a href=\"#issue-\(number)\" class=\"issue-ref\">#\(number)</a>"
            
        case .commitSHA(_, let short):
            return "<code class=\"commit-sha\">\(short)</code>"
            
        case .repositoryReference(let owner, let repo):
            return "<a href=\"https://github.com/\(owner)/\(repo)\" class=\"repo-ref\">\(owner)/\(repo)</a>"
            
        case .pullRequestReference(let owner, let repo, let number):
            return "<a href=\"https://github.com/\(owner)/\(repo)/pull/\(number)\" class=\"pr-ref\">\(owner)/\(repo)#\(number)</a>"
            
        case .footnoteReference(let label):
            return "<sup><a href=\"#fn-\(label)\" class=\"footnote-ref\">[\(label)]</a></sup>"

        case .extensionInline(let node):
            return escapeHTML(node.literal)
        }
    }
    
    private func renderListItem(_ item: MarkdownParser.ListItem, configuration: MarkdownConfiguration) -> String {
        let content = item.content.map { renderBlock($0, configuration: configuration) }.joined(separator: "\n")
        
        if item.isTask {
            let checkbox = item.isChecked ?? false ? "☑" : "☐"
            return "<li class=\"task-item\">\(checkbox) \(content)</li>"
        }
        
        return "<li>\(content)</li>"
    }
    
    private func renderTableCell(_ cell: MarkdownParser.TableCell, isHeader: Bool) -> String {
        let tag = isHeader ? "th" : "td"
        let content = renderInlines(cell.content, configuration: MarkdownConfiguration.default)
        let alignStyle: String
        
        switch cell.alignment {
        case .left: alignStyle = " style=\"text-align: left;\""
        case .center: alignStyle = " style=\"text-align: center;\""
        case .right: alignStyle = " style=\"text-align: right;\""
        case .none: alignStyle = ""
        }
        
        return "<\(tag)\(alignStyle)>\(content)</\(tag)>"
    }
    
    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
    
    private func highlightCode(_ code: String, language: String) -> String? {
        // Simplified - in production, you'd use a proper syntax highlighter
        return "<span class=\"hljs-code\" data-lang=\"\(language)\">\(escapeHTML(code))</span>"
    }
    
    private func generateCSS() -> String {
        """
        <style>
            .markdown-content {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
                line-height: 1.6;
                color: #333;
                max-width: 800px;
                margin: 0 auto;
                padding: 20px;
            }
            
            .\(options.cssClasses.heading) {
                margin-top: 1.5em;
                margin-bottom: 0.5em;
                font-weight: 600;
            }
            
            .\(options.cssClasses.heading)-1 { font-size: 2em; }
            .\(options.cssClasses.heading)-2 { font-size: 1.5em; }
            .\(options.cssClasses.heading)-3 { font-size: 1.25em; }
            
            .\(options.cssClasses.paragraph) {
                margin: 1em 0;
            }
            
            .\(options.cssClasses.blockquote) {
                border-left: 4px solid #ddd;
                padding-left: 1em;
                margin: 1em 0;
                color: #666;
            }
            
            .\(options.cssClasses.codeBlock) {
                background: #f6f8fa;
                border-radius: 6px;
                padding: 16px;
                overflow-x: auto;
            }
            
            .\(options.cssClasses.inlineCode) {
                background: rgba(175, 184, 193, 0.2);
                padding: 0.2em 0.4em;
                border-radius: 3px;
                font-size: 85%;
            }
            
            .\(options.cssClasses.table) {
                border-collapse: collapse;
                width: 100%;
                margin: 1em 0;
            }
            
            .\(options.cssClasses.table) th,
            .\(options.cssClasses.table) td {
                border: 1px solid #ddd;
                padding: 8px;
            }
            
            .\(options.cssClasses.table) th {
                background: #f6f8fa;
                font-weight: 600;
            }
            
            .\(options.cssClasses.link) {
                color: #0366d6;
                text-decoration: none;
            }
            
            .\(options.cssClasses.link):hover {
                text-decoration: underline;
            }
            
            .\(options.cssClasses.image) {
                max-width: 100%;
                height: auto;
            }
            
            .task-list {
                list-style: none;
                padding-left: 0;
            }
            
            .task-item {
                padding-left: 1.5em;
            }
        </style>
        """
    }
}

// MARK: - Plain Text Renderer

/// Custom plain text renderer (removes all formatting)
public struct PlainTextMarkdownRenderer: MarkdownRendererProtocol {
    public typealias Output = String
    
    public init() {}
    
    public func render(blocks: [MarkdownParser.BlockNode], configuration: MarkdownConfiguration) -> String {
        blocks.map { renderBlock($0, configuration: configuration) }.joined(separator: "\n\n")
    }
    
    public func renderBlock(_ block: MarkdownParser.BlockNode, configuration: MarkdownConfiguration) -> String {
        switch block {
        case .heading(_, let children, _):
            return renderInlines(children, configuration: configuration).uppercased()
            
        case .paragraph(let children):
            return renderInlines(children, configuration: configuration)
            
        case .blockquote(let children):
            let content = children.map { renderBlock($0, configuration: configuration) }.joined(separator: "\n")
            return content.split(separator: "\n").map { "> \($0)" }.joined(separator: "\n")
            
        case .codeBlock(_, let content):
            return content
            
        case .list(_, _, let items):
            return items.enumerated().map { index, item in
                let content = item.content.map { renderBlock($0, configuration: configuration) }.joined(separator: " ")
                return "• \(content)"
            }.joined(separator: "\n")
            
        case .table(let header, let rows):
            let headerText = header.map { renderInlines($0.content, configuration: configuration) }.joined(separator: " | ")
            let rowsText = rows.map { row in
                row.map { renderInlines($0.content, configuration: configuration) }.joined(separator: " | ")
            }.joined(separator: "\n")
            return "\(headerText)\n\(rowsText)"
            
        case .horizontalRule:
            return "---"
            
        case .html:
            return ""  // Skip HTML in plain text
            
        case .footnoteDefinition(let label, let children):
            let content = children.map { renderBlock($0, configuration: configuration) }.joined(separator: " ")
            return "[\(label)] \(content)"
            
        case .taskList(let items):
            return items.map { item in
                let checkbox = item.isChecked ? "[x]" : "[ ]"
                let content = renderInlines(item.content, configuration: configuration)
                return "\(checkbox) \(content)"
            }.joined(separator: "\n")
        }
    }
    
    public func renderInlines(_ inlines: [MarkdownParser.InlineNode], configuration: MarkdownConfiguration) -> String {
        inlines.map { renderInline($0) }.joined()
    }
    
    private func renderInline(_ inline: MarkdownParser.InlineNode) -> String {
        switch inline {
        case .text(let text):
            return text
            
        case .emphasis(let children), .strong(let children), .strikethrough(let children):
            return renderInlines(children, configuration: .default)
            
        case .code(let text):
            return text
            
        case .link(_, _, let children):
            return renderInlines(children, configuration: .default)
            
        case .image(_, let alt, _):
            return "[Image: \(alt)]"
            
        case .lineBreak, .softBreak:
            return "\n"
            
        case .html:
            return ""
            
        case .autolink(_, _, let text):
            return text
            
        case .mention(let username):
            return "@\(username)"
            
        case .issueReference(let number):
            return "#\(number)"
            
        case .commitSHA(_, let short):
            return short
            
        case .repositoryReference(let owner, let repo):
            return "\(owner)/\(repo)"
            
        case .pullRequestReference(let owner, let repo, let number):
            return "\(owner)/\(repo)#\(number)"
            
        case .footnoteReference(let label):
            return "[\(label)]"

        case .extensionInline(let node):
            return node.literal
        }
    }
}

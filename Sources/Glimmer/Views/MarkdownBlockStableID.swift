import Foundation

enum MarkdownBlockStableID {
    static func pairs(for blocks: [MarkdownParser.BlockNode]) -> [(id: String, block: MarkdownParser.BlockNode)] {
        var occurrences: [String: Int] = [:]
        return blocks.map { block in
            let baseID = make(for: block)
            let occurrence = occurrences[baseID, default: 0]
            occurrences[baseID] = occurrence + 1
            return (id: "\(baseID)#\(occurrence)", block: block)
        }
    }

    private static func make(for block: MarkdownParser.BlockNode) -> String {
        switch block {
        case .heading(let level, let children, let id):
            return "h|\(level)|\(inlineText(children))|\(id ?? "")"
        case .paragraph(let children):
            return "p|\(inlineText(children))"
        case .codeBlock(let lang, let content):
            var hasher = Hasher()
            content.hash(into: &hasher)
            return "c|\(lang ?? "")|\(hasher.finalize())"
        case .table(let header, let rows):
            let head = header.map { inlineText($0.content) }.joined(separator: "|")
            // Include only a sample of rows to keep keys small.
            let body = rows.prefix(20).map { row in
                row.map { inlineText($0.content) }.joined(separator: "|")
            }.joined(separator: ";")
            return "t|H:\(head)|R:\(body)"
        case .horizontalRule:
            return "hr"
        case .blockquote(let children):
            var hasher = Hasher()
            for child in children {
                make(for: child).hash(into: &hasher)
            }
            return "bq|\(hasher.finalize())"
        case .list(let ordered, _, let items):
            var hasher = Hasher()
            ordered.hash(into: &hasher)
            for item in items {
                for block in item.content {
                    make(for: block).hash(into: &hasher)
                }
            }
            return "li|\(hasher.finalize())"
        case .taskList(let items):
            var hasher = Hasher()
            for item in items {
                inlineText(item.content).hash(into: &hasher)
                item.isChecked.hash(into: &hasher)
            }
            return "tl|\(hasher.finalize())"
        case .html(let content):
            var hasher = Hasher()
            content.hash(into: &hasher)
            return "html|\(hasher.finalize())"
        case .footnoteDefinition(let label, let children):
            var hasher = Hasher()
            label.hash(into: &hasher)
            for child in children {
                make(for: child).hash(into: &hasher)
            }
            return "fn|\(hasher.finalize())"
        }
    }

    private static func inlineText(_ nodes: [MarkdownParser.InlineNode]) -> String {
        var out = ""
        out.reserveCapacity(64)
        for node in nodes {
            switch node {
            case .text(let text):
                out += text
            case .emphasis(let children), .strong(let children), .strikethrough(let children):
                out += inlineText(children)
            case .code(let code):
                out += code
            case .link(_, _, let children):
                out += inlineText(children)
            case .autolink(_, _, let original):
                out += original
            case .mention(let username):
                out += "@" + username
            case .issueReference(let number):
                out += "#" + String(number)
            case .commitSHA(_, let short):
                out += short
            case .repositoryReference(let owner, let repo):
                out += owner + "/" + repo
            case .pullRequestReference(let owner, let repo, let number):
                out += owner + "/" + repo + "#" + String(number)
            case .lineBreak, .softBreak:
                out += "\n"
            case .html(let html):
                out += html
            case .image(_, let alt, _):
                out += alt
            case .footnoteReference(let label):
                out += "[" + label + "]"
            }
        }
        return out
    }
}

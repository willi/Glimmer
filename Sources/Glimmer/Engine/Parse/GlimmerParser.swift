import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Parses CommonMark plus GFM tables, strikethrough, autolinks, task lists and footnotes into Glimmer's block tree.
public enum GlimmerParser {
    private typealias Node = UnsafeMutablePointer<cmark_node>

    private static let extensionNames = ["table", "strikethrough", "autolink", "tasklist"]
    private static let registration: Void = cmark_gfm_core_extensions_ensure_registered()

    public static func parse(_ markdown: String) -> [GlimmerBlock] {
        parseWithLines(markdown).map(\.block)
    }

    /// Top-level blocks with the 1-based source line each starts on. `GlimmerStreamingDocument` uses the last
    /// block's line to re-parse only the open tail.
    static func parseWithLines(_ markdown: String) -> [(block: GlimmerBlock, startLine: Int)] {
        _ = registration
        guard let parser = cmark_parser_new(CMARK_OPT_DEFAULT | CMARK_OPT_FOOTNOTES) else { return [] }
        defer { cmark_parser_free(parser) }
        for name in extensionNames {
            if let syntaxExtension = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, syntaxExtension)
            }
        }
        var source = markdown
        source.withUTF8 { bytes in
            guard let base = bytes.baseAddress else { return }
            base.withMemoryRebound(to: CChar.self, capacity: bytes.count) { characters in
                cmark_parser_feed(parser, characters, bytes.count)
            }
        }
        guard let document = cmark_parser_finish(parser) else { return [] }
        defer { cmark_node_free(document) }
        var result: [(block: GlimmerBlock, startLine: Int)] = []
        for node in children(of: document) {
            guard let block = block(node) else { continue }
            // cmark moves every referenced definition after the last block, in reference order: one block holds them.
            if case .footnoteDefinitions(let notes) = block, case .footnoteDefinitions(let earlier)? = result.last?.block {
                result[result.count - 1].block = .footnoteDefinitions(earlier + notes)
            } else {
                result.append((block, Int(cmark_node_get_start_line(node))))
            }
        }
        return result
    }

    // MARK: - Blocks

    private static func blocks(in node: Node) -> [GlimmerBlock] {
        children(of: node).compactMap(block)
    }

    private static func block(_ node: Node) -> GlimmerBlock? {
        switch cmark_node_get_type(node) {
        case CMARK_NODE_PARAGRAPH:
            return .paragraph(inlines(in: node))
        case CMARK_NODE_HEADING:
            return .heading(level: Int(cmark_node_get_heading_level(node)), inlines(in: node))
        case CMARK_NODE_BLOCK_QUOTE:
            return .blockQuote(blocks(in: node))
        case CMARK_NODE_LIST:
            return .list(list(node))
        case CMARK_NODE_CODE_BLOCK:
            return .codeBlock(language: language(node), code: codeLiteral(node))
        case CMARK_NODE_HTML_BLOCK:
            return .htmlBlock(string(cmark_node_get_literal(node)))
        case CMARK_NODE_THEMATIC_BREAK:
            return .thematicBreak
        case CMARK_NODE_FOOTNOTE_DEFINITION:
            return .footnoteDefinitions([GlimmerFootnote(label: string(cmark_node_get_literal(node)), blocks: blocks(in: node))])
        default:
            return typeString(node) == "table" ? .table(table(node)) : nil
        }
    }

    private static func list(_ node: Node) -> GlimmerList {
        let kind: GlimmerList.Kind = cmark_node_get_list_type(node) == CMARK_ORDERED_LIST
            ? .ordered(start: Int(cmark_node_get_list_start(node)))
            : .bullet
        let items = children(of: node).map { item in
            GlimmerListItem(
                checkbox: typeString(item) == "tasklist" ? cmark_gfm_extensions_get_tasklist_item_checked(item) : nil,
                blocks: blocks(in: item)
            )
        }
        return GlimmerList(kind: kind, isTight: cmark_node_get_list_tight(node) != 0, items: items)
    }

    private static func table(_ node: Node) -> GlimmerTable {
        let columns = Int(cmark_gfm_extensions_get_table_columns(node))
        let rawAlignments = cmark_gfm_extensions_get_table_alignments(node)
        let alignments: [GlimmerTable.Alignment] = (0..<columns).map { index in
            let raw = rawAlignments.map { $0[index] } ?? 0
            switch raw {
            case UInt8(ascii: "l"): return .left
            case UInt8(ascii: "c"): return .center
            case UInt8(ascii: "r"): return .right
            default: return .none
            }
        }
        var header: [[GlimmerInline]] = []
        var rows: [[[GlimmerInline]]] = []
        for row in children(of: node) {
            let cells = children(of: row).map { inlines(in: $0) }
            if typeString(row) == "table_header" {
                header = cells
            } else {
                rows.append(cells)
            }
        }
        return GlimmerTable(alignments: alignments, header: header, rows: rows)
    }

    private static func language(_ node: Node) -> String? {
        let info = string(cmark_node_get_fence_info(node)).trimmingCharacters(in: .whitespaces)
        guard let word = info.split(whereSeparator: \.isWhitespace).first, !word.isEmpty else { return nil }
        return String(word)
    }

    private static func codeLiteral(_ node: Node) -> String {
        var code = string(cmark_node_get_literal(node))
        if code.hasSuffix("\n") { code.removeLast() }
        return code
    }

    // MARK: - Inlines

    private static func inlines(in node: Node) -> [GlimmerInline] {
        var result: [GlimmerInline] = []
        for child in children(of: node) {
            guard let inline = inline(child) else { continue }
            if case .text(let next) = inline, case .text(let previous)? = result.last {
                result[result.count - 1] = .text(previous + next)
            } else {
                result.append(inline)
            }
        }
        return result.flatMap(splittingFootnoteReferences)
    }

    /// cmark leaves a reference whose definition hasn't arrived (or never does) as the text `[^label]`: a marker too.
    private static func splittingFootnoteReferences(_ inline: GlimmerInline) -> [GlimmerInline] {
        guard case .text(let text) = inline, text.contains("[^") else { return [inline] }
        var pieces: [GlimmerInline] = []
        var cursor = text.startIndex
        for match in text.matches(of: #/\[\^([^\]\s]+)\]/#) {
            if cursor < match.range.lowerBound { pieces.append(.text(String(text[cursor..<match.range.lowerBound]))) }
            pieces.append(.footnoteReference(label: String(match.output.1)))
            cursor = match.range.upperBound
        }
        if cursor < text.endIndex { pieces.append(.text(String(text[cursor...]))) }
        return pieces
    }

    private static func inline(_ node: Node) -> GlimmerInline? {
        switch cmark_node_get_type(node) {
        case CMARK_NODE_TEXT:
            return .text(string(cmark_node_get_literal(node)))
        case CMARK_NODE_CODE:
            return .code(string(cmark_node_get_literal(node)))
        case CMARK_NODE_EMPH:
            return .emphasis(inlines(in: node))
        case CMARK_NODE_STRONG:
            return .strong(inlines(in: node))
        case CMARK_NODE_SOFTBREAK:
            return .softBreak
        case CMARK_NODE_LINEBREAK:
            return .lineBreak
        case CMARK_NODE_HTML_INLINE:
            return .html(string(cmark_node_get_literal(node)))
        case CMARK_NODE_FOOTNOTE_REFERENCE:
            // cmark replaced the reference's literal with its own number; the label is its definition's literal.
            guard let definition = cmark_node_parent_footnote_def(node) else { return nil }
            return .footnoteReference(label: string(cmark_node_get_literal(definition)))
        case CMARK_NODE_LINK:
            return .link(
                destination: string(cmark_node_get_url(node)),
                title: nonEmpty(cmark_node_get_title(node)),
                inlines(in: node)
            )
        case CMARK_NODE_IMAGE:
            return .image(
                source: string(cmark_node_get_url(node)),
                title: nonEmpty(cmark_node_get_title(node)),
                alt: GlimmerInline.plainText(inlines(in: node))
            )
        default:
            return typeString(node) == "strikethrough" ? .strikethrough(inlines(in: node)) : nil
        }
    }

    // MARK: - Helpers

    private static func children(of node: Node) -> [Node] {
        var result: [Node] = []
        var child = cmark_node_first_child(node)
        while let current = child {
            result.append(current)
            child = cmark_node_next(current)
        }
        return result
    }

    private static func typeString(_ node: Node) -> String {
        string(cmark_node_get_type_string(node))
    }

    private static func string(_ raw: UnsafePointer<CChar>?) -> String {
        raw.map { String(cString: $0) } ?? ""
    }

    private static func nonEmpty(_ raw: UnsafePointer<CChar>?) -> String? {
        let value = string(raw)
        return value.isEmpty ? nil : value
    }
}

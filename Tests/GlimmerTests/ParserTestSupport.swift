import Foundation
import XCTest
@testable import Glimmer

enum ParserCanonicalSnapshot {
    static func canonicalDescription(for blocks: [MarkdownParser.BlockNode]) -> String {
        var output = ""
        appendBlocks(blocks, indent: "", to: &output)
        return output
    }

    static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    static func assertSemanticallyEqual(
        _ actual: [MarkdownParser.BlockNode],
        _ expected: [MarkdownParser.BlockNode],
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actualDescription = canonicalDescription(for: actual)
        let expectedDescription = canonicalDescription(for: expected)
        XCTAssertEqual(actualDescription, expectedDescription, message(), file: file, line: line)
    }

    private static func appendBlocks(
        _ blocks: [MarkdownParser.BlockNode],
        indent: String,
        to output: inout String
    ) {
        for block in blocks {
            appendBlock(block, indent: indent, to: &output)
        }
    }

    private static func appendBlock(
        _ block: MarkdownParser.BlockNode,
        indent: String,
        to output: inout String
    ) {
        switch block {
        case let .heading(level, children, id):
            output += "\(indent)heading(\(level),id:\(escape(id ?? "")))\n"
            appendInlines(children, indent: indent + "  ", to: &output)
        case let .paragraph(children):
            output += "\(indent)paragraph\n"
            appendInlines(children, indent: indent + "  ", to: &output)
        case let .blockquote(children):
            output += "\(indent)blockquote\n"
            appendBlocks(children, indent: indent + "  ", to: &output)
        case let .codeBlock(language, content):
            output += "\(indent)codeBlock(lang:\(escape(language ?? "")),content:\(escape(content)))\n"
        case let .list(ordered, tight, items):
            output += "\(indent)list(ordered:\(ordered),tight:\(tight))\n"
            for item in items {
                output += "\(indent)  item(marker:\(escape(item.marker)),task:\(item.isTask),checked:\(String(describing: item.isChecked)))\n"
                appendBlocks(item.content, indent: indent + "    ", to: &output)
            }
        case let .taskList(items):
            output += "\(indent)taskList\n"
            for item in items {
                output += "\(indent)  task(checked:\(item.isChecked))\n"
                appendInlines(item.content, indent: indent + "    ", to: &output)
            }
        case let .table(header, rows):
            output += "\(indent)table\n"
            output += "\(indent)  header\n"
            appendTableCells(header, indent: indent + "    ", to: &output)
            for row in rows {
                output += "\(indent)  row\n"
                appendTableCells(row, indent: indent + "    ", to: &output)
            }
        case .horizontalRule:
            output += "\(indent)horizontalRule\n"
        case let .html(content):
            output += "\(indent)html(\(escape(content)))\n"
        case let .footnoteDefinition(label, children):
            output += "\(indent)footnoteDefinition(\(escape(label)))\n"
            appendBlocks(children, indent: indent + "  ", to: &output)
        }
    }

    private static func appendTableCells(
        _ cells: [MarkdownParser.TableCell],
        indent: String,
        to output: inout String
    ) {
        for cell in cells {
            output += "\(indent)cell(align:\(cell.alignment))\n"
            appendInlines(cell.content, indent: indent + "  ", to: &output)
        }
    }

    private static func appendInlines(
        _ inlines: [MarkdownParser.InlineNode],
        indent: String,
        to output: inout String
    ) {
        for inline in inlines {
            appendInline(inline, indent: indent, to: &output)
        }
    }

    private static func appendInline(
        _ inline: MarkdownParser.InlineNode,
        indent: String,
        to output: inout String
    ) {
        switch inline {
        case let .text(text):
            output += "\(indent)text(\(escape(text)))\n"
        case let .emphasis(children):
            output += "\(indent)emphasis\n"
            appendInlines(children, indent: indent + "  ", to: &output)
        case let .strong(children):
            output += "\(indent)strong\n"
            appendInlines(children, indent: indent + "  ", to: &output)
        case let .strikethrough(children):
            output += "\(indent)strikethrough\n"
            appendInlines(children, indent: indent + "  ", to: &output)
        case let .code(code):
            output += "\(indent)code(\(escape(code)))\n"
        case let .link(url, title, children):
            output += "\(indent)link(url:\(escape(url.absoluteString)),title:\(escape(title ?? "")))\n"
            appendInlines(children, indent: indent + "  ", to: &output)
        case let .image(url, alt, title):
            output += "\(indent)image(url:\(escape(url.absoluteString)),alt:\(escape(alt)),title:\(escape(title ?? "")))\n"
        case let .autolink(url, type, originalText):
            output += "\(indent)autolink(url:\(escape(url.absoluteString)),type:\(type),original:\(escape(originalText)))\n"
        case let .mention(username):
            output += "\(indent)mention(\(escape(username)))\n"
        case let .issueReference(number):
            output += "\(indent)issue(\(number))\n"
        case let .commitSHA(sha, short):
            output += "\(indent)commit(sha:\(escape(sha)),short:\(escape(short)))\n"
        case let .repositoryReference(owner, repo):
            output += "\(indent)repo(owner:\(escape(owner)),repo:\(escape(repo)))\n"
        case let .pullRequestReference(owner, repo, number):
            output += "\(indent)pr(owner:\(escape(owner)),repo:\(escape(repo)),number:\(number))\n"
        case .lineBreak:
            output += "\(indent)lineBreak\n"
        case .softBreak:
            output += "\(indent)softBreak\n"
        case let .html(html):
            output += "\(indent)html(\(escape(html)))\n"
        case let .footnoteReference(label):
            output += "\(indent)footnoteReference(\(escape(label)))\n"
        case let .extensionInline(node):
            output += "\(indent)extension(\(escape(node.namespace)),\(escape(node.name)),\(escape(node.literal)))\n"
            for key in node.fields.keys.sorted() {
                output += "\(indent)  field(\(escape(key)):\(escape(node.fields[key] ?? "")))\n"
            }
        }
    }

    private static func escape(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\":
                output += "\\\\"
            case "\n":
                output += "\\n"
            case "\r":
                output += "\\r"
            case "\t":
                output += "\\t"
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        return output
    }
}

enum ParserBoundaryCorpus {
    static func parallelChunkBoundary(repetitions: Int) -> String {
        var markdown = ""
        for index in 0..<repetitions {
            markdown +=
                """
                Heading \(index)
                ========

                Paragraph \(index) with **bold**, [link](https://example.com/\(index)), @octocat, and #\(index).

                ```swift
                let value = "\(index)"
                ```

                | A | B |
                |---|---|
                | \(index) | value |

                > quote \(index)
                > continued

                - item \(index)
                  continuation
                - second \(index)

                [^\(index)]: footnote \(index)

                """
        }
        return markdown
    }
}

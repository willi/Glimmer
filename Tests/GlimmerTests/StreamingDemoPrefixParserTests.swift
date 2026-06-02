import XCTest
@testable import Glimmer

final class StreamingDemoPrefixParserTests: XCTestCase {
    func testGrowingPrefixKeepsFeaturesSectionPresent() {
        let fullContent = makeLongStreamingDemoMarkdown()
        guard let sectionRange = fullContent.range(of: "## Section 1") else {
            XCTFail("Expected Section 1 marker in demo markdown")
            return
        }

        let baseLength = fullContent.distance(from: fullContent.startIndex, to: sectionRange.lowerBound)
        let checkpoints = [0, 120, 260, 520, 900]

        for extra in checkpoints {
            let prefixLength = min(baseLength + extra, fullContent.count)
            let prefix = String(fullContent.prefix(prefixLength))
            let blocks = Glimmer.parse(prefix, configuration: .default)
            let summary = topLevelSummary(blocks)

            XCTAssertTrue(containsHeading("Streaming Demo", in: blocks), "Missing H1 at prefix \(prefixLength). Blocks: \(summary)")
            XCTAssertTrue(containsHeading("Features", in: blocks), "Missing Features heading at prefix \(prefixLength). Blocks: \(summary)")
        }
    }

    private func containsHeading(_ text: String, in blocks: [MarkdownParser.BlockNode]) -> Bool {
        for block in blocks {
            if case .heading(_, let children, _) = block {
                if plainInlineText(children).trimmingCharacters(in: .whitespacesAndNewlines) == text {
                    return true
                }
            }
        }
        return false
    }

    private func plainInlineText(_ nodes: [MarkdownParser.InlineNode]) -> String {
        nodes.map { node in
            switch node {
            case .text(let text):
                return text
            case .emphasis(let children), .strong(let children), .strikethrough(let children):
                return plainInlineText(children)
            case .code(let code):
                return code
            case .link(_, _, let children):
                return plainInlineText(children)
            case .autolink(_, _, let originalText):
                return originalText
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
            case .lineBreak, .softBreak:
                return "\n"
            case .html(let html):
                return html
            case .image(_, let alt, _):
                return alt
            case .footnoteReference(let label):
                return "[\(label)]"
            }
        }.joined()
    }

    private func topLevelSummary(_ blocks: [MarkdownParser.BlockNode]) -> String {
        blocks.map { block in
            switch block {
            case .heading(let level, let children, _):
                return "h\(level):\(plainInlineText(children).prefix(32))"
            case .paragraph(let children):
                return "p:\(plainInlineText(children).prefix(32))"
            case .list(let ordered, _, let items):
                return ordered ? "ol[\(items.count)]" : "ul[\(items.count)]"
            case .taskList(let items):
                return "tl[\(items.count)]"
            case .table(let header, let rows):
                return "table[\(header.count)x\(rows.count)]"
            case .blockquote(let children):
                return "blockquote[\(children.count)]"
            case .codeBlock(let language, _):
                return "code(\(language ?? "-"))"
            case .horizontalRule:
                return "hr"
            case .html:
                return "html"
            case .footnoteDefinition(let label, _):
                return "fn[\(label)]"
            }
        }.joined(separator: ", ")
    }

    private func makeLongStreamingDemoMarkdown() -> String {
        var parts: [String] = []
        parts.append("""
        # Streaming Demo

        Watch a much longer markdown document appear progressively.

        ## Features
        - Progressive rendering
        - Memory efficient updates
        - Smooth partial parsing
        - Works with headings, lists, tables, and code blocks
        """)

        for section in 1...24 {
            parts.append("""
            ## Section \(section)

            This section simulates incoming realtime content for a large markdown document.
            It includes mixed syntax so the parser and renderer update incrementally.

            ### Checklist
            - [x] Parsed heading \(section)
            - [x] Parsed list \(section)
            - [ ] Parsed footnotes (demo placeholder)

            ### Numbered Steps
            1. Receive chunk \(section)
            2. Parse chunk \(section)
            3. Render chunk \(section)

            ### Table
            | Metric | Value |
            |:--|--:|
            | Section | \(section) |
            | Characters | \(section * 420) |
            | Throughput | \(50 + section) chunks/s |

            ### Code
            ```swift
            struct StreamChunk\(section) {
                let id: Int
                let text: String
            }

            func consume(chunk: StreamChunk\(section)) {
                print("Chunk \\(chunk.id): \\(chunk.text.count) chars")
            }
            ```

            > Streaming note: section \(section) was appended without resetting prior content.
            """)
        }

        parts.append("""
        ## Final Notes

        This demo intentionally uses a large markdown payload to stress incremental rendering.
        Stop and restart streaming at any point to replay from the beginning.

        **End of long streaming demo**
        """)

        return parts.joined(separator: "\n\n")
    }
}

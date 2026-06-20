import Foundation

private struct BenchmarkCase {
    let name: String
    let markdown: String
    let configuration: MarkdownConfiguration
}

private let environment = ProcessInfo.processInfo.environment
private let sections = Int(environment["GLIMMER_PARSER_BENCH_SECTIONS"] ?? "") ?? 120
private let repeats = Int(environment["GLIMMER_PARSER_BENCH_REPEATS"] ?? "") ?? 7
private let warmups = Int(environment["GLIMMER_PARSER_BENCH_WARMUPS"] ?? "") ?? 2
private let selectedCorpora = Set(
    (environment["GLIMMER_PARSER_BENCH_CORPORA"] ?? "plain,inline,containers,mixed")
        .split(separator: ",")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
)

private func configured(_ github: Bool) -> MarkdownConfiguration {
    var configuration = MarkdownConfiguration.default
    configuration.enableCaching = false
    configuration.enableRenderCaching = false
    if github {
        configuration.enableMentions = true
        configuration.enableIssueReferences = true
        configuration.enableAutolinks = true
        configuration.enableCommitSHAs = true
        configuration.enableRepositoryReferences = true
        configuration.enablePullRequestReferences = true
        configuration.enableEmojiShortcodes = true
    }
    return configuration
}

private func makeCorpus(kind: String, sections: Int) -> String {
    var output = "# \(kind) Corpus\n\n"
    output.reserveCapacity(sections * 1_200)

    for index in 0..<sections {
        switch kind {
        case "plain":
            output += """
            ## Section \(index)

            This paragraph exercises paragraph collection, continuation scanning, punctuation, and numbers \(index).
            A second sentence keeps the literal inline parser busy without GitHub-specific syntax.

            Another paragraph follows so blank-line boundaries remain part of the timing.

            """
        case "inline":
            output += """
            ## Inline \(index)

            Paragraph \(index) with **bold**, *italic*, ~~struck~~, `inline code`, [link](https://example.com/\(index) "title"),
            https://github.com/glimmer/\(index), @octocat\(index % 7), #\(100 + index), apple/swift#\(index), and :tada:.

            """
        case "containers":
            output += """
            > Quote \(index) with **bold** and [link](https://example.com/q\(index)).
            > - nested quoted item
            >   - deeper quoted item

            - Level one item \(index) with **bold** text
              - Level two with `code`
                - Level three with *italics*
            - Another level one

            - [x] Completed task \(index)
            - [ ] Pending task \(index)

            """
        default:
            output += """
            ## Section \(index): The *quick* **brown** fox :rocket:

            Paragraph \(index) with **bold**, *italic*, ~~struck~~, `inline code`, [link](https://example.com/page/\(index)),
            https://github.com/glimmer/issue\(index), @octocat\(index % 7), #\(100 + index), apple/swift#\(index), and :sparkles:.

            - Level one item \(index)
              - Level two with `code` and [link](https://example.com/\(index))
                - Level three with *italics*

            | A | *B* | **C** |
            |---|-----|-------|
            | cell \(index) | [t](https://x.y/\(index)) | `code` |
            | @mention | #\(index) | ~~gone~~ |

            ```swift
            let value = \(index)
            ```

            > Quoted wisdom \(index) with **bold**.

            Footnote reference here.[^\(index)]

            [^\(index)]: The footnote *content* for section \(index).

            ---

            """
        }
    }

    return output
}

private func makeCases() -> [BenchmarkCase] {
    let names = ["plain", "inline", "containers", "mixed"].filter {
        selectedCorpora.contains("all") || selectedCorpora.contains($0)
    }
    return names.map { name in
        BenchmarkCase(
            name: name,
            markdown: makeCorpus(kind: name, sections: sections),
            configuration: configured(name == "inline" || name == "mixed")
        )
    }
}

@inline(never)
private func parseScore(_ markdown: String, configuration: MarkdownConfiguration) -> Int {
    scoreBlocks(MarkdownParser.parse(markdown, configuration: configuration))
}

private func scoreBlocks(_ blocks: [MarkdownParser.BlockNode]) -> Int {
    var result = blocks.count
    for block in blocks {
        result = (result &* 31) ^ scoreBlock(block)
    }
    return result
}

private func scoreBlock(_ block: MarkdownParser.BlockNode) -> Int {
    switch block {
    case let .heading(level, children, id):
        return level ^ (id?.utf8.count ?? 0) ^ scoreInlines(children)
    case let .paragraph(children):
        return 3 ^ scoreInlines(children)
    case let .blockquote(children):
        return 5 ^ scoreBlocks(children)
    case let .codeBlock(language, content):
        return 7 ^ (language?.utf8.count ?? 0) ^ content.utf8.count
    case let .list(ordered, tight, items):
        var result = ordered ? 11 : 13
        result ^= tight ? 17 : 19
        for item in items {
            result = (result &* 31) ^ item.marker.utf8.count ^ scoreBlocks(item.content)
        }
        return result
    case let .taskList(items):
        var result = 23
        for item in items {
            result = (result &* 31) ^ (item.isChecked ? 29 : 31) ^ scoreInlines(item.content)
        }
        return result
    case let .table(header, rows):
        var result = 37 ^ scoreCells(header)
        for row in rows {
            result = (result &* 31) ^ scoreCells(row)
        }
        return result
    case .horizontalRule:
        return 41
    case let .html(content):
        return 43 ^ content.utf8.count
    case let .footnoteDefinition(label, children):
        return 47 ^ label.utf8.count ^ scoreBlocks(children)
    }
}

private func scoreCells(_ cells: [MarkdownParser.TableCell]) -> Int {
    var result = cells.count
    for cell in cells {
        result = (result &* 31) ^ scoreAlignment(cell.alignment) ^ scoreInlines(cell.content)
    }
    return result
}

private func scoreAlignment(_ alignment: MarkdownParser.TableAlignment) -> Int {
    switch alignment {
    case .left: return 2
    case .center: return 3
    case .right: return 5
    case .none: return 7
    }
}

private func scoreInlines(_ nodes: [MarkdownParser.InlineNode]) -> Int {
    var result = nodes.count
    for node in nodes {
        result = (result &* 31) ^ scoreInline(node)
    }
    return result
}

private func scoreInline(_ node: MarkdownParser.InlineNode) -> Int {
    switch node {
    case let .text(value):
        return value.utf8.count
    case let .emphasis(children):
        return 53 ^ scoreInlines(children)
    case let .strong(children):
        return 59 ^ scoreInlines(children)
    case let .strikethrough(children):
        return 61 ^ scoreInlines(children)
    case let .code(value):
        return 67 ^ value.utf8.count
    case let .link(url, title, children):
        return 71 ^ url.absoluteString.utf8.count ^ (title?.utf8.count ?? 0) ^ scoreInlines(children)
    case let .image(url, alt, title):
        return 73 ^ url.absoluteString.utf8.count ^ alt.utf8.count ^ (title?.utf8.count ?? 0)
    case let .autolink(url, type, originalText):
        return 79 ^ url.absoluteString.utf8.count ^ scoreAutolinkType(type) ^ originalText.utf8.count
    case let .mention(username):
        return 83 ^ username.utf8.count
    case let .issueReference(number):
        return 89 ^ number
    case let .commitSHA(sha, short):
        return 97 ^ sha.utf8.count ^ short.utf8.count
    case let .repositoryReference(owner, repo):
        return 101 ^ owner.utf8.count ^ repo.utf8.count
    case let .pullRequestReference(owner, repo, number):
        return 103 ^ owner.utf8.count ^ repo.utf8.count ^ number
    case .lineBreak:
        return 107
    case .softBreak:
        return 109
    case let .html(value):
        return 113 ^ value.utf8.count
    case let .footnoteReference(label):
        return 127 ^ label.utf8.count
    case let .extensionInline(node):
        return 131 ^ node.namespace.utf8.count ^ node.name.utf8.count ^ node.literal.utf8.count
    }
}

private func scoreAutolinkType(_ type: MarkdownParser.AutolinkType) -> Int {
    switch type {
    case .url: return 2
    case .www: return 3
    case .email: return 5
    }
}

private func timed(_ block: () -> Int) -> (seconds: Double, score: Int) {
    let start = DispatchTime.now().uptimeNanoseconds
    let score = block()
    let end = DispatchTime.now().uptimeNanoseconds
    return (Double(end - start) / 1_000_000_000, score)
}

private func median(_ values: [Double]) -> Double {
    values.sorted()[values.count / 2]
}

private func milliseconds(_ seconds: Double) -> String {
    String(format: "%.2f", seconds * 1000)
}

private let cases = makeCases()
precondition(!cases.isEmpty, "No benchmark corpora selected")

print("[BENCH] standalone parser release benchmark")
print("[BENCH] sections=\(sections) repeats=\(repeats) warmups=\(warmups) corpora=\(cases.map(\.name).joined(separator: ","))")

for benchmarkCase in cases {
    for _ in 0..<warmups {
        _ = parseScore(benchmarkCase.markdown, configuration: benchmarkCase.configuration)
    }

    var timings: [Double] = []
    var lastScore = 0
    for _ in 0..<repeats {
        let result = timed {
            parseScore(benchmarkCase.markdown, configuration: benchmarkCase.configuration)
        }
        timings.append(result.seconds)
        lastScore = result.score
    }

    print(
        "[BENCH] \(benchmarkCase.name): bytes=\(benchmarkCase.markdown.utf8.count) " +
        "median=\(milliseconds(median(timings))) ms checksum=\(lastScore)"
    )
}

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
    if kind == "progit" {
        return makeProGitStyleCorpus(sections: sections)
    }

    if kind == "commonmark-samples" {
        return makeCommonMarkSamplesCorpus(sections: sections)
    }

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

private func makeProGitStyleCorpus(sections: Int) -> String {
    let sectionCount = max(1, sections)
    let topics = [
        ("Getting Started", "Snapshots", "repository", "working tree"),
        ("Branching", "Fast Context Switching", "branch pointer", "merge base"),
        ("Remote Workflows", "Publishing Changes", "remote tracking branch", "upstream"),
        ("History Review", "Inspecting Changes", "commit graph", "revision range"),
        ("Maintenance", "Keeping Repositories Healthy", "object database", "pack file"),
        ("Collaboration", "Reviewing Contributions", "topic branch", "pull request"),
    ]

    var output = """
    # Pro Git-Style Technical Corpus

    This generated corpus models the shape of a long technical Git book without vendoring external prose. It mixes
    chapter headings, explanatory paragraphs, command transcripts, nested lists, tables, links, images, footnotes, and
    reference definitions so parser timings include realistic long-document structure.

    """
    output.reserveCapacity(sectionCount * 2_600)

    for index in 0..<sectionCount {
        let topic = topics[index % topics.count]
        output += """
        # Chapter \(index + 1): \(topic.0)

        \(topic.1)
        \(String(repeating: "=", count: topic.1.count))

        A \(topic.2) records a sequence of snapshots instead of a loose collection of file differences. Each snapshot
        has a parent relationship, an author, a message, and enough metadata for the tools to explain how the
        \(topic.3) moved from one useful state to another.

        When the repository grows, the important performance question is not only whether a parser recognizes the
        syntax correctly. It is also whether long chapters with repeated paragraphs, commands, and reference-style
        links continue to parse predictably after thousands of lines.

        ## Command Transcript \(index)

        ```console
        $ git init example-\(index)
        $ cd example-\(index)
        $ git status --short
        $ git add Sources/App.swift README.md
        $ git commit -m "Record chapter \(index) example"
        ```

        The transcript above should stay literal even when it contains hashes like #\(1000 + index), pipes such as
        alpha | beta | gamma, and characters that usually start inline parsing like *stars* or [brackets].

        ## Review Checklist \(index)

        1. Confirm the \(topic.2) is clean before changing history.
           - Save work on a topic branch named `chapter-\(index)`.
           - Compare against `origin/main` with a range like `main..chapter-\(index)`.
        2. Read the command output before applying the next step.
           - A clean result should show no modified files.
           - A conflicted result should be handled before continuing.
        3. Link the explanation back to [the generated chapter reference][chapter-\(index)].

        | Command | Purpose | Typical Output |
        | --- | --- | --- |
        | `git status` | inspect the worktree | `nothing to commit` |
        | `git log --oneline` | review compact history | `a1b2c3d topic` |
        | `git diff --stat` | summarize changes | `3 files changed` |

        > Note: generated technical prose is intentionally repetitive. Repetition keeps benchmark inputs stable while
        > still exercising headings, paragraphs, lists, block quotes, tables, links, and code blocks.

        ![Generated branch diagram \(index)](images/branch-\(index).png "Branch diagram \(index)")

        [^progit-\(index)]: Generated footnote \(index) records a detail about \(topic.1.lowercased()) and keeps
        footnote parsing active in the large document corpus.

        [chapter-\(index)]: https://example.com/progit/chapter-\(index) "Generated chapter \(index)"

        ---

        """
    }

    return output
}

private func makeCommonMarkSamplesCorpus(sections: Int) -> String {
    let rounds = max(1, min(sections, 8))
    let referenceCount = max(50, min(sections * 3, 120))

    var output = """
    # CommonMark Sample Stress Corpus

    This generated corpus mirrors the component-level benchmark shapes used by markdown-it, commonmark.js, and cmark:
    nested containers, reference definitions, worst-case emphasis delimiters, links, entities, escapes, HTML, raw tabs,
    and code fences. It is a parser hotspot corpus, not an average prose document.

    """
    output.reserveCapacity(rounds * 3_000 + referenceCount * 48)

    for index in 0..<rounds {
        output += """
        ## Block Containers \(index)

        > flat quote \(index)
        > with continuation and **inline emphasis**

        > nested quote \(index)
        > > second level with [link](https://example.com/\(index))
        > > > third level with `code`

         - this
           - is
             - a
               - deeply
                 - nested
                   - bullet
                     - list \(index)

         1. ordered
            2. nested
               3. deeper
                  4. deepest \(index)

         - 1
          - 2
           - 3
            - 4
           - 3
          - 2
         - 1

        ## Inline Delimiters \(index)

        *this *is *a *worst *case *for *em *backtracking \(index)

        __this __is __a __worst __case __for __em __backtracking \(index)

        ***this ***is ***a ***worst ***case ***for ***em ***backtracking \(index)

        Valid links:

        [[[](https://example.com/\(index))](https://example.com/\(index))](https://example.com/\(index))

        ## Escapes, Entities, HTML, and Tabs \(index)

        Escaped punctuation: \\*not emphasis\\* \\[not a link\\] \\`not code\\` \\\\ backslash.

        Entities: AT&amp;T, &#35;\(index), &#x1F680;, &copy;, and unknown &madeup\(index); text.

        Autolinks: <https://example.com/\(index)?a=1&b=2> and <person\(index)@example.com>.

        <div class="sample" data-index="\(index)">
        <span>inline html \(index)</span>
        </div>

        ```swift
        let sample\(index) = "backticks ``` stay inside fenced code"
        print(sample\(index))
        ```

        1\t4444
        22\t333
        333\t22
        4444\t1

        \ttab-indented line \(index)
            space-indented line \(index)
        \ttab-indented line \(index)

        a lot of                                                spaces in between here

        a lot of\t\t\t\t\t\t\t\t\t\t\t\ttabs in between here

        """
    }

    output += "## Reference Definition List\n\n"
    for index in 1...referenceCount {
        output += "[item \(index)]: <https://example.com/reference/\(index)> \"Reference title \(index)\"\n"
    }
    output += "\n"

    return output
}

private func makeCases() -> [BenchmarkCase] {
    let names = ["plain", "inline", "containers", "mixed", "progit", "commonmark-samples"].filter {
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

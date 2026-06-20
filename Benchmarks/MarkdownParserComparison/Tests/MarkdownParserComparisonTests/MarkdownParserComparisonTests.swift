import Foundation
import Glimmer
import Ink
import protocol Markdown.Markup
import struct Markdown.Document
import MarkdownKit
import SwiftyMarkdown
import XCTest

final class MarkdownParserComparisonTests: XCTestCase {
    func testMarkdownParserComparison() throws {
        guard Self.isBenchmarkEnabled else {
            throw XCTSkip(
                "set GLIMMER_COMPARE_MARKDOWN_PARSERS=1 or touch " +
                "/tmp/glimmer-run-markdown-parser-comparison to run parser comparison benchmarks"
            )
        }

        let sections = Self.intEnvironmentValue("GLIMMER_COMPARE_MARKDOWN_SECTIONS", default: 40)
        let repeats = Self.intEnvironmentValue("GLIMMER_COMPARE_MARKDOWN_REPEATS", default: 5)
        let warmups = Self.intEnvironmentValue("GLIMMER_COMPARE_MARKDOWN_WARMUPS", default: 1, minimum: 0)
        let corpora = Self.selectedCorpora(from: Self.makeCorpora(sections: sections))
        let cases = Self.makeBenchmarkCases()

        print("[COMPARE] sections=\(sections), repeats=\(repeats), warmups=\(warmups)")
        print("[COMPARE] corpora=\(corpora.map(\.name).joined(separator: ","))")
        print("[COMPARE] use relative timings only inside each corpus and operation group")

        var results: [BenchmarkResult] = []
        var failures: [String] = []
        var aggregateChecksum = 0

        for corpus in corpora {
            for benchmark in cases {
                do {
                    let result = try Self.run(benchmark, corpus: corpus, repeats: repeats, warmups: warmups)
                    aggregateChecksum &+= result.checksum
                    results.append(result)
                } catch {
                    failures.append("\(corpus.name) / \(benchmark.name): \(error)")
                    print("[COMPARE] failed \(corpus.name) / \(benchmark.name): \(error)")
                }
            }
        }

        XCTAssertFalse(results.isEmpty, "Expected at least one benchmark result.")
        Self.printResults(results, corpusOrder: corpora.map(\.name))

        if !failures.isEmpty {
            print("[COMPARE] failures:")
            for failure in failures {
                print("[COMPARE] - \(failure)")
            }
        }

        XCTAssertGreaterThan(aggregateChecksum, 0)
    }

    // MARK: - Benchmark Cases

    private static func makeBenchmarkCases() -> [BenchmarkCase] {
        var glimmerMinimalCold = MarkdownConfiguration.minimal
        glimmerMinimalCold.enableCaching = false
        glimmerMinimalCold.enableRenderCaching = false

        var glimmerDefaultCold = MarkdownConfiguration.default
        glimmerDefaultCold.enableCaching = false
        glimmerDefaultCold.enableRenderCaching = false

        var glimmerGitHubCold = MarkdownConfiguration.github
        glimmerGitHubCold.enableCaching = false
        glimmerGitHubCold.enableRenderCaching = false

        var glimmerDefaultCached = MarkdownConfiguration.default
        glimmerDefaultCached.enableCaching = true
        glimmerDefaultCached.enableRenderCaching = false

        var glimmerGitHubCached = MarkdownConfiguration.github
        glimmerGitHubCached.enableCaching = true
        glimmerGitHubCached.enableRenderCaching = false

        let inkParser = Ink.MarkdownParser()
        let markdownKitParser = MarkdownKit.MarkdownParser()
        let swiftyMarkdown = SwiftyMarkdown(string: "")

        return [
            BenchmarkCase(
                name: "Glimmer minimal parse",
                operation: "AST/tree",
                notes: "GFM off, footnotes off, caches off",
                prepare: { Glimmer.clearCache() }
            ) { markdown in
                Glimmer.parse(markdown, configuration: glimmerMinimalCold).count
            },
            BenchmarkCase(
                name: "Glimmer default parse",
                operation: "AST/tree",
                notes: "GFM off, footnotes on, caches off",
                prepare: { Glimmer.clearCache() }
            ) { markdown in
                Glimmer.parse(markdown, configuration: glimmerDefaultCold).count
            },
            BenchmarkCase(
                name: "Glimmer github parse",
                operation: "AST/tree",
                notes: "GFM enabled, caches off",
                prepare: { Glimmer.clearCache() }
            ) { markdown in
                Glimmer.parse(markdown, configuration: glimmerGitHubCold).count
            },
            BenchmarkCase(name: "Apple swift-markdown", operation: "AST/tree", notes: "Markdown.Document") { markdown in
                let document = Document(parsing: markdown)
                return Self.countMarkdownNodes(document)
            },
            BenchmarkCase(
                name: "Glimmer default cached parse",
                operation: "AST/tree cached",
                notes: "same input, parser cache enabled",
                prepare: { Glimmer.clearCache() }
            ) { markdown in
                Glimmer.parse(markdown, configuration: glimmerDefaultCached).count
            },
            BenchmarkCase(
                name: "Glimmer github cached parse",
                operation: "AST/tree cached",
                notes: "same input, parser cache enabled",
                prepare: { Glimmer.clearCache() }
            ) { markdown in
                Glimmer.parse(markdown, configuration: glimmerGitHubCached).count
            },
            BenchmarkCase(name: "Ink", operation: "HTML", notes: "MarkdownParser.html") { markdown in
                inkParser.html(from: markdown).utf8.count
            },
            BenchmarkCase(
                name: "Glimmer default attributed",
                operation: "Attributed",
                notes: "GFM off, render cache off",
                prepare: {
                    Glimmer.clearCache()
                    Glimmer.clearRenderCache()
                }
            ) { markdown in
                Glimmer.parseToAttributedString(markdown, configuration: glimmerDefaultCold).characters.count
            },
            BenchmarkCase(
                name: "Glimmer github attributed",
                operation: "Attributed",
                notes: "GFM enabled, render cache off",
                prepare: {
                    Glimmer.clearCache()
                    Glimmer.clearRenderCache()
                }
            ) { markdown in
                Glimmer.parseToAttributedString(markdown, configuration: glimmerGitHubCold).characters.count
            },
            BenchmarkCase(name: "Foundation", operation: "Attributed", notes: "AttributedString(markdown:)") { markdown in
                let attributed = try AttributedString(markdown: markdown)
                return attributed.characters.count
            },
            BenchmarkCase(name: "MarkdownKit", operation: "Attributed", notes: "NSAttributedString parser") { markdown in
                markdownKitParser.parse(markdown).length
            },
            BenchmarkCase(name: "SwiftyMarkdown", operation: "Attributed", notes: "NSAttributedString parser") { markdown in
                swiftyMarkdown.attributedString(from: markdown).length
            },
        ]
    }

    private static func run(
        _ benchmark: BenchmarkCase,
        corpus: BenchmarkCorpus,
        repeats: Int,
        warmups: Int
    ) throws -> BenchmarkResult {
        benchmark.prepare()
        var checksum = 0

        for _ in 0..<max(0, warmups) {
            let outputCount = try autoreleasepool {
                try benchmark.run(corpus.markdown)
            }
            checksum &+= outputCount
        }

        var samples: [Double] = []

        for _ in 0..<max(1, repeats) {
            let start = DispatchTime.now().uptimeNanoseconds
            let outputCount = try autoreleasepool {
                try benchmark.run(corpus.markdown)
            }
            let end = DispatchTime.now().uptimeNanoseconds

            checksum &+= outputCount
            samples.append(Double(end - start) / 1_000_000)
        }

        return BenchmarkResult(
            corpus: corpus.name,
            corpusBytes: corpus.markdown.utf8.count,
            name: benchmark.name,
            operation: benchmark.operation,
            notes: benchmark.notes,
            samples: samples,
            checksum: checksum
        )
    }

    // MARK: - Output

    private static func printResults(_ results: [BenchmarkResult], corpusOrder: [String]) {
        for corpus in corpusOrder {
            let corpusResults = results.filter { $0.corpus == corpus }
            guard !corpusResults.isEmpty else {
                continue
            }

            let corpusKB = (corpusResults.first?.corpusBytes ?? 0) / 1024
            print("")
            print("[COMPARE] Corpus: \(corpus) (\(corpusKB) KB)")
            let grouped = Dictionary(grouping: corpusResults, by: \.operation)

            for operation in ["AST/tree", "AST/tree cached", "HTML", "Attributed"] {
                guard let group = grouped[operation]?.sorted(by: { $0.median < $1.median }),
                      let fastest = group.first?.median else {
                    continue
                }

                print("")
                print("[COMPARE] \(operation)")
                print("| Rank | Parser | Median | Min | Max | Relative | Checksum | Notes |")
                print("| ---: | --- | ---: | ---: | ---: | ---: | ---: | --- |")

                for (index, result) in group.enumerated() {
                    let relative = fastest > 0 ? result.median / fastest : 0
                    print(
                        "| \(index + 1) | \(result.name) | \(Self.ms(result.median)) | " +
                        "\(Self.ms(result.minimum)) | \(Self.ms(result.maximum)) | " +
                        "\(String(format: "%.2fx", relative)) | \(result.checksum) | \(result.notes) |"
                    )
                }
            }
        }
    }

    private static func ms(_ value: Double) -> String {
        String(format: "%.2f ms", value)
    }

    // MARK: - Corpora

    private static func selectedCorpora(from corpora: [BenchmarkCorpus]) -> [BenchmarkCorpus] {
        let rawValue = Self.stringEnvironmentValue("GLIMMER_COMPARE_MARKDOWN_CORPORA", default: "all")
        let requested = Set(
            rawValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )

        if requested.isEmpty || requested.contains("all") {
            return corpora
        }

        return corpora.filter { requested.contains($0.name) }
    }

    private static func makeCorpora(sections: Int) -> [BenchmarkCorpus] {
        [
            BenchmarkCorpus(name: "plain", markdown: makePlainCorpus(sections: sections)),
            BenchmarkCorpus(name: "inline", markdown: makeInlineCorpus(sections: sections)),
            BenchmarkCorpus(name: "titles", markdown: makeTitleCorpus(sections: sections)),
            BenchmarkCorpus(name: "gfm", markdown: makeGitHubCorpus(sections: sections)),
            BenchmarkCorpus(name: "tables", markdown: makeTableCorpus(sections: sections)),
            BenchmarkCorpus(name: "setext", markdown: makeSetextCorpus(sections: sections)),
            BenchmarkCorpus(name: "code", markdown: makeCodeCorpus(sections: sections)),
            BenchmarkCorpus(name: "mixed", markdown: makeMixedCorpus(sections: sections)),
        ]
    }

    private static func makePlainCorpus(sections: Int) -> String {
        var output = "# Plain Paragraph Corpus\n\n"

        for index in 0..<sections {
            output += """
            ## Section \(index)

            This paragraph contains only ordinary prose with predictable punctuation. It is meant to isolate block
            splitting, heading detection, paragraph collection, and basic text node construction without inline markup.

            This second paragraph repeats enough words to produce realistic body text while avoiding trigger characters
            that cause link, mention, issue, emoji, or table recognizers to do extra work in the parser.

            """
        }

        return output
    }

    private static func makeInlineCorpus(sections: Int) -> String {
        var output = "# Inline Markup Corpus\n\n"

        for index in 0..<sections {
            output += """
            ## Section \(index): The *quick* **brown** fox

            Paragraph \(index) with **bold**, *italic*, ~~struck~~, `inline code`, [link](https://example.com/\(index)),
            nested **strong *emphasis* here**, escaped \\*literal asterisks\\*, and repeated `code spans` in one line.

            - Level one item \(index) with **bold** text
              - Level two with `code` and [link](https://example.com/list/\(index))
                - Level three with *italics*
            - Another level one item with ~~deleted~~ content

            > Quote \(index) with **bold**, *italic*, and [link](https://example.com/q\(index)).

            """
        }

        return output
    }

    private static func makeTitleCorpus(sections: Int) -> String {
        var output = "# Link Title Corpus\n\n"

        for index in 0..<sections {
            output += """
            ## Title Section \(index)

            Paragraph \(index) includes [double](https://example.com/double/\(index) "Double title \(index)"),
            [single](https://example.com/single/\(index) 'Single title \(index)'), and
            [parenthesized](https://example.com/paren/\(index) (Parenthesized title \(index))) links.

            Repeated titled links keep the title scanner hot: [alpha](https://example.com/a/\(index) "Alpha title \(index)")
            [beta](https://example.com/b/\(index) "Beta title \(index)") [gamma](https://example.com/c/\(index) "Gamma title \(index)").

            Images also carry titles: ![diagram \(index)](https://example.com/image/\(index).png "Diagram title \(index)")
            and ![icon \(index)](https://example.com/icon/\(index).png 'Icon title \(index)').

            Escaped title fallback remains represented by [escaped](https://example.com/e/\(index) "A \\\"quoted\\\" title \(index)").

            """
        }

        return output
    }

    private static func makeGitHubCorpus(sections: Int) -> String {
        var output = "# GitHub Feature Corpus\n\n"

        for index in 0..<sections {
            output += """
            ## GitHub Section \(index) :rocket:

            Work item \(index) mentions @octocat\(index % 7), issue #\(100 + index), repository apple/swift, pull request
            swiftlang/swift-markdown#\(index), autolink https://github.com/glimmer/issue\(index), and commit
            deadbeefdeadbeefdeadbeefdeadbeefdeadbeef. Emoji :tada: :sparkles: :rocket: appear repeatedly.

            - [x] Completed task \(index) with @reviewer\(index % 5)
            - [ ] Pending task for repo owner\(index % 9)/project\(index)

            Footnote reference here.[^\(index)]

            [^\(index)]: Footnote content for section \(index) with @mention and #\(index).

            """
        }

        return output
    }

    private static func makeTableCorpus(sections: Int) -> String {
        var output = "# Table Corpus\n\n"

        for index in 0..<sections {
            output += """
            ## Table Section \(index)

            | Column A | Column *B* | **C** | `D` |
            |----------|-----------:|:------|-----|
            | cell \(index) | *styled* | [t](https://x.y/\(index)) | `code` |
            | alpha beta gamma | 12345 | ~~gone~~ | text |
            | row3 \(index) | **bb** | plain | text |

            Paragraph after table \(index) keeps the parser moving between table and paragraph modes.

            """
        }

        return output
    }

    private static func makeSetextCorpus(sections: Int) -> String {
        var output = """
        Setext Heading Corpus
        =====================

        """

        for index in 0..<sections {
            output += """
            Setext Section \(index)! Value \(index * 7)
            ===========================================

            This paragraph follows a level-one setext heading and keeps enough ordinary text around it to exercise
            paragraph boundaries, inline parsing, and heading ID generation without table or list work dominating.

            Detailed Setext Subsection \(index): Parser Notes
            -------------------------------------------------

            Follow-up paragraph \(index) includes **bold**, *italic*, and `inline code` so the benchmark still covers
            normal inline parsing after setext recognition and slug generation.

            """
        }

        return output
    }

    private static func makeCodeCorpus(sections: Int) -> String {
        var output = "# Code Block Corpus\n\n"

        for index in 0..<sections {
            output += """
            ## Code Section \(index)

            ```swift
            struct Section\(index): View {
                let value = \(index)
                var body: some View {
                    Text("hello \\(value)")
                        .font(.body)
                        .padding(\(index % 16))
                }
            }
            ```

            Regular paragraph after code block \(index) with `inline code` and **bold** text.

            ```
            raw block \(index)
            line two with | pipes | and # symbols that should stay literal
            ```

            """
        }

        return output
    }

    private static func makeMixedCorpus(sections: Int) -> String {
        var output = "# Mixed Markdown Parser Comparison Corpus\n\n"

        for index in 0..<sections {
            output += """
            ## Section \(index): The *quick* **brown** fox :rocket:

            Paragraph \(index) with **bold**, *italic*, ~~struck~~, `inline code`, a [link](https://example.com/page/\(index)),
            an autolink https://github.com/glimmer/issue\(index), a mention @octocat\(index % 7), issue #\(100 + index),
            repo apple/swift and PR swiftlang/swift-markdown#\(index). Emoji :tada: :sparkles: and nested **strong *emphasis* here**.

            - Level one item \(index) with **bold** text
              - Level two with `code` and [link](https://example.com/\(index))
                - Level three with *italics* and :rocket:
              - Level two again @user\(index % 5)
            - Another level one #\(index)

            - [x] Completed task \(index) with **bold**
            - [ ] Pending task with [link](https://example.com/t\(index))

            | Column A | Column *B* | **C** | `D` |
            |----------|-----------|-------|-----|
            | cell \(index) | *styled* | [t](https://x.y/\(index)) | `code` |
            | @mention | #\(index) | :tada: | ~~gone~~ |
            | row3 \(index) | **bb** | plain | text |

            ```swift
            struct Section\(index): View {
                let value = \(index)
                var body: some View {
                    Text("hello \\(value)")
                        .font(.body)
                        .padding(\(index % 16))
                }
            }
            ```

            > Quoted wisdom \(index) with **bold** and a [link](https://example.com/q\(index)).
            > Second line of the quote with `code`.

            Footnote reference here.[^\(index)]

            [^\(index)]: The footnote *content* for section \(index).

            ---

            """
        }

        return output
    }

    // MARK: - Helpers

    private static var isBenchmarkEnabled: Bool {
        ProcessInfo.processInfo.environment["GLIMMER_COMPARE_MARKDOWN_PARSERS"] == "1" ||
        FileManager.default.fileExists(atPath: "/tmp/glimmer-run-markdown-parser-comparison")
    }

    private static func countMarkdownNodes(_ markup: any Markup) -> Int {
        markup.children.reduce(1) { count, child in
            count + countMarkdownNodes(child)
        }
    }

    private static func intEnvironmentValue(_ key: String, default defaultValue: Int, minimum: Int = 1) -> Int {
        if let rawValue = ProcessInfo.processInfo.environment[key],
           let value = Int(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
           value >= minimum {
            return value
        }

        if let filePath = overrideFilePath(for: key),
           let rawValue = try? String(contentsOfFile: filePath, encoding: .utf8),
           let value = Int(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
           value >= minimum {
            return value
        }

        return defaultValue
    }

    private static func stringEnvironmentValue(_ key: String, default defaultValue: String) -> String {
        if let rawValue = ProcessInfo.processInfo.environment[key],
           !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return rawValue
        }

        if let filePath = overrideFilePath(for: key),
           let rawValue = try? String(contentsOfFile: filePath, encoding: .utf8),
           !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return rawValue
        }

        return defaultValue
    }

    private static func overrideFilePath(for key: String) -> String? {
        switch key {
        case "GLIMMER_COMPARE_MARKDOWN_SECTIONS":
            return "/tmp/glimmer-compare-markdown-sections"
        case "GLIMMER_COMPARE_MARKDOWN_REPEATS":
            return "/tmp/glimmer-compare-markdown-repeats"
        case "GLIMMER_COMPARE_MARKDOWN_WARMUPS":
            return "/tmp/glimmer-compare-markdown-warmups"
        case "GLIMMER_COMPARE_MARKDOWN_CORPORA":
            return "/tmp/glimmer-compare-markdown-corpora"
        default:
            return nil
        }
    }
}

private struct BenchmarkCorpus {
    let name: String
    let markdown: String
}

private struct BenchmarkCase {
    let name: String
    let operation: String
    let notes: String
    let prepare: () -> Void
    let run: (String) throws -> Int

    init(
        name: String,
        operation: String,
        notes: String,
        prepare: @escaping () -> Void = {},
        run: @escaping (String) throws -> Int
    ) {
        self.name = name
        self.operation = operation
        self.notes = notes
        self.prepare = prepare
        self.run = run
    }
}

private struct BenchmarkResult {
    let corpus: String
    let corpusBytes: Int
    let name: String
    let operation: String
    let notes: String
    let samples: [Double]
    let checksum: Int

    var median: Double {
        let sorted = samples.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    var minimum: Double {
        samples.min() ?? 0
    }

    var maximum: Double {
        samples.max() ?? 0
    }
}

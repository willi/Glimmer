# Markdown Parser Comparison Benchmark

This opt-in benchmark compares Glimmer against popular Markdown parsers commonly used in iOS apps:

- Glimmer
- Apple's `swift-markdown`
- Foundation `AttributedString(markdown:)`
- Down
- Ink
- MarkdownKit
- SwiftyMarkdown

MarkdownUI is intentionally not part of the timed set. It is a popular SwiftUI Markdown renderer, but its public surface is a view-rendering API rather than a standalone parser/converter API that can be fairly called in a parser benchmark.

Down is benchmarked from the sibling package at `../DownMarkdownParserComparison`. Down bundles classic `libcmark`, while Apple's `swift-markdown` depends on `swift-cmark`; putting both in one SwiftPM graph causes C module/header conflicts. Keeping Down isolated lets both benchmarks build cleanly.

## Candidate Coverage

| Package | Source | Timed here | Operation |
| --- | --- | --- | --- |
| Glimmer | Local package | Yes | AST/tree, attributed |
| Apple `swift-markdown` | https://github.com/swiftlang/swift-markdown | Yes | AST/tree |
| Foundation `AttributedString(markdown:)` | Apple Foundation | Yes | Attributed |
| Down | https://github.com/johnxnguyen/Down | Yes, isolated package | HTML |
| Ink | https://github.com/JohnSundell/Ink | Yes | HTML |
| MarkdownKit | https://github.com/bmoliveira/MarkdownKit | Yes | Attributed |
| SwiftyMarkdown | https://github.com/SimonFairbairn/SwiftyMarkdown | Yes | Attributed |
| MarkdownUI | https://github.com/gonzalezreal/swift-markdown-ui | No | SwiftUI rendering API |
| Swift MarkdownKit | https://github.com/objecthub/swift-markdownkit | No | Shares the `MarkdownKit` package/product name with the legacy MarkdownKit benchmarked above; compare in a separate package if needed. |

## Run

Run both benchmark packages from the repository root:

```sh
sh Benchmarks/run-markdown-parser-comparison.sh
```

The runner defaults to `Release`, `platform=iOS Simulator,name=iPhone 17 Pro`, 40 sections per corpus, 5 repeats, 1 warmup, and all corpus profiles. Override those defaults with:

```sh
GLIMMER_COMPARE_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro'
GLIMMER_COMPARE_CONFIGURATION=Release
GLIMMER_COMPARE_MARKDOWN_SECTIONS=80
GLIMMER_COMPARE_MARKDOWN_REPEATS=7
GLIMMER_COMPARE_MARKDOWN_WARMUPS=2
GLIMMER_COMPARE_MARKDOWN_CORPORA=plain,inline,titles,gfm,tables,setext,code,mixed,progit,commonmark-samples
```

Corpus profiles:

- `plain`: headings and paragraphs with no inline trigger characters.
- `inline`: emphasis, links, code spans, lists, and block quotes.
- `titles`: repeated links and images with double-quoted, single-quoted, parenthesized, and escaped titles.
- `gfm`: mentions, issue references, repository and PR references, autolinks, emoji shortcodes, task lists, and footnotes.
- `tables`: repeated tables with styled cells.
- `setext`: repeated setext headings with paragraph and inline parsing.
- `code`: fenced code blocks and literal-heavy content.
- `mixed`: combined stress corpus similar to real README/chat output.
- `progit`: generated long-form technical-document corpus modeled after Pro Git-style chapters, with headings,
  prose, command transcripts, nested lists, tables, links, images, footnotes, and reference definitions.
- `commonmark-samples`: generated hotspot corpus modeled after the markdown-it/commonmark.js/cmark sample suites,
  including nested containers, reference-definition lists, worst-case emphasis delimiters, nested links, entities,
  escapes, HTML, raw tabs, and code fences.

To run only the externally inspired corpus shapes:

```sh
GLIMMER_COMPARE_MARKDOWN_CORPORA=progit,commonmark-samples \
  sh Benchmarks/run-markdown-parser-comparison.sh
```

The generated `progit` corpus avoids vendoring external book text while preserving the large technical-document shape
used by cmark and swift-cmark benchmarks. The generated `commonmark-samples` corpus is intentionally capped so slow
third-party comparators can finish; it is intended for parser hotspot and regression checks, not as an average-document
performance claim.

To run manually, create the `/tmp` opt-in flag first. `xcodebuild` does not reliably pass shell environment variables through to the simulator XCTest process for generated SwiftPM schemes, so the tests also read `/tmp` flag/config files.

```sh
touch /tmp/glimmer-run-markdown-parser-comparison
printf 40 > /tmp/glimmer-compare-markdown-sections
printf 5 > /tmp/glimmer-compare-markdown-repeats
printf 1 > /tmp/glimmer-compare-markdown-warmups
printf plain,gfm,mixed > /tmp/glimmer-compare-markdown-corpora

xcodebuild -scheme MarkdownParserComparison-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Release \
  test
```

Run the Down comparison separately from `../DownMarkdownParserComparison`:

```sh
xcodebuild -scheme DownMarkdownParserComparison-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Release \
  test
```

Remove `/tmp/glimmer-run-markdown-parser-comparison` after manual runs. The benchmark is skipped unless `GLIMMER_COMPARE_MARKDOWN_PARSERS=1` is visible to the test process or the `/tmp` flag exists, so the nested packages can be built without turning timing into a CI gate.

Inside Xcode, a scheme test environment variable of `GLIMMER_COMPARE_MARKDOWN_PARSERS=1` also enables the benchmark.

## Output Groups

Not every library exposes the same abstraction, so results are grouped by operation:

- `AST/tree`: parses into a structural tree.
- `AST/tree cached`: parses the same input repeatedly with Glimmer's parser cache enabled.
- `HTML`: parses and converts to HTML.
- `Attributed`: parses and produces attributed text.

Use relative timings only within the same operation group. Comparing an AST parser directly to an attributed-string renderer is not an apples-to-apples measurement.

@testable import Glimmer

enum ParserCorrectnessFixtures {
    struct SemanticFixture {
        let name: String
        let markdown: String
        let configuration: MarkdownConfiguration
        let expectedBlockCount: Int
        let expectedHash: String
    }

    struct NamedMarkdown {
        let name: String
        let markdown: String
        let configuration: MarkdownConfiguration
    }

    static let semanticFixtures: [SemanticFixture] = [
        SemanticFixture(
            name: "commonmarkContainers",
            markdown: """
            # Title

            > Quote **bold**
            > continued
            >
            > - nested item
            >   continuation
            > - second

            1. ordered
               - nested unordered
               - second nested

            Paragraph with [link](https://example.com/a(b)c "Title") and ![alt](https://example.com/i.png).
            """,
            configuration: .default,
            expectedBlockCount: 5,
            expectedHash: "73804767c997afe1"
        ),
        SemanticFixture(
            name: "githubOptIn",
            markdown: """
            ## GitHub

            @octocat fixed #42 in apple/swift#123 with deadbeefdeadbeefdeadbeefdeadbeefdeadbeef and :rocket:.

            - [x] done
            - [ ] todo

            [^note]: Footnote with @reviewer and https://github.com/apple/swift.
            """,
            configuration: .github,
            expectedBlockCount: 4,
            expectedHash: "ed188770a5705c9a"
        ),
        SemanticFixture(
            name: "githubDisabled",
            markdown: """
            @octocat fixed #42 in apple/swift#123 with deadbeefdeadbeefdeadbeefdeadbeefdeadbeef and :rocket:.

            [ref][id]

            [id]: https://example.com
            """,
            configuration: .default,
            expectedBlockCount: 3,
            expectedHash: "5649c6c83abcfb83"
        ),
        SemanticFixture(
            name: "unicodeEscapesAndInlineHTML",
            markdown: """
            Paragraph with café, family emoji 👨‍👩‍👧‍👦, escaped \\*marker\\*, <br>, and [unicode](https://example.com/café "Cafe").
            """,
            configuration: .default,
            expectedBlockCount: 1,
            expectedHash: "8b3e7e0212d3cd33"
        ),
        SemanticFixture(
            name: "tableFootnoteAndTaskList",
            markdown: """
            | A | B |
            |---|:---:|
            | **bold** | [link](https://example.com) |

            Footnote here.[^a]

            [^a]: first line
                continuation with *style*
            """,
            configuration: .github,
            expectedBlockCount: 3,
            expectedHash: "f7e246cd7f6964c7"
        )
    ]

    static let blockquoteEquivalence: [NamedMarkdown] = [
        NamedMarkdown(
            name: "paragraphLazyContinuation",
            markdown: """
            > Quote line 1
            lazy continuation with **bold**
            >
            > second paragraph with [link](https://example.com)
            """,
            configuration: .default
        ),
        NamedMarkdown(
            name: "nestedBlocks",
            markdown: """
            > ## Quoted Heading
            >
            > - first
            > - second
            >
            > ```swift
            > let x = 1
            > ```
            """,
            configuration: .github
        ),
        NamedMarkdown(
            name: "unicode",
            markdown: """
            > café quoted
            continued 世界
            """,
            configuration: .default
        )
    ]

    static let listItemContentEquivalence: [NamedMarkdown] = [
        NamedMarkdown(
            name: "paragraphContinuation",
            markdown: """
            first line with **bold**
              continuation with [link](https://example.com)
            """,
            configuration: .default
        ),
        NamedMarkdown(
            name: "taskItem",
            markdown: """
            [x] completed task
              continuation with `code`
            """,
            configuration: .github
        ),
        NamedMarkdown(
            name: "nestedBlockFallback",
            markdown: """
            first paragraph

              ## nested heading
              nested paragraph
            """,
            configuration: .default
        )
    ]

    static let footnoteDefinitionEquivalence: [NamedMarkdown] = [
        NamedMarkdown(
            name: "paragraphFastPath",
            markdown: """
            [^one]: first line with **bold**
                continuation with [link](https://example.com)
            """,
            configuration: .github
        ),
        NamedMarkdown(
            name: "nestedBlockFallback",
            markdown: """
            [^two]: first line
                - nested item
                - second item
            """,
            configuration: .github
        )
    ]

    static let inlineEquivalence: [NamedMarkdown] = [
        NamedMarkdown(
            name: "plainAndMarkers",
            markdown: "Plain ASCII before **bold** and *italic* after",
            configuration: .default
        ),
        NamedMarkdown(
            name: "linksEscapesAndCode",
            markdown: "Escaped \\*marker\\*, `code`, and [link](https://example.com/docs \"Title\")",
            configuration: .default
        ),
        NamedMarkdown(
            name: "githubEnabled",
            markdown: "@octocat fixed #42 in apple/swift#123 with :rocket:",
            configuration: .github
        ),
        NamedMarkdown(
            name: "unicodeFallback",
            markdown: "Unicode café and 世界 keep character-safe parsing",
            configuration: .default
        )
    ]

    static let linkEquivalence: [NamedMarkdown] = [
        NamedMarkdown(
            name: "simple",
            markdown: "[label](https://example.com/path)",
            configuration: .default
        ),
        NamedMarkdown(
            name: "styledLabelAndTitle",
            markdown: "[**Guide** and *topic*](https://example.com/docs \"Title\")",
            configuration: .default
        ),
        NamedMarkdown(
            name: "escapedBracket",
            markdown: "[a \\[b\\]](http://example.com)",
            configuration: .default
        ),
        NamedMarkdown(
            name: "balancedDestination",
            markdown: "[t](https://example.com/a(b)c)",
            configuration: .default
        ),
        NamedMarkdown(
            name: "unicodeDestination",
            markdown: "[cafe](https://example.com/café \"Cafe title\")",
            configuration: .default
        )
    ]

    static let inlineLinkResources: [String] = [
        "https://example.com/docs/123?ref=glimmer)",
        "https://example.com/docs \"Title\")",
        "https://example.com/docs 'Title')",
        "https://example.com/a(b)c)",
        #"https://example.com/a\)b)"#,
        "https://example.com/café)"
    ]
}

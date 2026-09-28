/// Realistic answers for streaming tests. No setext headings or link reference definitions: those legitimately
/// restyle earlier text (see the plan's ruling on tail re-parse).
enum StreamingFixtures {
    static let all: [(name: String, markdown: String)] = [
        ("prose", """
        Here is a short answer with **bold words**, some *emphasis*, a `code span`, and a [link](https://example.com/docs). \
        It keeps going for a while so the reveal has several lines to work through.

        A second paragraph follows. It mentions emoji 👋🏽 and a bit of right-to-left text: مرحبا بالعالم. Then it ends.
        """),
        ("lists", """
        ## Steps

        1. Install the package.
        2. Configure the **theme** and the extensions.
        3. Stream the answer:
           - start the request
           - append each chunk
        - [x] Parser done
        - [ ] Reveal tuned
        """),
        ("code-and-table", """
        Use this snippet:

        ```swift
        let view = GlimmerView()
        view.update(markdown: text, isStreaming: true)
        ```

        | Option | Default |
        |:--|--:|
        | fade | 0.6 s |
        | base rate | 60 chars/s |

        That is all.
        """),
        ("quotes-and-headings", """
        # Summary

        > The answer is quoted here with **emphasis**.
        > > And a nested quote.

        ### Details

        Final line after the quotes, with a trailing link to [the spec](https://example.com/spec).
        """),
        ("mixed", """
        Intro sentence before a rule.

        ---

        - item with `inline code`
        - item with ~~strikethrough~~

        Closing paragraph that is long enough to wrap across more than one line on a phone-sized screen width.
        """),
    ]
}

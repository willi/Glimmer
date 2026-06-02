import SwiftUI
import Glimmer

struct EdgeCasesDemo: View {
    @State private var selectedCase = 0
    
    private let testCases: [(name: String, markdown: String)] = [
        ("Nested Structures", nestedStructures),
        ("Special Characters", specialCharacters),
        ("Mixed Languages", mixedLanguages),
        ("Malformed Markdown", malformedMarkdown),
        ("Performance Stress", performanceStress),
        ("Unicode & Emoji", unicodeAndEmoji),
        ("Code Block Edge Cases", codeBlockEdgeCases),
        ("Link Edge Cases", linkEdgeCases),
        ("Table Edge Cases", tableEdgeCases),
        ("Empty & Whitespace", emptyAndWhitespace)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Case selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(testCases.enumerated()), id: \.offset) { index, testCase in
                        Button(action: { selectedCase = index }) {
                            Text(testCase.name)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedCase == index ? Color.accentColor : Color.gray.opacity(0.2))
                                .foregroundColor(selectedCase == index ? .white : .primary)
                                .cornerRadius(15)
                        }
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Test case description
            VStack(alignment: .leading, spacing: 8) {
                Text(testCases[selectedCase].name)
                    .font(.headline)
                Text(getDescription(for: selectedCase))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.gray.opacity(0.05))
            
            Divider()
            
            // Rendered markdown
            ScrollView {
                MarkdownView(
                    markdown: testCases[selectedCase].markdown,
                    configuration: .default,
                    onLinkTap: { url in
                        print("🔗 Edge case link: \(url)")
                    }
                )
                .padding()
            }
        }
        .navigationTitle("Edge Cases")
    }
    
    func getDescription(for index: Int) -> String {
        switch index {
        case 0: return "Deeply nested lists, blockquotes, and mixed structures"
        case 1: return "Special characters, escaping, and character entities"
        case 2: return "Multiple languages, RTL text, and mixed scripts"
        case 3: return "Intentionally malformed markdown to test error handling"
        case 4: return "Large amounts of content to stress test performance"
        case 5: return "Unicode characters, emoji, and special symbols"
        case 6: return "Code blocks with special cases and edge conditions"
        case 7: return "Various link formats and edge cases"
        case 8: return "Complex tables with various alignments and content"
        case 9: return "Empty elements and whitespace handling"
        default: return "Edge case test"
        }
    }
}

// MARK: - Test Cases

private let nestedStructures = """
# Deeply Nested Structures

> Level 1 blockquote
> > Level 2 blockquote with **bold**
> > > Level 3 blockquote with *italic*
> > > > Level 4 blockquote with `code`
> > > > > Level 5 blockquote with ~~strikethrough~~
> > > > > > Level 6 blockquote with [link](https://example.com)

## Nested Lists

1. First level ordered
   1. Second level ordered
      1. Third level ordered
         - Fourth level unordered
           - Fifth level unordered
             * Sixth level with **bold**
               + Seventh level with *italic*
                 - Eighth level with `code`
   2. Back to second level
2. Back to first level

## Mixed Nesting

> Blockquote with list:
> 1. First item in quote
>    > Nested quote in list
>    > - Unordered in nested quote
>    >   ```swift
>    >   // Code in nested quote in list
>    >   print("Deep nesting!")
>    >   ```
> 2. Second item
>    - Sub-item with **bold** and *italic* and `code`

## Task Lists in Blockquotes

> - [x] Completed task in blockquote
> - [ ] Incomplete task in blockquote
>   > - [x] Nested completed task
>   > - [ ] Nested incomplete task

## Tables in Lists

1. First item
   
   | Header 1 | Header 2 |
   |----------|----------|
   | Cell 1   | Cell 2   |
   
2. Second item
   > Table in blockquote in list:
   > 
   > | Col A | Col B |
   > |-------|-------|
   > | A1    | B1    |
"""

private let specialCharacters = """
# Special Characters & Escaping

## Literal Characters

\\*not italic\\* and \\*\\*not bold\\*\\*

\\[not a link\\](not-a-url)

\\# Not a heading

\\> Not a blockquote

\\- Not a list item

\\`not code\\`

\\~\\~not strikethrough\\~\\~

## HTML Entities

&lt;not a tag&gt;

&amp; &copy; &trade; &reg; &nbsp; &mdash; &ndash;

&quot;quoted&quot; and &apos;apostrophe&apos;

## Special Markdown Characters

Asterisks: * ** ***

Underscores: _ __ ___

Backticks: ` `` ``` ```` \\`\\`\\`\\`\\`

Tildes: ~ ~~ ~~~

Brackets: [] [[]] [[[text]]]

Parentheses: () (()) (((text)))

Angle brackets: <> <<>> <text>

## Edge Case Combinations

**bold *and italic* together**

***all bold and italic***

**bold with `code` inside**

*italic with `code` inside*

~~strikethrough with **bold** and *italic*~~

[link with **bold** and *italic*](https://example.com)

## Backslashes

\\\\ (backslash)

\\n (not a newline)

\\t (not a tab)

Line\\
Break\\
Test
"""

private let mixedLanguages = """
# Mixed Languages & Scripts

## English
Hello, World! This is English text.

## Arabic (RTL)
مرحبا بالعالم! هذا نص عربي.

## Hebrew (RTL)
שלום עולם! זהו טקסט עברי.

## Chinese
你好，世界！这是中文文本。

## Japanese
こんにちは、世界！これは日本語のテキストです。

## Korean
안녕하세요, 세계! 이것은 한국어 텍스트입니다.

## Russian
Привет, мир! Это русский текст.

## Greek
Γεια σου κόσμε! Αυτό είναι ελληνικό κείμενο.

## Mixed Direction

This is English مع عربي and עברית together 中文 も あります.

**Bold عربي** and *italic עברית* and `code 中文`

## In Lists

1. English item
2. عنصر عربي
3. פריט עברי
4. 中文项目
5. 日本語の項目

## In Tables

| Language | Text | Direction |
|----------|------|-----------|
| English | Hello | LTR |
| Arabic | مرحبا | RTL |
| Hebrew | שלום | RTL |
| Chinese | 你好 | LTR |
| Japanese | こんにちは | LTR |
"""

private let malformedMarkdown = """
# Malformed Markdown Tests

## Unclosed Elements

**This is bold but never closes

*This is italic but never closes

[This is a link but never closes

`This is code but never closes

## Mismatched Elements

**bold with *italic** mismatch*

__underscore with *asterisk__ mismatch*

## Invalid Structures

### List without proper spacing
-item 1
-item 2
-item 3

### Header without space
#No space after hash
##Two hashes no space
###Three hashes no space

## Broken Tables

| Header 1 | Header 2 | Header 3
|----------|-------
| Cell 1 | Cell 2 | Cell 3 |
| Cell 4 | Cell 5
Cell 6 | Cell 7 | Cell 8

## Mixed Fence Types

```swift
func example() {
    print("Start with backticks")
~~~
    print("End with tildes?")
}
```

## Broken Links and Images

[Broken link](
[Another broken](https://
![Broken image](
![Another broken image](https://

## Incomplete Code Blocks

```
This code block has no language

```javascript
This code block never closes...

## Invalid Task Lists

- [] Missing x
- [X] Capital X
- [ x ] Spaces around x
- [?] Invalid character
-[] No space after dash
"""

private let performanceStress: String = {
    var result = """
# Performance Stress Test

## Massive Paragraph

"""
    
    // Add repeated paragraph
    result += String(repeating: "This is a very long paragraph that repeats many times to test performance. ", count: 100)
    
    result += """


## Many List Items

"""
    
    // Add list items
    for i in 1...100 {
        result += "- List item #\(i) with some **bold** and *italic* text\n"
    }
    
    result += """

## Many Headers

"""
    
    // Add headers
    for i in 1...50 {
        result += "### Header \(i)\n\nParagraph under header \(i).\n\n"
    }
    
    result += """
## Large Table

| Column 1 | Column 2 | Column 3 | Column 4 | Column 5 |
|----------|----------|----------|----------|----------|

"""
    
    // Add table rows
    for row in 1...50 {
        result += "| Cell \(row)A | Cell \(row)B | Cell \(row)C | Cell \(row)D | Cell \(row)E |\n"
    }
    
    result += """

## Many Code Blocks

"""
    
    // Add code blocks
    for i in 1...20 {
        result += """

```swift
func function\(i)() {
    print("Function #\(i)")
    // Some more code here
    let value = \(i) * 2
    return value
}
```

"""
    }
    
    return result
}()

private let unicodeAndEmoji = """
# Unicode & Emoji Tests

## Emoji Variety

😀 😃 😄 😁 😆 😅 🤣 😂 🙂 🙃 😉 😊 😇

🥰 😍 🤩 😘 😗 😚 😙 😋 😛 😜 🤪 😝

🤑 🤗 🤭 🤫 🤔 🤐 🤨 😐 😑 😶 😏 😒

## GitHub Emoji Codes

:rocket: :heart: :fire: :star: :tada: :100: :+1: :-1:

:octocat: :shipit: :trollface: :suspect: :hurtrealbad:

## Unicode Symbols

✓ ✗ ★ ☆ ♠ ♣ ♥ ♦ ♪ ♫ ☀ ☁ ☂ ☃ ☄ ⚡ ❄ 

← → ↑ ↓ ⇐ ⇒ ⇑ ⇓ ⇠ ⇢ ⇡ ⇣

½ ⅓ ¼ ⅛ ⅔ ⅖ ¾ ⅗ ⅜ ⅘ ⅚ ⅝ ⅞

## Mathematical Symbols

∞ ∑ ∏ ∫ √ ≈ ≠ ≤ ≥ ± × ÷ ∝ ∈ ∉ ⊂ ⊃ ∩ ∪

## Box Drawing

┌─────────┐
│ Box     │
├─────────┤
│ Content │
└─────────┘

## Combining Characters

a̐ e̋ i̍ o̎ ủ a̅ e̅ i̅ o̅ u̅

## Zero-Width Characters

Zero​Width​Space: "​"
Zero‌Width‌Non‌Joiner: "‌"
Zero‍Width‍Joiner: "‍"

## In Markdown Elements

**Bold 😀 emoji** and *italic 🎉 emoji* and `code ✓ symbol`

- List with 🚀 emoji
- Another with ☀️ sun
- And ⭐ star

| Emoji | Name |
|-------|------|
| 😀 | Smile |
| ❤️ | Heart |
| 🚀 | Rocket |
"""

private let codeBlockEdgeCases = """
# Code Block Edge Cases

## Empty Code Block

```
```

## Code Block with Only Whitespace

```
    
    
```

## Very Long Line

```swift
let veryLongLine = "This is an extremely long line of code that should test horizontal scrolling capabilities when rendered in a code block. It contains many words and continues for quite a while to ensure that it exceeds typical viewport widths on most devices."
```

## Nested Fence Markers

```markdown
This is a code block that contains fence markers:
```
Nested code block?
```
Still in the original block
```

## Special Characters in Code

```swift
let special = "<>&\\"'`~!@#$%^&*()_+-=[]{}|;:,.<>?"
let unicode = "😀 🎉 ✓ ✗ α β γ δ"
let escaped = "\\n\\t\\r\\\\\\"
```

## Multiple Languages

```swift
// Swift code
struct Example {
    var name: String
}
```

```python
# Python code
def example():
    return "Hello"
```

```javascript
// JavaScript code
const example = () => {
    return "Hello";
};
```

## Code with Markdown-like Content

```
**This looks like bold** but it's in a code block
*This looks like italic* but it's in a code block
[This looks like a link](but-its-not)
# This looks like a header but it's not
```

## Inline Code Edge Cases

Regular `code`, empty ``, just backticks `, double ``code``, triple ```code```

Inline `code with **markdown** inside` should not parse

Multiple `backticks` in `the` same `line` with `various` content

## Language Not Supported

```unknownlanguage
This language doesn't exist
But it should still render as code
```
"""

private let linkEdgeCases = """
# Link Edge Cases

## Various URL Formats

[HTTP Link](http://example.com)
[HTTPS Link](https://example.com)
[FTP Link](ftp://example.com)
[Mailto Link](mailto:user@example.com)
[Tel Link](tel:+1234567890)
[File Link](file:///path/to/file)

## Special Characters in URLs

[Link with spaces](https://example.com/path with spaces)
[Link with unicode](https://example.com/路径/文件)
[Link with parameters](https://example.com?foo=bar&baz=qux)
[Link with fragment](https://example.com#section)
[Link with everything](https://example.com/path?query=1#fragment)

## Nested Markdown in Links

[Link with **bold**](https://example.com)
[Link with *italic*](https://example.com)
[Link with `code`](https://example.com)
[Link with ~~strikethrough~~](https://example.com)

## Reference Links

[Reference link][1]
[Another reference][2]
[Link with space in reference][ref with space]
[Case insensitive][REF]

[1]: https://example1.com
[2]: https://example2.com "With title"
[ref with space]: https://example3.com
[ref]: https://example4.com

## Autolinks

<https://example.com>
<http://example.com>
<mailto:user@example.com>
<ftp://files.example.com>

## Bare URLs

https://example.com
http://example.com
www.example.com
example.com

## Edge Cases

[Empty link]()
[Link with no URL]( )
[](https://example.com)
[]()

[Broken link](https://
[Another broken](
[Incomplete](https://example.com

## Images

![Image](https://example.com/image.png)
![Image with title](https://example.com/image.png "Title")
![](https://example.com/image.png)
![Broken image](
![Empty]()

## Mixed with Other Elements

**[Bold link](https://example.com)**
*[Italic link](https://example.com)*
~~[Strikethrough link](https://example.com)~~

> [Link in blockquote](https://example.com)

- [Link in list](https://example.com)

| [Link in table](https://example.com) |
|---------------------------------------|
| Cell content |
"""

private let tableEdgeCases = """
# Table Edge Cases

## Minimal Table

| A |
|---|
| 1 |

## No Header Separator

| Header 1 | Header 2 |
| Cell 1 | Cell 2 |

## Inconsistent Columns

| Col 1 | Col 2 | Col 3 |
|-------|-------|
| A | B | C | D | E |
| 1 | 2 |
| X |

## Various Alignments

| Left | Center | Right | Default |
|:-----|:------:|------:|---------|
| L1 | C1 | R1 | D1 |
| Left aligned | Center aligned | Right aligned | Default |

## Empty Cells

| Header 1 | Header 2 | Header 3 |
|----------|----------|----------|
| | Empty | |
| Data | | Data |
| | | |

## Special Characters in Tables

| Special | Characters |
|---------|------------|
| & | Ampersand |
| < > | Brackets |
| \\| | Pipe |
| \\` | Backtick |
| * | Asterisk |

## Markdown in Tables

| Format | Example |
|--------|---------|
| **Bold** | **Text** |
| *Italic* | *Text* |
| `Code` | `code` |
| [Link](url) | [Click](https://example.com) |
| ~~Strike~~ | ~~Text~~ |

## Large Table Content

| Very Long Header That Should Wrap | Another Long Header | Short |
|------------------------------------|---------------------|-------|
| This is a very long cell content that should test how tables handle wrapping and overflow when the content exceeds normal bounds | More content here | OK |

## Nested Tables (Not Supported)

| Outer | Table |
|-------|-------|
| | Inner | Table | |
| | ----- | ----- | |
| | A | B | |

## Table with Code

| Language | Code |
|----------|------|
| Swift | `let x = 5` |
| Python | `x = 5` |
| JavaScript | `const x = 5` |
"""

private let emptyAndWhitespace = """
# Empty & Whitespace Tests

## Empty Elements

### Empty Header

**​** (empty bold)

*​* (empty italic)

`​` (empty code)

[​](https://example.com) (empty link text)

![​](https://example.com/image.png) (empty alt text)

## Whitespace Only

###    

**    **

*    *

`    `

## Multiple Blank Lines




(Multiple blank lines above)

## Trailing Spaces

This line has trailing spaces    
This line has trailing tabs		
This line has no trailing whitespace

## Leading Whitespace

    Indented with spaces
	Indented with tab
		Indented with two tabs
    	Mixed spaces and tabs

## Zero-Width Spaces

Normal​text​with​zero​width​spaces

## Line Breaks

Hard break with two spaces  
Next line

Hard break with backslash\\
Next line

Soft break
Next line

## Unicode Whitespace

Em space: " "
En space: " "
Thin space: " "
Hair space: " "
Zero-width space: "​"
Non-breaking space: " "

## Empty Lists

- 
- 
- 

1. 
2. 
3. 

## Empty Table Cells

|   |   |   |
|---|---|---|
|   |   |   |
|   |   |   |
"""

#Preview {
    NavigationStack {
        EdgeCasesDemo()
    }
}
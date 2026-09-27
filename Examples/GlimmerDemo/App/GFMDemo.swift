import SwiftUI
import Glimmer

struct GFMDemo: View {
    @State private var selectedTab = 0
    
    private let tabs = [
        "Overview",
        "Autolinks",
        "References",
        "Tables",
        "Task Lists",
        "Strikethrough",
        "Emoji",
        "Code Blocks",
        "Line Breaks",
        "Disallowed HTML"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                        Button(action: { selectedTab = index }) {
                            Text(tab)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedTab == index ? Color.accentColor : Color.gray.opacity(0.2))
                                .foregroundColor(selectedTab == index ? .white : .primary)
                                .cornerRadius(15)
                        }
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Content
            ScrollView {
                MarkdownView(
                    markdown: getContent(for: selectedTab),
                    configuration: .github,
                    onLinkTap: { url in
                        print("🔗 Link tapped: \(url)")
                    },
                    onMentionTap: { username in
                        print("👤 Mention tapped: @\(username)")
                    },
                    onIssueTap: { issue in
                        print("🔢 Issue tapped: #\(issue)")
                    }
                )
                .padding()
            }
        }
        .navigationTitle("GitHub Flavored Markdown")
    }
    
    func getContent(for index: Int) -> String {
        switch index {
        case 0: return gfmOverview
        case 1: return gfmAutolinks
        case 2: return gfmReferences
        case 3: return gfmTables
        case 4: return gfmTaskLists
        case 5: return gfmStrikethrough
        case 6: return gfmEmoji
        case 7: return gfmCodeBlocks
        case 8: return gfmLineBreaks
        case 9: return gfmDisallowedHTML
        default: return gfmOverview
        }
    }
}

// MARK: - GFM Content

private let gfmOverview = """
# GitHub Flavored Markdown (GFM)

GitHub Flavored Markdown is a dialect of Markdown that GitHub uses across its platform. It extends standard Markdown with several GitHub-specific features.

## Key Extensions

### 1. Tables
Create tables with pipes and hyphens:

| Feature | Supported | Notes |
|---------|-----------|-------|
| Tables | ✅ | With alignment |
| Task Lists | ✅ | Interactive |
| Strikethrough | ✅ | ~~Like this~~ |
| Autolinks | ✅ | URLs and mentions |
| Emoji | ✅ | :rocket: :tada: |

### 2. Task Lists
Track progress with checkboxes:
- [x] Implement GFM parser
- [x] Add table support
- [ ] Add more themes
- [ ] Write documentation

### 3. Strikethrough
Cross out text with ~~double tildes~~.

### 4. Autolinks
- URLs: https://github.com
- Mentions: @octocat
- Issues: #123
- Commits: a5c3785ed8d6a35868bc169f07e40e889087fd2e

### 5. Emoji
Use emoji codes like :smile: :heart: :rocket:

### 6. Syntax Highlighting
```python
def hello_gfm():
    print("Hello, GitHub Flavored Markdown!")
    return {"supported": True, "awesome": True}
```

### 7. Line Breaks
Hard line breaks with two spaces at the end of a line  
or with a backslash\\
at the end.

## Why GFM?

GitHub Flavored Markdown was created to address common needs on GitHub:
- **Tables** for comparing data
- **Task lists** for tracking progress
- **Strikethrough** for showing changes
- **Autolinks** for easy navigation
- **Emoji** for expressiveness
- **Enhanced code blocks** with syntax highlighting

All these features make documentation more interactive and useful for developers.
"""

private let gfmAutolinks = """
# GFM Autolinks

GitHub automatically links certain patterns without requiring explicit link syntax.

## URL Autolinks

### Standard URLs
These URLs are automatically linked:
- https://github.com
- http://example.com
- https://docs.github.com/en/get-started

### Extended Autolinks (GitHub-specific)
Even without angle brackets:
- www.github.com
- www.example.com

### FTP and Other Protocols
- ftp://ftp.example.com
- ftps://secure.example.com

## Email Autolinks

### With Angle Brackets (Standard)
<user@example.com>
<support@github.com>

### Without Angle Brackets (Not autolinked in GFM)
user@example.com - This won't be autolinked
support@github.com - Neither will this

## GitHub-Specific Autolinks

### User Mentions
- @octocat - Links to user profile
- @github - Links to organization
- @torvalds - Links to user profile

### Issue and PR References
- #42 - Links to issue/PR in current repo
- #1337 - Another issue reference
- GH-99 - Alternative format

### Repository References
- facebook/react - Links to repository
- microsoft/vscode - Another repository
- apple/swift - Repository reference

### Cross-Repository Issues
- facebook/react#16 - Issue in another repo
- microsoft/vscode#1234 - Cross-repo PR
- nodejs/node#39987 - Specific issue

### Commit SHAs
Full SHA: a5c3785ed8d6a35868bc169f07e40e889087fd2e
Short SHA: a5c3785
Another: deadbeef

### Compare View
- master...feature-branch
- v1.0.0...v2.0.0
- main@{1day}...main

## Autolink Suppression

Prevent autolinks with backslashes:
- \\https://github.com - Not linked
- \\@octocat - Not a mention
- \\#123 - Not an issue

Or use code spans:
- `https://github.com` - Not linked
- `@octocat` - Not a mention
- `#123` - Not an issue

## Combined Examples

Check out @octocat's work on microsoft/vscode#1234, especially commit a5c3785 which fixes the issue described at https://github.com/microsoft/vscode/issues/1234.

The PR facebook/react#16 by @gaearon introduced hooks. See the comparison at https://github.com/facebook/react/compare/15.0.0...16.0.0
"""

private let gfmReferences = """
# GFM References & Links

## Issue References

### In Current Repository
- Basic: #1
- Multiple digits: #1234
- With text: See issue #42 for details
- In lists:
  - Fix #101
  - Close #102
  - Resolve #103

### Keywords with Issues
These keywords create special relationships:
- Fixes #1
- Fixed #2
- Fix #3
- Closes #4
- Closed #5
- Close #6
- Resolves #7
- Resolved #8
- Resolve #9

### Cross-Repository Issues
- apple/swift#1988
- rust-lang/rust#12345
- python/cpython#98765

## Pull Request References

Pull requests use the same syntax as issues:
- PR #99
- Merge #100
- Review #101

Cross-repository PRs:
- facebook/react#16000
- microsoft/typescript#40000

## Commit References

### Full SHA (40 characters)
- a5c3785ed8d6a35868bc169f07e40e889087fd2e
- 4c3ff5e5b3c3f3e3c3f3e3c3f3e3c3f3e3c3f3e3

### Short SHA (7+ characters)
- a5c3785
- 4c3ff5e
- deadbeef

### With Repository
- facebook/react@a5c3785ed8d6a35868bc169f07e40e889087fd2e
- torvalds/linux@deadbeef

## User and Team Mentions

### User Mentions
- @octocat
- @defunkt
- @mojombo
- @torvalds

### Team Mentions (in organizations)
- @github/security
- @facebook/react-core
- @microsoft/vscode-team

### Mention Suppression
Not mentions: \\@octocat, email@example.com

## Repository References

### Basic Repository Links
- facebook/react
- microsoft/vscode
- apple/swift
- rust-lang/rust

### With Paths
- facebook/react/blob/main/README.md
- microsoft/vscode/tree/master/src
- apple/swift/issues
- rust-lang/rust/pulls

## Compare & Diff Links

### Branch Comparison
- master...feature-branch
- main...develop
- v1.0...v2.0

### Tag Comparison
- v1.0.0...v2.0.0
- release-1...release-2

### Time-based Comparison
- master@{1day}...master
- main@{2021-01-01}...main@{2021-12-31}
- develop@{1week}...develop

## Combined References

Here's a complex example combining multiple reference types:

As @octocat mentioned in facebook/react#16, the new hooks API (introduced in commit a5c3785) solves the issues described in #101, #102, and #103. 

You can see the full diff at react@15.0.0...16.0.0. The @facebook/react-core team did amazing work!

The implementation in microsoft/vscode#50000 by @bpasero follows a similar pattern to what @torvalds suggested in torvalds/linux@deadbeef.
"""

private let gfmTables = """
# GFM Tables

Tables are one of the most requested features that GFM adds to standard Markdown.

## Basic Table

| Header 1 | Header 2 | Header 3 |
|----------|----------|----------|
| Cell 1   | Cell 2   | Cell 3   |
| Cell 4   | Cell 5   | Cell 6   |

## Column Alignment

### Left, Center, Right Aligned

| Left Aligned | Center Aligned | Right Aligned |
|:-------------|:--------------:|--------------:|
| Left         | Center         | Right         |
| This         | Is             | Aligned       |
| Accordingly  | In Each        | Column        |

### Default Alignment (Left)

| Default | Also Default |
|---------|--------------|
| Left    | Left         |
| Aligned | By Default   |

## Inline Formatting in Tables

| **Bold** | *Italic* | ~~Strikethrough~~ | `Code` |
|----------|----------|-------------------|--------|
| **Yes**  | *Yes*    | ~~Yes~~           | `Yes`  |
| Works    | In       | Tables            | Too    |

## Links and References in Tables

| Type | Example | Result |
|------|---------|--------|
| Link | [GitHub](https://github.com) | Clickable |
| Mention | @octocat | Interactive |
| Issue | #123 | Reference |
| Emoji | :rocket: | 🚀 |

## Complex Table Example

| Language | Stars | Forks | Issues | Pull Requests | Contributors |
|----------|------:|------:|-------:|--------------:|-------------:|
| [React](https://github.com/facebook/react) | 200k+ | 40k+ | 1,000+ | 300+ | 1,500+ |
| [Vue](https://github.com/vuejs/vue) | 190k+ | 30k+ | 500+ | 100+ | 400+ |
| [Angular](https://github.com/angular/angular) | 85k+ | 22k+ | 3,000+ | 500+ | 600+ |
| [Svelte](https://github.com/sveltejs/svelte) | 65k+ | 3k+ | 800+ | 200+ | 300+ |

## Escaped Pipes in Tables

| Column 1 | Column 2 | Column 3 |
|----------|----------|----------|
| Use \\| to | escape | pipes |
| Like \\| this | works | fine |

## Empty Cells

| Some | Cells | Are | Empty |
|------|-------|-----|-------|
| This |       | is  |       |
|      | OK    |     | Too   |
|      |       |     |       |

## Wide Content in Tables

| Short | Very Long Content That Might Wrap |
|-------|-----------------------------------|
| A | This is a very long piece of text that might cause the table cell to wrap depending on the rendering width |
| B | Another long text: Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt |

## Nested Tables (Not Supported)

Tables cannot be nested, but you can describe table-like data:

| Category | Description |
|----------|-------------|
| Nested | • Item 1<br>• Item 2<br>• Item 3 |
| Lists | • First<br>• Second<br>• Third |

## Table Without Header Separator (Invalid)

This is not a valid table:
| Header 1 | Header 2 |
| Cell 1 | Cell 2 |

## Minimum Valid Table

| A |
|---|
| 1 |

## Maximum Columns Example

| A | B | C | D | E | F | G | H | I | J |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
"""

private let gfmTaskLists = """
# GFM Task Lists

Task lists are lists with checkboxes that can track progress on issues and pull requests.

## Basic Task Lists

### Unchecked Tasks
- [ ] This is an unchecked task
- [ ] Another task to complete
- [ ] Third pending task

### Checked Tasks
- [x] This task is complete
- [x] Another completed task
- [x] All done with this one

### Mixed Status
- [x] Setup development environment
- [x] Write initial code
- [ ] Write tests
- [ ] Update documentation
- [ ] Create pull request

## Nested Task Lists

- [x] Phase 1: Planning
  - [x] Define requirements
  - [x] Create mockups
  - [x] Get approval
- [ ] Phase 2: Implementation
  - [x] Set up project
  - [ ] Implement features
    - [x] Feature A
    - [ ] Feature B
    - [ ] Feature C
  - [ ] Write tests
- [ ] Phase 3: Deployment
  - [ ] Code review
  - [ ] Testing
  - [ ] Release

## Task Lists in Different Contexts

### In Numbered Lists
1. [x] First task
2. [ ] Second task
3. [ ] Third task
   1. [ ] Subtask 3.1
   2. [x] Subtask 3.2

### In Blockquotes
> - [x] Task in a quote
> - [ ] Another quoted task
> - [ ] Third task
>   > - [ ] Nested quote task
>   > - [x] Completed nested task

### In Lists with Other Content
- [x] **Bold task**
- [ ] *Italic task*
- [ ] Task with `code`
- [x] Task with [link](https://github.com)
- [ ] Task with @mention
- [x] Task with #123 issue reference
- [ ] Task with :rocket: emoji

## Real-World Examples

### Feature Development
- [x] Research and planning
- [x] Create feature branch
- [x] Implement core functionality
- [ ] Add error handling
- [ ] Write unit tests
- [ ] Write integration tests
- [ ] Update documentation
- [ ] Create PR
- [ ] Code review
- [ ] Merge to main

### Bug Fix Checklist
- [x] Reproduce the bug
- [x] Identify root cause
- [x] Write failing test
- [x] Implement fix
- [x] Verify test passes
- [ ] Test edge cases
- [ ] Update changelog
- [ ] Request review

### Release Checklist
- [ ] All tests passing
- [ ] Documentation updated
- [ ] Changelog updated
- [ ] Version bumped
- [ ] Tag created
- [ ] Release notes written
- [ ] Package published
- [ ] Announcement sent

## Invalid Task List Syntax

These won't render as task lists:
- [] Missing space after brackets
- [ ] Extra space: [ x ]
- [X] Capital X
- [?] Invalid character
- [-] Different character
-[ ] No space after dash

## Task Lists with Long Content

- [x] This is a very long task description that might wrap to multiple lines depending on the width of the rendering container, but it should still display correctly with the checkbox at the beginning
- [ ] Another long task: Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua

## Accessibility Note

Task lists in GitHub Issues and Pull Requests are interactive - you can check/uncheck them directly. In this demo, they're display-only but still convey the visual state of completion.
"""

private let gfmStrikethrough = """
# GFM Strikethrough

Strikethrough text is created using double tildes (`~~`).

## Basic Strikethrough

This is ~~deleted text~~ that has been struck through.

You can ~~cross out~~ any text you want.

## Strikethrough with Other Formatting

### Combined with Bold
- **~~Bold and strikethrough~~**
- ~~**Strikethrough and bold**~~
- **This is ~~partially~~ bold**

### Combined with Italic
- *~~Italic and strikethrough~~*
- ~~*Strikethrough and italic*~~
- *This is ~~partially~~ italic*

### Combined with Both
- ***~~Bold, italic, and strikethrough~~***
- ~~***All three formats***~~

### With Code
- ~~`strikethrough code`~~
- `~~not struck in code~~` (tildes are literal)

### With Links
- ~~[Struck link](https://github.com)~~
- [Link with ~~struck~~ text](https://github.com)

## Use Cases

### Showing Changes
Original: ~~MongoDB~~ → Updated: PostgreSQL

Before: ~~React Class Components~~ → After: React Hooks

### Deprecation Notices
- ~~`oldFunction()`~~ - Deprecated, use `newFunction()` instead
- ~~Version 1.x API~~ - No longer supported
- ~~Legacy endpoint~~ - Removed in v2.0

### Todo Lists with Strikethrough
- ~~Write tests~~ ✓ Done
- ~~Fix bug #123~~ ✓ Fixed
- ~~Update documentation~~ ✓ Completed
- Implement new feature (in progress)

### Corrections
I think the meeting is at ~~2:00 PM~~ 3:00 PM.

The price is ~~$99~~ $79 (on sale!).

### Humor and Emphasis
This is ~~totally not~~ definitely the best feature.

I ~~hate~~ love writing documentation!

## Edge Cases

### Multiple Tildes
~~~This needs three or more tildes~~~
~~~~Four tildes~~~~

### Incomplete Strikethrough
~~This is not closed properly

This is not opened properly~~

### Escaped Strikethrough
\\~~This is not struck through\\~~

### Strikethrough Across Lines
~~This strikethrough
spans multiple
lines~~

### In Lists
- ~~First item~~ (completed)
- ~~Second item~~ (completed)
- Third item (pending)
  - ~~Subtask 1~~ (done)
  - Subtask 2 (todo)

### In Tables

| Status | Task | Notes |
|--------|------|-------|
| Done | ~~Setup~~ | Completed |
| Done | ~~Testing~~ | Finished |
| Active | Development | In progress |
| Pending | ~~Review~~ → Deployment | Next step |

### In Blockquotes
> ~~This is struck text in a quote~~
> 
> Someone said: "~~Never~~ Always write tests!"

### In Code Blocks
```
// Tildes in code blocks are literal
// ~~This is not struck~~
function ~~notStruck~~() {
    return "~~still not struck~~";
}
```

## Common Mistakes

1. Single tildes don't work: ~not struck~
2. Spaces break it: ~ ~not struck~ ~
3. Must be doubled: ~~correct~~ vs ~incorrect~

## Nested Strikethrough (Not Recommended)

While technically possible, avoid:
~~This has ~~nested~~ strikethrough~~ (confusing)

## Accessibility Consideration

Strikethrough text can be harder to read for some users. Consider providing context or alternatives when using it extensively.
"""

private let gfmEmoji = """
# GFM Emoji Support 🎉

GitHub supports emoji shortcodes that get converted to Unicode emoji or images.

## Common Emoji

### Smileys & Emotion
:smile: :laughing: :blush: :heart_eyes: :smiling_face_with_three_hearts:
:grin: :wink: :thinking: :neutral_face: :expressionless:
:confused: :upside_down_face: :money_mouth_face: :astonished: :frowning:
:sob: :cry: :tired_face: :yawning_face: :sleeping:

### Gestures & Body
:+1: :-1: :ok_hand: :wave: :clap:
:raised_hands: :pray: :handshake: :muscle: :point_up:
:point_down: :point_left: :point_right: :middle_finger: :crossed_fingers:

### Hearts & Love
:heart: :orange_heart: :yellow_heart: :green_heart: :blue_heart:
:purple_heart: :black_heart: :broken_heart: :two_hearts: :sparkling_heart:
:heartpulse: :heartbeat: :revolving_hearts: :cupid: :gift_heart:

### Development & Tech
:rocket: :computer: :keyboard: :desktop_computer: :printer:
:mouse: :trackball: :joystick: :dvd: :cd:
:floppy_disk: :iphone: :phone: :telephone: :pager:

### GitHub Special
:octocat: :atom: :electron: :github:
:shipit: (Squirrel)

### Status & Feedback
:white_check_mark: :heavy_check_mark: :x: :negative_squared_cross_mark: :o:
:warning: :no_entry: :ok: :sos: :bangbang:
:interrobang: :question: :exclamation: :100: :boom:

### Awards & Celebration
:1st_place_medal: :2nd_place_medal: :3rd_place_medal: :medal_sports: :trophy:
:tada: :confetti_ball: :partying_face: :champagne: :birthday:

### Nature & Animals
:dog: :cat: :mouse: :hamster: :rabbit:
:fox_face: :bear: :panda_face: :penguin: :bird:
:monkey: :see_no_evil: :hear_no_evil: :speak_no_evil: :dragon:

### Food & Drink
:apple: :pear: :orange: :lemon: :banana:
:watermelon: :grapes: :strawberry: :melon: :cherries:
:pizza: :hamburger: :fries: :hotdog: :taco:
:coffee: :tea: :beer: :wine_glass: :cocktail:

### Travel & Places
:car: :taxi: :bus: :train: :airplane:
:rocket: :ship: :anchor: :construction: :fuel_pump:
:house: :house_with_garden: :office: :hospital: :school:

### Weather & Time
:sunny: :cloud: :partly_sunny: :cloud_with_rain: :cloud_with_lightning_and_rain:
:snowflake: :snowman: :wind_face: :fog: :rainbow:
:alarm_clock: :stopwatch: :timer_clock: :hourglass: :watch:

## Using Emoji in Context

### In Headers
# :rocket: Launch Plan
## :bug: Bug Fixes
### :sparkles: New Features

### In Lists
- :white_check_mark: Completed task
- :x: Failed test
- :construction: Work in progress
- :warning: Needs attention
- :zap: Performance improvement

### In Tables
| Status | Icon | Description |
|--------|------|-------------|
| Success | :white_check_mark: | All tests passing |
| Warning | :warning: | Needs review |
| Error | :x: | Failed to compile |
| In Progress | :construction: | Currently working |

### Commit Message Examples
- :bug: Fix: Resolve null pointer exception
- :sparkles: Feature: Add dark mode support
- :zap: Perf: Optimize database queries
- :memo: Docs: Update README
- :art: Style: Format code with prettier
- :fire: Remove: Delete deprecated methods
- :rocket: Deploy: Version 2.0.0
- :white_check_mark: Test: Add unit tests
- :lock: Security: Fix XSS vulnerability
- :arrow_up: Upgrade: Update dependencies

### PR/Issue Labels
- :bug: `bug` - Something isn't working
- :sparkles: `enhancement` - New feature
- :memo: `documentation` - Documentation only
- :question: `question` - Further information requested
- :+1: `good first issue` - Good for newcomers

## Custom GitHub Emoji

Some emoji are special to GitHub:
- :octocat: - GitHub's mascot
- :shipit: - Ship It Squirrel
- :trollface: - Classic meme
- :suspect: - Suspicious face
- :hurtrealbad: - Hurt real bad

## Emoji in Code Comments

```javascript
// :warning: This is deprecated
function oldFunction() {
    // :bug: Known issue here
    return null; // :boom: This might explode
}

// :sparkles: New improved version
function newFunction() {
    // :white_check_mark: All good!
    return true;
}
```

## Accessibility Note

While emoji add visual appeal, always ensure your content is understandable without them. Use them to enhance, not replace, clear communication.

## Fun Combinations

:robot: + :heart: = :purple_heart: AI Love
:coffee: + :computer: = :zap: Productivity
:bug: + :fire: = :boom: Critical Issue
:rocket: + :moon: = :stars: To the Moon!

## Seasonal Emoji

### Holidays
:christmas_tree: :santa: :gift: (Christmas)
:jack_o_lantern: :ghost: :candy: (Halloween)
:hearts: :cupid: :chocolate_bar: (Valentine's)
:rabbit: :egg: :tulip: (Easter)

### Seasons
:sunny: :sunflower: :ice_cream: (Summer)
:fallen_leaf: :maple_leaf: :corn: (Autumn)
:snowflake: :snowman: :ski: (Winter)
:cherry_blossom: :tulip: :seedling: (Spring)

## Pro Tip

You can search for emoji codes at:
- https://emojipedia.org
- https://github.com/ikatyang/emoji-cheat-sheet
- Use `:` in GitHub to trigger emoji autocomplete
"""

private let gfmCodeBlocks = """
# GFM Code Blocks & Syntax Highlighting

GitHub Flavored Markdown provides enhanced code blocks with syntax highlighting for 100+ languages.

## Fenced Code Blocks

### Basic Code Block
```
This is a basic code block
without any syntax highlighting
```

### With Language Specification
```javascript
// JavaScript with syntax highlighting
function greet(name) {
    console.log(`Hello, ${name}!`);
    return true;
}
```

## Supported Languages

### Web Technologies

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>GFM Demo</title>
</head>
<body>
    <h1>Hello, World!</h1>
    <p class="intro">Welcome to GFM</p>
</body>
</html>
```

```css
/* CSS Styling */
.container {
    display: flex;
    justify-content: center;
    align-items: center;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
}

@media (max-width: 768px) {
    .container {
        flex-direction: column;
    }
}
```

```typescript
// TypeScript with types
interface User {
    id: number;
    name: string;
    email?: string;
}

class UserService {
    async getUser(id: number): Promise<User> {
        const response = await fetch(`/api/users/${id}`);
        return response.json();
    }
}
```

### Systems Programming

```rust
// Rust example
#[derive(Debug)]
struct Point {
    x: f64,
    y: f64,
}

impl Point {
    fn distance(&self, other: &Point) -> f64 {
        ((self.x - other.x).powi(2) + (self.y - other.y).powi(2)).sqrt()
    }
}

fn main() {
    let p1 = Point { x: 0.0, y: 0.0 };
    let p2 = Point { x: 3.0, y: 4.0 };
    println!("Distance: {}", p1.distance(&p2));
}
```

```go
// Go example
package main

import (
    "fmt"
    "net/http"
)

func handler(w http.ResponseWriter, r *http.Request) {
    fmt.Fprintf(w, "Hello, GFM!")
}

func main() {
    http.HandleFunc("/", handler)
    fmt.Println("Server starting on :8080")
    http.ListenAndServe(":8080", nil)
}
```

```swift
// Swift example
struct ContentView: View {
    @State private var count = 0
    
    var body: some View {
        VStack {
            Text("Count: \\(count)")
                .font(.largeTitle)
            
            Button("Increment") {
                count += 1
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
```

### Data & Config

```json
{
    "name": "glimmer",
    "version": "1.0.0",
    "description": "GFM parser for SwiftUI",
    "features": {
        "tables": true,
        "taskLists": true,
        "emoji": true,
        "syntaxHighlighting": {
            "enabled": true,
            "languages": ["swift", "javascript", "python", "rust"]
        }
    }
}
```

```yaml
# YAML Configuration
name: glimmer
version: 1.0.0
description: GFM parser for SwiftUI

features:
  - tables
  - task_lists
  - emoji
  - syntax_highlighting

languages:
  supported:
    - swift
    - javascript
    - python
    - rust
    - go
```

```toml
# TOML Configuration
[package]
name = "glimmer"
version = "1.0.0"
description = "GFM parser for SwiftUI"

[features]
tables = true
task_lists = true
emoji = true

[languages]
supported = ["swift", "javascript", "python", "rust", "go"]
```

### Shell & Scripts

```bash
#!/bin/bash
# Bash script example

echo "Setting up Glimmer..."

# Check if Swift is installed
if command -v swift &> /dev/null; then
    echo "✓ Swift is installed"
    swift --version
else
    echo "✗ Swift is not installed"
    exit 1
fi

# Build the project
echo "Building project..."
swift build --configuration release

# Run tests
echo "Running tests..."
swift test

echo "Setup complete! 🎉"
```

```python
# Python example
import asyncio
from typing import List, Optional

class MarkdownParser:
    \"\"\"A simple markdown parser example.\"\"\"
    
    def __init__(self, content: str):
        self.content = content
        self.blocks: List[str] = []
    
    async def parse(self) -> List[str]:
        \"\"\"Parse markdown content asynchronously.\"\"\"
        lines = self.content.split('\\n')
        
        for line in lines:
            if line.startswith('#'):
                self.blocks.append(f"Header: {line}")
            elif line.startswith('-'):
                self.blocks.append(f"List: {line}")
            else:
                self.blocks.append(f"Paragraph: {line}")
        
        return self.blocks

# Usage
async def main():
    parser = MarkdownParser("# Hello\\n- Item 1\\n- Item 2")
    blocks = await parser.parse()
    print(blocks)

if __name__ == "__main__":
    asyncio.run(main())
```

### Database & Queries

```sql
-- SQL Example
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO users (username, email) VALUES
    ('octocat', 'octocat@github.com'),
    ('defunkt', 'defunkt@github.com');

-- Complex query with JOIN
SELECT 
    u.username,
    COUNT(r.id) as repo_count,
    MAX(r.stars) as max_stars
FROM users u
LEFT JOIN repositories r ON u.id = r.owner_id
GROUP BY u.username
HAVING COUNT(r.id) > 0
ORDER BY repo_count DESC;
```

## Special Features

### Line Numbers (in some renderers)
```javascript {.line-numbers}
function fibonacci(n) {
    if (n <= 1) return n;
    return fibonacci(n - 1) + fibonacci(n - 2);
}
```

### Highlighting Specific Lines (GitHub)
```javascript {highlight: [2, 4-6]}
function example() {
    const important = "This line is highlighted";
    const normal = "This is not";
    const alsoImportant = "This is highlighted";
    const veryImportant = "So is this";
    const andThis = "And this too";
    const notThis = "But not this";
}
```

### Diff Syntax
```diff
- Old line that was removed
+ New line that was added
  Unchanged line
! Important change
# Comment about the change
```

## Code Block in Lists

1. First, install the package:
   ```bash
   npm install glimmer
   ```

2. Then import it:
   ```javascript
   import { MarkdownParser } from 'glimmer';
   ```

3. Finally, use it:
   ```javascript
   const parser = new MarkdownParser();
   const result = parser.parse(markdown);
   ```

## Code in Blockquotes

> Here's how to use it:
> ```swift
> let parser = MarkdownParser()
> let blocks = parser.parse(markdown)
> ```
> Simple as that!

## Inline Code vs Code Blocks

Inline code like `let x = 5` is for short snippets.

Code blocks are for longer examples:
```swift
let x = 5
let y = 10
let sum = x + y
print("Sum: \\(sum)")
```

## Edge Cases

### Empty Code Block
```
```

### Code Block with Special Characters
```
< > & " ' ` ~ ! @ # $ % ^ & * ( ) _ + - = [ ] { } | \\ : ; , . ? /
```

### Very Long Lines
```javascript
const veryLongLine = "This is an extremely long line of code that might require horizontal scrolling in some renderers. It goes on and on and on and on and on and on and on and on and on and on and on.";
```

## Pro Tips

1. Always specify the language for better highlighting
2. Use code blocks for multi-line code
3. Use inline code for variable names and short expressions
4. Consider line length for readability
5. Test your code blocks in different renderers
"""

private let gfmLineBreaks = """
# GFM Line Breaks & Paragraphs

GitHub Flavored Markdown handles line breaks differently than standard Markdown.

## Soft Line Breaks

In GFM, a single line break
doesn't create a new paragraph.
These three lines will render
as a single paragraph.

This is a new paragraph because there's a blank line above.

## Hard Line Breaks

### Method 1: Two Spaces
End a line with two spaces  
to create a hard line break.  
Each of these lines  
ends with two spaces.

### Method 2: Backslash
End a line with a backslash\\
to create a hard line break.\\
This also works\\
for multiple lines.

### Method 3: HTML Break Tag
Use HTML <br> tag
<br>to create
<br>line breaks
<br>anywhere you want.

## Paragraphs

Paragraphs are separated by blank lines.

This is a second paragraph. Notice the blank line above.

This is a third paragraph. Again, separated by a blank line.

## Line Breaks in Different Contexts

### In Lists

- First item with no break
  Second line of first item
  
- Second item with hard break  
  This is on a new line
  
- Third item with backslash\\
  Also on a new line

### In Blockquotes

> First line with soft break
> Still in the same paragraph

> First line with hard break  
> This is a new line

> Using backslash\\
> Also creates a new line

### In Tables

| Method | Example | Result |
|--------|---------|--------|
| Soft | Line 1 Line 2 | Single line |
| Two spaces | Line 1  Line 2 | Two lines |
| HTML | Line 1<br>Line 2 | Two lines |

## Practical Examples

### Address Format
John Doe  
123 Main Street  
New York, NY 10001  
USA

### Poetry or Verses
Roses are red  
Violets are blue  
Markdown is awesome  
And so are you

### Signatures
Best regards,  
  
John Doe  
Senior Developer  
Acme Corporation

### Multiple Line Breaks

Single break:
Next line

Double break:


Next line with more space

Triple break:



Even more space

## Common Mistakes

### Mistake 1: Expecting Single Newline to Work
This line
and this line
will be on the same paragraph.

### Mistake 2: Forgetting Spaces
This line doesn't have two spaces at the end
So this appears on the same line.

### Mistake 3: Too Many Spaces
This line has many spaces at the end      
But only two are needed for a line break.

## URL Line Breaks

Long URLs might break naturally:
https://github.com/very/long/url/that/might/need/to/wrap/across/multiple/lines/in/the/rendered/output

But you can control breaks:
Visit our documentation at  
https://docs.example.com/guide

## Code and Line Breaks

Inline code `doesn't  
break` even with two spaces.

But code blocks preserve all formatting:
```
Line 1
Line 2

Line 4 (with blank line above)
```

## Special Characters and Line Breaks

### With Emoji
Hello :wave:  
Welcome to GFM :rocket:  
Have a great day :sun_with_face:

### With Special Characters
First line with → arrow  
Second line with ← arrow  
Third line with ↑ arrow

### With Unicode
Line with Chinese 中文  
Line with Arabic عربي  
Line with Emoji 😊

## Edge Cases

### Trailing Whitespace Visualization
Line with no trailing space|
Line with one trailing space |
Line with two trailing spaces  |
Line with tab at end	|

### Mixed Break Methods
Two spaces  
<br>HTML break
\\Backslash method  
Two spaces again

### In Nested Structures

> - List in quote  
>   With line break
>   > Nested quote  
>   > With break too

## Best Practices

1. **Use two spaces** for most line breaks (most compatible)
2. **Use blank lines** for paragraphs
3. **Be consistent** within a document
4. **Test your breaks** in the target renderer
5. **Avoid trailing whitespace** except for intentional breaks

## Platform Differences

Note: Line break handling may vary between:
- GitHub.com
- GitHub mobile apps
- GitHub Desktop
- Third-party Markdown renderers
- Different Markdown parsers

Always test in your target environment!
"""

private let gfmDisallowedHTML = """
# GFM Disallowed Raw HTML

For security reasons, GitHub Flavored Markdown filters certain HTML tags and attributes.

## Allowed HTML Tags

These HTML tags are allowed and will render:

### Basic Formatting
<strong>Bold text using strong tag</strong>
<em>Italic text using em tag</em>
<code>Inline code using code tag</code>
<del>Strikethrough using del tag</del>

### Structure
<blockquote>This is a blockquote using HTML</blockquote>

<details>
<summary>Click to expand</summary>
This content is hidden until you click the summary.
You can put any markdown here!

- List item 1
- List item 2

```javascript
console.log("Even code blocks work!");
```
</details>

### Line Breaks and Separators
Line one<br>Line two with BR tag
<hr>
Horizontal rule with HR tag

### Links and Images
<a href="https://github.com">Link using anchor tag</a>

## Filtered/Disallowed HTML

These tags are filtered out for security:

### Script Tags (Removed)
<script>alert('This will not execute');</script>

The script tag above is completely removed.

### Style Tags (Removed)
<style>
  .custom { color: red; }
</style>

The style tag above is filtered out.

### Event Handlers (Removed)
<div onclick="alert('clicked')">This div has no onclick</div>
<a href="#" onmouseover="alert('hover')">Link without onmouseover</a>

### Form Elements (Removed)
<form action="/submit">
  <input type="text" name="username">
  <button type="submit">Submit</button>
</form>

Form elements are filtered for security.

### Iframe (Removed)
<iframe src="https://example.com"></iframe>

Iframes are not allowed.

### Object and Embed (Removed)
<object data="file.pdf"></object>
<embed src="video.mp4">

These embedding tags are filtered.

## Sanitized Attributes

### Style Attribute (Removed)
<p style="color: red; font-size: 20px;">This won't be red or large</p>
<div style="background: yellow;">No yellow background</div>

### Class and ID (Removed in most contexts)
<div class="custom-class">No custom class</div>
<span id="custom-id">No custom ID</span>

### JavaScript URLs (Sanitized)
<a href="javascript:alert('xss')">This link won't execute JS</a>
<a href="data:text/html,<script>alert('xss')</script>">Data URL sanitized</a>

## Safe HTML Patterns

### Details/Summary for Collapsible Content
<details>
<summary>✅ Safe: System Requirements</summary>

- OS: iOS 17.0+
- Swift: 5.9+
- Xcode: 15.0+
- Memory: 4GB RAM minimum

</details>

<details>
<summary>✅ Safe: Installation Steps</summary>

1. Clone the repository
2. Open in Xcode
3. Build and run
4. Enjoy!

</details>

### Tables with HTML
<table>
  <tr>
    <th>Feature</th>
    <th>Supported</th>
  </tr>
  <tr>
    <td>Tables</td>
    <td>✅</td>
  </tr>
  <tr>
    <td>Scripts</td>
    <td>❌</td>
  </tr>
</table>

### Abbreviations and Definitions
<abbr title="GitHub Flavored Markdown">GFM</abbr> is awesome!

<dl>
  <dt>GFM</dt>
  <dd>GitHub Flavored Markdown</dd>
  <dt>HTML</dt>
  <dd>HyperText Markup Language</dd>
</dl>

### Keyboard Input
Press <kbd>Cmd</kbd> + <kbd>C</kbd> to copy

Press <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>I</kbd> for developer tools

### Superscript and Subscript
E = mc<sup>2</sup>

H<sub>2</sub>O is water

### Mark/Highlight
This is <mark>highlighted text</mark> for emphasis.

## HTML Entities

These HTML entities are supported:

- Less than: &lt; (`&lt;`)
- Greater than: &gt; (`&gt;`)
- Ampersand: &amp; (`&amp;`)
- Quote: &quot; (`&quot;`)
- Apostrophe: &apos; (`&apos;`)
- Copyright: &copy; (`&copy;`)
- Registered: &reg; (`&reg;`)
- Trademark: &trade; (`&trade;`)
- Euro: &euro; (`&euro;`)
- Non-breaking space: &nbsp; (`&nbsp;`)
- Em dash: &mdash; (`&mdash;`)
- En dash: &ndash; (`&ndash;`)

## Security Considerations

### Why HTML is Filtered

1. **XSS Prevention**: Blocks JavaScript execution
2. **Clickjacking**: Prevents iframe embedding
3. **Phishing**: Limits form submissions
4. **Style Injection**: Prevents CSS attacks
5. **Data Exfiltration**: Blocks external resource loading

### Safe Alternatives

Instead of:
- `<script>` → Use code blocks
- `<style>` → Use Markdown formatting
- `<iframe>` → Use links or images
- `onclick` → Use standard links
- `style=` → Use Markdown emphasis

## Testing HTML Sanitization

Try viewing this document in different contexts:
1. GitHub.com (strictest)
2. GitHub Desktop
3. VS Code preview
4. Other Markdown renderers

Each may have different sanitization rules!

## Best Practices

1. **Prefer Markdown** over HTML when possible
2. **Test your HTML** in the target environment
3. **Avoid inline styles** and scripts
4. **Use semantic HTML** when needed
5. **Document security** considerations

## Note on GitHub Pages

GitHub Pages may have different HTML filtering rules than GitHub.com repositories. Always test in your deployment environment!
"""

#Preview {
    NavigationStack {
        GFMDemo()
    }
}

import SwiftUI
import Glimmer

// MARK: - Basic Features Demo
struct BasicFeaturesDemo: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Basic Markdown
            ScrollView {
                MarkdownView(markdown: basicMarkdown)
                    .padding()
            }
            .tabItem {
                Label("Basic", systemImage: "text.alignleft")
            }
            .tag(0)
            
            // Interactive Elements
            ScrollView {
                MarkdownView(
                    markdown: interactiveMarkdown,
                    onLinkTap: { url in
                        print("🔗 Link: \(url)")
                    },
                    onMentionTap: { username in
                        print("👤 Mention: @\(username)")
                    },
                    onIssueTap: { issue in
                        print("🐛 Issue: #\(issue)")
                    }
                )
                .padding()
            }
            .tabItem {
                Label("Interactive", systemImage: "hand.tap")
            }
            .tag(1)
            
            // Syntax Highlighting
            ScrollView {
                MarkdownView(markdown: codeMarkdown)
                    .padding()
            }
            .tabItem {
                Label("Code", systemImage: "curlybraces")
            }
            .tag(2)
        }
        .navigationTitle("Basic Features")
    }
    
    private let basicMarkdown = """
    # Markdown Basics
    
    ## Text Formatting
    
    This is **bold text**, this is *italic text*, and this is ***bold italic***.
    
    You can also use `inline code` and ~~strikethrough~~.
    
    ## Lists
    
    ### Unordered List
    - First item
    - Second item
      - Nested item
      - Another nested item
    - Third item
    
    ### Ordered List
    1. First step
    2. Second step
       1. Sub-step A
       2. Sub-step B
    3. Third step
    
    ## Blockquotes
    
    > This is a blockquote.
    > It can span multiple lines.
    >
    > > And can be nested too!
    
    ## Tables
    
    | Feature | Status | Notes |
    |---------|--------|-------|
    | Parsing | ✅ | Fast and efficient |
    | Rendering | ✅ | SwiftUI native |
    | Themes | ✅ | Light and dark |
    
    ## Horizontal Rule
    
    ---
    
    ## Task Lists
    
    - [x] Completed task
    - [ ] Pending task
    - [x] Another completed task
    """
    
    private let interactiveMarkdown = """
    # Interactive Elements
    
    ## Links
    - [Apple Developer](https://developer.apple.com)
    - [Swift.org](https://swift.org)
    - [GitHub](https://github.com)
    
    ## GitHub Features
    
    ### Mentions
    Thanks to @tim, @craig, and @johnny for their contributions!
    
    ### Issues and PRs
    - Fixed in #1234
    - See PR #5678
    - Related to issue #90
    
    ### Auto-linking
    - URLs: https://example.com/path/to/page
    - Email: support@example.com
    
    ## Combined Example
    As mentioned by @alice in #123, the solution at https://docs.swift.org works great!
    """
    
    private let codeMarkdown = """
    # Syntax Highlighting
    
    ## Swift
    ```swift
    struct ContentView: View {
        @State private var count = 0
        
        var body: some View {
            Button("Count: \\(count)") {
                count += 1
            }
        }
    }
    ```
    
    ## Python
    ```python
    def quicksort(arr):
        if len(arr) <= 1:
            return arr
        pivot = arr[len(arr) // 2]
        left = [x for x in arr if x < pivot]
        middle = [x for x in arr if x == pivot]
        right = [x for x in arr if x > pivot]
        return quicksort(left) + middle + quicksort(right)
    ```
    
    ## JavaScript
    ```javascript
    const fibonacci = (n) => {
        if (n <= 1) return n;
        return fibonacci(n - 1) + fibonacci(n - 2);
    };
    
    console.log(fibonacci(10));
    ```
    """
}

// MARK: - Advanced Features Demo
struct AdvancedDemo: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ConfigurationDemo()
                .tabItem {
                    Label("Config", systemImage: "slider.horizontal.3")
                }
                .tag(0)
            
            StreamingDemo()
                .tabItem {
                    Label("Streaming", systemImage: "arrow.down.to.line")
                }
                .tag(1)

            ExportDemo()
                .tabItem {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .tag(2)
        }
        .navigationTitle("Advanced Features")
    }
}

// MARK: - Configuration Demo
private struct ConfigurationDemo: View {
    @State private var useGitHub = true
    @State private var theme: CodeHighlightingTheme = .light
    @State private var maxImageWidth: CGFloat = 300
    
    private let sampleMarkdown = """
    # Configuration Demo
    
    **Fluent configuration builder** in action.
    
    ```swift
    let config = MarkdownConfiguration.builder()
        .enableGitHubFeatures()
        .setTheme(.dark)
        .build()
    ```
    
    @username mentions and #123 issue references.
    
    :rocket: Let's go!
    """
    
    var currentConfig: MarkdownConfiguration {
        var builder = MarkdownConfiguration.builder()
            .setTheme(theme)
            .setImageSize(maxWidth: maxImageWidth)
        
        if useGitHub {
            builder = builder.enableGitHubFeatures()
        }
        
        return builder.build()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Options") {
                    Toggle("GitHub Features", isOn: $useGitHub)
                    
                    Picker("Theme", selection: $theme) {
                        Text("Light").tag(CodeHighlightingTheme.light)
                        Text("Dark").tag(CodeHighlightingTheme.dark)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    HStack {
                        Text("Image Width: \(Int(maxImageWidth))px")
                        Slider(value: $maxImageWidth, in: 100...500, step: 50)
                    }
                }
            }
            .frame(maxHeight: 200)
            
            Divider()
            
            ScrollView {
                MarkdownView(markdown: sampleMarkdown, configuration: currentConfig)
                    .padding()
            }
        }
    }
}

// MARK: - Streaming Demo
private struct StreamingDemo: View {
    @State private var streamedContent = ""
    @State private var isStreaming = false
    @State private var streamTask: Task<Void, Never>?
    
    private let fullContent: String = {
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
    }()
    
    var body: some View {
        VStack {
            HStack {
                Button(isStreaming ? "Stop" : "Start") {
                    if isStreaming {
                        stopStreaming()
                    } else {
                        startStreaming()
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Button("Reset") {
                    streamedContent = ""
                }
                .buttonStyle(.bordered)
                .disabled(isStreaming)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                if streamedContent.isEmpty {
                    Text("Click 'Start' to begin streaming")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    StreamingMarkdownView(markdown: streamedContent)
                        .padding()
                }
            }
        }
    }
    
    func startStreaming() {
        streamedContent = ""
        isStreaming = true
        
        streamTask?.cancel()
        streamTask = Task {
            let content = fullContent
            let chunkSize = max(20, content.count / 320)
            
            for i in stride(from: 0, to: content.count, by: chunkSize) {
                guard isStreaming else { break }
                
                let end = min(i + chunkSize, content.count)
                let substring = String(content.prefix(end))
                
                await MainActor.run {
                    streamedContent = substring
                }
                
                try? await Task.sleep(nanoseconds: 35_000_000) // 35ms
            }
            
            await MainActor.run {
                isStreaming = false
            }
        }
    }
    
    func stopStreaming() {
        isStreaming = false
        streamTask?.cancel()
    }
}

// MARK: - Performance Demo
// Removed redundant PerformanceDemo (benchmarks screen exists separately)

// MARK: - Export Demo
private struct ExportDemo: View {
    @State private var inputMarkdown = """
    # Export Demo
    
    Convert **markdown** to different formats!
    
    - HTML export
    - Plain text
    - Custom formats
    """
    
    @State private var exportedContent = ""
    @State private var exportFormat = 0
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("Format", selection: $exportFormat) {
                Text("HTML").tag(0)
                Text("Plain Text").tag(1)
                Text("Markdown").tag(2)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            HStack(spacing: 0) {
                VStack(alignment: .leading) {
                    Text("Input")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    TextEditor(text: $inputMarkdown)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                }
                
                Divider()
                
                VStack(alignment: .leading) {
                    HStack {
                        Text("Output")
                            .font(.headline)
                        Spacer()
                        Button("Export") {
                            export()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal)
                    
                    ScrollView {
                        Text(exportedContent.isEmpty ? "Click 'Export' to see result" : exportedContent)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(exportedContent.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                }
            }
        }
    }
    
    func export() {
        let blocks = MarkdownParser.parse(inputMarkdown, configuration: .default)
        
        switch exportFormat {
        case 0: // HTML
            let renderer = HTMLMarkdownRenderer()
            exportedContent = renderer.render(blocks: blocks, configuration: .default)
        case 1: // Plain Text
            let renderer = PlainTextMarkdownRenderer()
            exportedContent = renderer.render(blocks: blocks, configuration: .default)
        case 2: // Markdown
            exportedContent = MarkdownExporter.export(blocks)
        default:
            exportedContent = ""
        }
    }
}

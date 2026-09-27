import Glimmer
import SwiftUI

/// 1.x's Advanced Features: configuration, streaming and export, one tab each, on 2.0's API.
struct AdvancedDemo: View {
    @State private var selectedTab = DemoExample.launchSection ?? 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Config", systemImage: "slider.horizontal.3", value: 0) {
                ConfigurationDemo()
            }
            Tab("Streaming", systemImage: "arrow.down.to.line", value: 1) {
                StreamingDemo()
            }
            Tab("Export", systemImage: "square.and.arrow.up", value: 2) {
                ExportDemo()
            }
        }
        .navigationTitle("Advanced Features")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Configuration Demo

/// `GlimmerConfiguration` live: extensions, theme options and the image loader. A `GlimmerText` reads its
/// configuration once, so a change gives it a new identity.
private struct ConfigurationDemo: View {
    @State private var usesGitHubExtensions = true
    @State private var underlinesLinks = false
    @State private var showsCodeBlockHeader = true
    @State private var loadsImages = true
    @State private var isLarge = false
    @State private var maxImageHeight: CGFloat = 200

    private let sampleMarkdown = """
    # Configuration Demo

    **GlimmerConfiguration** in action, with a [link](https://swift.org).

    ```swift
    var configuration = GlimmerConfiguration(extensions: [GlimmerEmojiShortcodes(), GlimmerMentions()])
    configuration.theme.underlinesLinks = true
    ```

    @username mentions and #123 issue references.

    :rocket: Let's go!

    ![Swift](https://developer.apple.com/assets/elements/icons/swift/swift-96x96_2x.png)
    """

    private var configuration: GlimmerConfiguration {
        var configuration = usesGitHubExtensions ? GlimmerConfiguration.demoGitHub : GlimmerConfiguration()
        configuration.imageLoader = loadsImages ? DemoImageLoader() : nil
        configuration.theme.underlinesLinks = underlinesLinks
        configuration.theme.showsCodeBlockHeader = showsCodeBlockHeader
        configuration.theme.maxImageHeight = maxImageHeight
        if isLarge {
            configuration.theme.bodyFont = .systemFont(ofSize: 20)
            configuration.theme.codeFont = .monospacedSystemFont(ofSize: 17, weight: .regular)
        }
        return configuration
    }

    /// Changes whenever the configuration does.
    private var configurationID: String {
        "\(usesGitHubExtensions)-\(underlinesLinks)-\(showsCodeBlockHeader)-\(loadsImages)-\(isLarge)-\(maxImageHeight)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Options") {
                    Toggle("GitHub Extensions", isOn: $usesGitHubExtensions)
                    Toggle("Underline Links", isOn: $underlinesLinks)
                    Toggle("Code Block Header", isOn: $showsCodeBlockHeader)
                    Toggle("Load Images", isOn: $loadsImages)

                    Picker("Theme", selection: $isLarge) {
                        Text("Default").tag(false)
                        Text("Large").tag(true)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Image Height: \(Int(maxImageHeight)) pt")
                        Slider(value: $maxImageHeight, in: 100...400, step: 50)
                    }
                }
            }
            .frame(maxHeight: 330)

            Divider()

            ScrollView {
                GlimmerText(sampleMarkdown, configuration: configuration)
                    .id(configurationID)
                    .padding()
            }
        }
    }
}

// MARK: - Streaming Demo

/// A long document streamed into `GlimmerText` a chunk every 35 ms, as 1.x did; 2.0 reveals it phrase by phrase.
private struct StreamingDemo: View {
    @State private var streamedContent = ""
    @State private var isStreaming = false
    @State private var streamTask: Task<Void, Never>?
    @State private var runID = UUID()

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
                .accessibilityIdentifier("streaming.start")

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
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    GlimmerText(streamedContent, isStreaming: isStreaming, revealID: runID.uuidString)
                        .padding()
                }
            }
            .defaultScrollAnchor(.top)
        }
        .onDisappear { stopStreaming() }
    }

    func startStreaming() {
        streamedContent = ""
        runID = UUID()
        isStreaming = true

        streamTask?.cancel()
        streamTask = Task {
            let content = fullContent
            let chunkSize = max(20, content.count / 320)

            for i in stride(from: 0, to: content.count, by: chunkSize) {
                guard isStreaming, !Task.isCancelled else { break }
                let end = min(i + chunkSize, content.count)
                streamedContent = String(content.prefix(end))
                try? await Task.sleep(for: .milliseconds(35))
            }
            isStreaming = false
        }
    }

    func stopStreaming() {
        isStreaming = false
        streamTask?.cancel()
    }
}

// MARK: - Export Demo

/// What copy writes: the whole answer as markdown or plain text (`markdownSource(for:)`, `plainText(for:)`), or a
/// selection in the preview through its edit menu. 2.0 has no HTML export.
private struct ExportDemo: View {
    @State private var inputMarkdown = """
    # Export Demo

    Convert **markdown** to different formats!

    - Plain text
    - Markdown
    - Any selection in the preview
    """

    @State private var exportedContent = ""
    @State private var exportFormat = 0
    /// Holds the answer the export reads; `GlimmerText` keeps its own view private.
    @State private var exporter: GlimmerView?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Format", selection: $exportFormat) {
                Text("Plain Text").tag(0)
                Text("Markdown").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            HStack(spacing: 0) {
                VStack(alignment: .leading) {
                    Text("Input")
                        .font(.headline)
                        .padding(.horizontal)

                    TextEditor(text: $inputMarkdown)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .accessibilityIdentifier("export.input")
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
                        .accessibilityIdentifier("export.button")
                    }
                    .padding(.horizontal)

                    ScrollView {
                        Text(exportedContent.isEmpty ? "Click 'Export' to see result" : exportedContent)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(exportedContent.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("export.output")
                    }
                }
            }

            Divider()

            ScrollView {
                GlimmerText(
                    inputMarkdown,
                    editMenuActions: { selection in
                        [UIAction(title: "Export Selection") { _ in
                            exportedContent = exportFormat == 0 ? selection.plainText : selection.markdown
                        }]
                    }
                )
                .padding()
            }
            .frame(maxHeight: 220)
        }
    }

    func export() {
        let exporter = exporter ?? GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil, reveal: .none))
        self.exporter = exporter
        exporter.update(markdown: inputMarkdown)
        exportedContent = exportFormat == 0 ? exporter.plainText() : exporter.markdownSource()
    }
}

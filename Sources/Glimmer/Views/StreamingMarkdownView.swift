import SwiftUI

/// A special markdown view optimized for streaming content without flickering
public struct StreamingMarkdownView: View {
    let markdown: String
    let configuration: MarkdownConfiguration
    let interactive: Bool
    let onLinkTap: ((URL) -> Void)?
    
    @State private var blocks: [MarkdownParser.BlockNode] = []
    @State private var lastMarkdown = ""
    @State private var parseTask: Task<Void, Never>?
    @Environment(\.openURL) private var openURL
    
    public init(
        markdown: String,
        configuration: MarkdownConfiguration = .default,
        interactive: Bool = true,
        onLinkTap: ((URL) -> Void)? = nil
    ) {
        self.markdown = markdown
        self.configuration = configuration
        self.interactive = interactive
        self.onLinkTap = onLinkTap
    }
    
    public var body: some View {
        ScrollView {
            if blocks.isEmpty && !markdown.isEmpty {
                Text("Loading...")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if blocks.isEmpty {
                Text("Click 'Start Streaming' to see content appear progressively")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                if interactive {
                    InteractiveMarkdownContent(
                        blocks: blocks,
                        configuration: configuration,
                        onLinkTap: handleLinkTap,
                        onMentionTap: nil,
                        onIssueTap: nil,
                        onFootnoteTap: nil
                    )
                    .padding()
                } else {
                    // Use VStack directly to have more control over updates
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                            MarkdownBlockView(
                                block: block,
                                configuration: configuration,
                                depth: 0
                            )
                            // Use stable ID to prevent view recreation
                            .id("\(index)-\(blockHash(block))")
                        }
                    }
                    .padding()
                }
            }
        }
        .task(id: markdown) {
            await processMarkdownStream()
        }
        .onDisappear {
            parseTask?.cancel()
        }
    }
    
    private func processMarkdownStream() async {
        // Cancel any existing parse task
        parseTask?.cancel()
        
        // Skip if no change
        guard markdown != lastMarkdown else { return }
        
        // Check if this is incremental growth (streaming)
        let isIncremental = markdown.hasPrefix(lastMarkdown) && markdown.count > lastMarkdown.count
        
        if isIncremental {
            // For streaming, update without clearing
            parseTask = Task {
                let parsed = await parseMarkdownAsync(markdown)
                if !Task.isCancelled {
                    // Direct assignment without animation for smooth updates
                    blocks = parsed
                    lastMarkdown = markdown
                }
            }
        } else {
            // For new content, clear and rebuild
            parseTask = Task {
                let parsed = await parseMarkdownAsync(markdown)
                if !Task.isCancelled {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        blocks = parsed
                    }
                    lastMarkdown = markdown
                }
            }
        }
    }
    
    private func parseMarkdownAsync(_ content: String) async -> [MarkdownParser.BlockNode] {
        await Task.detached(priority: .userInitiated) {
            Glimmer.parse(content, configuration: configuration)
        }.value
    }
    
    private func handleLinkTap(_ url: URL) {
        if let onLinkTap = onLinkTap {
            onLinkTap(url)
        } else {
            openURL(url)
        }
    }
    
    /// Generate a stable hash for a block to use as ID
    private func blockHash(_ block: MarkdownParser.BlockNode) -> Int {
        var hasher = Hasher()
        
        switch block {
        case .heading(let level, let children, _):
            hasher.combine("heading")
            hasher.combine(level)
            hasher.combine(inlineNodesHash(children))
        case .paragraph(let children):
            hasher.combine("paragraph")
            hasher.combine(inlineNodesHash(children))
        case .codeBlock(let lang, let content):
            hasher.combine("code")
            hasher.combine(lang ?? "")
            hasher.combine(content.prefix(100)) // Use prefix to avoid huge hashes
        case .list(let ordered, _, let items):
            hasher.combine("list")
            hasher.combine(ordered)
            hasher.combine(items.count)
        case .blockquote(let children):
            hasher.combine("quote")
            hasher.combine(children.count)
        case .horizontalRule:
            hasher.combine("hr")
        default:
            hasher.combine("other")
        }
        
        return hasher.finalize()
    }
    
    private func inlineNodesHash(_ nodes: [MarkdownParser.InlineNode]) -> Int {
        var hasher = Hasher()
        for node in nodes.prefix(5) { // Only hash first few nodes for performance
            switch node {
            case .text(let text):
                hasher.combine(text.prefix(50))
            case .strong, .emphasis, .code:
                hasher.combine("inline")
            default:
                break
            }
        }
        return hasher.finalize()
    }
}

/// A more advanced streaming view using AsyncStream for real-time updates
public struct AsyncStreamingMarkdownView: View {
    let markdownStream: AsyncStream<String>
    let configuration: MarkdownConfiguration
    
    @State private var blocks: [MarkdownParser.BlockNode] = []
    @State private var currentMarkdown = ""
    
    public init(
        markdownStream: AsyncStream<String>,
        configuration: MarkdownConfiguration = .default
    ) {
        self.markdownStream = markdownStream
        self.configuration = configuration
    }
    
    public var body: some View {
        ScrollView {
            if blocks.isEmpty {
                ProgressView("Waiting for content...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                MarkdownContentView(
                    blocks: blocks,
                    configuration: configuration
                )
            }
        }
        .task {
            for await markdown in markdownStream {
                currentMarkdown = markdown
                let parsed = await Task.detached {
                    Glimmer.parse(markdown, configuration: configuration)
                }.value
                
                // Update blocks smoothly
                blocks = parsed
            }
        }
    }
}

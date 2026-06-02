import SwiftUI
import Combine
import Glimmer

// Experimental: Live preview with diffing (demo only)
@MainActor
final class MarkdownDiffingEngine: ObservableObject {
    enum DiffOperation {
        case insert(blocks: [MarkdownParser.BlockNode], at: Int)
        case delete(range: Range<Int>)
    }

    struct PreviewState {
        var blocks: [MarkdownParser.BlockNode] = []
        var isDirty: Bool = false
    }

    @Published private(set) var previewState = PreviewState()
    private var previousMarkdown: String = ""
    private var previousBlocks: [MarkdownParser.BlockNode] = []
    private let configuration: MarkdownConfiguration
    private let debounceDelay: TimeInterval
    private var pendingTask: Task<Void, Never>?

    init(configuration: MarkdownConfiguration = .default, debounceDelay: TimeInterval = 0.3) {
        self.configuration = configuration
        self.debounceDelay = debounceDelay
    }

    func update(markdown: String) {
        pendingTask?.cancel()
        previewState.isDirty = true
        pendingTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(debounceDelay * 1_000_000_000))
            await self.compute(markdown: markdown)
        }
    }

    private func compute(markdown: String) async {
        guard markdown != previousMarkdown else {
            previewState.isDirty = false
            return
        }
        let newBlocks = MarkdownParser.parse(markdown, configuration: configuration)
        previousMarkdown = markdown
        previousBlocks = newBlocks
        previewState.blocks = newBlocks
        previewState.isDirty = false
    }
}

struct LiveMarkdownPreview: View {
    @ObservedObject private var engine: MarkdownDiffingEngine
    @Binding private var markdown: String
    private let configuration: MarkdownConfiguration

    init(markdown: Binding<String>, configuration: MarkdownConfiguration = .default) {
        _markdown = markdown
        self.configuration = configuration
        self.engine = MarkdownDiffingEngine(configuration: configuration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if engine.previewState.isDirty { ProgressView().padding(.vertical) }
            ScrollView {
                MarkdownContentView(blocks: engine.previewState.blocks, configuration: configuration)
                    .padding(.horizontal)
            }
        }
        .onChange(of: markdown) { _, newValue in
            engine.update(markdown: newValue)
        }
        .onAppear { engine.update(markdown: markdown) }
    }
}

// Simple demo wrapper for the Examples app
struct LivePreviewDemoScreen: View {
    @State private var text: String = "# Live Preview\n\nType to see updates."

    var body: some View {
        VStack {
            TextEditor(text: $text)
                .frame(height: 140)
                .border(Color.secondary)
                .padding()
            Divider()
            LiveMarkdownPreview(markdown: $text, configuration: .default)
        }
        .navigationTitle("Live Preview (Demo)")
    }
}


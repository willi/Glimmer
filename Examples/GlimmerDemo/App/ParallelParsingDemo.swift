import SwiftUI
import Glimmer

struct ParallelParsingDemo: View {
    @State private var documentSize = 50000
    @State private var concurrency = 4
    @State private var isParsing = false
    @State private var progress: Double = 0
    @State private var parseResults: ParseResults?
    @State private var useParallel = true
    @State private var showMetrics = false
    @State private var parserRef: ParallelMarkdownParser? = nil
    
    struct ParseResults: Sendable {
        let blocks: [MarkdownParser.BlockNode]
        let parseTime: TimeInterval
        let strategy: String
        // Metrics support removed; keep shape minimal
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Configuration
                    GroupBox("Configuration") {
                        VStack(alignment: .leading, spacing: 12) {
                            // Document size
                            VStack(alignment: .leading) {
                                HStack {
                                    Text("Document Size")
                                    Spacer()
                                    Text("\(documentSize) characters")
                                        .foregroundColor(.secondary)
                                }
                                Slider(value: Binding(
                                    get: { Double(documentSize) },
                                    set: { documentSize = Int($0) }
                                ), in: 1000...200000, step: 1000)
                            }
                            
                            // Concurrency
                            VStack(alignment: .leading) {
                                HStack {
                                    Text("Concurrency")
                                    Spacer()
                                    Text("\(concurrency) threads")
                                        .foregroundColor(.secondary)
                                }
                                Slider(value: Binding(
                                    get: { Double(concurrency) },
                                    set: { concurrency = Int($0) }
                                ), in: 1...8, step: 1)
                                .disabled(!useParallel)
                            }
                            
                            // Strategy toggle
                            Toggle("Use Parallel Parsing", isOn: $useParallel)
                            
                            Toggle("Show Detailed Metrics", isOn: $showMetrics)
                        }
                    }
                    
                    // Parse button
                    Button(action: performParsing) {
                        if isParsing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        } else {
                            Label("Parse Document", systemImage: "bolt.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isParsing)
                    
                    // Progress
                    if isParsing {
                        VStack(spacing: 8) {
                            ProgressView(value: progress)
                            Text("Parsing: \(Int(progress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    }
                    
                    // Results
                    if let results = parseResults {
                        GroupBox("Results") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Label("Strategy", systemImage: "cpu")
                                    Spacer()
                                    Text(results.strategy)
                                        .bold()
                                }
                                
                                HStack {
                                    Label("Parse Time", systemImage: "clock")
                                    Spacer()
                                    Text(String(format: "%.3f seconds", results.parseTime))
                                        .bold()
                                }
                                
                                HStack {
                                    Label("Blocks Parsed", systemImage: "doc.text")
                                    Spacer()
                                    Text("\(results.blocks.count)")
                                        .bold()
                                }
                                
                                // Detailed metrics not available in current API
                            }
                        }
                        
                        // Block type breakdown
                        GroupBox("Block Type Distribution") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(blockTypeStats(results.blocks).enumerated()), id: \.offset) { _, stat in
                                    HStack {
                                        Text(stat.type)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(stat.count)")
                                            .bold()
                                        
                                        // Bar graph
                                        GeometryReader { geometry in
                                            Rectangle()
                                                .fill(Color.accentColor.opacity(0.3))
                                                .frame(width: geometry.size.width * stat.percentage)
                                        }
                                        .frame(width: 100, height: 20)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(4)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Comparison
                    if parseResults != nil {
                        GroupBox("Strategy Comparison") {
                            Button("Run Comparison Test") {
                                runComparisonTest()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Parallel Parsing")
        }
    }
    
    private func performParsing() {
        isParsing = true
        progress = 0
        
        let markdown = generateDocument(size: documentSize)
        let startTime = CFAbsoluteTimeGetCurrent()
        
        if useParallel {
            let selectedConcurrency = concurrency
            // Parallel parsing
            let config = ParallelMarkdownParser.ParallelConfiguration(
                concurrency: selectedConcurrency,
                minimumSizeThreshold: 1000,
                chunkSize: 5000
            )
            
            let parser = ParallelMarkdownParser(
                parallelConfig: config,
                markdownConfig: .default
            )
            // Retain parser for the duration of the async parse to keep operation alive
            parserRef = parser
            
            parser.parseAsync(markdown, progress: { prog in
                Task { @MainActor in
                    progress = prog
                }
            }, completion: { blocks in
                let endTime = CFAbsoluteTimeGetCurrent()
                
                Task { @MainActor in
                    parseResults = ParseResults(
                        blocks: blocks,
                        parseTime: endTime - startTime,
                        strategy: "Parallel (\(selectedConcurrency) threads)"
                    )
                    isParsing = false
                    // Release retained parser
                    parserRef = nil
                }
            })
        } else {
            // Sequential parsing
            Task {
                let blocks = await Task.detached {
                    MarkdownParser.parse(markdown, configuration: .default)
                }.value
                
                let endTime = CFAbsoluteTimeGetCurrent()
                
                await MainActor.run {
                    parseResults = ParseResults(
                        blocks: blocks,
                        parseTime: endTime - startTime,
                        strategy: "Sequential"
                    )
                    progress = 1.0
                    isParsing = false
                }
            }
        }
    }
    
    private func runComparisonTest() {
        let markdown = generateDocument(size: documentSize)
        
        Task {
            var results: [(String, TimeInterval)] = []
            
            // Test sequential
            let seqStart = CFAbsoluteTimeGetCurrent()
            _ = MarkdownParser.parse(markdown, configuration: .default)
            results.append(("Sequential", CFAbsoluteTimeGetCurrent() - seqStart))
            
            // Test parallel with different concurrency levels
            for threads in [2, 4, 8] {
                let config = ParallelMarkdownParser.ParallelConfiguration(
                    concurrency: threads,
                    minimumSizeThreshold: 1000
                )
                let parser = ParallelMarkdownParser(parallelConfig: config)
                
                let parStart = CFAbsoluteTimeGetCurrent()
                _ = parser.parse(markdown)
                results.append(("Parallel (\(threads))", CFAbsoluteTimeGetCurrent() - parStart))
            }
            
            // Adaptive parser not available; skip
            
            // Show results
            await MainActor.run {
                showComparisonResults(results)
            }
        }
    }
    
    private func showComparisonResults(_ results: [(String, TimeInterval)]) {
        // In a real app, you'd show this in a sheet or alert
        print("=== Comparison Results ===")
        for (strategy, time) in results {
            print("\(strategy): \(String(format: "%.3f", time))s")
        }
    }
    
    private func blockTypeStats(_ blocks: [MarkdownParser.BlockNode]) -> [(type: String, count: Int, percentage: Double)] {
        var stats: [String: Int] = [:]
        
        for block in blocks {
            let type = blockTypeName(block)
            stats[type, default: 0] += 1
        }
        
        let total = Double(blocks.count)
        
        return stats.map { (type: $0.key, count: $0.value, percentage: Double($0.value) / total) }
            .sorted { $0.count > $1.count }
    }
    
    private func blockTypeName(_ block: MarkdownParser.BlockNode) -> String {
        switch block {
        case .heading: return "Heading"
        case .paragraph: return "Paragraph"
        case .list: return "List"
        case .codeBlock: return "Code Block"
        case .blockquote: return "Blockquote"
        case .table: return "Table"
        case .horizontalRule: return "HR"
        default: return "Other"
        }
    }
    
    private func metricRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
    
    private func generateDocument(size: Int) -> String {
        var content = ""
        let templates = [
            "# Heading \(UUID().uuidString)\n\nThis is a paragraph with **bold** and *italic* text.\n\n",
            "## Subheading\n\n- List item one\n- List item two\n- List item three\n\n",
            "```swift\nfunc example() {\n    print(\"Hello\")\n}\n```\n\n",
            "> This is a blockquote\n> with multiple lines\n\n",
            "| Column 1 | Column 2 |\n|----------|----------|\n| Data | Data |\n\n"
        ]
        
        while content.count < size {
            content += templates.randomElement()!
        }
        
        return String(content.prefix(size))
    }
}

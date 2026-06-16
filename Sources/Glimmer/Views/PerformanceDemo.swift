import SwiftUI

public struct PerformanceDemo: View {
    @State private var iterations: Int = 5
    @State private var size: CorpusSize = .medium
    @State private var chunkBytes: Int = 4096
    @State private var isRunning = false
    @State private var results: [ResultRow] = []

    public init() {}

    public var body: some View {
        List {
            Section("Configuration") {
                Picker("Corpus", selection: $size) {
                    ForEach(CorpusSize.allCases, id: \.self) { s in
                        Text(s.label).tag(s)
                    }
                }
                Stepper(value: $iterations, in: 3...25) {
                    Text("Iterations: \(iterations)")
                }
                Stepper(value: $chunkBytes, in: 1024...16384, step: 1024) {
                    Text("Streaming chunk: \(chunkBytes) bytes")
                }
                Button(action: runBenchmarks) {
                    HStack {
                        if isRunning { ProgressView() }
                        Text(isRunning ? "Running…" : "Run Benchmarks")
                    }
                }
                .disabled(isRunning)
            }

            if !results.isEmpty {
                Section("Results (median of \(iterations) runs)") {
                    ForEach(results) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.strategy.rawValue).font(.headline)
                            Text(String(format: "Time: %.2f ms", row.milliseconds))
                            Text("Blocks: \(row.blocks), Chars/sec: \(row.charsPerSecDisplay)")
                        }
                    }
                }
            }
        }
        .navigationTitle("Performance Benchmarks")
    }

    private func runBenchmarks() {
        if isRunning { return }
        isRunning = true
        results = []

        let markdown = CorpusGenerator.make(size: size)
        let charCount = markdown.count
        let chunkBytes = chunkBytes
        let iterations = iterations

        Task.detached {
            // Warm-up each once (not recorded)
            _ = Benchmark.runOnce(.sequential, markdown: markdown, chunkBytes: chunkBytes)
            _ = Benchmark.runOnce(.parallel, markdown: markdown, chunkBytes: chunkBytes)
            _ = Benchmark.runOnce(.streaming, markdown: markdown, chunkBytes: chunkBytes)
            // lazy strategy removed

            var rows: [ResultRow] = []
            for strategy in Strategy.allCases {
                var times: [Double] = []
                var blocksOut = 0
                for _ in 0..<iterations {
                    let r = Benchmark.runOnce(strategy, markdown: markdown, chunkBytes: chunkBytes)
                    times.append(r.seconds)
                    blocksOut = r.blocks
                }
                times.sort()
                let median = times[times.count/2]
                let cps = Double(charCount) / median
                rows.append(ResultRow(strategy: strategy, seconds: median, blocks: blocksOut, charsPerSec: cps))
            }

            await MainActor.run {
                self.results = rows
                self.isRunning = false
            }
        }
    }
}

// MARK: - Types

private enum Strategy: String, CaseIterable, Identifiable, Sendable {
    case sequential = "Sequential"
    case parallel = "Parallel"
    case streaming = "Streaming"
    var id: String { rawValue }
}

private struct ResultRow: Identifiable, Sendable {
    let id = UUID()
    let strategy: Strategy
    let seconds: Double
    let blocks: Int
    let charsPerSec: Double
    var milliseconds: Double { seconds * 1000.0 }
    var charsPerSecDisplay: String { String(Int(charsPerSec)) }
}

private enum CorpusSize: CaseIterable, Sendable { case small, medium, large, xl
    var label: String {
        switch self { case .small: return "Small (~2KB)"; case .medium: return "Medium (~20KB)"; case .large: return "Large (~200KB)"; case .xl: return "XL (~1MB)" }
    }
}

private enum CorpusGenerator {
    static func make(size: CorpusSize) -> String {
        let base = Self.baseSample
        let targetBytes: Int = {
            switch size { case .small: return 2*1024; case .medium: return 20*1024; case .large: return 200*1024; case .xl: return 1024*1024 }
        }()
        var out = ""
        out.reserveCapacity(targetBytes)
        while out.utf8.count < targetBytes {
            out += base
        }
        return out
    }

    // A mixed sample covering headings, lists, code, tables, links, mentions, issues, repos, and long paragraphs
    private static let baseSample: String = {
        var s = ""
        s += "# Title :rocket:\n\n"
        s += "Paragraph with @user, owner/repo#123 and SHA deadbeefcafebabe. Visit https://example.com.\n\n"
        s += "- Item 1\n- Item 2\n- [Link](https://example.com)\n\n"
        s += "| Col A | Col B |\n| --- | ---: |\n| 123 | 456 |\n\n"
        s += "```swift\nlet x = 42 // code\n```\n\n"
        s += String(repeating: "This is a very long paragraph to stress inline parsing. ", count: 10) + "\n\n"
        return s
    }()
}

private enum Benchmark {
    static func runOnce(_ strategy: Strategy, markdown: String, chunkBytes: Int) -> (seconds: Double, blocks: Int) {
        switch strategy {
        case .sequential:
            let start = CFAbsoluteTimeGetCurrent()
            let blocks = MarkdownParser.parse(markdown, configuration: .default)
            let end = CFAbsoluteTimeGetCurrent()
            return (end - start, blocks.count)
        case .parallel:
            let parser = ParallelMarkdownParser()
            let start = CFAbsoluteTimeGetCurrent()
            let blocks = parser.parse(markdown)
            let end = CFAbsoluteTimeGetCurrent()
            return (end - start, blocks.count)
        case .streaming:
            let s = StreamingMarkdownParser(configuration: .default)
            let start = CFAbsoluteTimeGetCurrent()
            for chunk in chunks(of: markdown, size: chunkBytes) {
                _ = s.parseChunk(chunk)
            }
            let blocks = s.finish()
            let end = CFAbsoluteTimeGetCurrent()
            return (end - start, blocks.count)
        }
    }

    private static func chunks(of text: String, size: Int) -> [String] {
        var chunks: [String] = []
        chunks.reserveCapacity(max(1, text.utf8.count / size))
        var current = ""
        current.reserveCapacity(size)
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if current.utf8.count + line.utf8.count + 1 > size { // +1 for newline
                chunks.append(current)
                current = ""
            }
            current += line
            current += "\n"
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}

#Preview {
    PerformanceDemo()
}

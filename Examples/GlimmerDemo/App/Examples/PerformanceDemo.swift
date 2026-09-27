import Glimmer
import SwiftUI

/// 1.x's Parallel Parsing and Performance Benchmarks, as one screen of 2.0's own numbers for a document of the chosen
/// size: parsing, showing it settled (parse, compose and measure), and streaming it into the view below a chunk a
/// frame while a display link counts late frames. Debug builds are several times slower than Release.
struct PerformanceDemo: View {
    @State private var documentSize = 20_000
    @State private var runs = 3
    @State private var isRunning = false
    @State private var results: [Result] = []
    @State private var streamed = ""
    @State private var isStreaming = false
    @State private var monitor = FrameMonitor()

    struct Result: Identifiable {
        let name: String
        let detail: String
        var id: String { name }
    }

    private static let configuration = GlimmerConfiguration(imageLoader: nil, reveal: .none)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Configuration") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Document Size")
                            Spacer()
                            Text("\(documentSize.formatted()) characters")
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(get: { Double(documentSize) }, set: { documentSize = Int($0) }),
                            in: 1_000...200_000, step: 1_000
                        )
                        .accessibilityIdentifier("performance.size")
                        Stepper("Runs: \(runs)", value: $runs, in: 1...10)
                    }
                }

                Button(action: run) {
                    if isRunning {
                        ProgressView()
                    } else {
                        Label("Run Benchmark", systemImage: "bolt.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)
                .accessibilityIdentifier("performance.run")

                if !results.isEmpty {
                    GroupBox("Results") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(results) { result in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.name).font(.subheadline.weight(.semibold))
                                    Text(result.detail).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("performance.results")
                    }
                }

                if !streamed.isEmpty {
                    GlimmerText(streamed, isStreaming: isStreaming, revealID: "performance", configuration: Self.configuration)
                        .frame(maxHeight: 320, alignment: .top)
                        .clipped()
                }
            }
            .padding()
        }
        .navigationTitle("Performance")
    }

    /// A document of about `size` characters: the gallery's sample, which has every element, repeated.
    private static func document(size: Int, salt: String) -> String {
        let sample = EngineGalleryDemo.sample
        let copies = Array(repeating: sample, count: max(1, size / sample.count + 1)).joined(separator: "\n\n")
        // Cut at a paragraph, and end with a unique line so no run reads another's cached result.
        let cut = copies.prefix(size)
        let end = cut.range(of: "\n\n", options: .backwards)?.lowerBound ?? cut.endIndex
        return String(cut[..<end]) + "\n\nRun \(salt)."
    }

    private func run() {
        isRunning = true
        results = []
        streamed = ""
        let size = documentSize
        let runs = runs
        Task { @MainActor in
            var parse: [Double] = []
            var settled: [Double] = []
            for index in 0..<runs {
                let document = Self.document(size: size, salt: "\(index)-\(UUID())")
                parse.append(await Task.detached { Self.milliseconds { _ = GlimmerParser.parse(document) } }.value)
                settled.append(Self.milliseconds {
                    let view = GlimmerView(configuration: Self.configuration)
                    view.update(markdown: document)
                    _ = view.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude))
                })
                await Task.yield()
            }
            results = [
                Result(name: "Parse", detail: Self.summary(parse)),
                Result(name: "Settled render (parse, compose, measure)", detail: Self.summary(settled)),
            ]
            await stream(Self.document(size: size, salt: UUID().uuidString))
            isRunning = false
        }
    }

    /// Streams the document into the view below in 120 chunks, one per 120 Hz frame, and counts late frames.
    private func stream(_ document: String) async {
        let chunkSize = max(1, document.count / 120)
        let started = ContinuousClock.now
        isStreaming = true
        monitor.start()
        var index = document.startIndex
        while index < document.endIndex {
            index = document.index(index, offsetBy: chunkSize, limitedBy: document.endIndex) ?? document.endIndex
            streamed = String(document[..<index])
            try? await Task.sleep(for: .milliseconds(8))
        }
        isStreaming = false
        try? await Task.sleep(for: .seconds(1))
        monitor.stop()
        let elapsed = ContinuousClock.now - started
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let counter = monitor.counter
        results.append(Result(
            name: "Streamed render (120 updates)",
            detail: String(format: "%.1f s · %d frames · %d late · worst %.1f ms · %.2f ms/s",
                           seconds, counter.frames, counter.hitches, counter.worstInterval * 1000, counter.hitchTimeRatio)
        ))
    }

    nonisolated private static func milliseconds(_ work: () -> Void) -> Double {
        let start = ContinuousClock.now
        work()
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    }

    nonisolated private static func summary(_ times: [Double]) -> String {
        let sorted = times.sorted()
        let median = sorted[sorted.count / 2]
        return String(format: "median %.1f ms · best %.1f ms · %d runs", median, sorted[0], sorted.count)
    }
}

#Preview {
    NavigationStack { PerformanceDemo() }
}

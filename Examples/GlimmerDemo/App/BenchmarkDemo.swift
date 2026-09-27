import Glimmer
import SwiftUI

/// Streams about 1,000 words below a settled 5,000-word answer at Gemini's cadence, with a frame monitor. The
/// cadence is seeded, so every run streams the same chunks at the same times. Used by BenchmarkHitchUITests.
struct BenchmarkDemo: View {
    private static let history = Array(repeating: EngineGalleryDemo.sample, count: 20).joined(separator: "\n\n---\n\n")
    private static let answer = Array(repeating: StreamingLabDemo.answer, count: 3).joined(separator: "\n\n")
    private static let configuration = GlimmerConfiguration(imageLoader: nil)

    @State private var shown = ""
    @State private var isStreaming = false
    @State private var summary = "idle"
    @State private var monitor = FrameMonitor()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GlimmerText(Self.history, configuration: Self.configuration)
                GlimmerText(shown, isStreaming: isStreaming, revealID: "benchmark", configuration: Self.configuration)
            }
            .padding(16)
        }
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .accessibilityIdentifier("benchmark.scrollView")
        .navigationTitle("Benchmark")
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(summary)
                    .font(.caption.monospaced())
                    .accessibilityIdentifier("benchmark.summary")
                Spacer()
                Button("Start", action: start)
                    .buttonStyle(.borderedProminent)
                    .disabled(isStreaming)
                    .accessibilityIdentifier("benchmark.start")
            }
            .padding()
            .background(.bar)
        }
    }

    private func start() {
        shown = ""
        isStreaming = true
        summary = "running"
        monitor.start()
        var generator = SeededGenerator(seed: 42)
        let chunks = StreamingLabDemo.chunks(of: Self.answer, cadence: .gemini, using: &generator)
        Task { @MainActor in
            for (text, delay) in chunks {
                try? await Task.sleep(for: delay)
                shown += text
            }
            isStreaming = false
            // Let the reveal finish before reading the monitor.
            try? await Task.sleep(for: .seconds(3))
            monitor.stop()
            let counter = monitor.counter
            summary = String(format: "done frames=%d hitches=%d worst=%.1fms", counter.frames, counter.hitches,
                             counter.worstInterval * 1000)
        }
    }
}

/// SplitMix64: a small deterministic generator, so the benchmark's cadence is the same on every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

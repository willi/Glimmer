import SwiftUI
import Glimmer

/// Demo for `GlimmerRevealView`: pick any of the ten reveal styles, then
/// either simulate an LLM streaming tokens into the buffer or play the full
/// text one-shot. Rich markdown (headings, lists, code, links, quotes)
/// reveals styled from frame one and settles with no engine swap.
struct StreamingRevealDemo: View {
    @State private var style: RevealStyle = .wordFade
    @State private var buffer = ""
    @State private var isStreaming = false
    @State private var runID = 0
    @State private var streamTask: Task<Void, Never>?

    private let sample = """
    # Glimmer Reveal

    Streaming **markdown** that *animates* in — headings, lists, `code`, and \
    [links](https://github.com) reveal in style.

    ## Why it works

    - One renderer for streaming **and** settled output
    - No layout pop at the hand-off
    - Paced by a clock, not the network

    ```swift
    GlimmerRevealView(
        markdown: message.text,
        reveal: RevealConfiguration(style: .wordFade)
    )
    ```

    > The reveal *is* the final view — there is nothing to mismatch.
    """

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Style", selection: $style) {
                    ForEach(RevealStyle.allCases.filter { $0 != .none }) { s in
                        Text(s.displayName).tag(s)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Button("Simulate Stream") { startStreaming() }
                        .buttonStyle(.borderedProminent)
                    Button("Play Full Text") { playFull() }
                        .buttonStyle(.bordered)
                }

                if !buffer.isEmpty {
                    GlimmerRevealView(
                        markdown: buffer,
                        reveal: RevealConfiguration(
                            style: style,
                            catchUp: .adaptive(maxLagSeconds: 1.5),
                            isStreaming: isStreaming,
                            revealID: "demo-\(runID)"
                        ),
                        onLinkTap: { url in print("🔗 Link: \(url)") },
                        onComplete: { print("✅ Reveal complete") }
                    )
                    // New identity per run/style: replays cleanly and lets the
                    // driver pick up the selected style.
                    .id("\(runID)-\(style.rawValue)")
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                } else {
                    Text("Pick a style, then Simulate Stream or Play Full Text.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Streaming Reveal")
        .onChange(of: style) { _, _ in
            if !buffer.isEmpty { playFull() }
        }
        .onDisappear { streamTask?.cancel() }
    }

    /// Feeds the buffer in random 2–8 char chunks every 30–80 ms, like an LLM
    /// token stream. The reveal cadence is independent of this (spec R3).
    private func startStreaming() {
        streamTask?.cancel()
        runID += 1
        buffer = ""
        isStreaming = true
        let full = sample
        streamTask = Task {
            var index = full.startIndex
            while index < full.endIndex, !Task.isCancelled {
                index = full.index(index, offsetBy: Int.random(in: 2...8), limitedBy: full.endIndex) ?? full.endIndex
                buffer = String(full[full.startIndex..<index])
                try? await Task.sleep(nanoseconds: UInt64.random(in: 30_000_000...80_000_000))
            }
            if !Task.isCancelled { isStreaming = false }
        }
    }

    /// One-shot: full text in the buffer, driver reveals it at cadence.
    private func playFull() {
        streamTask?.cancel()
        runID += 1
        isStreaming = false
        buffer = sample
    }
}

#Preview {
    NavigationView {
        StreamingRevealDemo()
    }
}

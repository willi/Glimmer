import Glimmer
import SwiftUI

/// Streams a canned answer through `GlimmerText` with realistic network cadences, to judge the reveal by eye.
struct StreamingLabDemo: View {
    enum Cadence: String, CaseIterable, Identifiable {
        case gemini = "Gemini"
        case bursty = "Bursty"
        case slow = "Slow"
        var id: String { rawValue }
    }

    @State private var cadence: Cadence = .gemini
    @State private var shown = ""
    @State private var isStreaming = false
    @State private var runID = UUID()
    @State private var task: Task<Void, Never>?
    /// While paused no chunk arrives; the answer stays streaming, so the reveal catches up and waits.
    @State private var isPaused = false
    @State private var isDark = false

    var body: some View {
        ScrollView {
            GlimmerText(shown, isStreaming: isStreaming, revealID: runID.uuidString)
                .padding(16)
        }
        .navigationTitle("Streaming Lab")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Picker("Cadence", selection: $cadence) {
                    ForEach(Cadence.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Button(isPaused ? "Resume" : "Pause") { isPaused.toggle() }
                        .buttonStyle(.bordered)
                        .disabled(!isStreaming)
                        .accessibilityIdentifier("streamingLab.pause")
                    Spacer()
                    Button(isStreaming ? "Stop" : "Stream") { isStreaming ? stop() : start() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("streamingLab.toggle")
                }
            }
            .padding()
            .background(.bar)
        }
        .toolbar {
            Toggle("Dark", isOn: $isDark)
                .accessibilityIdentifier("streamingLab.dark")
        }
        .preferredColorScheme(isDark ? .dark : nil)
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--streaming-lab") { start() }
        }
    }

    private func start() {
        task?.cancel()
        runID = UUID()
        shown = ""
        isPaused = false
        isStreaming = true
        let chunks = Self.chunks(of: Self.answer, cadence: cadence)
        task = Task { @MainActor in
            for (text, delay) in chunks {
                try? await Task.sleep(for: delay)
                while isPaused, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(50)) }
                guard !Task.isCancelled else { return }
                shown += text
            }
            isStreaming = false
        }
    }

    private func stop() {
        task?.cancel()
        isPaused = false
        isStreaming = false
    }

    /// The answer split the way a server would send it for `cadence`: each chunk with the delay before it.
    static func chunks(of text: String, cadence: Cadence) -> [(String, Duration)] {
        var generator = SystemRandomNumberGenerator()
        return chunks(of: text, cadence: cadence, using: &generator)
    }

    /// The same, drawing sizes and delays from `generator`: a seeded one gives the same chunks every run.
    static func chunks<G: RandomNumberGenerator>(of text: String, cadence: Cadence, using generator: inout G) -> [(String, Duration)] {
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map { String($0) + " " }
        var result: [(String, Duration)] = []
        var index = 0
        while index < words.count {
            let size: Int
            let delay: Duration
            switch cadence {
            case .gemini:
                size = Int.random(in: 3...8, using: &generator)
                delay = .milliseconds(Int.random(in: 70...230, using: &generator))
            case .bursty:
                size = Int.random(in: 20...60, using: &generator)
                delay = .milliseconds(Int.random(in: 400...1200, using: &generator))
            case .slow:
                size = 1
                delay = .milliseconds(150)
            }
            let end = min(words.count, index + size)
            result.append((words[index..<end].joined(), delay))
            index = end
        }
        return result
    }

    static let answer = """
    # Streaming with Glimmer

    Glimmer reveals an answer **phrase by phrase**, fading each one in while the network keeps sending text. \
    Nothing jumps: text is laid out once, in place, and only the newest phrases change opacity.

    ## How it works

    1. The document re-parses only the open tail.
    2. Each update edits the text view in one transaction.
    3. A Core Animation mask fades new phrases in.

    > Fast streams reveal in longer phrases, so the reveal keeps up without flickering.

    ```swift
    let view = GlimmerView()
    container.addSubview(view)
    view.update(markdown: received, isStreaming: true, revealID: messageID)
    ```

    | Setting | Value |
    |:--|--:|
    | Fade | 0.6 s |
    | Minimum spacing | 60 ms |

    ## Ten steps

    1. Add the package.
    2. Create a view:

       ```swift
       let view = GlimmerView()
       ```

    3. Send it the text received so far.
    4. Pass one reveal ID per message.
    5. Let the height follow the reveal.
    6. Tap a link to open it.
    7. Copy a code block.
    8. Scroll a wide table.
    9. Switch to dark mode.
    10. Watch item 10 arrive without moving the list.

    That's the whole idea — the answer ends here.
    """
}

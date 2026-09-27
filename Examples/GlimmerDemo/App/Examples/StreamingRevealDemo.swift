import Glimmer
import SwiftUI
import UIKit

/// The reveal: pick a host (SwiftUI `GlimmerText` or UIKit `GlimmerView`) and the reveal's options, then simulate an
/// LLM streaming tokens into the buffer or play the full text at once. 1.x's twelve reveal styles are one reveal in
/// 2.0: phrases fade in, paced to the stream.
struct StreamingRevealDemo: View {
    @State private var host = RevealDemoHost.launchSelection
    @State private var isSmooth = true
    @State private var fadeDuration: TimeInterval = 0.6
    @State private var buffer = ""
    @State private var isStreaming = false
    @State private var runID = UUID()
    @State private var streamTask: Task<Void, Never>?
    @State private var lastTap: String?

    private let sample = """
    # Glimmer Reveal

    Streaming **markdown** that *animates* in — headings, lists, `code`, and \
    [links](https://github.com) reveal in style.

    ## Why it works

    - One renderer for streaming **and** settled output
    - No layout pop at the hand-off
    - Paced by a clock, not the network

    ```swift
    GlimmerText(
        message.text,
        isStreaming: message.isStreaming,
        revealID: message.id
    )
    ```

    > The reveal *is* the final view — there is nothing to mismatch.
    """

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Renderer", selection: $host) {
                    ForEach(RevealDemoHost.allCases) { host in
                        Text(host.rawValue).tag(host)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Reveal", selection: $isSmooth) {
                    Text("Smooth").tag(true)
                    Text("None").tag(false)
                }
                .pickerStyle(.segmented)

                if isSmooth {
                    Picker("Fade", selection: $fadeDuration) {
                        Text("Fade 0.3 s").tag(0.3)
                        Text("0.6 s").tag(0.6)
                        Text("1.2 s").tag(1.2)
                    }
                    .pickerStyle(.segmented)
                }

                HStack {
                    Button("Simulate Stream") { startStreaming() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("reveal.stream")
                    Button("Play Full Text") { playFull() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("reveal.playFull")
                }

                if !buffer.isEmpty {
                    Group {
                        if host == .uikit {
                            UIKitRevealDemoContent(
                                markdown: buffer, isStreaming: isStreaming, revealID: runID.uuidString,
                                configuration: configuration, onLinkTap: { lastTap = "UIKit link \($0.absoluteString)" }
                            )
                        } else {
                            GlimmerText(
                                buffer,
                                isStreaming: isStreaming,
                                revealID: runID.uuidString,
                                configuration: configuration,
                                onLinkTap: { lastTap = "Link \($0.absoluteString)" }
                            )
                        }
                    }
                    // A new identity per run and option: replays cleanly and reads the new configuration.
                    .id("\(runID)-\(host.rawValue)-\(isSmooth)-\(fadeDuration)")
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    Text("Pick the options, then Simulate Stream or Play Full Text.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) { DemoTapBanner(text: lastTap) }
        .navigationTitle("Streaming Reveal")
        .onChange(of: isSmooth) { _, _ in replay() }
        .onChange(of: fadeDuration) { _, _ in replay() }
        .onChange(of: host) { _, _ in replay() }
        .task {
            if ProcessInfo.processInfo.arguments.contains("--reveal-autoplay"), buffer.isEmpty {
                startStreaming()
            }
        }
        .onDisappear { streamTask?.cancel() }
    }

    private var configuration: GlimmerConfiguration {
        var options = GlimmerRevealOptions()
        options.fadeDuration = fadeDuration
        return GlimmerConfiguration(reveal: isSmooth ? .smooth(options) : .none)
    }

    private func replay() {
        if isStreaming { startStreaming() } else if !buffer.isEmpty { playFull() }
    }

    /// Feeds the buffer in random 2–8 character chunks every 30–80 ms, like an LLM token stream, with one pause a
    /// third of the way in. The view gets only what has arrived, unfinished markdown included.
    private func startStreaming() {
        streamTask?.cancel()
        runID = UUID()
        buffer = ""
        isStreaming = true
        let full = sample
        streamTask = Task {
            var index = full.startIndex
            let pauseIndex = full.index(full.startIndex, offsetBy: full.count / 3)
            var didPause = false
            while index < full.endIndex, !Task.isCancelled {
                index = full.index(index, offsetBy: Int.random(in: 2...8), limitedBy: full.endIndex) ?? full.endIndex
                buffer = String(full[full.startIndex..<index])
                if !didPause, index >= pauseIndex {
                    didPause = true
                    try? await Task.sleep(for: .milliseconds(900))
                }
                try? await Task.sleep(for: .milliseconds(Int.random(in: 30...80)))
            }
            if !Task.isCancelled { isStreaming = false }
        }
    }

    /// The whole text at once: it arrives as one streamed update, then the stream ends, and the reveal plays it out.
    private func playFull() {
        streamTask?.cancel()
        runID = UUID()
        buffer = sample
        isStreaming = true
        streamTask = Task {
            await Task.yield()
            if !Task.isCancelled { isStreaming = false }
        }
    }
}

private enum RevealDemoHost: String, CaseIterable, Identifiable {
    case swiftui = "SwiftUI"
    case uikit = "UIKit"

    var id: String { rawValue }

    static var launchSelection: Self {
        ProcessInfo.processInfo.arguments.contains("--reveal-host=uikit") ? .uikit : .swiftui
    }
}

/// The UIKit host: a view controller that owns a `GlimmerView`, as a UIKit chat screen embeds it.
private struct UIKitRevealDemoContent: UIViewControllerRepresentable {
    let markdown: String
    let isStreaming: Bool
    let revealID: String
    let configuration: GlimmerConfiguration
    let onLinkTap: (URL) -> Void

    func makeUIViewController(context: Context) -> RevealViewController {
        RevealViewController(configuration: configuration)
    }

    func updateUIViewController(_ controller: RevealViewController, context: Context) {
        controller.answerView.onLinkTap = onLinkTap
        controller.answerView.update(markdown: markdown, isStreaming: isStreaming, revealID: revealID)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: RevealViewController, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return uiViewController.answerView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}

/// Pins a `GlimmerView` to its edges and asks SwiftUI to re-measure when the answer's height changes.
final class RevealViewController: UIViewController {
    let answerView: GlimmerView

    init(configuration: GlimmerConfiguration) {
        answerView = GlimmerView(configuration: configuration)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        answerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(answerView)
        NSLayoutConstraint.activate([
            answerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            answerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            answerView.topAnchor.constraint(equalTo: view.topAnchor),
        ])
        answerView.onHeightChange = { [weak self] in self?.view.invalidateIntrinsicContentSize() }
    }
}

#Preview {
    NavigationStack { StreamingRevealDemo() }
}

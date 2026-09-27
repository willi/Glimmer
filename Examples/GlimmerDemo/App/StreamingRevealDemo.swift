import SwiftUI
import UIKit
import Glimmer

/// Demo for `GlimmerRevealView`: choose a reveal style and a host, then
/// either simulate an LLM streaming tokens into the buffer or play the full
/// text one-shot. Headings, lists, code, links, and quotes demonstrate rich
/// markdown while incoming chunks may contain unfinished syntax.
struct StreamingRevealDemo: View {
    @State private var style: RevealStyle = .smoothTrail
    @State private var host = RevealDemoHost.launchSelection
    @State private var buffer = ""
    @State private var isStreaming = false
    @State private var runID = UUID()
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
        reveal: RevealConfiguration(style: .smoothTrail)
    )
    ```

    > The reveal *is* the final view — there is nothing to mismatch.
    """

    private let nativeSample = """
    Native UIKit streaming.

    New words arrive softly, then brighten into crisp, readable text. The trail keeps settling when the stream pauses, just as it does while more words arrive.

    This is a real UITextView with UIKit fonts, attributed text, native selection, and a tappable Glimmer link. There is no Markdown parsing in this mode.

    A short pause partway through this sample lets you watch the last words finish fading. When the stream resumes, previously revealed words stay steady.
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

                if host == .native {
                    Text("Smooth Trail · native attributed text · no Markdown parsing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Style", selection: $style) {
                        ForEach(RevealStyle.allCases.filter { $0 != .none }) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack {
                    Button("Simulate Stream") { startStreaming() }
                        .buttonStyle(.borderedProminent)
                    Button("Play Full Text") { playFull() }
                        .buttonStyle(.bordered)
                }

                if !buffer.isEmpty {
                    Group {
                        if host == .native {
                            NativeTrailDemoContent(attributedText: nativeAttributedBuffer, isStreaming: isStreaming)
                        } else if host == .uikit {
                            UIKitRevealDemoContent(markdown: buffer, reveal: revealConfiguration)
                        } else {
                            GlimmerRevealView(
                                markdown: buffer,
                                reveal: revealConfiguration,
                                onLinkTap: { url in print("🔗 Link: \(url)") },
                                onComplete: { print("✅ Reveal complete") }
                            )
                        }
                    }
                    // New identity per run/style: replays cleanly and lets the
                    // driver pick up the selected style.
                    .id("\(runID)-\(host.rawValue)-\(style.rawValue)")
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
        .onChange(of: host) { _, _ in
            if isStreaming { startStreaming() }
            else if !buffer.isEmpty { playFull() }
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("--reveal-autoplay"), buffer.isEmpty {
                startStreaming()
            }
        }
        .onDisappear { streamTask?.cancel() }
    }

    private var activeSample: String { host == .native ? nativeSample : sample }

    private var nativeAttributedBuffer: NSAttributedString {
        let font = UIFont.preferredFont(forTextStyle: .body)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let text = NSMutableAttributedString(string: buffer, attributes: [
            .font: font, .foregroundColor: UIColor.label, .paragraphStyle: paragraph
        ])
        let string = buffer as NSString
        let newline = string.range(of: "\n").location
        let firstLine = NSRange(location: 0, length: newline == NSNotFound ? string.length : newline)
        if let bold = font.fontDescriptor.withSymbolicTraits(.traitBold), firstLine.length > 0 {
            text.addAttribute(.font, value: UIFont(descriptor: bold, size: font.pointSize), range: firstLine)
        }
        let link = string.range(of: "Glimmer link")
        if link.location != NSNotFound, let url = URL(string: "https://github.com") {
            text.addAttributes([.link: url, .foregroundColor: UIColor.link], range: link)
        }
        return text
    }

    private var revealConfiguration: RevealConfiguration {
        RevealConfiguration(
            style: style,
            catchUp: .adaptive(maxLagSeconds: 1.5),
            isStreaming: isStreaming,
            revealID: "demo-\(runID)-\(style.rawValue)"
        )
    }

    /// Feeds the buffer in random 2–8 char chunks every 30–80 ms, like an LLM
    /// token stream. Only received text is provided to the renderer, including
    /// temporarily incomplete markdown syntax from actual streaming prefixes.
    private func startStreaming() {
        streamTask?.cancel()
        runID = UUID()
        buffer = ""
        isStreaming = true
        let full = activeSample
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
                try? await Task.sleep(nanoseconds: UInt64.random(in: 30_000_000...80_000_000))
            }
            if !Task.isCancelled { isStreaming = false }
        }
    }

    /// One-shot: full text in the buffer, driver reveals it at cadence.
    private func playFull() {
        streamTask?.cancel()
        runID = UUID()
        isStreaming = false
        buffer = activeSample
    }
}

private enum RevealDemoHost: String, CaseIterable, Identifiable {
    case swiftui = "SwiftUI"
    case uikit = "UIKit Markdown"
    case native = "UIKit TextKit"

    var id: String { rawValue }

    static var launchSelection: Self {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--reveal-host=native") { return .native }
        if arguments.contains("--reveal-host=uikit") { return .uikit }
        return .swiftui
    }
}

private struct NativeTrailDemoContent: UIViewRepresentable {
    let attributedText: NSAttributedString
    let isStreaming: Bool

    func makeUIView(context: Context) -> GlimmerTrailTextView {
        GlimmerTrailTextView()
    }

    func updateUIView(_ textView: GlimmerTrailTextView, context: Context) {
        textView.update(attributedText: attributedText, isStreaming: isStreaming)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: GlimmerTrailTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}

/// Exercises the same controller API a UIKit chat screen embeds directly.
private struct UIKitRevealDemoContent: UIViewControllerRepresentable {
    let markdown: String
    let reveal: RevealConfiguration

    func makeUIViewController(context: Context) -> GlimmerRevealViewController {
        GlimmerRevealViewController(
            markdown: markdown,
            reveal: reveal,
            onLinkTap: { url in print("🔗 UIKit link: \(url)") },
            onComplete: { print("✅ UIKit reveal complete") }
        )
    }

    func updateUIViewController(_ controller: GlimmerRevealViewController, context: Context) {
        controller.update(markdown: markdown, isStreaming: reveal.isStreaming)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiViewController: GlimmerRevealViewController,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return uiViewController.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}

#Preview {
    NavigationView {
        StreamingRevealDemo()
    }
}

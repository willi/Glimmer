import SwiftUI

/// Renders streaming markdown with per-unit animated reveal, settling into
/// Glimmer's normal rich rendering with zero visual mismatch — the reveal
/// path IS the settled path (spec settle strategy A).
public struct GlimmerRevealView: View {
    private let markdown: String
    private let reveal: RevealConfiguration
    private let configuration: MarkdownConfiguration
    private let onLinkTap: ((URL) -> Void)?
    private let onComplete: (() -> Void)?

    @State private var model: RevealModel = .empty
    @State private var driver: RevealDriver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    /// - Note: `reveal.style` and `reveal.revealID` are captured when the view
    ///   identity is created. To switch styles mid-stream, give the view a new
    ///   identity (e.g. `.id(style)`).
    public init(
        markdown: String,
        reveal: RevealConfiguration,
        configuration: MarkdownConfiguration = .default,
        onLinkTap: ((URL) -> Void)? = nil,
        onComplete: (() -> Void)? = nil
    ) {
        self.markdown = markdown
        self.reveal = reveal
        self.configuration = configuration
        self.onLinkTap = onLinkTap
        self.onComplete = onComplete
        _driver = State(initialValue: RevealDriver(configuration: reveal))
    }

    public var body: some View {
        if reveal.style == .none {
            // Opt-out: today's behavior, no reveal machinery (spec R12).
            MarkdownView(markdown: markdown, configuration: configuration, onLinkTap: onLinkTap)
                .onAppear { onComplete?() }
        } else {
            revealBody
        }
    }

    private var effectiveTreatment: RevealTreatment {
        reduceMotion ? .plain : reveal.style.treatment
    }

    private var revealBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(visibleBlocks) { block in
                RevealBlockView(
                    block: block,
                    revealedCount: driver.revealedCount,
                    animateFrom: driver.animateFrom,
                    treatment: effectiveTreatment,
                    showCaret: showCaret(for: block),
                    configuration: configuration,
                    onLinkTap: handleLink
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(fullPlainText))
        .onChange(of: markdown, initial: true) { _, newValue in
            rebuild(newValue)
        }
        .onChange(of: reveal.isStreaming) { _, streaming in
            driver.update(totalCountable: model.countableCount, isStreaming: streaming)
        }
        .task {
            await driver.run()
            if driver.isComplete { onComplete?() }
        }
    }

    private var visibleBlocks: [RevealBlock] {
        if effectiveTreatment == .scramble {
            // Diffusion shows all buffered text as scramble noise that locks in.
            return model.blocks
        }
        return model.blocks.filter { $0.firstRevealIndex <= driver.revealedCount }
    }

    private func showCaret(for block: RevealBlock) -> Bool {
        guard effectiveTreatment == .caret, !driver.isComplete else { return false }
        return block.id == visibleBlocks.last?.id
    }

    private func rebuild(_ markdown: String) {
        // Parse once per buffer change (spec R10); advancing the counter never
        // re-parses. Glimmer.parse goes through the shared LRU parse cache.
        let blocks = Glimmer.parse(markdown, configuration: configuration)
        model = RevealFlattener.flatten(
            blocks, granularity: reveal.style.granularity, configuration: configuration
        )
        driver.update(totalCountable: model.countableCount, isStreaming: reveal.isStreaming)
    }

    /// VoiceOver reads the full current text, not per-word fragments (R11).
    private var fullPlainText: String {
        model.blocks.flatMap(\.words).flatMap(\.atoms).reduce(into: "") { acc, atom in
            switch atom.kind {
            case .text(let s), .space(let s): acc += String(s.characters)
            case .lineBreak: acc += "\n"
            case .block: break
            }
        }
    }

    private func handleLink(_ url: URL) {
        if let onLinkTap {
            onLinkTap(url)
        } else {
            openURL(url)
        }
    }
}

// MARK: - One-shot demo mode (spec R9)

public extension GlimmerRevealView {
    /// Plays the reveal once over a fixed string; long inputs are compressed
    /// to fit `durationCap` seconds.
    static func demo(
        _ markdown: String,
        style: RevealStyle,
        durationCap: Double? = 6,
        configuration: MarkdownConfiguration = .default
    ) -> GlimmerRevealView {
        GlimmerRevealView(
            markdown: markdown,
            reveal: RevealConfiguration(
                style: style,
                isStreaming: false,
                demoDurationCap: durationCap
            ),
            configuration: configuration
        )
    }
}

// MARK: - Per-block reveal rendering

struct RevealBlockView: View {
    let block: RevealBlock
    let revealedCount: Int
    let animateFrom: Int
    let treatment: RevealTreatment
    let showCaret: Bool
    let configuration: MarkdownConfiguration
    let onLinkTap: (URL) -> Void

    var body: some View {
        switch block.kind {
        case .paragraph, .heading:
            inlineContent
        case .listItem(let marker, let depth):
            HStack(alignment: .top, spacing: 0) {
                Text(marker).font(configuration.baseFont)
                inlineContent
            }
            .padding(.leading, CGFloat(depth) * 16)
        case .blockquote(let depth):
            HStack(spacing: 12) {
                Rectangle()
                    .fill(configuration.blockquoteColor)
                    .frame(width: 4)
                inlineContent
            }
            .padding(.leading, CGFloat(max(0, depth - 1)) * 16)
        case .wholeBlock:
            if let node = block.node {
                // Whole-unit blocks render via Glimmer's existing block view,
                // entering with a block-level fade when revealed (spec 4.6).
                MarkdownBlockView(block: node, configuration: configuration, depth: 0)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder private var inlineContent: some View {
        switch treatment {
        case .plain, .caret:
            RevealPrefixTextView(block: block, revealedCount: revealedCount, showCaret: showCaret)
        case .scramble:
            RevealScrambleTextView(block: block, revealedCount: revealedCount)
        default:
            RevealFlowLayout(lineSpacing: 2) {
                ForEach(visibleWords) { word in
                    wordView(word)
                }
            }
        }
    }

    private var visibleWords: [RevealWord] {
        block.words.filter { word in
            word.atoms.contains { $0.revealIndex <= revealedCount }
        }
    }

    @ViewBuilder private func wordView(_ word: RevealWord) -> some View {
        if word.isLineBreak {
            Color.clear
                .frame(width: 0, height: 0)
                .revealLineBreak()
        } else if word.isWhitespace {
            if case .space(let s) = word.atoms[0].kind {
                Text(s)
            }
        } else {
            if let url = word.atoms.first?.url {
                HStack(spacing: 0) {
                    ForEach(word.atoms.filter { $0.revealIndex <= revealedCount }) { atom in
                        if case .text(let s) = atom.kind {
                            RevealUnitView(
                                attributed: s,
                                treatment: treatment,
                                animate: atom.revealIndex > animateFrom
                            )
                        }
                    }
                }
                .accessibilityHidden(true)
                .contentShape(Rectangle())
                .onTapGesture { onLinkTap(url) }
            } else {
                HStack(spacing: 0) {
                    ForEach(word.atoms.filter { $0.revealIndex <= revealedCount }) { atom in
                        if case .text(let s) = atom.kind {
                            RevealUnitView(
                                attributed: s,
                                treatment: treatment,
                                animate: atom.revealIndex > animateFrom
                            )
                        }
                    }
                }
                .accessibilityHidden(true)
            }
        }
    }
}

/// Plain/caret styles: the revealed prefix renders as ONE growing Text so
/// line wrapping is native; a blinking caret is appended while streaming.
struct RevealPrefixTextView: View {
    let block: RevealBlock
    let revealedCount: Int
    let showCaret: Bool

    private var prefix: AttributedString {
        var result = AttributedString()
        for atom in block.words.flatMap(\.atoms) where atom.revealIndex <= revealedCount {
            switch atom.kind {
            case .text(let s), .space(let s): result.append(s)
            case .lineBreak: result.append(AttributedString("\n"))
            case .block: break
            }
        }
        return result
    }

    var body: some View {
        if showCaret {
            caretView
        } else {
            Text(prefix)
        }
    }

    private var caretView: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            caretText(date: context.date)
        }
    }

    private func caretText(date: Date) -> Text {
        let on = Int(date.timeIntervalSinceReferenceDate * 2).isMultiple(of: 2)
        return Text(prefix) + Text(on ? "▍" : " ")
    }
}

/// Diffusion style: buffered-but-unrevealed characters show random glyphs
/// (re-randomized by one shared TimelineView — no per-glyph timers, spec R10),
/// locking to the real glyph when revealed.
struct RevealScrambleTextView: View {
    let block: RevealBlock
    let revealedCount: Int

    private static let glyphs: [Character] = Array(
        "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz0123456789@#%&*+=<>/?"
    )

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.055)) { _ in
            RevealFlowLayout(lineSpacing: 2) {
                ForEach(block.words) { word in
                    if word.isLineBreak {
                        Color.clear
                            .frame(width: 0, height: 0)
                            .revealLineBreak()
                    } else if word.isWhitespace {
                        if case .space(let s) = word.atoms[0].kind {
                            Text(s)
                        }
                    } else {
                        HStack(spacing: 0) {
                            ForEach(word.atoms) { atom in
                                if case .text(let s) = atom.kind {
                                    if atom.revealIndex <= revealedCount {
                                        Text(s)
                                    } else {
                                        Text(scrambled(s)).opacity(0.7)
                                    }
                                }
                            }
                        }
                        .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    /// Replaces the glyph but keeps the atom's attributes (font/size match).
    private func scrambled(_ s: AttributedString) -> AttributedString {
        var copy = s
        let glyph = Self.glyphs.randomElement() ?? "x"
        copy.characters.replaceSubrange(
            copy.characters.startIndex..<copy.characters.endIndex, with: [glyph]
        )
        return copy
    }
}

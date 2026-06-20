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
    @State private var revealSession: RevealSession
    @State private var fullPlainText: String = ""
    @State private var didComplete = false
    @State private var hasBuiltModel = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    /// - Note: the entire `RevealConfiguration` except `isStreaming` is
    ///   captured when the view identity is created (style, catch-up policy,
    ///   `revealID`, duration cap). To change any of them mid-stream, give the
    ///   view a new identity (e.g. `.id(style)`). Hosts that re-mount the view
    ///   (lazy lists, optimistic→final message swaps) should set `revealID` so
    ///   progress resumes instead of replaying (spec R6).
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
        _revealSession = State(initialValue: RevealSession(
            granularity: reveal.style.granularity,
            configuration: configuration
        ))
    }

    public var body: some View {
        if shouldRenderSettledContent {
            settledContent
            .onAppear { fireCompletionOnce() }
        } else {
            revealBody
        }
    }

    private var shouldRenderSettledContent: Bool {
        reveal.style == .none
            || (!reveal.isStreaming && hasBuiltModel && driver.revealedCount >= model.countableCount)
    }

    private var settledContent: some View {
        // Opt-out/settled rendering uses Glimmer's canonical interactive block
        // tree so the final animated state is identical to normal markdown.
        InteractiveMarkdownContent(
            blocks: Glimmer.parse(markdown, configuration: configuration),
            configuration: configuration,
            onLinkTap: handleLink,
            onMentionTap: nil,
            onIssueTap: nil,
            onFootnoteTap: nil
        )
    }

    private var effectiveTreatment: RevealTreatment {
        reduceMotion ? .plain : reveal.style.treatment
    }

    private var revealBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(visibleBlocks, id: \.viewIdentity) { block in
                RevealBlockView(
                    block: block,
                    revealedCount: driver.revealedCount,
                    animateFrom: driver.animateFrom,
                    treatment: effectiveTreatment,
                    showCaret: showCaret(for: block),
                    isComplete: driver.isComplete,
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
            if driver.isComplete { fireCompletionOnce() }
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
        // re-parses. Append-only streams reuse previously flattened blocks
        // when the last buffer ended at a conservative block boundary.
        model = revealSession.update(markdown)
        hasBuiltModel = true
        driver.update(totalCountable: model.countableCount, isStreaming: reveal.isStreaming)
        // Cache VoiceOver text so it isn't recomputed on every body evaluation (Fix 6).
        fullPlainText = model.blocks.flatMap(\.words).flatMap(\.atoms).reduce(into: "") { acc, atom in
            switch atom.kind {
            case .text(let s), .space(let s): acc += String(s.characters)
            case .lineBreak: acc += "\n"
            case .block: break
            }
        }
    }

    private func fireCompletionOnce() {
        guard !didComplete else { return }
        didComplete = true
        onComplete?()
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
    let isComplete: Bool
    let configuration: MarkdownConfiguration
    let onLinkTap: (URL) -> Void

    var body: some View {
        if isFullyRevealed, let node = block.node {
            InteractiveBlockView(
                block: node,
                configuration: configuration,
                onLinkTap: onLinkTap,
                onMentionTap: nil,
                onIssueTap: nil,
                onFootnoteTap: nil
            )
        } else {
            revealContent
        }
    }

    @ViewBuilder private var revealContent: some View {
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
                // Whole-unit blocks use the same renderer as settled markdown,
                // entering with a block-level fade when revealed.
                InteractiveBlockView(
                    block: node,
                    configuration: configuration,
                    onLinkTap: onLinkTap,
                    onMentionTap: nil,
                    onIssueTap: nil,
                    onFootnoteTap: nil
                )
                    .transition(.opacity)
            }
        }
    }

    private var isFullyRevealed: Bool {
        !block.words.contains { word in
            word.atoms.contains { atom in
                atom.isCountable && atom.revealIndex > revealedCount
            }
        }
    }

    @ViewBuilder private var inlineContent: some View {
        switch treatment {
        case .plain, .caret:
            RevealPrefixTextView(block: block, revealedCount: revealedCount, showCaret: showCaret)
        case .scramble:
            RevealScrambleTextView(block: block, revealedCount: revealedCount)
        case .trailFade:
            RevealTrailTextView(
                block: block,
                revealedCount: revealedCount,
                isComplete: isComplete,
                onLinkTap: onLinkTap
            )
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

/// Trail-fade style (Gemini-like): words stream in fast behind a soft opacity
/// gradient — the word at the reveal cursor is faintest and brightens as the
/// cursor sweeps past. Opacity is a pure function of distance from the cursor
/// (`RevealTrail`), so the whole trail brightens smoothly on every tick and
/// snaps to full opacity on completion.
struct RevealTrailTextView: View {
    let block: RevealBlock
    let revealedCount: Int
    let isComplete: Bool
    let onLinkTap: (URL) -> Void

    var body: some View {
        RevealFlowLayout(lineSpacing: 2) {
            ForEach(visibleWords) { word in
                wordView(word)
            }
        }
        .animation(.easeOut(duration: 0.4), value: revealedCount)
        .animation(.easeOut(duration: 0.6), value: isComplete)
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
        } else if case .text(let s) = word.atoms[0].kind {
            let opacity = RevealTrail.opacity(
                revealIndex: word.atoms[0].revealIndex,
                revealedCount: revealedCount,
                isComplete: isComplete
            )
            if let url = word.atoms[0].url {
                Text(s)
                    .opacity(opacity)
                    .accessibilityHidden(true)
                    .contentShape(Rectangle())
                    .onTapGesture { onLinkTap(url) }
            } else {
                Text(s)
                    .opacity(opacity)
                    .accessibilityHidden(true)
            }
        }
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

    /// True when every countable atom in the block is at or below revealedCount.
    private var isFullyRevealed: Bool {
        !block.words.contains { word in
            word.atoms.contains { $0.isCountable && $0.revealIndex > revealedCount }
        }
    }

    var body: some View {
        if isFullyRevealed {
            // Fully revealed: stop the 55ms timeline; nothing left to scramble (R10).
            flowContent { s in s }
        } else {
            TimelineView(.periodic(from: .now, by: 0.055)) { _ in
                flowContent { s in scrambled(s) }
            }
        }
    }

    /// Flow layout content, parameterized by a transform applied to unrevealed atoms.
    @ViewBuilder private func flowContent(
        unrevealed transform: @escaping (AttributedString) -> AttributedString
    ) -> some View {
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
                                    Text(transform(s)).opacity(0.7)
                                }
                            }
                        }
                    }
                    .accessibilityHidden(true)
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

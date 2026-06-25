// MARK: - Granularity & Treatment

/// The unit a reveal style unlocks at a time (spec R1).
public enum RevealGranularity: Sendable, Equatable {
    case character, word, line
}

/// The entrance animation applied to each newly revealed unit (spec 4.5).
public enum RevealTreatment: Sendable, Equatable {
    case plain, caret, fade, blur, slide, dropIn, tracking, glow, shimmer, scramble
    /// Soft opacity gradient trailing the reveal cursor (Gemini-like): the
    /// newest words are faintest and brighten as the cursor moves past.
    case trailFade
}

// MARK: - RevealStyle

/// A named reveal style: granularity + cadence + treatment (spec 4.2, appendix).
public enum RevealStyle: String, CaseIterable, Identifiable, Sendable, Equatable {
    /// No reveal: `GlimmerRevealView` renders the full document via the
    /// standard `MarkdownView` path and never starts the reveal driver.
    /// (Named `none` to match the reveal spec; avoid `RevealStyle?` in API
    /// signatures so this never collides with `Optional.none`.)
    case none
    case typewriter
    case llmTokens
    case wordFade
    case blurIn
    case lineSlide
    case charCascade
    case shimmer
    case tracking
    case diffusion
    case waveGlow
    case trailFade

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: "None"
        case .typewriter: "Typewriter"
        case .llmTokens: "LLM Tokens"
        case .wordFade: "Word Fade"
        case .blurIn: "Blur-In"
        case .lineSlide: "Line Slide"
        case .charCascade: "Char Cascade"
        case .shimmer: "Shimmer"
        case .tracking: "Tracking"
        case .diffusion: "Diffusion"
        case .waveGlow: "Wave Glow"
        case .trailFade: "Trail Fade"
        }
    }

    public var granularity: RevealGranularity {
        switch self {
        case .typewriter, .llmTokens, .charCascade, .diffusion: .character
        case .lineSlide: .line
        case .none, .wordFade, .blurIn, .shimmer, .tracking, .waveGlow, .trailFade: .word
        }
    }

    public var treatment: RevealTreatment {
        switch self {
        case .none, .llmTokens: .plain
        case .typewriter: .caret
        case .wordFade: .fade
        case .blurIn: .blur
        case .lineSlide: .slide
        case .charCascade: .dropIn
        case .shimmer: .shimmer
        case .tracking: .tracking
        case .diffusion: .scramble
        case .waveGlow: .glow
        case .trailFade: .trailFade
        }
    }

    /// Nominal milliseconds between units; a non-degenerate range expresses jitter.
    public var nominalUnitIntervalMs: ClosedRange<Double> {
        switch self {
        case .none: 0...0
        case .typewriter: 18...42
        case .llmTokens: 60...140
        case .wordFade: 75...75
        case .blurIn: 100...100
        case .lineSlide: 320...320
        case .charCascade: 22...22
        case .shimmer: 85...85
        case .tracking: 100...100
        case .diffusion: 22...40
        case .waveGlow: 105...105
        case .trailFade: 75...75
        }
    }

    /// Units unlocked per tick (LLM-token chunks unlock 1-4 chars at once).
    public var unitsPerStep: ClosedRange<Int> {
        switch self {
        case .llmTokens: 1...4
        case .none, .typewriter, .wordFade, .blurIn, .lineSlide,
             .charCascade, .shimmer, .tracking, .diffusion, .waveGlow, .trailFade: 1...1
        }
    }
}

// MARK: - Catch-up & configuration

/// How the reveal cadence reacts when the buffer races ahead (spec R4).
public enum CatchUpPolicy: Sendable, Equatable {
    /// Always the exact style cadence, regardless of backlog.
    case strict
    /// Accelerate (shorten intervals, down to 0.25x) to keep lag within bound.
    /// `maxLagSeconds` must be > 0.
    case adaptive(maxLagSeconds: Double)
    /// Exact cadence until lag exceeds the cap, then snap to fully revealed.
    /// `maxLagSeconds` must be > 0.
    case cappedSnap(maxLagSeconds: Double)
}

/// Host-supplied reveal settings for `GlimmerRevealView` (spec 4.3).
public struct RevealConfiguration: Sendable, Equatable {
    public var style: RevealStyle
    public var catchUp: CatchUpPolicy
    /// True while the producer is still appending to the buffer.
    public var isStreaming: Bool
    /// Stable id (e.g. chat turn id) for cross-remount resume (spec R6).
    public var revealID: String?
    /// One-shot mode: scale intervals so the whole reveal fits in N seconds (spec R9).
    public var demoDurationCap: Double?
    /// A small one-shot delay before the very first unit is revealed (only for a
    /// fresh run, i.e. nothing resumed). Lets a little buffer accumulate so the
    /// reveal eases in instead of unlocking the first word the instant the first
    /// token lands — makes a live stream feel smoother. Default 0 (no delay).
    public var startDelay: Double

    public init(
        style: RevealStyle = .wordFade,
        catchUp: CatchUpPolicy = .adaptive(maxLagSeconds: 1.5),
        isStreaming: Bool = false,
        revealID: String? = nil,
        demoDurationCap: Double? = nil,
        startDelay: Double = 0
    ) {
        self.style = style
        self.catchUp = catchUp
        self.isStreaming = isStreaming
        self.revealID = revealID
        self.demoDurationCap = demoDurationCap
        self.startDelay = max(0, startDelay)
    }
}

// MARK: - Block tags

/// Layout-relevant classification of the block that owns an atom (spec 4.1).
public enum BlockKindTag: Sendable, Equatable {
    case paragraph
    case heading(level: Int)
    case listItem(marker: String, depth: Int)
    case blockquote(depth: Int)
    case codeBlock(language: String?)
    case table
    /// Structural markdown that must keep canonical layout - thematic breaks,
    /// raw HTML, or image paragraphs - revealed as one unit via the existing
    /// block view.
    case wholeBlock
}

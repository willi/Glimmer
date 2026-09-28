import Foundation

/// Tuning for the streaming reveal: phrases paced against the arriving text, each fading in (spec §5).
public struct GlimmerRevealOptions: Equatable, Sendable {
    /// Seconds for a phrase to fade from transparent to opaque (linear).
    public var fadeDuration: TimeInterval = 0.6
    /// The slowest reveal speed, in UTF-16 characters per second.
    public var baseRate: Double = 60
    /// How far behind the arrived text the reveal aims to stay while streaming.
    public var targetLag: TimeInterval = 0.4
    /// Once streaming ends, the remaining text is revealed within about this long.
    public var drainDuration: TimeInterval = 1.5
    /// The smallest gap between two phrase starts. Fast streams get longer phrases instead of faster starts.
    public var minPhraseSpacing: TimeInterval = 0.06
    /// How gradually the speed follows the backlog; larger is smoother.
    public var rateSmoothing: TimeInterval = 0.25
    public var minPhraseWords = 3
    public var maxPhraseWords = 8

    public init() {}
}

/// Whether and how a streaming answer is revealed.
public enum GlimmerReveal: Equatable, Sendable {
    /// Text appears as soon as it arrives.
    case none
    /// Gemini-style phrase fades paced against the arriving text.
    case smooth(GlimmerRevealOptions)
}

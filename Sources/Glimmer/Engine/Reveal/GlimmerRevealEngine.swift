import Foundation

/// Decides what is revealed when. Works on UTF-16 offsets and seconds only (no UIKit), so it is unit-tested with a
/// hand-driven clock. `GlimmerView` feeds it the text and the time; `GlimmerRevealMask` draws its state.
struct GlimmerRevealEngine {
    struct Phrase: Equatable {
        var range: NSRange
        var start: TimeInterval
    }

    let options: GlimmerRevealOptions
    /// Phrases that have started but not finished fading, oldest first.
    private(set) var phrases: [Phrase] = []
    /// Characters covered by started phrases.
    private(set) var revealedLength: Int
    /// Characters whose fade has finished.
    private(set) var settledLength: Int
    private(set) var isStreaming = true
    private(set) var nextPhraseStart: TimeInterval?

    private var text: NSString = ""
    private var pacing: GlimmerPacing
    /// When the next phrase may start once more text arrives, if the reveal is waiting for text.
    private var earliestNextStart: TimeInterval?

    init(options: GlimmerRevealOptions, alreadyRevealed: Int = 0) {
        self.options = options
        pacing = GlimmerPacing(options: options)
        revealedLength = alreadyRevealed
        settledLength = alreadyRevealed
    }

    /// The whole current text. What was revealed stays revealed, clamped if the text got shorter.
    mutating func textChanged(_ text: NSString, isStreaming: Bool, now: TimeInterval) {
        self.text = text
        self.isStreaming = isStreaming
        revealedLength = min(revealedLength, text.length)
        settledLength = min(settledLength, revealedLength)
        phrases = phrases.compactMap { phrase in
            let end = min(NSMaxRange(phrase.range), revealedLength)
            guard end > phrase.range.location else { return nil }
            return Phrase(range: NSRange(location: phrase.range.location, length: end - phrase.range.location), start: phrase.start)
        }
        if nextPhraseStart == nil, revealedLength < text.length {
            nextPhraseStart = max(now, earliestNextStart ?? now)
        }
    }

    /// Starts every phrase due by `now` and settles every fade finished by `now`.
    mutating func advance(to now: TimeInterval) {
        while let due = nextPhraseStart, due <= now {
            pacing.updateRate(backlog: text.length - revealedLength, isStreaming: isStreaming, now: due)
            guard var end = chunk(from: revealedLength) else {
                nextPhraseStart = nil
                earliestNextStart = due
                break
            }
            // Fast streams: grow the phrase instead of starting phrases closer than `minPhraseSpacing`.
            while end - revealedLength < pacing.minimumPhraseLength, end < text.length, let next = chunk(from: end) {
                end = next
            }
            let phrase = Phrase(range: NSRange(location: revealedLength, length: end - revealedLength), start: due)
            phrases.append(phrase)
            revealedLength = end
            nextPhraseStart = due + pacing.interval(forPhraseLength: phrase.range.length)
        }
        while let first = phrases.first, first.start + options.fadeDuration <= now {
            phrases.removeFirst()
            settledLength = NSMaxRange(first.range)
        }
        if phrases.isEmpty { settledLength = revealedLength }
    }

    /// The next time `advance(to:)` has work to do, or nil when idle.
    var nextWake: TimeInterval? {
        let start = revealedLength < text.length ? nextPhraseStart : nil
        return [start, phrases.first.map { $0.start + options.fadeDuration }].compactMap { $0 }.min()
    }

    var isComplete: Bool {
        !isStreaming && revealedLength >= text.length && phrases.isEmpty
    }

    private func chunk(from start: Int) -> Int? {
        GlimmerPhraseChunker.phraseEnd(in: text, from: start, isStreaming: isStreaming,
                                       minWords: options.minPhraseWords, maxWords: options.maxPhraseWords)
    }
}

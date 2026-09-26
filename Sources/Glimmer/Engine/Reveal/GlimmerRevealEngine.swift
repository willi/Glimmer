import Foundation

/// Decides what is revealed when. Works on UTF-16 offsets and seconds only (no UIKit), so it is unit-tested with a
/// hand-driven clock. `GlimmerView` feeds it the text and the time; `GlimmerRevealMask` draws its state.
struct GlimmerRevealEngine {
    struct Phrase: Equatable {
        var range: NSRange
        var start: TimeInterval
        /// For a phrase inside an embed: which reveal unit (code line, table row) it shows.
        var unit: Int? = nil
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
    /// Embeds that reveal in units: attachment offset → each unit's text length.
    private(set) var embedUnits: [Int: [Int]] = [:]
    /// Units started, per embed offset.
    private(set) var unitsRevealed: [Int: Int] = [:]
    /// Units whose fade has finished, per embed offset.
    private(set) var unitsSettled: [Int: Int] = [:]

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
    mutating func textChanged(_ text: NSString, isStreaming: Bool, now: TimeInterval, embedUnits: [Int: [Int]] = [:]) {
        self.text = text
        self.isStreaming = isStreaming
        self.embedUnits = embedUnits
        revealedLength = min(revealedLength, text.length)
        settledLength = min(settledLength, revealedLength)
        phrases = phrases.compactMap { phrase in
            // A unit phrase sits at its embed, which `revealedLength` reaches but passes only after the last unit.
            if let unit = phrase.unit {
                guard phrase.range.location <= revealedLength, unit < embedUnits[phrase.range.location]?.count ?? 0 else { return nil }
                return phrase
            }
            let end = min(NSMaxRange(phrase.range), revealedLength)
            guard end > phrase.range.location else { return nil }
            return Phrase(range: NSRange(location: phrase.range.location, length: end - phrase.range.location), start: phrase.start)
        }
        var revealedUnits: [Int: Int] = [:]
        for (offset, count) in unitsRevealed {
            if let units = embedUnits[offset] { revealedUnits[offset] = min(count, units.count) }
        }
        unitsRevealed = revealedUnits
        unitsSettled = unitsSettled.filter { embedUnits[$0.key] != nil }
        if nextPhraseStart == nil, revealedLength < text.length {
            nextPhraseStart = max(now, earliestNextStart ?? now)
        }
    }

    /// Starts every phrase due by `now` and settles every fade finished by `now`.
    mutating func advance(to now: TimeInterval) {
        while let due = nextPhraseStart, due <= now {
            pacing.updateRate(backlog: text.length - revealedLength, isStreaming: isStreaming, now: due)
            // An embed that reveals in units: one phrase per code line or table row, paced by the unit's length.
            if let units = embedUnits[revealedLength] {
                let shown = unitsRevealed[revealedLength, default: 0]
                if shown < units.count {
                    phrases.append(Phrase(range: NSRange(location: revealedLength, length: 1), start: due, unit: shown))
                    unitsRevealed[revealedLength] = shown + 1
                    nextPhraseStart = due + pacing.interval(forPhraseLength: max(1, units[shown]))
                    continue
                }
                // Every known unit has started. Move past the embed once it can no longer grow.
                guard revealedLength + 1 < text.length || !isStreaming else {
                    nextPhraseStart = nil
                    earliestNextStart = due
                    break
                }
                revealedLength += 1
                continue
            }
            guard var end = chunk(from: revealedLength) else {
                nextPhraseStart = nil
                earliestNextStart = due
                break
            }
            // Fast streams: grow the phrase instead of starting phrases closer than `minPhraseSpacing`.
            while end - revealedLength < pacing.minimumPhraseLength, end < text.length, let next = chunk(from: end) {
                end = next
            }
            // A text phrase stops before an embed that reveals in units.
            if let embed = embedUnits.keys.filter({ $0 > revealedLength && $0 < end }).min() { end = embed }
            let phrase = Phrase(range: NSRange(location: revealedLength, length: end - revealedLength), start: due)
            phrases.append(phrase)
            revealedLength = end
            nextPhraseStart = due + pacing.interval(forPhraseLength: phrase.range.length)
        }
        while let first = phrases.first, first.start + options.fadeDuration <= now {
            phrases.removeFirst()
            if let unit = first.unit {
                let offset = first.range.location
                unitsSettled[offset] = unit + 1
                // The embed's character settles with its last unit, once the reveal has moved past it.
                let isLast = unit + 1 == embedUnits[offset]?.count
                settledLength = isLast && revealedLength > offset ? offset + 1 : offset
            } else {
                settledLength = NSMaxRange(first.range)
            }
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

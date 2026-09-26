import Foundation

/// Splits arriving text into reveal phrases.
enum GlimmerPhraseChunker {
    /// The UTF-16 offset where the phrase starting at `start` ends, or nil while not enough complete text has arrived.
    ///
    /// A phrase ends after punctuation once it has `minWords` words, at `maxWords` words, or at a line end. Words and
    /// grapheme clusters are never split; a block attachment on its own line is a phrase by itself. While streaming, a
    /// word counts only once whitespace follows it.
    static func phraseEnd(in text: NSString, from start: Int, isStreaming: Bool, minWords: Int, maxWords: Int) -> Int? {
        let length = text.length
        guard start < length else { return nil }
        var index = start
        var words = 0
        var inWord = false
        var lastWordEndsWithPunctuation = false
        var lastCompleteEnd: Int?
        while index < length {
            let range = text.rangeOfComposedCharacterSequence(at: index)
            let character = text.substring(with: range)
            if character == "\n" { return NSMaxRange(range) }
            if character == " " || character == "\t" {
                if inWord {
                    inWord = false
                    words += 1
                    if words >= maxWords || (words >= minWords && lastWordEndsWithPunctuation) {
                        return endOfWhitespace(in: text, from: NSMaxRange(range))
                    }
                }
                lastCompleteEnd = NSMaxRange(range)
            } else {
                inWord = true
                // A closing quote or bracket after punctuation ("stop.") keeps the sentence end.
                if !(character.count == 1 && "\"'\u{201D}\u{2019})]\u{00BB}".contains(character)) {
                    lastWordEndsWithPunctuation = character.count == 1 && ",.;:!?".contains(character)
                }
            }
            index = NSMaxRange(range)
        }
        if !isStreaming { return length }
        if words >= minWords, let lastCompleteEnd { return lastCompleteEnd }
        return nil
    }

    /// Past the spaces after a phrase, and past one line end if that is what follows them.
    private static func endOfWhitespace(in text: NSString, from index: Int) -> Int {
        var end = index
        while end < text.length {
            let unit = text.character(at: end)
            if unit == 0x20 || unit == 0x09 { end += 1; continue }
            if unit == 0x0A { end += 1 }
            break
        }
        return end
    }
}

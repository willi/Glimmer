import Foundation

enum ParsingHelpers {
    @inline(__always)
    static func isHexChar(_ char: Character) -> Bool {
        return (char >= "0" && char <= "9") ||
               (char >= "a" && char <= "f") ||
               (char >= "A" && char <= "F")
    }

    @inline(__always)
    static func isWhitespace(_ char: Character) -> Bool {
        return char == " " || char == "\t" || char == "\n" || char == "\r"
    }

    @inline(__always)
    static func skipSpaces(in text: String, from index: inout String.Index, end: String.Index) {
        while index < end && (text[index] == " " || text[index] == "\t") {
            index = text.index(after: index)
        }
    }

    // Scan a quoted string: title delimiters '"', '\'', or parentheses. Supports backslash escapes for quotes.
    // Returns (content, endIndexAfterClosing) or nil on failure.
    static func scanQuoted(in text: String, from start: String.Index, end: String.Index, delimiter: Character) -> (String, String.Index)? {
        if let simple = scanSimpleQuoted(in: text, from: start, end: end, delimiter: delimiter) {
            return simple
        }

        var idx = start
        var result = ""
        switch delimiter {
        case Character("\""):
            while idx < end {
                let ch = text[idx]
                if ch == "\\" { // escape
                    let next = text.index(after: idx)
                    if next < end { result.append(text[next]); idx = text.index(after: next) } else { return nil }
                } else if ch == Character("\"") {
                    return (result, text.index(after: idx))
                } else {
                    result.append(ch); idx = text.index(after: idx)
                }
            }
            return nil
        case Character("'"):
            while idx < end {
                let ch = text[idx]
                if ch == "\\" {
                    let next = text.index(after: idx)
                    if next < end { result.append(text[next]); idx = text.index(after: next) } else { return nil }
                } else if ch == Character("'") {
                    return (result, text.index(after: idx))
                } else {
                    result.append(ch); idx = text.index(after: idx)
                }
            }
            return nil
        case Character("("):
            // Read until matching ')' without nesting for simplicity
            while idx < end {
                let ch = text[idx]
                if ch == ")" {
                    return (result, text.index(after: idx))
                } else if ch == "\\" {
                    let next = text.index(after: idx)
                    if next < end { result.append(text[next]); idx = text.index(after: next) } else { return nil }
                } else {
                    result.append(ch); idx = text.index(after: idx)
                }
            }
            return nil
        default:
            return nil
        }
    }

    private static func scanSimpleQuoted(
        in text: String,
        from start: String.Index,
        end: String.Index,
        delimiter: Character
    ) -> (String, String.Index)? {
        let closeByte: UInt8
        switch delimiter {
        case "\"": closeByte = 0x22
        case "'": closeByte = 0x27
        case "(": closeByte = 0x29
        default: return nil
        }

        guard let utf8Start = start.samePosition(in: text.utf8),
              let utf8End = end.samePosition(in: text.utf8) else {
            return nil
        }

        let utf8 = text.utf8
        var scan = utf8Start
        while scan < utf8End {
            let byte = utf8[scan]
            if byte == closeByte {
                let afterClose = utf8.index(after: scan)
                guard let closeIndex = String.Index(scan, within: text),
                      let afterCloseIndex = String.Index(afterClose, within: text) else {
                    return nil
                }
                return (String(text[start..<closeIndex]), afterCloseIndex)
            }
            if byte == 0x5C {
                return nil
            }
            scan = utf8.index(after: scan)
        }

        return nil
    }

    // Scan while predicate returns true, starting at index. Advances the provided index and
    // returns the collected String. If maxCount is provided, stops after consuming that many chars.
    @inline(__always)
    static func scanWhile(in text: String, from index: inout String.Index, end: String.Index, while predicate: (Character) -> Bool, maxCount: Int? = nil) -> String {
        var result = ""
        var count = 0
        while index < end {
            let ch = text[index]
            if let max = maxCount, count >= max { break }
            if predicate(ch) {
                result.append(ch)
                index = text.index(after: index)
                count += 1
            } else {
                break
            }
        }
        return result
    }

    // Scan a balanced region given opening and closing delimiters.
    // Precondition: `start` points to the character immediately after the first opening delimiter.
    // Returns (contentBetween, indexAfterMatchingClose) or nil if not balanced before end.
    static func scanBalanced(in text: String, from start: String.Index, end: String.Index, open: Character, close: Character, allowEscape: Bool = true) -> (String, String.Index)? {
        guard let scanned = scanBalancedRange(
            in: text,
            from: start,
            end: end,
            open: open,
            close: close,
            allowEscape: allowEscape
        ) else {
            return nil
        }

        return (String(text[scanned.range]), scanned.after)
    }

    static func scanBalancedRange(
        in text: String,
        from start: String.Index,
        end: String.Index,
        open: Character,
        close: Character,
        allowEscape: Bool = true
    ) -> (range: Range<String.Index>, after: String.Index)? {
        guard let openByte = asciiByte(for: open),
              let closeByte = asciiByte(for: close),
              let utf8Start = start.samePosition(in: text.utf8),
              let utf8End = end.samePosition(in: text.utf8) else {
            return scanBalancedRangeByCharacter(
                in: text,
                from: start,
                end: end,
                open: open,
                close: close,
                allowEscape: allowEscape
            )
        }

        let utf8 = text.utf8
        var index = utf8Start
        var depth = 1

        while index < utf8End {
            let byte = utf8[index]

            if allowEscape && byte == 0x5C {
                let next = utf8.index(after: index)
                guard next < utf8End else {
                    return nil
                }
                index = utf8.index(after: next)
                continue
            }

            if byte == openByte {
                depth += 1
                index = utf8.index(after: index)
                continue
            }

            if byte == closeByte {
                depth -= 1
                if depth == 0 {
                    let after = utf8.index(after: index)
                    guard let closeIndex = String.Index(index, within: text),
                          let afterIndex = String.Index(after, within: text) else {
                        return nil
                    }
                    return (start..<closeIndex, afterIndex)
                }
            }

            index = utf8.index(after: index)
        }

        return nil
    }

    private static func scanBalancedRangeByCharacter(
        in text: String,
        from start: String.Index,
        end: String.Index,
        open: Character,
        close: Character,
        allowEscape: Bool
    ) -> (range: Range<String.Index>, after: String.Index)? {
        var index = start
        var depth = 1

        while index < end {
            let ch = text[index]

            if allowEscape && ch == "\\" {
                let next = text.index(after: index)
                guard next < end else {
                    return nil
                }
                index = text.index(after: next)
                continue
            }

            if ch == open {
                depth += 1
                index = text.index(after: index)
                continue
            }

            if ch == close {
                depth -= 1
                if depth == 0 {
                    return (start..<index, text.index(after: index))
                }
            }

            index = text.index(after: index)
        }

        return nil
    }

    @inline(__always)
    private static func asciiByte(for character: Character) -> UInt8? {
        switch character {
        case "(": return 0x28
        case ")": return 0x29
        case "[": return 0x5B
        case "]": return 0x5D
        case "{": return 0x7B
        case "}": return 0x7D
        case "<": return 0x3C
        case ">": return 0x3E
        default: return nil
        }
    }

    // MARK: - ASCII fast-path helpers
    @inline(__always) static func isASCIIDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }
    @inline(__always) static func isASCIIAlpha(_ b: UInt8) -> Bool {
        let folded = b | 0x20
        return folded >= 0x61 && folded <= 0x7A
    }
    @inline(__always) static func isASCIIHex(_ b: UInt8) -> Bool {
        let folded = b | 0x20
        return isASCIIDigit(b) || (folded >= 0x61 && folded <= 0x66)
    }
    @inline(__always) static func isASCIIAlnum(_ b: UInt8) -> Bool { isASCIIDigit(b) || isASCIIAlpha(b) }

    // UTF-8 backed scanning for ASCII-only predicates.
    // Advances `index` and returns collected substring.
    static func scanWhileUTF8(
        in text: String,
        from index: inout String.Index,
        end: String.Index,
        while predicate: (UInt8) -> Bool,
        maxCount: Int? = nil
    ) -> String {
        let scan = scanUTF8Range(in: text, from: &index, end: end, while: predicate, maxCount: maxCount)
        return String(text[scan.range])
    }

    // UTF-8 backed scanning for ASCII-only predicates.
    // Advances `index` and returns the matched source range without copying bytes.
    @inline(__always)
    static func scanUTF8Range(
        in text: String,
        from index: inout String.Index,
        end: String.Index,
        while predicate: (UInt8) -> Bool,
        maxCount: Int? = nil
    ) -> (range: Range<String.Index>, count: Int) {
        let rangeStart = index
        guard let startUTF8 = index.samePosition(in: text.utf8), let endUTF8 = end.samePosition(in: text.utf8) else {
            return (rangeStart..<rangeStart, 0)
        }
        var uidx = startUTF8
        var count = 0
        while uidx < endUTF8 {
            let b = text.utf8[uidx]
            if b < 0x80 { // ASCII fast path only
                if let max = maxCount, count >= max { break }
                if predicate(b) {
                    count += 1
                    uidx = text.utf8.index(after: uidx)
                    continue
                }
            }
            break
        }
        guard let newIdx = String.Index(uidx, within: text) else {
            return (rangeStart..<rangeStart, 0)
        }
        index = newIdx
        return (rangeStart..<newIdx, count)
    }

    @inline(__always)
    static func scanASCIIInteger(
        in text: String,
        from index: inout String.Index,
        end: String.Index
    ) -> (value: Int?, count: Int) {
        guard let startUTF8 = index.samePosition(in: text.utf8),
              let endUTF8 = end.samePosition(in: text.utf8) else {
            return (nil, 0)
        }

        var uidx = startUTF8
        var value = 0
        var count = 0
        var overflowed = false

        while uidx < endUTF8 {
            let byte = text.utf8[uidx]
            guard isASCIIDigit(byte) else { break }

            if !overflowed {
                let digit = Int(byte - 0x30)
                if value > (Int.max - digit) / 10 {
                    overflowed = true
                } else {
                    value = value * 10 + digit
                }
            }

            count += 1
            uidx = text.utf8.index(after: uidx)
        }

        guard let newIndex = String.Index(uidx, within: text) else {
            return (nil, 0)
        }
        index = newIndex

        guard count > 0, !overflowed else {
            return (nil, count)
        }
        return (value, count)
    }

    // Fast ASCII content check using UTF-8 view
    @inline(__always)
    static func isASCII(_ text: String) -> Bool {
        if let result = text.utf8.withContiguousStorageIfAvailable({ bytes in
            for byte in bytes {
                if byte & 0x80 != 0 {
                    return false
                }
            }
            return true
        }) {
            return result
        }

        for b in text.utf8 { if b & 0x80 != 0 { return false } }
        return true
    }

    @inline(__always)
    static func isASCII(in text: String, from start: String.Index, to end: String.Index) -> Bool {
        var index = start
        let utf8 = text.utf8
        while index < end {
            if utf8[index] & 0x80 != 0 {
                return false
            }
            index = utf8.index(after: index)
        }
        return true
    }

    // Find first ASCII space or tab from index to end; returns end if none found.
    // Scanning UTF-8 bytes is safe here because 0x20 and 0x09 cannot occur inside a non-ASCII scalar.
    @inline(__always)
    static func firstASCIISpaceOrTab(in text: String, from: String.Index, end: String.Index) -> String.Index {
        guard let uStart = from.samePosition(in: text.utf8), let uEnd = end.samePosition(in: text.utf8) else {
            var idx = from
            while idx < end {
                let ch = text[idx]
                if ch == " " || ch == "\t" {
                    return idx
                }
                idx = text.index(after: idx)
            }
            return end
        }
        var uidx = uStart
        while uidx < uEnd {
            let b = text.utf8[uidx]
            if b == 0x20 || b == 0x09 { // space or tab
                if let idx = String.Index(uidx, within: text) { return idx }
                break
            }
            uidx = text.utf8.index(after: uidx)
        }
        return end
    }

    // MARK: - Slugification
    /// Fast slugifier for heading IDs: keep letters, digits, spaces, and hyphens;
    /// convert spaces to single hyphens; trim leading/trailing hyphens. Lowercases ASCII.
    @inline(__always)
    static func slugifyHeading(_ text: String) -> String {
        slugifyHeading(in: text, range: text.startIndex..<text.endIndex)
    }

    @inline(__always)
    static func slugifyHeading(in text: String, range: Range<String.Index>) -> String {
        if range.isEmpty { return "" }
        let rangeUTF8Count = text.utf8.distance(from: range.lowerBound, to: range.upperBound)
        var out = String()
        out.reserveCapacity(rangeUTF8Count)
        var prevWasHyphen = false
        for scalar in text[range].unicodeScalars {
            switch scalar.value {
            case 0x30...0x39: // 0-9
                out.unicodeScalars.append(scalar)
                prevWasHyphen = false
            case 0x41...0x5A: // A-Z
                out.unicodeScalars.append(UnicodeScalar(scalar.value + 0x20)!) // lowercase
                prevWasHyphen = false
            case 0x61...0x7A: // a-z
                out.unicodeScalars.append(scalar)
                prevWasHyphen = false
            case 0x20, 0x09: // space or tab -> hyphen
                if !out.isEmpty && !prevWasHyphen {
                    out.append("-")
                    prevWasHyphen = true
                }
            case 0x2D: // '-'
                if !out.isEmpty && !prevWasHyphen {
                    out.append("-")
                    prevWasHyphen = true
                }
            default:
                // Skip other punctuation/marks for simplicity
                continue
            }
        }
        if out.last == "-" { out.removeLast() }
        return out
    }
}

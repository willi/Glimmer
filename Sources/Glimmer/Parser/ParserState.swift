import Foundation

/// Parser state with position tracking and fragment buffer
public struct ParserState {
    let text: String
    // String.Index-based cursor for efficient navigation
    var currentIndex: String.Index
    let endIndex: String.Index
    var line: Int
    var column: Int
    // Enables ASCII/UTF-8 fast path scans for inline parsing
    var asciiFastPath: Bool
    
    // Fragment buffer for accumulating text efficiently
    private var fragmentBuffer: ContiguousArray<Character>
    
    public init(text: String) {
        self.text = text
        self.currentIndex = text.startIndex
        self.endIndex = text.endIndex
        self.line = 1
        self.column = 1
        self.asciiFastPath = false
        self.fragmentBuffer = ContiguousArray<Character>()
        self.fragmentBuffer.reserveCapacity(min(text.count, 1024))
    }
    
    // MARK: - Navigation (String.Index-based)
    
    @inline(__always)
    var isAtEnd: Bool { currentIndex >= endIndex }
    
    @inline(__always)
    func current() -> Character? {
        guard !isAtEnd else { return nil }
        return text[currentIndex]
    }
    
    @inline(__always)
    func peek(_ n: Int = 1) -> Character? {
        guard n >= 0 else { return nil }
        var idx = currentIndex
        var k = n
        while k > 0 && idx < endIndex {
            idx = text.index(after: idx)
            k -= 1
        }
        if idx >= endIndex { return nil }
        return text[idx]
    }
    
    @inline(__always)
    mutating func advance() {
        guard !isAtEnd else { return }
        let ch = text[currentIndex]
        if ch == "\n" {
            line += 1
            column = 1
        } else {
            column += 1
        }
        currentIndex = text.index(after: currentIndex)
    }

    @inline(__always)
    mutating func advance(by n: Int) {
        var k = n
        while k > 0 { advance(); k -= 1 }
    }
    
    mutating func advanceLine() {
        while let ch = current(), ch != "\n" { advance() }
        if let ch = current(), ch == "\n" { advance() }
    }
    
    // Move forward to a given index; assumes target >= currentIndex
    mutating func advance(to target: String.Index) {
        var idx = currentIndex
        while idx < target && idx < endIndex {
            advance()
            idx = currentIndex
        }
    }

    // Move directly to a String.Index
    mutating func move(to target: String.Index) {
        guard target != currentIndex else { return }

        // Forward movement can preserve position tracking by advancing.
        if target > currentIndex {
            advance(to: target)
            return
        }

        // Backward movement: adjust line/column by scanning only the rewound region.
        var newlineCount = 0
        var probe = currentIndex
        while probe > target {
            let prev = text.index(before: probe)
            if text[prev] == "\n" { newlineCount += 1 }
            probe = prev
        }
        line = max(1, line - newlineCount)

        var scan = target
        var newColumn = 1
        while scan > text.startIndex {
            let prev = text.index(before: scan)
            if text[prev] == "\n" { break }
            newColumn += 1
            scan = prev
        }
        column = newColumn
        currentIndex = target
    }
    
    // Snapshot/restore position
    struct Mark {
        let index: String.Index
        let line: Int
        let column: Int
    }
    
    @inline(__always)
    func mark() -> Mark { Mark(index: currentIndex, line: line, column: column) }
    
    @inline(__always)
    mutating func restore(_ m: Mark) {
        currentIndex = m.index
        line = m.line
        column = m.column
    }
    
    @inline(__always)
    func index(offsetBy n: Int) -> String.Index? {
        guard n >= 0 else { return nil }
        var idx = currentIndex
        var k = n
        while k > 0 && idx < endIndex {
            idx = text.index(after: idx)
            k -= 1
        }
        return k == 0 ? idx : nil
    }
    
    // MARK: - Text Access
    
    func substring(from start: Int, to end: Int) -> String {
        guard start < end && start >= 0 && end <= text.count else {
            return ""
        }
        let startIndex = text.index(text.startIndex, offsetBy: start)
        let endIndex = text.index(text.startIndex, offsetBy: end)
        return String(text[startIndex..<endIndex])
    }
    
    func substring(from start: String.Index, to end: String.Index) -> String {
        guard start <= end && end <= endIndex else { return "" }
        return String(text[start..<end])
    }
    
    func remainingSubstring() -> String {
        guard !isAtEnd else { return "" }
        return String(text[currentIndex...])
    }
    
    // Check if current line is empty (spaces/tabs only until newline or end)
    @inline(__always)
    func isAtEmptyLine() -> Bool {
        var idx = currentIndex
        while idx < endIndex {
            let ch = text[idx]
            if ch == " " || ch == "\t" {
                idx = text.index(after: idx)
                continue
            }
            return ch == "\n"
        }
        return true
    }
    
    // MARK: - Fragment Buffer Management
    
    @inline(__always)
    mutating func appendToFragmentBuffer(_ char: Character) { fragmentBuffer.append(char) }
    
    mutating func flushFragmentBuffer(_ inlines: inout [MarkdownParser.InlineNode]) {
        if !fragmentBuffer.isEmpty {
            let text = String(fragmentBuffer)
            if !text.isEmpty { inlines.append(.text(text)) }
            fragmentBuffer.removeAll(keepingCapacity: true)
        }
    }
}

// MARK: - String Extension for Parser

// Int subscript removed; String.Index is canonical in parsers

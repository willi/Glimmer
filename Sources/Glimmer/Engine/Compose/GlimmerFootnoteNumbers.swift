import Foundation

/// Footnote numbers in order of first reference, as remark-gfm numbers them. A streaming document keeps one for its
/// lifetime, so a marker's number never changes once shown, whether or not its definition ever arrives.
final class GlimmerFootnoteNumbers: @unchecked Sendable {
    private let lock = NSLock()
    private var numbers: [String: Int] = [:]

    /// The number for `label`: the next one the first time it is asked for.
    func number(for label: String) -> Int {
        lock.withLock {
            if let number = numbers[label] { return number }
            let number = numbers.count + 1
            numbers[label] = number
            return number
        }
    }
}

import Foundation

struct RevealSessionStats: Sendable, Equatable {
    var updates: Int = 0
    var incrementalUpdates: Int = 0
    var fullRebuilds: Int = 0
}

/// Maintains a reveal model across append-only markdown updates.
///
/// The fast path is intentionally conservative: it commits complete markdown
/// through the last blank-line block boundary, then reparses only the current
/// tail. Any replacement falls back to rebuilding session state while keeping
/// parsing anchored to the canonical parser.
final class RevealSession {
    private struct OpenFence {
        let marker: Character
        let length: Int
    }

    private let granularity: RevealGranularity
    private let configuration: MarkdownConfiguration

    private var markdown = ""
    private var committedCharacterCount = 0
    private var committedRevealBlocks: [RevealBlock] = []
    private var committedCountableCount = 0
    private var nextCommittedAtomID = 0
    private var lastModel: RevealModel = .empty

    private(set) var stats = RevealSessionStats()

    init(granularity: RevealGranularity, configuration: MarkdownConfiguration) {
        self.granularity = granularity
        self.configuration = configuration
    }

    @discardableResult
    func update(_ newMarkdown: String) -> RevealModel {
        stats.updates += 1

        guard newMarkdown != markdown else {
            return lastModel
        }

        guard !newMarkdown.isEmpty else {
            clearState()
            markdown = ""
            lastModel = .empty
            return .empty
        }

        guard !markdown.isEmpty else {
            return rebuild(newMarkdown)
        }

        guard newMarkdown.hasPrefix(markdown) else {
            return rebuild(newMarkdown)
        }

        let newCommittedCharacterCount = lastConservativeBoundaryCharacterCount(
            in: newMarkdown,
            startingAt: committedCharacterCount
        )
        guard newCommittedCharacterCount >= committedCharacterCount else {
            return rebuild(newMarkdown)
        }

        appendCommittedPrefixIfNeeded(in: newMarkdown, through: newCommittedCharacterCount)
        markdown = newMarkdown
        stats.incrementalUpdates += 1

        lastModel = modelWithCurrentTail(from: newMarkdown)
        return lastModel
    }

    func reset() {
        clearState()
        stats = RevealSessionStats()
    }

    private func clearState() {
        markdown = ""
        committedCharacterCount = 0
        committedRevealBlocks.removeAll(keepingCapacity: true)
        committedCountableCount = 0
        nextCommittedAtomID = 0
        lastModel = .empty
    }

    private func rebuild(_ newMarkdown: String) -> RevealModel {
        clearState()
        let newCommittedCharacterCount = lastConservativeBoundaryCharacterCount(in: newMarkdown)
        appendCommittedPrefixIfNeeded(in: newMarkdown, through: newCommittedCharacterCount)
        markdown = newMarkdown
        lastModel = modelWithCurrentTail(from: newMarkdown)
        stats.fullRebuilds += 1
        return lastModel
    }

    private func appendCommittedPrefixIfNeeded(in value: String, through newCommittedCharacterCount: Int) {
        guard newCommittedCharacterCount > committedCharacterCount else { return }

        let segment = substring(value, from: committedCharacterCount, to: newCommittedCharacterCount)
        guard !segment.isEmpty else {
            committedCharacterCount = newCommittedCharacterCount
            return
        }

        let segmentBlocks = Glimmer.parse(segment, configuration: configuration)
        let segmentModel = RevealFlattener.flatten(
            segmentBlocks,
            granularity: granularity,
            configuration: configuration,
            atomIDOffset: nextCommittedAtomID,
            blockIDOffset: committedRevealBlocks.count,
            countableOffset: committedCountableCount
        )

        committedRevealBlocks.append(contentsOf: segmentModel.blocks)
        committedCountableCount += segmentModel.countableCount
        nextCommittedAtomID += segmentModel.atomCount
        committedCharacterCount = newCommittedCharacterCount
    }

    private func modelWithCurrentTail(from value: String) -> RevealModel {
        let tail = substring(value, from: committedCharacterCount, to: value.count)
        guard !tail.isEmpty else {
            return RevealModel(
                blocks: committedRevealBlocks,
                countableCount: committedCountableCount,
                atomCount: nextCommittedAtomID
            )
        }

        let tailBlocks = Glimmer.parse(tail, configuration: configuration)
        let tailModel = RevealFlattener.flatten(
            tailBlocks,
            granularity: granularity,
            configuration: configuration,
            atomIDOffset: nextCommittedAtomID,
            blockIDOffset: committedRevealBlocks.count,
            countableOffset: committedCountableCount
        )

        return RevealModel(
            blocks: committedRevealBlocks + tailModel.blocks,
            countableCount: committedCountableCount + tailModel.countableCount,
            atomCount: nextCommittedAtomID + tailModel.atomCount
        )
    }

    private func substring(_ value: String, from lowerBound: Int, to upperBound: Int) -> String {
        guard lowerBound < upperBound else { return "" }

        let lower = value.index(value.startIndex, offsetBy: lowerBound)
        let upper = value.index(value.startIndex, offsetBy: upperBound)
        return String(value[lower..<upper])
    }

    private func lastConservativeBoundaryCharacterCount(
        in value: String,
        startingAt startCharacterCount: Int = 0
    ) -> Int {
        guard startCharacterCount < value.count else {
            return startCharacterCount
        }

        var lastBoundary = startCharacterCount
        var openFence: OpenFence?
        var lineStart = value.index(value.startIndex, offsetBy: startCharacterCount)

        while lineStart < value.endIndex {
            let lineEnd = value[lineStart...].firstIndex(of: "\n")
                .map { value.index(after: $0) } ?? value.endIndex
            let line = value[lineStart..<lineEnd]
            let content = lineContentWithoutLineEnding(line)

            if openFence == nil, isBlankLine(content) {
                lastBoundary = value.distance(from: value.startIndex, to: lineEnd)
            } else if let fence = openFence {
                if isClosingFenceLine(content, for: fence) {
                    openFence = nil
                }
            } else if let fence = openingFence(in: content) {
                openFence = fence
            }

            lineStart = lineEnd
        }

        return lastBoundary
    }

    private func lineContentWithoutLineEnding(_ line: Substring) -> Substring {
        var end = line.endIndex
        if end > line.startIndex {
            let previous = line.index(before: end)
            if line[previous] == "\n" {
                end = previous
            }
        }
        if end > line.startIndex {
            let previous = line.index(before: end)
            if line[previous] == "\r" {
                end = previous
            }
        }
        return line[..<end]
    }

    private func isBlankLine(_ line: Substring) -> Bool {
        line.allSatisfy { $0 == " " || $0 == "\t" }
    }

    private func openingFence(in line: Substring) -> OpenFence? {
        var index = line.startIndex
        var leadingSpaces = 0

        while index < line.endIndex, line[index] == " ", leadingSpaces < 3 {
            leadingSpaces += 1
            index = line.index(after: index)
        }

        if index < line.endIndex, line[index] == " " {
            return nil
        }

        guard index < line.endIndex else { return nil }
        let marker = line[index]
        guard marker == "`" || marker == "~" else { return nil }

        let length = fenceLength(in: line[index...], marker: marker)
        guard length >= 3 else { return nil }
        return OpenFence(marker: marker, length: length)
    }

    private func isClosingFenceLine(_ line: Substring, for fence: OpenFence) -> Bool {
        guard line.first == fence.marker else {
            return false
        }

        return fenceLength(in: line, marker: fence.marker) >= fence.length
    }

    private func fenceLength(in line: Substring, marker: Character) -> Int {
        var count = 0
        var index = line.startIndex

        while index < line.endIndex, line[index] == marker {
            count += 1
            index = line.index(after: index)
        }

        return count
    }
}

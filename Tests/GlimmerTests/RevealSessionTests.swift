import XCTest
@testable import Glimmer

final class RevealSessionTests: XCTestCase {
    func testAppendOnlySessionMatchesFullRevealModelAtSafeBoundaries() {
        let updates = [
            "# Title\n\n",
            "Paragraph **bold** text with [link](https://example.com).\n\n",
            "- first\n- second\n\n",
            "| A | B |\n|---|---|\n| 1 | 2 |\n\n",
            "```swift\nlet x = 1\n```\n\n"
        ]
        let session = RevealSession(granularity: .word, configuration: .default)
        var buffer = ""

        for update in updates {
            buffer += update
            let sessionModel = session.update(buffer)
            let fullModel = Glimmer.revealModel(buffer, style: .wordFade, configuration: .default)
            XCTAssertEqual(summarize(sessionModel), summarize(fullModel))
        }

        XCTAssertEqual(session.stats.fullRebuilds, 1)
        XCTAssertEqual(session.stats.incrementalUpdates, updates.count - 1)
    }

    func testAppendOnlySessionMatchesFullRevealModelForPartialTailUpdates() {
        let updates = [
            "# Title\n\nPara",
            "# Title\n\nParagraph with **bo",
            "# Title\n\nParagraph with **bold** text\n\n- item",
            "# Title\n\nParagraph with **bold** text\n\n- item one\n- item two\n\nTrailing"
        ]
        let session = RevealSession(granularity: .word, configuration: .default)

        for markdown in updates {
            let sessionModel = session.update(markdown)
            let fullModel = Glimmer.revealModel(markdown, style: .wordFade, configuration: .default)
            XCTAssertEqual(summarize(sessionModel), summarize(fullModel))
        }

        XCTAssertEqual(session.stats.fullRebuilds, 1)
        XCTAssertEqual(session.stats.incrementalUpdates, updates.count - 1)
    }

    func testAppendOnlySessionDoesNotCommitInsideOpenBacktickFence() {
        let updates = [
            "Intro\n\n```swift\nfunc demo() {\n",
            "Intro\n\n```swift\nfunc demo() {\n\n",
            "Intro\n\n```swift\nfunc demo() {\n\n    print(\"hi\")\n",
            "Intro\n\n```swift\nfunc demo() {\n\n    print(\"hi\")\n}\n```\n\nAfter\n"
        ]
        let session = RevealSession(granularity: .word, configuration: .default)
        var finalModel = RevealModel.empty

        for markdown in updates {
            finalModel = session.update(markdown)
            let fullModel = Glimmer.revealModel(markdown, style: .wordFade, configuration: .default)
            XCTAssertEqual(summarize(finalModel), summarize(fullModel))
        }

        let finalSummary = summarize(finalModel)
        XCTAssertEqual(finalSummary.filter { $0.kind == .wholeBlock && $0.hasWholeBlockNode }.count, 1)
        XCTAssertEqual(session.stats.fullRebuilds, 1)
        XCTAssertGreaterThan(session.stats.incrementalUpdates, 0)
    }

    func testAppendOnlySessionDoesNotCommitInsideOpenTildeFence() {
        let updates = [
            "Intro\n\n~~~\nline one\n",
            "Intro\n\n~~~\nline one\n\n",
            "Intro\n\n~~~\nline one\n\nline two\n",
            "Intro\n\n~~~\nline one\n\nline two\n~~~\n\nAfter\n"
        ]
        let session = RevealSession(granularity: .word, configuration: .default)

        for markdown in updates {
            let sessionModel = session.update(markdown)
            let fullModel = Glimmer.revealModel(markdown, style: .wordFade, configuration: .default)
            XCTAssertEqual(summarize(sessionModel), summarize(fullModel))
        }

        XCTAssertEqual(session.stats.fullRebuilds, 1)
        XCTAssertGreaterThan(session.stats.incrementalUpdates, 0)
    }

    func testAppendOnlySessionMatchesFullRevealModelForCharacterGranularity() {
        let updates = [
            "Alpha beta\n\n",
            "Alpha beta\n\nGamma **delta**",
            "Alpha beta\n\nGamma **delta**\n\n"
        ]
        let session = RevealSession(granularity: .character, configuration: .default)

        for markdown in updates {
            let sessionModel = session.update(markdown)
            let fullModel = Glimmer.revealModel(markdown, style: .typewriter, configuration: .default)
            XCTAssertEqual(summarize(sessionModel), summarize(fullModel))
        }
    }

    func testAppendOnlySessionMatchesFullRevealModelForLineGranularity() {
        let updates = [
            "One two three four\n\n",
            "One two three four\n\nFive six seven",
            "One two three four\n\nFive six seven eight nine\n\n- list item\n"
        ]
        let session = RevealSession(granularity: .line, configuration: .default)

        for markdown in updates {
            let sessionModel = session.update(markdown)
            let fullModel = Glimmer.revealModel(markdown, style: .lineSlide, configuration: .default)
            XCTAssertEqual(summarize(sessionModel), summarize(fullModel))
        }
    }

    func testAppendOnlySessionKeepsContiguousAtomIDsAcrossCommittedPrefixAndTail() {
        let session = RevealSession(granularity: .word, configuration: .default)

        _ = session.update("Alpha beta\n\n")
        let model = session.update("Alpha beta\n\nGamma delta")
        let atoms = allAtoms(model)

        XCTAssertEqual(model.atomCount, atoms.count)
        XCTAssertEqual(atoms.map(\.id), Array(0..<atoms.count))
        XCTAssertEqual(model.countableCount, atoms.filter(\.isCountable).count)
    }

    func testUnsafeSetextAppendFallsBackAndMatchesFullRevealModel() {
        let session = RevealSession(granularity: .word, configuration: .default)

        _ = session.update("Title\n")
        let sessionModel = session.update("Title\n---\n")
        let fullModel = Glimmer.revealModel("Title\n---\n", style: .wordFade, configuration: .default)

        XCTAssertEqual(summarize(sessionModel), summarize(fullModel))
        XCTAssertEqual(session.stats.fullRebuilds, 1)
        XCTAssertEqual(session.stats.incrementalUpdates, 1)
    }

    func testReplacementFallsBackAndMatchesFullRevealModel() {
        let session = RevealSession(granularity: .word, configuration: .default)

        _ = session.update("One\n\n")
        let sessionModel = session.update("Two\n\n")
        let fullModel = Glimmer.revealModel("Two\n\n", style: .wordFade, configuration: .default)

        XCTAssertEqual(summarize(sessionModel), summarize(fullModel))
        XCTAssertEqual(session.stats.fullRebuilds, 2)
        XCTAssertEqual(session.stats.incrementalUpdates, 0)
    }

    func testSessionMatchesFullRevealModelForFullProfilingCorpus() {
        let markdown = ProfilingBenchmarkTests.makeCorpus(sections: 400)
        let session = RevealSession(granularity: .word, configuration: .github)

        let sessionModel = session.update(markdown)
        let fullModel = Glimmer.revealModel(markdown, style: .wordFade, configuration: .github)

        XCTAssertEqual(summarize(sessionModel), summarize(fullModel))
    }

    func testSessionMatchesFullRevealModelForComplexGitHubCorpusPrefixes() {
        let markdown = ProfilingBenchmarkTests.makeCorpus(sections: 60)
        let session = RevealSession(granularity: .word, configuration: .github)
        let step = max(1, markdown.count / 40)
        var index = markdown.startIndex

        while index < markdown.endIndex {
            index = markdown.index(index, offsetBy: step, limitedBy: markdown.endIndex) ?? markdown.endIndex
            let prefix = String(markdown[..<index])
            let sessionModel = session.update(prefix)
            let fullModel = Glimmer.revealModel(prefix, style: .wordFade, configuration: .github)

            XCTAssertEqual(summarize(sessionModel), summarize(fullModel))
        }

        XCTAssertGreaterThan(session.stats.incrementalUpdates, 0)
    }

    // MARK: - Summaries

    private struct BlockSummary: Equatable {
        let id: Int
        let kind: BlockKindTag
        let firstRevealIndex: Int
        let atoms: [AtomSummary]
        let hasWholeBlockNode: Bool
    }

    private struct AtomSummary: Equatable {
        let id: Int
        let text: String
        let isCountable: Bool
        let revealIndex: Int
        let url: String?
    }

    private func summarize(_ model: RevealModel) -> [BlockSummary] {
        model.blocks.map { block in
            BlockSummary(
                id: block.id,
                kind: block.kind,
                firstRevealIndex: block.firstRevealIndex,
                atoms: block.words.flatMap(\.atoms).map(summarize),
                hasWholeBlockNode: block.node != nil
            )
        }
    }

    private func allAtoms(_ model: RevealModel) -> [RevealAtom] {
        model.blocks.flatMap(\.words).flatMap(\.atoms)
    }

    private func summarize(_ atom: RevealAtom) -> AtomSummary {
        AtomSummary(
            id: atom.id,
            text: text(for: atom),
            isCountable: atom.isCountable,
            revealIndex: atom.revealIndex,
            url: atom.url?.absoluteString
        )
    }

    private func text(for atom: RevealAtom) -> String {
        switch atom.kind {
        case .text(let text), .space(let text):
            return String(text.characters)
        case .lineBreak:
            return "\n"
        case .block:
            return ""
        }
    }
}

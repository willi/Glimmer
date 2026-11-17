import SwiftUI
import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerStaticTextTests: XCTestCase {
    private let width: CGFloat = 320
    private var theme: GlimmerTheme {
        GlimmerTheme.default.scaled(for: UITraitCollection(preferredContentSizeCategory: .large))
    }

    private func document(_ markdown: String, configuration: GlimmerConfiguration = .default) -> GlimmerStaticDocument {
        GlimmerStaticDocument(markdown: markdown, configuration: configuration, dynamicTypeSize: .large)
    }

    // MARK: - Model

    func testAListBecomesMarkedItemsWithNesting() {
        let items = flattenedItems(document("- a\n  - b\n- c").blocks)
        XCTAssertEqual(items.map(\.depth), [0, 1, 0])
        XCTAssertEqual(items.map(\.text), ["a", "b", "c"])
        XCTAssertEqual(items.map(\.marker), ["•", "◦", "•"])
    }

    func testAnOrderedListKeepsItsNumbers() {
        let items = flattenedItems(document("3. x\n4. y").blocks)
        XCTAssertEqual(items.map(\.marker), ["3.", "4."])
        XCTAssertEqual(items.map(\.text), ["x", "y"])
    }

    func testTaskItemsShowBoxesAsMarkers() {
        let items = flattenedItems(document("- [x] done\n- [ ] todo").blocks)
        XCTAssertEqual(items.map(\.marker), ["\u{2611}\u{FE0E}", "\u{2610}"])
        XCTAssertEqual(items.map(\.text), ["done", "todo"])
    }

    func testAListHangsItsTextAtTheListIndent() throws {
        let blocks = document("- a").blocks
        guard case .list(let list) = try XCTUnwrap(blocks.first).content else { return XCTFail("not a list") }
        XCTAssertEqual(list.markerColumnWidth, theme.listIndent)
    }

    func testParagraphsKeepLinksAndEmphasis() throws {
        let markdown = "Hello **world** [x](https://a.example)"
        let text = try XCTUnwrap(texts(document(markdown).blocks).first)
        XCTAssertEqual(String(text.characters), String(GlimmerView.attributedString(for: markdown).characters))
        let x = try XCTUnwrap(text.range(of: "x"))
        XCTAssertEqual(text[x].link, URL(string: "https://a.example"))
        let world = try XCTUnwrap(text.range(of: "world"))
        XCTAssertTrue(text[world].uiKit.font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
        XCTAssertTrue(text.runs.allSatisfy { $0.swiftUI.font != nil && $0.swiftUI.foregroundColor != nil })
    }

    func testImagesAreLeftOut() {
        XCTAssertTrue(document("![a](https://a.example/a.png)").blocks.isEmpty)
    }

    func testQuotesCodeTablesAndRulesKeepTheirKinds() throws {
        let blocks = document("> quoted\n\n```\nlet x = 1\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n---\n\nend").blocks
        XCTAssertEqual(blocks.count, 5)
        guard case .quote(let quoted) = blocks[0].content else { return XCTFail("not a quote") }
        let quote = try XCTUnwrap(texts(quoted).first)
        XCTAssertEqual(quote.runs.first?.uiKit.foregroundColor, theme.secondaryTextColor)
        guard case .code(let code) = blocks[1].content else { return XCTFail("not code") }
        XCTAssertEqual(String(code.characters), "let x = 1")
        XCTAssertTrue(code.runs.first?.uiKit.font?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) ?? false)
        guard case .table(let rows) = blocks[2].content else { return XCTFail("not a table") }
        XCTAssertEqual(rows.map { String($0.characters) }, ["a\tb", "1\t2"])
        guard case .rule = blocks[3].content else { return XCTFail("not a rule") }
    }

    func testSpacingMirrorsTheEngine() {
        let blocks = document("Intro\n\n# Title\n\nBody\n\n- a\n- b\n\nAfter").blocks
        XCTAssertEqual(blocks.map(\.spacingAbove), [
            0,
            max(theme.paragraphSpacing, theme.blockSpacing), // a heading collapses into the space after the paragraph
            theme.paragraphSpacing,
            theme.paragraphSpacing,
            theme.paragraphSpacing, // a tight list ends with the outer paragraph spacing
        ])
        guard case .list(let list) = blocks[3].content else { return XCTFail("not a list") }
        XCTAssertEqual(list.items.map(\.spacingAbove), [0, theme.tightListSpacing])
    }

    func testTheDocumentIsBuiltOncePerInput() {
        let cache = GlimmerStaticDocumentCache()
        let first = cache.document(markdown: "a", configuration: .default, dynamicTypeSize: .large)
        XCTAssertTrue(cache.document(markdown: "a", configuration: .default, dynamicTypeSize: .large) === first)
        XCTAssertFalse(cache.document(markdown: "a", configuration: .default, dynamicTypeSize: .xLarge) === first)
        XCTAssertFalse(cache.document(markdown: "b", configuration: .default, dynamicTypeSize: .xLarge) === first)
        var purple = GlimmerConfiguration.default
        purple.theme.linkColor = .systemPurple
        XCTAssertFalse(cache.document(markdown: "a", configuration: purple, dynamicTypeSize: .large) === first,
                       "a new theme builds again instead of showing the old one")
        XCTAssertEqual(cache.builds, 4)
    }

    func testTheCacheKeepsTheMostRecentDocumentsAndEmptiesOnAMemoryWarning() {
        let cache = GlimmerStaticDocumentCache(capacity: 2)
        let a = cache.document(markdown: "a", configuration: .default, dynamicTypeSize: .large)
        _ = cache.document(markdown: "b", configuration: .default, dynamicTypeSize: .large)
        XCTAssertTrue(cache.document(markdown: "a", configuration: .default, dynamicTypeSize: .large) === a)
        _ = cache.document(markdown: "c", configuration: .default, dynamicTypeSize: .large)
        XCTAssertTrue(cache.document(markdown: "a", configuration: .default, dynamicTypeSize: .large) === a, "used last, kept")
        XCTAssertEqual(cache.builds, 3)
        _ = cache.document(markdown: "b", configuration: .default, dynamicTypeSize: .large)
        XCTAssertEqual(cache.builds, 4, "least recently used, dropped")
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertFalse(cache.document(markdown: "a", configuration: .default, dynamicTypeSize: .large) === a)
    }

    func testAReleasedCacheStopsObservingMemoryWarnings() {
        weak var observer: AnyObject?
        autoreleasepool {
            let cache = GlimmerStaticDocumentCache()
            observer = cache.memoryWarning
            XCTAssertNotNil(observer)
        }
        XCTAssertNil(observer, "the cache removes its memory-warning observer when it is released")
    }

    func testAConfigurationWithoutACacheIdentityIsNotShared() {
        let cache = GlimmerStaticDocumentCache()
        var configuration = GlimmerConfiguration.default
        configuration.extensions = [UncachedExtension()]
        let first = cache.document(markdown: "a", configuration: configuration, dynamicTypeSize: .large)
        XCTAssertFalse(cache.document(markdown: "a", configuration: configuration, dynamicTypeSize: .large) === first)
    }

    func testTwoViewsWithTheSameInputsShareOneBuild() {
        let cache = GlimmerStaticDocumentCache.shared
        cache.removeAll()
        let before = cache.builds
        let markdown = "- shared \(UUID().uuidString)"
        _ = height(of: VStack { GlimmerStaticText(markdown); GlimmerStaticText(markdown) }, width: width)
        XCTAssertEqual(cache.builds - before, 1)
        _ = height(of: GlimmerStaticText(markdown), width: width)
        XCTAssertEqual(cache.builds - before, 1, "a view made later reuses the document")
    }

    func testBlocksCompareByValue() {
        let markdown = "# T\n\n- a\n  - b\n\n> q\n\n```\nx\n```"
        XCTAssertEqual(document(markdown).blocks, document(markdown).blocks)
        XCTAssertNotEqual(document(markdown).blocks, document(markdown + "\n\nmore").blocks)
    }

    func testHeadingsKeepTheirLevelForVoiceOver() {
        XCTAssertEqual((1...6).map(GlimmerStaticBlockView.accessibilityHeadingLevel(_:)), [.h1, .h2, .h3, .h4, .h5, .h6])
        XCTAssertEqual(GlimmerStaticBlockView.accessibilityHeadingLevel(7), .unspecified)
        let levels = document("# a\n\n### b\n\nc").blocks.map { block -> Int? in
            if case .text(_, let level) = block.content { level } else { nil }
        }
        XCTAssertEqual(levels, [1, 3, nil])
    }

    func testTaskBoxesReadTheirStateAndOtherMarkersTheirText() throws {
        let tasks = try XCTUnwrap(lists(document("- [x] done\n- [ ] todo").blocks).first)
        XCTAssertEqual(tasks.items.map(\.markerAccessibilityLabel), ["Checked", "Unchecked"])
        let bullets = try XCTUnwrap(lists(document("- a").blocks).first)
        XCTAssertEqual(bullets.items.map(\.markerAccessibilityLabel), [nil])
        let numbers = try XCTUnwrap(lists(document("3. x").blocks).first)
        XCTAssertEqual(numbers.items.map(\.markerAccessibilityLabel), [nil])
    }

    func testAnItemsMarkerIsReadWithItsFirstBlockUnlessThatIsAList() throws {
        let nested = try XCTUnwrap(lists(document("- a\n  - b").blocks).first)
        XCTAssertTrue(nested.items[0].groupsMarkerWithFirstBlock)
        guard case .list(let inner) = nested.items[0].blocks[1].content else { return XCTFail("no nested list") }
        XCTAssertTrue(inner.items[0].groupsMarkerWithFirstBlock)
        let listFirst = try XCTUnwrap(lists(document("- - a").blocks).first)
        XCTAssertFalse(listFirst.items[0].groupsMarkerWithFirstBlock)
        let empty = try XCTUnwrap(lists(document("-\n- b").blocks).first)
        XCTAssertFalse(empty.items[0].groupsMarkerWithFirstBlock)
    }

    func testLinkTapsGoToTheHandler() throws {
        let url = try XCTUnwrap(URL(string: "https://a.example"))
        var tapped: URL?
        var ancestor: URL?
        openLink(url, routing: GlimmerStaticLinkRouting(onLinkTap: { tapped = $0 }), ancestor: { ancestor = $0 })
        XCTAssertEqual(tapped, url)
        XCTAssertNil(ancestor)
    }

    func testWithoutAHandlerLinkTapsGoToTheHostsOpenURL() throws {
        let url = try XCTUnwrap(URL(string: "https://a.example"))
        var ancestor: URL?
        openLink(url, routing: GlimmerStaticLinkRouting(onLinkTap: nil), ancestor: { ancestor = $0 })
        XCTAssertEqual(ancestor, url)
    }

    // MARK: - Hosted layout

    func testAWrappedListItemIndentsItsSecondLine() {
        // Short words, so taking the list indent off the width wraps the text onto more lines.
        let words = Array(repeating: "ab", count: 150).joined(separator: " ")
        let item = height(of: GlimmerStaticText("- " + words), width: width)
        let paragraph = height(of: GlimmerStaticText(words), width: width)
        let narrowed = height(of: GlimmerStaticText(words), width: width - theme.listIndent)
        XCTAssertGreaterThan(item, paragraph, "the item's lines wrap at the content column, not under the bullet")
        XCTAssertEqual(item, narrowed, accuracy: 1, "every line of the item starts at the list indent")
    }

    func testLineLimitTruncatesASingleParagraph() {
        let words = Array(repeating: "word", count: 60).joined(separator: " ")
        let limited = height(of: GlimmerStaticText(words).lineLimit(2), width: width)
        let full = height(of: GlimmerStaticText(words), width: width)
        // `Text` has no line height multiple, so a line is the font's line height.
        let line = theme.bodyFont.lineHeight
        XCTAssertLessThanOrEqual(limited, 2 * line + 2)
        XCTAssertGreaterThan(limited, line)
        XCTAssertGreaterThan(full, limited)
    }

    // MARK: - Helpers

    /// Opens `url` from inside `routing`, below an ancestor `openURL` handler, the way a tapped link in a `Text` does.
    private func openLink(_ url: URL, routing: GlimmerStaticLinkRouting, ancestor: @escaping (URL) -> Void) {
        let probe = LinkProbe(url: url)
            .modifier(routing)
            .environment(\.openURL, OpenURLAction { url in
                ancestor(url)
                return .handled
            })
        let host = UIHostingController(rootView: probe)
        let window = hostInWindow(host.view, width: width, height: 100)
        withExtendedLifetime(window) { settle(host.view) }
    }

    private func lists(_ blocks: [GlimmerStaticBlock]) -> [GlimmerStaticList] {
        blocks.compactMap { block in
            if case .list(let list) = block.content { list } else { nil }
        }
    }

    private func height(of view: some View, width: CGFloat) -> CGFloat {
        let host = UIHostingController(rootView: view.environment(\.dynamicTypeSize, .large))
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    private func texts(_ blocks: [GlimmerStaticBlock]) -> [AttributedString] {
        blocks.flatMap { block -> [AttributedString] in
            switch block.content {
            case .text(let text, _), .code(let text): [text]
            case .table(let rows): rows
            case .quote(let blocks): texts(blocks)
            case .list(let list): list.items.flatMap { texts($0.blocks) }
            case .rule: []
            }
        }
    }

    private func flattenedItems(
        _ blocks: [GlimmerStaticBlock], depth: Int = 0
    ) -> [(depth: Int, marker: String, text: String)] {
        blocks.flatMap { block -> [(depth: Int, marker: String, text: String)] in
            guard case .list(let list) = block.content else { return [] }
            return list.items.flatMap { item in
                let own = texts(item.blocks.filter {
                    if case .list = $0.content { false } else { true }
                }).map { String($0.characters) }.joined()
                return [(depth, String(item.marker.characters), own)] + flattenedItems(item.blocks, depth: depth + 1)
            }
        }
    }
}

/// An extension that is not `Hashable`, so documents composed with it are never shared.
private struct UncachedExtension: GlimmerExtension {
    func scan(_ text: String) -> [GlimmerInlineToken] { [] }
}

/// Opens a URL with the environment's `openURL` once it appears.
private struct LinkProbe: View {
    let url: URL
    @Environment(\.openURL) private var openURL

    var body: some View {
        Color.clear.frame(width: 10, height: 10).onAppear { openURL(url) }
    }
}

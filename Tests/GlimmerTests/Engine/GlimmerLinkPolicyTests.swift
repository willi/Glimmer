import SwiftUI
import UIKit
import XCTest
@testable import Glimmer

/// Links only to `https` URLs.
private struct HTTPSOnly: GlimmerLinkPolicy {
    func decision(for link: GlimmerLinkCandidate) -> GlimmerLinkDecision {
        link.url?.scheme == "https" ? .link : .text
    }
}

/// Links only to the given schemes.
private struct AllowSchemes: GlimmerLinkPolicy {
    var schemes: Set<String>
    func decision(for link: GlimmerLinkCandidate) -> GlimmerLinkDecision {
        link.url?.scheme.map { schemes.contains($0) } == true ? .link : .text
    }
}

/// Every link is a link.
private struct AllowAll: GlimmerLinkPolicy {
    func decision(for link: GlimmerLinkCandidate) -> GlimmerLinkDecision { .link }
}

/// Refuses a link whose title is "no".
private struct RefuseTitled: GlimmerLinkPolicy {
    func decision(for link: GlimmerLinkCandidate) -> GlimmerLinkDecision { link.title == "no" ? .text : .link }
}

@MainActor
final class GlimmerLinkPolicyTests: XCTestCase {
    /// Inputs where SuperMe's rewrite of the markdown and cmark disagreed about where a link ends.
    private let bypasses = [
        #"[y <span title="]">](someapp://evil2)"#,
        "[y <https://ok/]>](someapp://evil3)",
        "[x <https://a]>](someapp://evil)",
    ]

    override func setUp() async throws {
        GlimmerDocumentCache.shared.removeAll()
        GlimmerStaticDocumentCache.shared.removeAll()
    }

    private func compose(_ markdown: String, policy: (any GlimmerLinkPolicy)?) -> NSAttributedString {
        GlimmerComposer(theme: .default, linkPolicy: policy).compose(GlimmerParser.parse(markdown))
    }

    private func configuration(_ policy: (any GlimmerLinkPolicy)?) -> GlimmerConfiguration {
        GlimmerConfiguration(imageLoader: nil, reveal: .none, linkPolicy: policy)
    }

    private func links(in text: NSAttributedString) -> [URL] {
        var found: [URL] = []
        text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let url = value as? URL { found.append(url) }
        }
        return found
    }

    private func links(in text: AttributedString) -> [URL] {
        text.runs.compactMap(\.link)
    }

    private func attributes(of substring: String, in text: NSAttributedString) -> [NSAttributedString.Key: Any] {
        let range = (text.string as NSString).range(of: substring)
        guard range.location != NSNotFound else {
            XCTFail("missing \(substring.debugDescription) in \(text.string.debugDescription)")
            return [:]
        }
        return text.attributes(at: range.location, effectiveRange: nil)
    }

    private func markdown(of text: NSAttributedString) -> String {
        GlimmerMarkdownSerializer.markdown(from: text, range: NSRange(location: 0, length: text.length))
    }

    private func staticTexts(_ blocks: [GlimmerStaticBlock]) -> [AttributedString] {
        blocks.flatMap { block -> [AttributedString] in
            switch block.content {
            case .text(let text, _), .code(let text): [text]
            case .table(let rows): rows
            case .quote(let blocks): staticTexts(blocks)
            case .list(let list): list.items.flatMap { staticTexts($0.blocks) }
            case .rule: []
            }
        }
    }

    private func staticLinks(_ markdown: String, policy: (any GlimmerLinkPolicy)?) -> [URL] {
        let document = GlimmerStaticDocument(
            markdown: markdown, configuration: configuration(policy), dynamicTypeSize: .large
        )
        return staticTexts(document.blocks).flatMap { links(in: $0) }
    }

    // MARK: - Composing

    func testARefusedLinkComposesAsTheTextAroundIt() {
        let text = compose("See [x](someapp://a) here.", policy: HTTPSOnly())
        XCTAssertEqual(text.string, "See x here.")
        let link = attributes(of: "x", in: text)
        XCTAssertNil(link[.link])
        XCTAssertNil(link[.underlineStyle])
        XCTAssertEqual(link[.foregroundColor] as? UIColor, attributes(of: "See", in: text)[.foregroundColor] as? UIColor)
        XCTAssertTrue(links(in: text).isEmpty)
    }

    func testAnAllowedLinkKeepsItsLink() {
        let text = compose("See [x](https://a) here.", policy: HTTPSOnly())
        let link = attributes(of: "x", in: text)
        XCTAssertEqual(link[.link] as? URL, URL(string: "https://a"))
        XCTAssertEqual(link[.foregroundColor] as? UIColor, GlimmerTheme.default.linkColor)
    }

    func testAutolinksAndBareURLsFollowThePolicy() {
        let policy = HTTPSOnly()
        let autolink = compose("Open <someapp://a> now.", policy: policy)
        XCTAssertEqual(autolink.string, "Open someapp://a now.")
        XCTAssertTrue(links(in: autolink).isEmpty)
        let www = compose("Visit www.example.com today.", policy: policy)
        XCTAssertTrue(links(in: www).isEmpty, "a bare www URL links to http, which the policy refuses")
        let https = compose("Visit https://ok today.", policy: policy)
        XCTAssertEqual(links(in: https), [URL(string: "https://ok")].compactMap { $0 })
        XCTAssertEqual(links(in: compose("Open <https://ok>.", policy: policy)).count, 1)
    }

    func testThePolicySeesTheDestinationAndTitle() {
        let text = compose(#"[a](https://a "no") and [b](https://b "yes")"#, policy: RefuseTitled())
        XCTAssertEqual(links(in: text), [URL(string: "https://b")].compactMap { $0 })
        let candidate = GlimmerLinkCandidate(destination: "someapp://a", title: "t")
        XCTAssertEqual(candidate.url, URL(string: "someapp://a"))
        XCTAssertEqual(candidate.destination, "someapp://a")
        XCTAssertEqual(candidate.title, "t")
        XCTAssertNil(GlimmerLinkCandidate(destination: "https://a").title)
    }

    func testReviewerBypassesProduceNoRefusedLink() {
        let policy = HTTPSOnly()
        for markdown in bypasses {
            let text = compose(markdown, policy: policy)
            XCTAssertFalse(links(in: text).contains { $0.scheme == "someapp" }, markdown)
            let copied = compose(self.markdown(of: text), policy: nil)
            XCTAssertFalse(links(in: copied).contains { $0.scheme == "someapp" }, "copied: \(markdown)")
            let plain = GlimmerView.attributedString(for: markdown, configuration: configuration(policy))
            XCTAssertFalse(links(in: plain).contains { $0.scheme == "someapp" }, "attributed: \(markdown)")
            XCTAssertFalse(staticLinks(markdown, policy: policy).contains { $0.scheme == "someapp" }, "static: \(markdown)")
        }
    }

    func testARefusedLinkKeepsItsNestedEmphasis() throws {
        let text = compose("[**bold** and *it*](someapp://a)", policy: HTTPSOnly())
        XCTAssertEqual(text.string, "bold and it")
        let bold = try XCTUnwrap(attributes(of: "bold", in: text)[.font] as? UIFont)
        XCTAssertTrue(bold.fontDescriptor.symbolicTraits.contains(.traitBold))
        let italic = try XCTUnwrap(attributes(of: "it", in: text)[.font] as? UIFont)
        XCTAssertTrue(italic.fontDescriptor.symbolicTraits.contains(.traitItalic))
        XCTAssertTrue(links(in: text).isEmpty)
        XCTAssertEqual(markdown(of: text), "**bold** and *it*")
    }

    // MARK: - Copy

    func testARefusedLinkCopiesAsItsText() {
        let policy = HTTPSOnly()
        let text = compose("See [x](someapp://secret) and [y](https://ok).", policy: policy)
        XCTAssertEqual(markdown(of: text), "See x and [y](https://ok).")
        assertEquivalent(compose(markdown(of: text), policy: policy), text, "copied and composed again")
    }

    func testCopyAnswerNeverHandsOutARefusedURL() {
        let view = GlimmerView(configuration: configuration(HTTPSOnly()))
        let window = hostInWindow(view, width: 390, height: 600)
        view.update(markdown: "See [x](someapp://secret).")
        settle(view)
        XCTAssertEqual(view.markdownSource(), "See x.")
        XCTAssertEqual(view.plainText(), "See x.")
        _ = window
    }

    // MARK: - Standalone text

    func testAttributedStringHonoursThePolicy() {
        let markdown = "See [x](someapp://a) and [y](https://ok)."
        let text = GlimmerView.attributedString(for: markdown, configuration: configuration(HTTPSOnly()))
        XCTAssertEqual(links(in: text), [URL(string: "https://ok")].compactMap { $0 })
        XCTAssertEqual(links(in: GlimmerView.attributedString(for: markdown, configuration: configuration(nil))).count, 2)
    }

    func testStaticTextHonoursThePolicy() {
        let markdown = "See [x](someapp://a) and [y](https://ok).\n\n- [z](someapp://b)"
        XCTAssertEqual(staticLinks(markdown, policy: HTTPSOnly()), [URL(string: "https://ok")].compactMap { $0 })
        XCTAssertEqual(staticLinks(markdown, policy: nil).count, 3)
    }

    // MARK: - Caches

    func testEqualPoliciesShareSettledTextAndDifferentOnesDoNot() {
        let markdown = "See [x](someapp://a) and [y](https://ok)."
        let hits = GlimmerDocumentCache.shared.hits
        for _ in 0..<2 {
            let view = GlimmerView(configuration: configuration(HTTPSOnly()))
            view.update(markdown: markdown)
            XCTAssertEqual(links(in: view.textView.textStorage).count, 1)
        }
        XCTAssertEqual(GlimmerDocumentCache.shared.hits, hits + 1)
        let open = GlimmerView(configuration: configuration(nil))
        open.update(markdown: markdown)
        XCTAssertEqual(links(in: open.textView.textStorage).count, 2, "no policy never reuses text composed under one")
        let other = GlimmerView(configuration: configuration(AllowSchemes(schemes: ["someapp"])))
        other.update(markdown: markdown)
        XCTAssertEqual(links(in: other.textView.textStorage).map(\.scheme), ["someapp"])
        XCTAssertEqual(GlimmerDocumentCache.shared.hits, hits + 1)
    }

    func testLinkPoliciesAreKeyedByTypeAndValue() {
        let one = GlimmerLinkPolicyKey(policy: AllowSchemes(schemes: ["https"]))
        XCTAssertEqual(one, GlimmerLinkPolicyKey(policy: AllowSchemes(schemes: ["https"])))
        XCTAssertEqual(one.hashValue, GlimmerLinkPolicyKey(policy: AllowSchemes(schemes: ["https"])).hashValue)
        XCTAssertNotEqual(one, GlimmerLinkPolicyKey(policy: AllowSchemes(schemes: ["someapp"])))
        XCTAssertNotEqual(GlimmerLinkPolicyKey(policy: AllowAll()), GlimmerLinkPolicyKey(policy: HTTPSOnly()))
    }

    func testStaticDocumentsAreSharedOnlyUnderEqualPolicies() {
        let cache = GlimmerStaticDocumentCache()
        let markdown = "See [x](someapp://a)."
        let first = cache.document(markdown: markdown, configuration: configuration(HTTPSOnly()), dynamicTypeSize: .large)
        let again = cache.document(markdown: markdown, configuration: configuration(HTTPSOnly()), dynamicTypeSize: .large)
        XCTAssertTrue(again === first)
        let open = cache.document(markdown: markdown, configuration: configuration(nil), dynamicTypeSize: .large)
        XCTAssertFalse(open === first)
        let other = cache.document(
            markdown: markdown, configuration: configuration(AllowSchemes(schemes: ["someapp"])), dynamicTypeSize: .large
        )
        XCTAssertFalse(other === first)
        XCTAssertEqual(cache.builds, 3)
    }

    // MARK: - No policy

    func testWithNoPolicyEveryLinkIsALink() {
        XCTAssertNil(GlimmerConfiguration().linkPolicy)
        let markdown = "[x](someapp://a), <someapp://b>, www.example.com, https://ok and [**y**](https://y)"
        let text = compose(markdown, policy: nil)
        XCTAssertEqual(links(in: text).count, 5)
        assertEquivalent(text, compose(markdown, policy: AllowAll()), "no policy links like one that allows everything")
        assertEquivalent(
            text, GlimmerComposer(theme: .default).compose(GlimmerParser.parse(markdown)), "nil is the default"
        )
    }
}

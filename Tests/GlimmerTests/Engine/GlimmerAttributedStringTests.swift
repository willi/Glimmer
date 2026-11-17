import SwiftUI
import UIKit
import XCTest
@testable import Glimmer

/// A `[3]` chip that links to a page when rendered as plain text.
private struct LinkedCitations: GlimmerExtension {
    func scan(_ text: String) -> [GlimmerInlineToken] {
        text.ranges(of: #/\[\d+\]/#).map { range in
            let label = String(text[range])
            var token = GlimmerInlineToken(range: range, kind: "citation", displayText: label, source: label)
            token.url = URL(string: "https://a.example/cite")
            return token
        }
    }

    @MainActor func makeInlineView(for token: GlimmerInlineToken, theme: GlimmerTheme) -> UIView? { UILabel() }
}

@MainActor
final class GlimmerAttributedStringTests: XCTestCase {
    func testTextKeepsEmphasisAndLinks() throws {
        let text = GlimmerView.attributedString(for: "Hello **world** [x](https://a.example)")
        XCTAssertEqual(String(text.characters), "Hello world x")
        let x = try XCTUnwrap(text.range(of: "x"))
        XCTAssertEqual(text[x].link, URL(string: "https://a.example"))
        let world = try XCTUnwrap(text.range(of: "world"))
        XCTAssertTrue(text[world].uiKit.font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
        XCTAssertTrue(text.runs.allSatisfy { $0.swiftUI.font != nil && $0.swiftUI.foregroundColor != nil })
    }

    func testImagesAndTheirSpaceAreDropped() {
        let text = GlimmerView.attributedString(for: "Led by ![Acme](https://a.example/a.png) Acme.")
        XCTAssertEqual(String(text.characters), "Led by Acme.")
    }

    func testAnswerOfOnlyAnImageIsEmpty() {
        XCTAssertEqual(GlimmerView.attributedString(for: "![a](https://a.example/a.png)").characters.count, 0)
    }

    func testACodeBlockBecomesMonospacedText() throws {
        let text = GlimmerView.attributedString(for: "```\nlet x = 1\n```")
        XCTAssertEqual(String(text.characters), "let x = 1")
        let code = try XCTUnwrap(text.range(of: "let x = 1"))
        XCTAssertTrue(text[code].uiKit.font?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) ?? false)
        XCTAssertNotNil(text[code].swiftUI.font)
    }

    func testATableBecomesTabbedRows() {
        let text = GlimmerView.attributedString(for: "| a | b |\n|---|---|\n| 1 | 2 |")
        XCTAssertEqual(String(text.characters), "a\tb\n1\t2")
    }

    func testAThematicBreakIsDropped() {
        let text = GlimmerView.attributedString(for: "One\n\n---\n\nTwo")
        XCTAssertFalse(String(text.characters).contains("\u{FFFC}"))
        XCTAssertTrue(String(text.characters).hasPrefix("One"))
        XCTAssertTrue(String(text.characters).hasSuffix("Two"))
    }

    func testAChipBecomesLinkedText() throws {
        var configuration = GlimmerConfiguration()
        configuration.extensions = [LinkedCitations()]
        let text = GlimmerView.attributedString(for: "Source [3] here", configuration: configuration)
        XCTAssertEqual(String(text.characters), "Source [3] here")
        let chip = try XCTUnwrap(text.range(of: "[3]"))
        XCTAssertEqual(text[chip].link, URL(string: "https://a.example/cite"))
        XCTAssertNotNil(text[chip].swiftUI.font)
    }

    func testATappableTextTokenLosesItsInternalLink() throws {
        var configuration = GlimmerConfiguration()
        configuration.extensions = [GlimmerMentions()]
        let text = GlimmerView.attributedString(for: "Ask @grace now", configuration: configuration)
        XCTAssertEqual(String(text.characters), "Ask @grace now")
        let mention = try XCTUnwrap(text.range(of: "@grace"))
        XCTAssertNil(text[mention].link)
    }
}

import XCTest
import SwiftUI
import UIKit
@testable import Glimmer

@MainActor
final class RevealSettledParityTests: XCTestCase {
    func testCompletedRevealMatchesSettledMarkdownLayoutForRepresentativeMarkdown() {
        for fixture in fixtures {
            assertCompletedRevealMatchesSettledMarkdown(
                fixture.markdown,
                name: fixture.name,
                configuration: fixture.configuration
            )
        }
    }

    func testCompletedSmoothTrailMatchesSettledMarkdownLayout() {
        for fixture in fixtures {
            assertCompletedRevealMatchesSettledMarkdown(
                fixture.markdown,
                name: fixture.name,
                configuration: fixture.configuration,
                style: .smoothTrail
            )
        }
    }

    func testCompletedRevealTablesUseSettledTableSizing() {
        let markdown = """
        | | On-page SEO | Technical SEO | Off-page SEO | Content SEO |
        | --- | --- | --- | --- | --- |
        | **Focus** | Individual page elements | Site infrastructure | Signals from other sites | Useful pages and topical depth |
        | **What you control** | Titles, headings, keywords, meta tags, internal links | Site speed, UX, crawlability, sitemaps, structured data | Backlinks, mentions, authority, partnerships | Blog posts, guides, landing pages, search intent matching |
        | **Goal** | Help search engines understand what each page is about | Make the site easier for search engines to crawl, render, and rank | Prove trust and relevance outside your site | Satisfy the user's actual search intent |
        | **Effort type** | Copywriting + structure | Engineering + QA | Digital PR + relationships | Research + writing + product marketing |
        | **Speed of impact** | Medium - changes can show results in days/weeks | Fast for issues blocking crawl or indexing | Slow - takes months to compound | Medium to slow - compounds as topical authority builds |
        | **Example** | Optimizing a title tag for a product page | Fixing crawl errors and adding schema markup | Getting industry sites to link to a research report | Publishing a complete guide that answers a high-intent query |
        """

        let settled = host(
            GlimmerRevealView(
                markdown: markdown,
                reveal: RevealConfiguration(style: .none),
                configuration: .github
            )
        )
        let revealed = hostCompletedReveal(markdown: markdown, style: .trailFade, configuration: .github)

        pumpLayout(settled)
        pumpLayout(revealed)

        let settledScrollView = firstScrollView(in: settled.view)
        let revealedScrollView = firstScrollView(in: revealed.view)
        XCTAssertNotNil(settledScrollView)
        XCTAssertNotNil(revealedScrollView)

        if let settledScrollView, let revealedScrollView {
            XCTAssertEqual(revealedScrollView.bounds.height, settledScrollView.bounds.height, accuracy: 1)
            XCTAssertEqual(revealedScrollView.contentSize.height, settledScrollView.contentSize.height, accuracy: 1)
            XCTAssertGreaterThanOrEqual(
                revealedScrollView.bounds.height + 1,
                revealedScrollView.contentSize.height,
                "Completed reveal tables must not clip wrapped rows."
            )
        }
    }

    func testSettledAndCompletedRevealTablesStayCompactAtMobileWidth() {
        let markdown = """
        | Check | Result |
        | --- | --- |
        | Template headings | 22 ✓ |
        | Member responses across 21 panel templates | 63 (21 × 3) ✓ |
        """
        let settled = hostMobileChat(
            GlimmerRevealView(
                markdown: markdown,
                reveal: RevealConfiguration(style: .none),
                configuration: .github
            )
        )

        let revealID = "compact-completed-\(UUID().uuidString)"
        let model = Glimmer.revealModel(markdown, style: .trailFade, configuration: .github)
        RevealProgressStore.shared.record(model.countableCount, for: revealID)
        let revealed = hostMobileChat(
            GlimmerRevealView(
                markdown: markdown,
                reveal: RevealConfiguration(
                    style: .trailFade,
                    isStreaming: false,
                    revealID: revealID
                ),
                configuration: .github
            )
        )

        pumpLayout(settled)
        pumpLayout(revealed)

        let settledHeight = compactTableHeight(in: settled, label: "settled")
        let revealedHeight = compactTableHeight(in: revealed, label: "completed reveal")
        XCTAssertEqual(revealedHeight, settledHeight, accuracy: 1)
    }

    private var fixtures: [(name: String, markdown: String, configuration: MarkdownConfiguration)] {
        [
            (
                "paragraph with emphasis and link",
                "Some **bold** and *emphasized* text with [a link](https://example.com) and `code`.",
                .github
            ),
            (
                "headings and paragraphs",
                """
                ## Search basics

                Search visibility depends on useful content, crawlability, and trust.
                """,
                .github
            ),
            (
                "unordered and ordered lists",
                """
                - On-page SEO
                - Technical SEO
                    - Crawlability
                    - Speed

                1. Research intent
                2. Publish useful pages
                """,
                .github
            ),
            (
                "blockquote",
                """
                > Search traffic compounds when useful pages keep earning links.
                > Keep the answer direct and complete.
                """,
                .github
            ),
            (
                "code fence",
                """
                ```swift
                let title = "SEO"
                print(title)
                ```
                """,
                .github
            ),
            (
                "task list",
                """
                - [x] Audit titles
                - [ ] Fix crawl errors
                """,
                .github
            ),
            (
                "table",
                """
                | Area | Signal | Owner |
                | --- | --- | --- |
                | Content | Helpful pages | Marketing |
                | Technical | Crawlable site | Engineering |
                """,
                .github
            )
        ]
    }

    private func assertCompletedRevealMatchesSettledMarkdown(
        _ markdown: String,
        name: String,
        configuration: MarkdownConfiguration,
        style: RevealStyle = .trailFade,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let settled = host(
            GlimmerRevealView(
                markdown: markdown,
                reveal: RevealConfiguration(style: .none),
                configuration: configuration
            )
        )
        let revealed = hostCompletedReveal(markdown: markdown, style: style, configuration: configuration)

        pumpLayout(settled)
        pumpLayout(revealed)

        let settledSize = settled.sizeThatFits(in: CGSize(width: Self.width, height: Self.maxHeight))
        let revealedSize = revealed.sizeThatFits(in: CGSize(width: Self.width, height: Self.maxHeight))

        XCTAssertEqual(revealedSize.width, settledSize.width, accuracy: 0.5, name, file: file, line: line)
        XCTAssertEqual(revealedSize.height, settledSize.height, accuracy: 1.5, name, file: file, line: line)
    }

    private func hostCompletedReveal(
        markdown: String,
        style: RevealStyle,
        configuration: MarkdownConfiguration
    ) -> UIHostingController<AnyView> {
        let revealID = "completed-\(UUID().uuidString)"
        let model = Glimmer.revealModel(markdown, style: style, configuration: configuration)
        RevealProgressStore.shared.record(model.countableCount, for: revealID)

        return host(
            GlimmerRevealView(
                markdown: markdown,
                reveal: RevealConfiguration(
                    style: style,
                    isStreaming: false,
                    revealID: revealID
                ),
                configuration: configuration
            )
        )
    }

    private static let width: CGFloat = 430
    private static let maxHeight: CGFloat = 4_000

    private func hostMobileChat<V: View>(_ view: V) -> UIHostingController<AnyView> {
        let width: CGFloat = 320
        let host = UIHostingController(
            rootView: AnyView(view
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width, alignment: .leading)
                .transaction { $0.disablesAnimations = true })
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        return host
    }

    private func host<V: View>(_ view: V) -> UIHostingController<AnyView> {
        let host = UIHostingController(
            rootView: AnyView(view
                .frame(width: Self.width, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .transaction { $0.disablesAnimations = true })
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: Self.width, height: 932))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        return host
    }

    private func pumpLayout(_ host: UIHostingController<AnyView>) {
        for _ in 0..<8 {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private func compactTableHeight(
        in host: UIHostingController<AnyView>,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> CGFloat {
        guard let scrollView = firstScrollView(in: host.view) else {
            XCTFail("Expected \(label) output to contain a table scroll view.", file: file, line: line)
            return 0
        }

        XCTAssertGreaterThan(scrollView.bounds.height, 0, file: file, line: line)
        XCTAssertLessThan(
            scrollView.bounds.height,
            180,
            "The \(label) table should hug its rows at mobile width.",
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            scrollView.bounds.height + 1,
            scrollView.contentSize.height,
            "The \(label) table must not clip wrapped rows.",
            file: file,
            line: line
        )
        return scrollView.bounds.height
    }

    private func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView {
            return scrollView
        }

        for subview in view.subviews {
            if let match = firstScrollView(in: subview) {
                return match
            }
        }

        return nil
    }
}

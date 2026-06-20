import XCTest
import SwiftUI
import UIKit
@testable import Glimmer

final class TableColumnWidthTests: XCTestCase {
    func testConstrainedColumnWidthsCapWideColumnsForWrapping() {
        let widths: [CGFloat] = [120, 900, 240, 220]

        let constrained = TextMeasurement.constrainColumnWidthsForWrapping(
            widths,
            availableWidth: 360
        )

        XCTAssertEqual(constrained, [120, 198, 198, 198])
    }

    func testConstrainedColumnWidthsFillAvailableWidthForSmallTables() {
        let constrained = TextMeasurement.constrainColumnWidthsForWrapping(
            [80, 100],
            availableWidth: 320
        )

        XCTAssertEqual(constrained.reduce(0, +), 320)
        XCTAssertEqual(constrained, [160, 160])
    }

    func testConstrainedColumnWidthsKeepIntrinsicWidthsWithoutContainerWidth() {
        let widths: [CGFloat] = [100, 240, 180]

        let constrained = TextMeasurement.constrainColumnWidthsForWrapping(
            widths,
            availableWidth: 0
        )

        XCTAssertEqual(constrained, widths)
    }

    func testCoreTextInlineMeasurementMatchesTextKitForRepresentativeMarkdown() throws {
        let samples = try makeRepresentativeInlineMeasurementSamples()

        for sample in samples {
            let textKitWidth = TextMeasurement.measureInlineNodesWithTextKitForTesting(sample, baseFont: .body)
            let coreTextWidth = TextMeasurement.measureInlineNodesWithCoreTextForTesting(sample, baseFont: .body)

            XCTAssertEqual(
                coreTextWidth,
                textKitWidth,
                accuracy: 2,
                "CoreText width must match TextKit width for \(sample)."
            )
        }
    }

    func testCoreTextTableWidthsMatchTextKitTableWidths() throws {
        let markdown = """
        | Pillar | What it covers | Owner | Time to impact |
        | --- | --- | --- | --- |
        | **On-page SEO** | Keywords, titles, meta tags, headings, content structure, internal links | Content / marketing | Weeks to months |
        | Technical SEO | Site speed, crawlability, indexing, sitemaps, structured data, mobile UX, Core Web Vitals | Engineering / dev | Days to months |
        | Off-page SEO | Backlinks, brand mentions, domain authority, digital PR | Marketing / partnerships | Months to years |
        | Content | Blog posts, guides, landing pages, topical authority, search intent matching | Content / product marketing | Months (compounds) |
        """
        let blocks = MarkdownParser.parse(markdown, configuration: .github)
        guard case .table(let header, let rows) = blocks.first else {
            return XCTFail("Expected a parsed table")
        }

        let textKitWidths = TextMeasurement.calculateColumnWidthsUncachedWithTextKitForTesting(
            header: header,
            rows: rows,
            baseFont: .body
        )
        let coreTextWidths = TextMeasurement.calculateColumnWidthsUncachedForTesting(
            header: header,
            rows: rows,
            baseFont: .body
        )

        XCTAssertEqual(coreTextWidths.count, textKitWidths.count)
        for (coreTextWidth, textKitWidth) in zip(coreTextWidths, textKitWidths) {
            XCTAssertEqual(coreTextWidth, textKitWidth, accuracy: 2)
        }
    }

    func testChatSEOComparisonTableWidthsStayFiniteAndFast() throws {
        let markdown = """
        Here's a quick breakdown of the differences between the main SEO pillars:

        | | On-page SEO | Technical SEO | Off-page SEO |
        | --- | --- | --- | --- |
        | **Focus** | Individual page elements | Site infrastructure | Signals from other sites |
        | **What you do** | Optimize titles, headings, keywords, meta tags, internal links | Fix site speed, UX, crawlability, sitemaps, structured data | Build backlinks, mentions, authority, partnerships |
        | **Who controls it** | You (on your site) | You (with engineering help) | Other sites and the market |
        | **Why it matters** | Helps search engines understand each page | Helps crawlers access and rank the site | Shows trust and relevance outside your site |
        """
        let blocks = MarkdownParser.parse(markdown, configuration: .github)
        guard case .table(let header, let rows) = blocks.first(where: {
            if case .table = $0 { return true }
            return false
        }) else {
            return XCTFail("Expected parsed SEO comparison table")
        }

        TextMeasurement.clearColumnWidthCacheForTesting()
        let elapsed = timed {
            for _ in 0..<250 {
                _ = TextMeasurement.calculateColumnWidthsUncachedForTesting(
                    header: header,
                    rows: rows,
                    baseFont: .body
                )
            }
        }

        let measuredWidths = TextMeasurement.calculateColumnWidths(
            header: header,
            rows: rows,
            baseFont: .body
        )
        let constrainedWidths = TextMeasurement.constrainColumnWidthsForWrapping(
            measuredWidths,
            availableWidth: 430
        )

        XCTAssertEqual(constrainedWidths.count, 4)
        XCTAssertTrue(constrainedWidths.allSatisfy { $0.isFinite && $0 > 0 })
        XCTAssertLessThan(
            elapsed,
            0.5,
            "Chat-sized SEO tables should not hang the main-thread table width path."
        )
    }

    @MainActor
    func testWrappedTableHorizontalScrollViewExpandsToFullContentHeight() throws {
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
        let blocks = MarkdownParser.parse(markdown, configuration: .github)
        guard case .table(let header, let rows) = blocks.first(where: {
            if case .table = $0 { return true }
            return false
        }) else {
            return XCTFail("Expected parsed SEO comparison table")
        }

        assertHorizontalScrollViewShowsFullContentHeight(
            MarkdownTableView(header: header, rows: rows, configuration: .github)
        )
        assertHorizontalScrollViewShowsFullContentHeight(
            InteractiveMarkdownTableView(
                header: header,
                rows: rows,
                configuration: .github,
                onLinkTap: { _ in },
                onMentionTap: nil,
                onIssueTap: nil,
                onFootnoteTap: nil
            )
        )
    }

    private func makeRepresentativeInlineMeasurementSamples() throws -> [[MarkdownParser.InlineNode]] {
        let exampleURL = try XCTUnwrap(URL(string: "https://example.com/docs/table"))
        return [
            [.text("Plain table content")],
            [.strong(children: [.text("Bold"), .text(" header")])],
            [.emphasis(children: [.text("Italic value")])],
            [.strikethrough(children: [.text("Removed value")])],
            [.code("let value = row.count")],
            [.link(url: exampleURL, title: "Example", children: [.text("linked text")])],
            [.autolink(exampleURL, .url, originalText: "https://example.com/docs/table")],
            [.mention(username: "alice"), .text(" opened "), .issueReference(number: 42)],
            [
                .repositoryReference(owner: "openai", repo: "glimmer"),
                .text(" "),
                .pullRequestReference(owner: "openai", repo: "glimmer", number: 7)
            ],
            [.commitSHA(sha: "abcdef1234567890", short: "abcdef1")],
            [.image(url: exampleURL, alt: "diagram alt text", title: nil)],
            [.text("before"), .softBreak, .text("after")],
            [.text("before"), .lineBreak, .text("after")],
            [.footnoteReference(label: "inline-1"), .text(" footnote")],
            [
                .extensionInline(
                    MarkdownParser.ExtensionNode(
                        namespace: "test",
                        name: "token",
                        literal: "{{token}}",
                        fields: [:]
                    )
                )
            ]
        ]
    }

    private func timed(_ block: () -> Void) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        block()
        return CFAbsoluteTimeGetCurrent() - start
    }

    @MainActor
    private func assertHorizontalScrollViewShowsFullContentHeight<V: View>(
        _ view: V,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let host = UIHostingController(
            rootView: view
                .frame(width: 430, alignment: .leading)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 932))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds

        for _ in 0..<6 {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        guard let scrollView = firstScrollView(in: host.view) else {
            return XCTFail("Expected table view to contain a horizontal UIScrollView.", file: file, line: line)
        }

        XCTAssertGreaterThan(scrollView.contentSize.height, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(
            scrollView.bounds.height + 1,
            scrollView.contentSize.height,
            "The horizontal table scroll view must be tall enough for wrapped rows.",
            file: file,
            line: line
        )
    }

    @MainActor
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

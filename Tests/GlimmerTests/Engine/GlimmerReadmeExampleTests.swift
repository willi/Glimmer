import SwiftUI
import UIKit
import XCTest
import Glimmer

/// The README's examples, compiled and run. If one of these changes, change the README with it.
@MainActor
final class GlimmerReadmeExampleTests: XCTestCase {
    func testUIKitQuickStart() {
        let view = GlimmerView()
        view.onLinkTap = { url in UIApplication.shared.open(url) }
        view.update(markdown: "# Hello\n\nThis is **Glimmer**.")
        XCTAssertGreaterThan(view.sizeThatFits(CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)).height, 0)
    }

    func testStreaming() {
        let view = GlimmerView()
        let messageID = "message-1"
        var received = ""
        for chunk in ["Glimmer reveals ", "an answer ", "phrase by phrase."] {
            received += chunk
            view.update(markdown: received, isStreaming: true, revealID: messageID)
        }
        view.update(markdown: received, isStreaming: false, revealID: messageID)
    }

    func testStreamingControl() {
        let view = GlimmerView()
        view.update(markdown: "A finished answer.", isStreaming: false, revealID: "message-2", revealsFinishedText: true)
        view.finishReveal() // a newer answer started: stop animating this one
        XCTAssertFalse(view.isRevealing)
    }

    func testSizing() {
        let view = GlimmerView()
        view.update(markdown: "A short reply.")
        let width = view.fittingWidth(maximum: 280)
        let height = view.height(forWidth: width, notExceeding: 120)
        XCTAssertGreaterThan(width, 0)
        XCTAssertLessThanOrEqual(width, 280)
        XCTAssertGreaterThan(height, 0)
        XCTAssertTrue(view.isLayoutSettled)
    }

    func testSwiftUI() {
        struct Answer: View {
            let text: String
            let isStreaming: Bool
            var body: some View {
                ScrollView {
                    GlimmerText(text, isStreaming: isStreaming, revealID: "message-1") { url in print(url) }
                        .padding()
                }
            }
        }
        _ = UIHostingController(rootView: Answer(text: "Hi", isStreaming: false))
    }

    func testPlainAttributedText() {
        struct Summary: View {
            let markdown: String
            var body: some View {
                Text(GlimmerView.attributedString(for: markdown))
            }
        }
        _ = UIHostingController(rootView: Summary(markdown: "A **short** summary."))
        XCTAssertEqual(String(GlimmerView.attributedString(for: "A **short** summary.").characters), "A short summary.")
    }

    func testConfiguration() {
        var configuration = GlimmerConfiguration()
        configuration.theme.linkColor = .systemPurple
        configuration.reveal = .smooth(GlimmerRevealOptions())
        configuration.dataDetectors = [.phoneNumber]
        configuration.allowsFind = true
        let view = GlimmerView(configuration: configuration)
        view.editMenuActions = { selection in
            [UIAction(title: "Ask about this") { _ in print(selection.markdown) }]
        }
        view.linkMenuActions = { url in [UIAction(title: "Copy Link") { _ in UIPasteboard.general.url = url }] }
        _ = view.markdownSource()
    }

    func testExtension() {
        struct Citations: GlimmerExtension {
            func scan(_ text: String) -> [GlimmerInlineToken] {
                text.ranges(of: #/\[\d+\]/#).map { range in
                    let label = String(text[range])
                    return GlimmerInlineToken(range: range, kind: "citation", displayText: label, source: label,
                                              accessibilityLabel: "Source \(label.dropFirst().dropLast())")
                }
            }
        }
        var configuration = GlimmerConfiguration()
        configuration.extensions = [Citations()]
        GlimmerView(configuration: configuration).update(markdown: "As shown [1].")
    }
}

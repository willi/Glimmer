import SwiftUI
import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerRevealViewControllerTests: XCTestCase {
    func testUpdatesPreserveHostedControllerAndResetRestartsCompletion() {
        var completionCount = 0
        let controller = GlimmerRevealViewController(
            markdown: "First message",
            reveal: RevealConfiguration(style: .none),
            onComplete: { completionCount += 1 }
        )
        let window = mount(controller)
        pumpLayout(controller)
        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(controller.children.count, 1)
        let host = controller.children.first

        controller.update(markdown: "First message with more text", isStreaming: false)
        pumpLayout(controller)
        XCTAssertEqual(completionCount, 1, "An ordinary buffer update must preserve the reveal view identity.")
        XCTAssertTrue(controller.children.first === host)

        controller.reset(markdown: "A new message", reveal: RevealConfiguration(style: .none))
        pumpLayout(controller)
        XCTAssertEqual(completionCount, 2, "Reset creates a fresh reveal completion lifecycle.")
        XCTAssertTrue(controller.children.first === host, "Reset should reuse the UIKit controller hierarchy.")
        withExtendedLifetime(window) {}
    }

    func testFittingHeightGrowsWhenMarkdownAddsBlocks() {
        let controller = GlimmerRevealViewController(
            markdown: "Short text.",
            reveal: RevealConfiguration(style: .none)
        )
        let window = mount(controller)
        pumpLayout(controller)
        let proposal = CGSize(width: 300, height: 10_000)
        let initialSize = controller.sizeThatFits(in: proposal)

        controller.update(
            markdown: "# Heading\n\n" + String(repeating: "A longer paragraph with **styled** words. ", count: 30),
            isStreaming: false
        )
        pumpLayout(controller)
        let updatedSize = controller.sizeThatFits(in: proposal)

        XCTAssertGreaterThan(initialSize.height, 0)
        XCTAssertLessThanOrEqual(updatedSize.width, proposal.width + 1)
        XCTAssertGreaterThan(updatedSize.height, initialSize.height)
        withExtendedLifetime(window) {}
    }

    func testUpdatesBeforeViewLoadsAppearInInitialLayout() {
        let controller = GlimmerRevealViewController(reveal: RevealConfiguration(style: .none))
        XCTAssertFalse(controller.isViewLoaded)
        controller.update(markdown: "# Received before attachment\n\nThe complete buffer is retained.", isStreaming: false)
        XCTAssertFalse(controller.isViewLoaded)

        let size = controller.sizeThatFits(in: CGSize(width: 300, height: 10_000))
        XCTAssertTrue(controller.isViewLoaded)
        XCTAssertEqual(controller.children.count, 1)
        XCTAssertGreaterThan(size.height, 30)
    }

    func testSelfSizingRepresentableGrowsFromAnEmptyStream() async throws {
        let controller = GlimmerRevealViewController(
            reveal: RevealConfiguration(
                style: .smoothTrail,
                catchUp: .cappedSnap(maxLagSeconds: 0.01),
                isStreaming: true
            )
        )
        let input = ControllerSizingInput()
        let outer = UIHostingController(rootView: ControllerSizingRoot(controller: controller, input: input))
        let window = mount(outer)
        pumpLayout(outer)

        input.markdown = "First words arrive."
        try await Task.sleep(for: .milliseconds(200))
        pumpLayout(outer)
        let firstHeight = controller.view.bounds.height
        XCTAssertGreaterThan(firstHeight, 0, "An initially empty host must invalidate the representable's height.")

        input.markdown = "First words arrive.\n\n"
            + String(repeating: "The next paragraph grows across more lines. ", count: 15)
        input.isStreaming = false
        try await Task.sleep(for: .milliseconds(700))
        pumpLayout(outer)
        XCTAssertGreaterThan(controller.view.bounds.height, firstHeight)
        withExtendedLifetime(window) {}
    }

    private func mount(_ controller: UIViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        return window
    }

    private func pumpLayout(_ controller: UIViewController) {
        for _ in 0..<4 {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }
}

@MainActor
@Observable
private final class ControllerSizingInput {
    var markdown = ""
    var isStreaming = true
}

private struct ControllerSizingRoot: View {
    let controller: GlimmerRevealViewController
    let input: ControllerSizingInput

    var body: some View {
        ScrollView {
            ControllerSizingProbe(controller: controller, markdown: input.markdown, isStreaming: input.isStreaming)
                .frame(maxWidth: .infinity)
                .padding()
        }
    }
}

private struct ControllerSizingProbe: UIViewControllerRepresentable {
    let controller: GlimmerRevealViewController
    let markdown: String
    let isStreaming: Bool

    func makeUIViewController(context: Context) -> GlimmerRevealViewController { controller }

    func updateUIViewController(_ controller: GlimmerRevealViewController, context: Context) {
        controller.update(markdown: markdown, isStreaming: isStreaming)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiViewController: GlimmerRevealViewController,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return uiViewController.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}

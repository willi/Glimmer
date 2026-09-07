import SwiftUI
import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class RevealSmoothTrailRenderingTests: XCTestCase {
    func testAnimatedUIKitHostSettlesAndAcceptsLaterAppend() async throws {
        var completions = 0
        let start = ProcessInfo.processInfo.systemUptime
        var completedAt = 0.0
        let controller = GlimmerRevealViewController(
            markdown: "**First** [word](https://example.com)",
            reveal: .init(style: .smoothTrail, catchUp: .strict),
            onComplete: {
                completions += 1
                completedAt = ProcessInfo.processInfo.systemUptime
            }
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(completions, 0, "Completion must wait for the final fade.")
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(completions, 1)
        XCTAssertGreaterThanOrEqual(completedAt - start, RevealSmoothTrail.duration)
        let proposal = CGSize(width: 300, height: 10_000)
        let before = controller.sizeThatFits(in: proposal)

        controller.update(markdown: "**First** [word](https://example.com)\n\nAnother paragraph.", isStreaming: false)
        try await Task.sleep(for: .seconds(1))
        let after = controller.sizeThatFits(in: proposal)
        XCTAssertGreaterThan(after.height, before.height)
        XCTAssertEqual(completions, 1, "Completion remains once per message identity.")
        window.isHidden = true
    }

}

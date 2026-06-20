import SwiftUI
import UIKit
import XCTest
@testable import Glimmer

final class MarkdownDisplayProfilingTests: XCTestCase {
    @MainActor
    func testMarkdownDisplayScrollLoop() throws {
        let environment = ProcessInfo.processInfo.environment
        let profilingEnabled = environment["GLIMMER_DISPLAY_PROFILING"] == "1"
            || environment["TEST_RUNNER_GLIMMER_DISPLAY_PROFILING"] == "1"
        guard profilingEnabled else {
            throw XCTSkip("Set TEST_RUNNER_GLIMMER_DISPLAY_PROFILING=1 when recording display profiles.")
        }

        var configuration = MarkdownConfiguration.github
        configuration.maxRenderCacheEntries = 8192

        let markdown = ProfilingBenchmarkTests.makeCorpus(sections: 120)
        let blocks = MarkdownParser.parse(markdown, configuration: configuration)

        let host = UIHostingController(
            rootView: ScrollView {
                MarkdownContentView(blocks: blocks, configuration: configuration)
                    .padding()
            }
        )

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 932))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        guard let scrollView = firstScrollView(in: host.view) else {
            return XCTFail("Expected hosted markdown view to contain a UIScrollView.")
        }

        let durationValue = environment["GLIMMER_DISPLAY_PROFILE_SECONDS"]
            ?? environment["TEST_RUNNER_GLIMMER_DISPLAY_PROFILE_SECONDS"]
            ?? "30"
        let duration = TimeInterval(durationValue) ?? 30
        let deadline = Date().addingTimeInterval(duration)
        var iterations = 0
        let maxOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)

        while Date() < deadline {
            autoreleasepool {
                let progress = CGFloat(iterations % 360) / 359
                let offset = maxOffset * progress
                scrollView.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                iterations += 1
            }
            RunLoop.main.run(until: Date().addingTimeInterval(1.0 / 90.0))
        }

        print("[BENCH] display scroll iterations: \(iterations)")
        print("[BENCH] display blocks: \(blocks.count)")
        print("[BENCH] display content height: \(scrollView.contentSize.height)")
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

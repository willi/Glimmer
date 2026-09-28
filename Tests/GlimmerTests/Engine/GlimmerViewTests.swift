import UIKit
import XCTest
@testable import Glimmer

private struct ShoutExtension: GlimmerExtension {
    func preprocess(_ markdown: String) -> String { markdown.replacingOccurrences(of: "!!", with: "**") }
}

@MainActor
final class GlimmerViewTests: XCTestCase {
    func testRendersMarkdownIntoTheTextView() {
        let view = GlimmerView()
        view.update(markdown: "# Hi\n\nThere")
        XCTAssertEqual(view.textView.attributedText.string, "Hi\nThere")
    }

    func testEmptyMarkdownHasZeroHeight() {
        let view = GlimmerView()
        view.update(markdown: "")
        XCTAssertEqual(view.sizeThatFits(CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)).height, 0)
        view.update(markdown: "   \n ")
        XCTAssertEqual(view.sizeThatFits(CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)).height, 0)
    }

    func testPreprocessRunsBeforeParsing() {
        let view = GlimmerView(configuration: GlimmerConfiguration(extensions: [ShoutExtension()]))
        view.update(markdown: "!!loud!!")
        let font = view.textView.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
        XCTAssertEqual(view.textView.attributedText.string, "loud")
    }

    func testLongURLStaysWithinWidth() throws {
        let view = GlimmerView()
        view.update(markdown: "https://example.com/" + String(repeating: "a", count: 300))
        let height = view.sizeThatFits(CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)).height
        XCTAssertGreaterThan(height, 0)
        let window = hostInWindow(view, width: 320, height: height)
        let manager = try XCTUnwrap(view.textView.textLayoutManager)
        manager.ensureLayout(for: manager.documentRange)
        XCTAssertLessThanOrEqual(manager.usageBoundsForTextContainer.width, 320.5)
        _ = window
    }

    func testDynamicTypeScalesFonts() {
        let view = GlimmerView()
        view.update(markdown: "Body")
        let window = hostInWindow(view, width: 320, height: 200)
        let before = (view.textView.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.pointSize ?? 0
        view.traitOverrides.preferredContentSizeCategory = .accessibilityExtraLarge
        settle(view)
        let after = (view.textView.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.pointSize ?? 0
        XCTAssertGreaterThan(after, before)
        _ = window
    }

    func testIntrinsicHeightTracksWidth() {
        let view = GlimmerView()
        view.update(markdown: String(repeating: "Some words that wrap. ", count: 20))
        let window = hostInWindow(view, width: 390, height: 100)
        let wide = view.intrinsicContentSize.height
        view.frame.size.width = 250
        settle(view)
        XCTAssertGreaterThan(view.intrinsicContentSize.height, wide)
        _ = window
    }

    func testLinkActionRequiresAHandler() throws {
        let view = GlimmerView()
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        XCTAssertNil(view.linkAction(for: url))
        view.onLinkTap = { _ in }
        XCTAssertNotNil(view.linkAction(for: url))
    }

    private let longStream = Array(repeating: StreamingFixtures.all.map(\.markdown).joined(separator: "\n\n"), count: 10)
        .joined(separator: "\n\n")

    func testStreamingNeverResizesTheTextView() async {
        var configuration = GlimmerConfiguration(imageLoader: nil)
        configuration.reveal = .none
        let view = GlimmerView(configuration: configuration)
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: String(longStream.prefix(200)), isStreaming: true)
        await view.pendingDocument?.value
        settle(view)
        let frame = view.textView.frame
        var end = 200
        while end < longStream.count {
            end = min(longStream.count, end + 1_500)
            view.update(markdown: String(longStream.prefix(end)), isStreaming: true)
            await view.pendingDocument?.value
            settle(view)
            XCTAssertEqual(view.textView.frame, frame, "resized at \(end) characters")
        }
        XCTAssertGreaterThan(view.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height, 5_000)
        _ = window
    }

    func testIntrinsicSizeIsTheContentNotTheTextView() {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: "A short answer.\n\nWith two paragraphs.")
        view.layoutIfNeeded()
        let content = view.textView.laidOutHeight()
        // What Auto Layout hosts read: the intrinsic size and the fitted size at a width.
        XCTAssertEqual(view.intrinsicContentSize.height, content, accuracy: 1)
        let fitted = view.systemLayoutSizeFitting(
            CGSize(width: 390, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        )
        XCTAssertEqual(fitted.height, content, accuracy: 1)
        XCTAssertGreaterThan(view.textView.frame.height, content, "the text view is tall; the view is not")
        _ = window
    }

    func testAWidthChangeMidStreamReportsTheNewContentHeight() async {
        var configuration = GlimmerConfiguration(imageLoader: nil)
        configuration.reveal = .none
        let view = GlimmerView(configuration: configuration)
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: String(longStream.prefix(3_000)), isStreaming: true)
        await view.pendingDocument?.value
        settle(view)
        let narrow = view.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height
        view.frame.size.width = 700
        settle(view)
        XCTAssertEqual(view.textView.frame.width, 700)
        XCTAssertEqual(view.textView.frame.height, GlimmerView.textViewHeight)
        let wide = view.sizeThatFits(CGSize(width: 700, height: CGFloat.greatestFiniteMagnitude)).height
        XCTAssertLessThan(wide, narrow, "wider text wraps into fewer lines")
        XCTAssertEqual(wide, view.textView.laidOutHeight(), accuracy: 1)
        _ = window
    }

    func testTextTallerThanTheTextViewGrowsIt() async {
        let saved = GlimmerView.textViewHeight
        GlimmerView.textViewHeight = 2_000
        defer { GlimmerView.textViewHeight = saved }
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: String(longStream.prefix(20_000)))
        settle(view)
        let content = view.textView.laidOutHeight()
        XCTAssertGreaterThan(content, 2_000)
        XCTAssertGreaterThanOrEqual(view.textView.frame.height, content, "doubled until the text fits")
        _ = window
    }

    func testATallTextViewCostsNoMemory() {
        let before = physicalFootprint()
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: longStream)
        settle(view)
        // A backing store for a 1,000,000 pt layer would be gigabytes; the text itself is a few tens of megabytes.
        XCTAssertLessThan(physicalFootprint() - before, 150 * 1_024 * 1_024)
        _ = window
    }

    /// While revealing, the mask layers cover what is shown, not the tall text view.
    func testATallTextViewCostsNoMemoryWhileRevealing() async {
        let before = physicalFootprint()
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let clock = ManualRevealClock()
        view.clock = clock
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: longStream, isStreaming: true)
        await view.pendingDocument?.value
        clock.advance(to: 2)
        settle(view)
        XCTAssertNotNil(view.engine, "still revealing")
        XCTAssertLessThan(physicalFootprint() - before, 150 * 1_024 * 1_024)
        _ = window
    }

    /// An Auto Layout host: width from constraints, height from the intrinsic size, which follows the content. Like a
    /// multi-line label, one layout pass gives the right height, though the height depends on the width that pass sets.
    func testAnAutoLayoutHostSizesTheViewToItsContent() {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        let window = hostInWindow(host, width: 390, height: 800)
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil, reveal: .none))
        view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            view.topAnchor.constraint(equalTo: host.topAnchor),
        ])
        view.update(markdown: "A short answer.")
        host.layoutIfNeeded()
        let short = view.frame.height
        XCTAssertEqual(short, view.textView.laidOutHeight(), accuracy: 1)
        view.update(markdown: "A short answer.\n\nNow with a second paragraph that wraps onto another line or two.")
        host.layoutIfNeeded()
        XCTAssertGreaterThan(view.frame.height, short + 20, "the height follows the content")
        XCTAssertEqual(view.frame.height, view.textView.laidOutHeight(), accuracy: 1)
        _ = window
    }

    private func physicalFootprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }
}

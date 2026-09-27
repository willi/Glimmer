import UIKit
import XCTest
@testable import Glimmer

/// Puts `view` in a visible window at the given size and lets layout finish.
/// Keep the returned window alive for the rest of the test (`let window = …`).
@MainActor
@discardableResult
func hostInWindow(_ view: UIView, width: CGFloat, height: CGFloat) -> UIWindow {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: max(height, 1)))
    view.frame = CGRect(x: 0, y: 0, width: width, height: height)
    window.addSubview(view)
    window.makeKeyAndVisible()
    settle(view)
    return window
}

/// Lets UIKit and TextKit finish a layout pass, including attachment views that appear a run-loop turn later.
@MainActor
func settle(_ view: UIView) {
    view.layoutIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    view.layoutIfNeeded()
}

@MainActor
func findSubview<T: UIView>(_ type: T.Type, in root: UIView) -> T? {
    if let match = root as? T { return match }
    for subview in root.subviews {
        if let match = findSubview(type, in: subview) { return match }
    }
    return nil
}

/// Polls `condition` until it is true or `timeout` (wall clock) passes.
@MainActor
func waitUntil(timeout: TimeInterval = 2, _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

/// Every layout fragment of a TextKit 2 text view, with layout ensured.
@MainActor
func layoutFragments(_ textView: UITextView) -> [NSTextLayoutFragment] {
    guard let manager = textView.textLayoutManager else { return [] }
    manager.ensureLayout(for: manager.documentRange)
    var fragments: [NSTextLayoutFragment] = []
    manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) { fragment in
        fragments.append(fragment)
        return true
    }
    return fragments
}

/// Compares two attributed strings run by run. Attachments compare by type, because every composition creates new
/// attachment objects; every other attribute value must be `isEqual`.
func assertEquivalent(
    _ lhs: NSAttributedString, _ rhs: NSAttributedString, _ message: String,
    file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertEqual(lhs.string, rhs.string, message, file: file, line: line)
    guard lhs.string == rhs.string else { return }
    var index = 0
    while index < lhs.length {
        var lhsRange = NSRange()
        var rhsRange = NSRange()
        let left = lhs.attributes(at: index, effectiveRange: &lhsRange)
        let right = rhs.attributes(at: index, effectiveRange: &rhsRange)
        XCTAssertEqual(Set(left.keys.map(\.rawValue)), Set(right.keys.map(\.rawValue)), "\(message): keys at \(index)", file: file, line: line)
        for (key, leftValue) in left {
            guard let rightValue = right[key] else { continue }
            if let leftAttachment = leftValue as? NSTextAttachment, let rightAttachment = rightValue as? NSTextAttachment {
                XCTAssertTrue(type(of: leftAttachment) == type(of: rightAttachment), "\(message): attachment at \(index)", file: file, line: line)
            } else {
                XCTAssertTrue((leftValue as AnyObject).isEqual(rightValue), "\(message): \(key.rawValue) at \(index)", file: file, line: line)
            }
        }
        index = min(NSMaxRange(lhsRange), NSMaxRange(rhsRange))
    }
}

/// A reveal clock tests drive by hand: `advance(to:)` fires every due wake-up in order.
@MainActor
final class ManualRevealClock: GlimmerRevealClock {
    private(set) var now: TimeInterval = 0
    private(set) var scheduled: TimeInterval?
    private var action: (@MainActor () -> Void)?

    func wake(at time: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        scheduled = time
        self.action = action
    }

    func cancel() {
        scheduled = nil
        action = nil
    }

    func advance(to time: TimeInterval) {
        while let due = scheduled, due <= time, let pending = action {
            now = due
            scheduled = nil
            action = nil
            pending()
        }
        now = max(now, time)
    }
}

/// Whether `rect` of `view` shows dark pixels, meaning TextKit drew text there. Samples every seventh pixel.
@MainActor
func inked(_ view: UIView, in rect: CGRect) -> Bool {
    let image = UIGraphicsImageRenderer(bounds: rect).image { context in view.layer.render(in: context.cgContext) }
    guard let data = image.cgImage?.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return false }
    var dark = 0
    var index = 0
    while index + 3 < CFDataGetLength(data) {
        if bytes[index] < 128, bytes[index + 3] > 0 { dark += 1 }
        index += 4 * 7
    }
    return dark > 20
}

/// The UTF-16 range TextKit's viewport covers right now.
@MainActor
func viewportRange(_ textView: UITextView) -> NSRange? {
    guard let manager = textView.textLayoutManager, let content = manager.textContentManager,
          let range = manager.textViewportLayoutController.viewportRange else { return nil }
    let start = content.offset(from: content.documentRange.location, to: range.location)
    return NSRange(location: start, length: content.offset(from: range.location, to: range.endLocation))
}

/// Every view below `view`: TextKit gives each rendered layout fragment its own view.
@MainActor
func renderedViewCount(_ view: UIView) -> Int {
    view.subviews.reduce(view.subviews.count) { $0 + renderedViewCount($1) }
}

/// The block attachments in `text`, in order.
func blockAttachments(in text: NSAttributedString) -> [GlimmerBlockAttachment] {
    var attachments: [GlimmerBlockAttachment] = []
    text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
        if let attachment = value as? GlimmerBlockAttachment { attachments.append(attachment) }
    }
    return attachments
}

/// CPU time the calling thread has used so far. On the main thread, the difference across a stretch of work is its
/// main-thread cost wherever UIKit ran it — including layout and drawing Core Animation does while a test awaits a
/// worker — and excludes other threads and idle waiting.
func threadCPUTime() -> Duration {
    var info = thread_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<natural_t>.size)
    let thread = mach_thread_self()
    defer { mach_port_deallocate(mach_task_self_, thread) }
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count) }
    }
    guard result == KERN_SUCCESS else { return .zero }
    let micros = Int64(info.user_time.seconds + info.system_time.seconds) * 1_000_000
        + Int64(info.user_time.microseconds + info.system_time.microseconds)
    return .microseconds(micros)
}

/// Streams every `step`th prefix of `markdown` into a view and checks that text shown earlier never moves: at each step,
/// the text before the last paragraph shown at the previous step must be unchanged, with the same segment rects
/// (within 0.5 pt). The last paragraph may reflow as words arrive. Ends with the settled answer.
/// Synchronous (the run loop is pumped until the view's worker is done): a long chain of awaits in one XCTest async
/// method crashed the test runner in Swift Concurrency's task allocator.
@MainActor
func assertStreamingKeepsShownTextInPlace(
    _ markdown: String, configuration: GlimmerConfiguration = GlimmerConfiguration(imageLoader: nil, reveal: .none),
    every step: Int = 3, file: StaticString = #filePath, line: UInt = #line
) {
    let view = GlimmerView(configuration: configuration)
    let window = hostInWindow(view, width: 390, height: 800)
    var previous: ShownText?
    var end = markdown.startIndex
    while end < markdown.endIndex {
        end = markdown.index(end, offsetBy: step, limitedBy: markdown.endIndex) ?? markdown.endIndex
        view.update(markdown: String(markdown[..<end]), isStreaming: end < markdown.endIndex, revealID: "stability")
        let deadline = Date().addingTimeInterval(5)
        while view.pendingDocument != nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }
        view.layoutIfNeeded()
        let shown = ShownText(view.textView)
        if let previous, let failure = shown.movedText(since: previous) {
            XCTFail("at prefix \(markdown.distance(from: markdown.startIndex, to: end)) " +
                    "(…\(String(markdown[..<end].suffix(30)).debugDescription)): \(failure)", file: file, line: line)
            break
        }
        previous = shown
    }
    _ = window
}

/// What a text view shows before its last paragraph: the text, and its glyphs' segment rects. Zero-width segments are
/// line ends, not glyphs (their metrics follow the next line's font), so they are left out.
@MainActor
struct ShownText {
    let text: NSString
    let stableLength: Int
    let rects: [CGRect]

    init(_ textView: GlimmerTextView) {
        // A copy: the text storage's string is mutable and changes with the next update.
        text = NSString(string: textView.textStorage.string)
        let newline = text.range(of: "\n", options: .backwards)
        stableLength = newline.location == NSNotFound ? 0 : NSMaxRange(newline)
        rects = Self.glyphRects(in: textView, length: stableLength)
    }

    static func glyphRects(in textView: GlimmerTextView, length: Int) -> [CGRect] {
        textView.segmentRects(for: NSRange(location: 0, length: length)).filter { $0.width > 0 }
    }

    /// Why text `previous` showed before its last paragraph isn't where it was, or nil.
    func movedText(since previous: ShownText) -> String? {
        let stable = previous.stableLength
        guard text.length >= stable, text.substring(to: stable) == previous.text.substring(to: stable) else {
            return "text before offset \(stable) changed: \(previous.text.substring(to: stable).debugDescription) became " +
                "\(text.substring(to: min(stable, text.length)).debugDescription)"
        }
        let now = Array(rects.prefix(previous.rects.count))
        guard now.count == previous.rects.count else { return "\(previous.rects.count) glyph rects became \(now.count)" }
        for (before, after) in zip(previous.rects, now) where
            abs(before.minX - after.minX) > 0.5 || abs(before.minY - after.minY) > 0.5 ||
            abs(before.maxX - after.maxX) > 0.5 || abs(before.maxY - after.maxY) > 0.5 {
            return "a glyph rect moved: \(before) → \(after)"
        }
        return nil
    }
}

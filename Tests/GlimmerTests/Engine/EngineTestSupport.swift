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

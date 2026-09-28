# Glimmer 2.0 — Plan 3: Long Answers and Streaming Embeds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a 5,000-word streamed answer cost about what a 500-word one does, keep code blocks and tables stable and revealing line by line while they stream, and hit the spec's §3 budgets in a Release build.

**Architecture:** `GlimmerTextView` keeps an unbounded text container (a scrolling `UITextView` that never scrolls), which makes TextKit's lookups constant-time. On iOS 27 it overrides `viewportBounds(for:)`, so TextKit renders only a band around the screen, and ancestor scroll views move that band. Streaming embeds keep their attachment and view across re-composes and update in place. They reveal in units (code lines, table rows) that the reveal engine paces like phrases. Parse and compose for streaming updates move to a per-view worker actor; a settled answer still composes synchronously, and it comes from a cache when the same answer is shown again.

**Tech Stack:** Swift 6, iOS 18+ (the band needs iOS 27), UIKit, TextKit 2 (`NSTextViewportLayoutController`, `NSTextContentStorage`), Core Animation, Swift concurrency (actors), vendored cmark-gfm, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-25-glimmer-2-engine-design.md` (§3 success criteria, §4 architecture: parse and compose off-main, §4.3 sizing and height cache, §5.1 embeds reveal internally, §5.4 reuse, §9 memory pressure and non-append updates, §12 phase 6)

**Builds on:** Plans 1 and 2, both complete on `glimmer-2` (HEAD `95fa5f3`). Plan 2's final review ruled that viewport control opens Plan 3; that ruling is the reason for Tasks 1 and 2.

**Evidence behind the design (spike, 2026-09-26, iOS 27.0 simulator, the 31k-character mixed answer from `GlimmerStreamingPerformanceTests`):**

| Configuration | Layout pass after an append | Segment rect of the last character |
|---|---|---|
| Non-scrolling `UITextView` (today) | 30 ms | 2 ms |
| Scrolling `UITextView`, full-height frame | 8.6 ms | 30 µs |
| Scrolling, `viewportBounds(for:)` limited to a 2,700 pt band | 1.4 ms | 25 µs |

- The linear lookups come from a **finite text container height**. A non-scrolling `UITextView` pins the container height to its frame height. A standalone `NSTextLayoutManager` with a 40,000 pt container is just as slow (1 ms per lookup), and one with height 0 (unbounded) takes 8 µs.
- `UITextView` is its own `NSTextViewportLayoutControllerDelegate`, and from iOS 27 `viewportBounds(for:)` is public and overridable. With a band, the rendered subviews dropped from 1,637 to 127. `ensureLayout(for: documentRange)` still lays out all 696 fragments, the usage height stays exact (37441.55 vs 37441.67), and `selectionRects(for:)` spans the whole text.
- `sizeThatFits` still measures correctly on a scrolling text view (34–81 ms at 5k words, so it stays cached). Resizing a 37k-pt scrolling text view costs 8–10 ms, so the slack band in `fitTextViewToContent` stays.

**Plans after this one:** Plan 4 covers interaction and accessibility (spec §6) plus the compose and visual minors. Plan 5 covers the release: deleting 1.x (§10), the demo rebuild with the on-device `XCTHitchMetric` harness, the README, and the `2.0.0` tag.

## Global Constraints

- The branch is `glimmer-2`. Commit after every task. **Do not add `Co-Authored-By` trailers. Do not push.**
- Swift 6 language mode, iOS 18 minimum (`Package.swift`), no package dependencies. Engine code goes under `Sources/Glimmer/Engine/`. Do not touch 1.x sources.
- **TextKit 2 only.** Never read `layoutManager`.
- **No per-frame main-thread work.** Never use `CADisplayLink`. The main thread works only when text arrives, a phrase starts or settles, the layout changes, or a host scroll view moves.
- API newer than iOS 18 needs `@available` or `#available`. The band override is `@available(iOS 27.0, *)` and also checks `ProcessInfo.processInfo.isOperatingSystemAtLeast` at runtime; on iOS 18–26 TextKit keeps its own viewport.
- `NSTextAttachmentViewProvider` overrides stay on the Plan 1 pattern: a `nonisolated(unsafe) let` local plus `MainActor.assumeIsolated`.
- No force unwrapping (`!`) and no force casts in library code. Tests may force-unwrap.
- In tests, write `CGFloat.greatestFiniteMagnitude`, never `.greatestFiniteMagnitude`, in `CGSize(width: <literal>, …)`.
- Test command, with a passing run ending in `** TEST SUCCEEDED **`:
  ```bash
  DEST='platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0'
  xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/<TestClass> 2>&1 | tail -5
  ```
  xcodebuild sometimes hangs after printing its results. If the log shows `Test Suite 'Selected tests' passed|failed` and the process has not exited, kill it. Run one xcodebuild at a time; two on the same simulator stall each other.
- The **engine suite** is every class in `Tests/GlimmerTests/Engine/` whose file name ends in `Tests.swift`: one `-only-testing:GlimmerTests/<Class>` per file. The 1.x suite is already red on `main`; completion is gated on the engine suite only.
- The spec's §3 budgets are for Release on an iPhone 16 Pro Max. Debug simulator gates in this plan are looser (stated per test). Task 8 runs the Release gates.

## Review Focus

These are the five inputs the spec implies but the main tests don't exercise, ordered from most likely to bite a real user down. Each has a test in the task that owns the code.

1. **The host moves the view without scrolling** (a message above grows or is inserted, pushing this answer down the screen) → the next layout pass renders whatever text is now on screen. Test: Task 2 `testLayoutPassRefreshesTheBandAfterTheHostMovesTheView`.
2. **Nested scroll views** (a feed inside a paging view, a SwiftUI `ScrollView` in a sheet) → scrolling the outer one moves the band too. Test: Task 2 `testScrollingAnOuterScrollViewMovesTheBand`.
3. **A fence's info string that grows as it streams** (` ```py ` becomes ` ```python `) → a new code view with the new language, never a stale header. Test: Task 3 `testChangedFenceLanguageGetsANewAttachment`.
4. **A width change while an embed is mid-reveal** (rotation, split view) → unit geometry is rebuilt, and the final render is identical to a settled one. Test: Task 4 `testWidthChangeDuringAnEmbedRevealEndsIdenticalToSettled`.
5. **A theme or Dynamic Type change while a background compose is in flight** → the stale result is dropped, and the view shows the latest text in the new theme. Test: Task 5 `testRebuildWhileComposingNeverAppliesStaleText`.

---

## File Structure

```
Sources/Glimmer/Engine/
  GlimmerView.swift                       MODIFY  band tracking (T2), embed updates (T3), unit sync (T4), worker (T5), caches (T6)
  Render/GlimmerTextView.swift            MODIFY  unbounded container (T1), band override (T2), embed helpers (T4)
  Render/GlimmerViewportTracker.swift     CREATE  KVO on ancestor scroll views (T2)
  Embeds/GlimmerEmbed.swift               MODIFY  continues(_:), revealUnitLengths (T3, T4)
  Embeds/GlimmerEmbedView.swift           MODIFY  update(to:), revealUnitRects(), visibleUnitCount (T3, T4)
  Embeds/GlimmerBlockAttachment.swift     MODIFY  mutable embed, visibleUnitCount, fresh copies (T3, T4, T6)
  Embeds/GlimmerCodeBlockView.swift       MODIFY  in-place update, TextKit 2 line metrics, units (T3, T4)
  Embeds/GlimmerTableView.swift           MODIFY  in-place update, row units (T3, T4)
  Embeds/GlimmerImageEmbedView.swift      MODIFY  protocol conformance (T3, T4)
  Embeds/GlimmerRuleView.swift            MODIFY  protocol conformance (T3, T4)
  Compose/GlimmerComposer.swift           MODIFY  attachment reuse (T3), drop @MainActor (T5)
  Compose/GlimmerAttachmentReuse.swift    CREATE  reuse queue + emitted list (T3)
  Stream/GlimmerStreamingDocument.swift   MODIFY  embed records, updates, units (T3, T4), nonisolated (T5)
  Stream/GlimmerDocumentWorker.swift      CREATE  actor + GlimmerDocumentResult (T5)
  Stream/GlimmerTailHealer.swift          MODIFY  _/__ and setext holdback (T7)
  Stream/GlimmerDocumentCache.swift       CREATE  settled-text and height cache (T6)
  Reveal/GlimmerRevealEngine.swift        MODIFY  embed units (T4)
  Reveal/GlimmerRevealMask.swift          MODIFY  unit rects, settled units (T4)
  Reveal/GlimmerRevealStore.swift         MODIFY  prefix fingerprint (T7)
  Reveal/GlimmerRevealClock.swift         MODIFY  isolated deinit (T7)
  Reveal/GlimmerPhraseChunker.swift       MODIFY  closing quotes and brackets (T7)
  Theme/GlimmerTheme.swift                MODIFY  Hashable (T6)
Tests/GlimmerTests/Engine/
  EngineTestSupport.swift                 MODIFY  inked(_:in:), viewportRange(_:), blockAttachments(in:) (T2, T3)
  GlimmerTextViewTests.swift              MODIFY  (T1)
  GlimmerVisibleBandTests.swift           CREATE  (T2)
  GlimmerStreamingPerformanceTests.swift  MODIFY  (T1, T2, T5, T6, T8)
  GlimmerStreamingDocumentTests.swift     MODIFY  (T3, T4)
  GlimmerEmbedStreamingTests.swift        CREATE  (T3, T4)
  GlimmerRevealEngineTests.swift          MODIFY  (T4)
  GlimmerRevealMaskTests.swift            MODIFY  (T4)
  GlimmerViewStreamingTests.swift         MODIFY  async (T5), store (T7)
  GlimmerStreamParityTests.swift          MODIFY  async (T5)
  GlimmerDocumentWorkerTests.swift        CREATE  (T5)
  GlimmerDocumentCacheTests.swift         CREATE  (T6)
  GlimmerTailHealerTests.swift            MODIFY  (T7)
  GlimmerPhraseChunkerTests.swift         MODIFY  (T7)
  GlimmerRevealStoreTests.swift           CREATE  (T7; moves testStoreIsMonotonicAndBounded here)
Examples/GlimmerDemo/
  LongAnswerDemo.swift                    CREATE  (T2)
docs/superpowers/perf/
  2026-09-26-glimmer-2-plan-3-results.md  CREATE  (T8)
```

---

### Task 1: Unbounded text container

**Files:**
- Modify: `Sources/Glimmer/Engine/Render/GlimmerTextView.swift` (init, `contentOffset` lock, doc comments on `sizeThatFits` and `laidOutHeight`)
- Modify: `Sources/Glimmer/Engine/GlimmerView.swift` (`fitTextViewToContent`: an exact measure no longer needs the grow loop; return early when nothing changed)
- Test: `Tests/GlimmerTests/Engine/GlimmerTextViewTests.swift`, `Tests/GlimmerTests/Engine/GlimmerStreamingPerformanceTests.swift`

**Interfaces:**
- Consumes: `GlimmerTextView.segmentRects(for:)`, `laidOutHeight()`, `textVersion` (Plan 2)
- Produces: `GlimmerTextView` is a scrolling `UITextView` whose `contentOffset` is always `.zero` and whose `textContainer.size.height` is unbounded. `laidOutHeight()` is exact at any frame height.

- [ ] **Step 1: Write the failing tests**

In `GlimmerTextViewTests.swift`, delete `XCTAssertFalse(textView.isScrollEnabled)` from `testStaysOnTextKit2`, then add:

```swift
    func testKeepsAnUnboundedContainerAndNeverScrolls() {
        let textView = GlimmerTextView()
        textView.attributedText = GlimmerComposer(theme: .default).compose(GlimmerParser.parse(String(repeating: "A line of text.\n\n", count: 80)))
        let window = hostInWindow(textView, width: 390, height: 400)
        XCTAssertEqual(textView.textContainer.size.height, CGFloat.greatestFiniteMagnitude, "a finite container makes late lookups linear")
        XCTAssertFalse(textView.panGestureRecognizer.isEnabled, "the host's scroll view keeps every drag")
        textView.scrollRangeToVisible(NSRange(location: textView.textStorage.length - 1, length: 1))
        textView.setContentOffset(CGPoint(x: 0, y: 300), animated: false)
        textView.contentOffset = CGPoint(x: 0, y: 120)
        XCTAssertEqual(textView.contentOffset, .zero)
        _ = window
    }
```

In `GlimmerStreamingPerformanceTests.swift`, add:

```swift
    /// Spec §3: starting a phrase ≤ 0.2 ms, and its segment lookup is most of that. TextKit's time, so the budget holds
    /// in Debug too.
    func testFindingLateTextStaysCheap() {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: longMixedAnswer)
        view.layoutIfNeeded()
        let late = NSRange(location: view.textView.textStorage.length - 2, length: 1)
        let timer = ContinuousClock()
        var samples: [Duration] = []
        for _ in 0..<21 { samples.append(timer.measure { _ = view.textView.segmentRects(for: late) }) }
        XCTAssertLessThan(samples.sorted()[10], .microseconds(200), "median segment lookup at the end of 5,000 words")
        _ = window
    }
```

- [ ] **Step 2: Run to verify they fail**

Run the test command for `GlimmerTextViewTests` and `GlimmerStreamingPerformanceTests`.
Expected: `testKeepsAnUnboundedContainerAndNeverScrolls` FAILS (the container height is 400 and the pan gesture reports disabled only because scrolling is off; the first assertion fails). `testFindingLateTextStaysCheap` FAILS at about 2 ms.

- [ ] **Step 3: Configure the text view**

In `GlimmerTextView.init()`, replace `isScrollEnabled = false` with:

```swift
        // Scrolling stays on only so TextKit keeps the text container unbounded. A non-scrolling text view pins the
        // container to its frame height, and with any finite height TextKit finds late text in linear time (about
        // 2 ms per lookup at 5,000 words, against 25 µs). The frame always covers the text, so there is nothing to
        // scroll, and the pan gesture is off so the host's scroll view keeps every drag.
        isScrollEnabled = true
        panGestureRecognizer.isEnabled = false
        bounces = false
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        scrollsToTop = false
        contentInsetAdjustmentBehavior = .never
```

Add below `required init?(coder:)`:

```swift
    /// Always zero: the text view never scrolls itself (selection autoscroll, `scrollRangeToVisible`); the host does.
    override var contentOffset: CGPoint {
        get { super.contentOffset }
        set { super.contentOffset = .zero }
    }

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        super.setContentOffset(.zero, animated: false)
    }
```

Replace the doc comments of `sizeThatFits(_:)` and `laidOutHeight()`:

```swift
    /// Measured by `UITextView`: a full layout at `size.width`, so it is cached per text version and width. Use it only
    /// for a width the view is not laid out at; at the current width `laidOutHeight()` is exact and incremental. The
    /// attachments cache their views, so the provider churn this measurement causes rebuilds nothing.
```

```swift
    /// The height of the laid-out text at the current width. Cheap, because only changed paragraphs lay out again, and
    /// exact at any frame height, because the text container is unbounded (see `init`).
```

- [ ] **Step 4: Simplify `fitTextViewToContent`**

In `GlimmerView.swift`, replace `fitTextViewToContent()` and its doc comment with:

```swift
    /// Keeps the text view at least as tall as the document, with a slack band below it. The text container is
    /// unbounded, so `laidOutHeight()` is exact whatever the frame; the band exists only because resizing a tall text
    /// view costs about as much as laying it out (8–10 ms at 5,000 words), so the frame should change rarely. The band
    /// grows with the text.
    private func fitTextViewToContent() {
        guard bounds.width > 0 else { return }
        if textView.bounds.width != bounds.width {
            // A new width re-wraps everything: measure it in full once.
            let fullHeight = textView.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height
            textView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: fullHeight + slack(forContentHeight: fullHeight))
        } else if contentHeight?.version == textView.textVersion {
            return
        }
        let height = textView.laidOutHeight()
        let slack = slack(forContentHeight: height)
        if textView.bounds.height < height || textView.bounds.height > height + 2 * slack {
            textView.frame.size.height = height + slack
        }
        if textView.bounds.height < bounds.height { textView.frame.size.height = bounds.height }
        contentHeight = (textView.textVersion, height)
    }
```

- [ ] **Step 5: Run to verify they pass**

Run the test command for `GlimmerTextViewTests` and `GlimmerStreamingPerformanceTests`.
Expected: PASS. The segment-lookup median is about 30 µs. Also compare the `PERF` lines: the layout pass p95 at 5k words drops from about 30 ms to about 9 ms.

- [ ] **Step 6: Run the engine suite and commit**

Run every engine test class. Expected: all pass.

```bash
git add Sources/Glimmer/Engine/Render/GlimmerTextView.swift Sources/Glimmer/Engine/GlimmerView.swift Tests/GlimmerTests/Engine/GlimmerTextViewTests.swift Tests/GlimmerTests/Engine/GlimmerStreamingPerformanceTests.swift
git commit -m "Engine: keep the text container unbounded

A non-scrolling UITextView pins its container to the frame height, and with
a finite height TextKit finds late text in linear time. The text view now
scrolls in principle and never in practice: its pan gesture is off and its
content offset is locked at zero. At 5,000 words a segment lookup drops from
about 2 ms to 30 µs, and the layout pass after an append from 30 to 9 ms."
```

---

### Task 2: Render only a band around the screen

**Files:**
- Create: `Sources/Glimmer/Engine/Render/GlimmerViewportTracker.swift`
- Modify: `Sources/Glimmer/Engine/Render/GlimmerTextView.swift` (band override, `visibleBand()`, `refreshVisibleBandIfNeeded()`)
- Modify: `Sources/Glimmer/Engine/GlimmerView.swift` (tracker wiring in `init`, `didMoveToWindow`, `didMoveToSuperview`, `layoutSubviews`)
- Modify: `Tests/GlimmerTests/Engine/EngineTestSupport.swift` (`inked(_:in:)`, `viewportRange(_:)`, `renderedViewCount(_:)`)
- Test: `Tests/GlimmerTests/Engine/GlimmerVisibleBandTests.swift`, `GlimmerStreamingPerformanceTests.swift`
- Create: `Examples/GlimmerDemo/LongAnswerDemo.swift`, registered in `Examples/GlimmerDemo/GlimmerDemo.xcodeproj/project.pbxproj` and `ContentView.swift`

**Interfaces:**
- Consumes: Task 1's scrolling `GlimmerTextView`
- Produces: `GlimmerTextView.visibleBand() -> CGRect?`, `renderedBand: CGRect?`, `refreshVisibleBandIfNeeded()`, `static let bandOverscan: CGFloat`; `GlimmerViewportTracker.track(ancestorsOf:)`, `stop()`, `onScroll: (() -> Void)?`

- [ ] **Step 1: Add the test helpers**

Append to `EngineTestSupport.swift`:

```swift
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
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/GlimmerTests/Engine/GlimmerVisibleBandTests.swift`:

```swift
import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerVisibleBandTests: XCTestCase {
    private let long = Array(repeating: StreamingFixtures.all.map(\.markdown).joined(separator: "\n\n"), count: 29)
        .joined(separator: "\n\n")

    /// A long settled answer in a scroll view 800 pt tall, scrolled to the top.
    private func scrolled(in outer: UIScrollView? = nil) -> (GlimmerView, UIScrollView, UIWindow) {
        let scrollView = UIScrollView()
        let window: UIWindow
        if let outer {
            window = hostInWindow(outer, width: 390, height: 800)
            scrollView.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
            outer.addSubview(scrollView)
        } else {
            window = hostInWindow(scrollView, width: 390, height: 800)
        }
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        view.update(markdown: long)
        let height = view.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height
        view.frame = CGRect(x: 0, y: 0, width: 390, height: height)
        scrollView.addSubview(view)
        scrollView.contentSize = view.frame.size
        settle(scrollView)
        return (view, scrollView, window)
    }

    private func character(atY y: CGFloat, in textView: UITextView) -> Int {
        guard let manager = textView.textLayoutManager, let content = manager.textContentManager,
              let fragment = manager.textLayoutFragment(for: CGPoint(x: 10, y: y)) else { return -1 }
        return content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
    }

    func testRendersOnlyTheTextNearTheScreen() throws {
        let (view, _, window) = scrolled()
        XCTAssertLessThan(renderedViewCount(view.textView), 300, "a 5,000-word answer rendered every paragraph")
        let range = try XCTUnwrap(viewportRange(view.textView))
        XCTAssertLessThan(NSMaxRange(range), view.textView.textStorage.length / 4)
        XCTAssertTrue(inked(view.textView, in: CGRect(x: 0, y: 100, width: 390, height: 500)))
        _ = window
    }

    func testScrollingMovesTheRenderedBand() throws {
        let (view, scrollView, window) = scrolled()
        let middle = (view.bounds.height / 2).rounded()
        scrollView.contentOffset = CGPoint(x: 0, y: middle)
        settle(scrollView)
        let range = try XCTUnwrap(viewportRange(view.textView))
        XCTAssertTrue(NSLocationInRange(character(atY: middle + 400, in: view.textView), range))
        XCTAssertTrue(inked(view.textView, in: CGRect(x: 0, y: middle + 100, width: 390, height: 600)))
        _ = window
    }

    func testScrollingAnOuterScrollViewMovesTheBand() throws {
        let outer = UIScrollView()
        let (view, inner, window) = scrolled(in: outer)
        // The inner scroll view is as tall as the answer; only the outer one scrolls.
        inner.frame.size.height = view.bounds.height
        outer.contentSize = inner.frame.size
        let middle = (view.bounds.height / 2).rounded()
        outer.contentOffset = CGPoint(x: 0, y: middle)
        settle(outer)
        let range = try XCTUnwrap(viewportRange(view.textView))
        XCTAssertTrue(NSLocationInRange(character(atY: middle + 400, in: view.textView), range))
        _ = window
    }

    func testLayoutPassRefreshesTheBandAfterTheHostMovesTheView() throws {
        let container = UIView()
        let window = hostInWindow(container, width: 390, height: 800)
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        view.update(markdown: long)
        let height = view.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height
        view.frame = CGRect(x: 0, y: 0, width: 390, height: height)
        container.addSubview(view)
        settle(container)
        // Content inserted above pushes the answer up by half its height, with no scroll view involved.
        let middle = (height / 2).rounded()
        view.frame.origin.y = -middle
        view.setNeedsLayout()
        settle(container)
        let range = try XCTUnwrap(viewportRange(view.textView))
        XCTAssertTrue(NSLocationInRange(character(atY: middle + 400, in: view.textView), range))
        _ = window
    }

    func testSelectionStillSpansTheWholeAnswer() throws {
        let (view, _, window) = scrolled()
        let textView = view.textView
        textView.selectedRange = NSRange(location: 10, length: textView.textStorage.length - 20)
        let rects = textView.selectionRects(for: try XCTUnwrap(textView.selectedTextRange))
        XCTAssertGreaterThan(rects.last?.rect.maxY ?? 0, view.bounds.height - 200)
        _ = window
    }
}
```

In `GlimmerStreamingPerformanceTests.swift`, host `streamTail`'s view in a scroll view that follows the bottom (like a chat), and gate the layout pass. Replace the setup and loop of `streamTail(of:reveal:)` with:

```swift
        var configuration = GlimmerConfiguration(imageLoader: nil)
        configuration.reveal = reveal
        let view = GlimmerView(configuration: configuration)
        let clock = ManualRevealClock()
        view.clock = clock
        let scrollView = UIScrollView()
        let window = hostInWindow(scrollView, width: 390, height: 800)
        scrollView.addSubview(view)
        /// Sizes the view to its height and scrolls to its bottom, as a chat follows a streaming answer.
        func follow() {
            let height = view.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height
            view.frame = CGRect(x: 0, y: 0, width: 390, height: height)
            scrollView.contentSize = view.frame.size
            scrollView.contentOffset = CGPoint(x: 0, y: max(0, height - 800))
        }
        let characters = Array(markdown)
        var end = characters.count - 1_200
        view.update(markdown: String(characters[..<end]), isStreaming: true)
        follow()
        view.layoutIfNeeded()
        var time = 1.0
        clock.advance(to: time)
        var samples: [Duration] = []
        var updates: [Duration] = []
        var layouts: [Duration] = []
        let timer = ContinuousClock()
        while end < characters.count {
            end = min(end + 30, characters.count)
            let prefix = String(characters[..<end])
            time += 0.05
            let update = timer.measure { view.update(markdown: prefix, isStreaming: true) }
            let layout = timer.measure {
                follow()
                view.layoutIfNeeded()
                clock.advance(to: time)
            }
            updates.append(update)
            layouts.append(layout)
            samples.append(update + layout)
        }
```

Make `streamTail` return both p95s, `-> (update: Duration, layout: Duration)`, ending with `return (p(updates, 95), p(layouts, 95))`. Then change each test to gate both:

```swift
    private let layoutBudget: Duration = .milliseconds(4)

    func testUpdatesNearTheEndOfALongAnswerStayWithinBudget() {
        let p95 = streamTail(of: longMixedAnswer, reveal: .none)
        XCTAssertLessThan(p95.update, budget, "update p95")
        XCTAssertLessThan(p95.layout, layoutBudget, "layout pass p95")
    }
```

Do the same in `testRevealingUpdatesNearTheEndOfALongAnswerStayWithinBudget`. `testUpdatesNearTheEndOfALongListStayWithinBudget` keeps its 25 ms update gate and adds the `layoutBudget` gate. Update the type comment: the layout pass is now gated; delete its "printed, not gated" paragraph.

- [ ] **Step 3: Run to verify they fail**

Run the test command for `GlimmerVisibleBandTests` and `GlimmerStreamingPerformanceTests`.
Expected: `testRendersOnlyTheTextNearTheScreen` FAILS (about 1,600 views). The two scrolling tests may pass by accident, because today TextKit renders everything. The layout-pass gates FAIL at about 9 ms. `testSelectionStillSpansTheWholeAnswer` passes; it guards the next steps.

- [ ] **Step 4: The band on the text view**

Append to `GlimmerTextView.swift` inside the class:

```swift
    // MARK: - Visible band

    /// How far past the screen, in screen heights, TextKit still renders. Enough that a fling lands on rendered text
    /// before the next band update.
    static let bandOverscan: CGFloat = 1

    /// The rect TextKit rendered last, in this view's coordinates, or nil while it renders its own viewport.
    private(set) var renderedBand: CGRect?

    /// This view's part within `bandOverscan` screens of its window's bounds, full width. It is zero-height off screen
    /// or outside a window (a cell sized before it is shown renders nothing), and nil before the view has a width.
    func visibleBand() -> CGRect? {
        guard bounds.width > 0 else { return nil }
        guard let window else { return CGRect(x: 0, y: 0, width: bounds.width, height: 0) }
        let screen = convert(window.bounds, from: window)
        let band = screen.insetBy(dx: 0, dy: -window.bounds.height * Self.bandOverscan).intersection(bounds)
        guard !band.isNull else { return CGRect(x: 0, y: 0, width: bounds.width, height: 0) }
        return CGRect(x: 0, y: band.minY, width: bounds.width, height: band.height)
    }

    /// Re-renders when the screen has moved within half an overscan of the rendered band's edge.
    func refreshVisibleBandIfNeeded() {
        guard let window, let rendered = renderedBand else { return }
        let screen = convert(window.bounds, from: window).intersection(bounds)
        guard !screen.isNull else { return }
        let needed = screen.insetBy(dx: 0, dy: -window.bounds.height * Self.bandOverscan / 2).intersection(bounds)
        if !rendered.contains(needed) { textLayoutManager?.textViewportLayoutController.layoutViewport() }
    }

    /// TextKit renders whatever this returns. Public from iOS 27, where it is the band around the screen: without it,
    /// TextKit renders the whole bounds of this full-height view — every paragraph of a long answer, on every change.
    @available(iOS 27.0, *)
    override func viewportBounds(for textViewportLayoutController: NSTextViewportLayoutController) -> CGRect {
        // UIKit calls this on older systems too (the text view has always been its viewport's delegate), where it is
        // untested: keep TextKit's own viewport there.
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)),
              let band = visibleBand() else {
            renderedBand = nil
            return super.viewportBounds(for: textViewportLayoutController)
        }
        renderedBand = band
        return band
    }
```

- [ ] **Step 5: The scroll tracker**

Create `Sources/Glimmer/Engine/Render/GlimmerViewportTracker.swift`:

```swift
import UIKit

/// Calls `onScroll` whenever a scroll view above a view scrolls, so the view can move its rendered band. It observes
/// `contentOffset` with KVO; `stop()` tears the observations down when the view leaves its window.
@MainActor
final class GlimmerViewportTracker {
    var onScroll: (() -> Void)?
    private var observations: [NSKeyValueObservation] = []

    func track(ancestorsOf view: UIView) {
        observations.removeAll()
        var ancestor = view.superview
        while let current = ancestor {
            if let scrollView = current as? UIScrollView {
                observations.append(scrollView.observe(\.contentOffset, options: []) { [weak self] _, _ in
                    // Scroll views change their offset on the main thread.
                    MainActor.assumeIsolated { self?.onScroll?() }
                })
            }
            ancestor = current.superview
        }
    }

    func stop() {
        observations.removeAll()
    }
}
```

- [ ] **Step 6: Wire it into `GlimmerView`**

Add a property below `revealMask`:

```swift
    private let viewportTracker = GlimmerViewportTracker()
```

At the end of `init(configuration:)`, add:

```swift
        viewportTracker.onScroll = { [weak self] in self?.textView.refreshVisibleBandIfNeeded() }
```

Add below `layoutSubviews()`:

```swift
    public override func didMoveToWindow() {
        super.didMoveToWindow()
        trackScrollViews()
    }

    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        trackScrollViews()
    }

    /// Follows the scroll views above this view while it is in a window.
    private func trackScrollViews() {
        if window == nil { viewportTracker.stop() } else { viewportTracker.track(ancestorsOf: self) }
        textView.setNeedsLayout()
    }
```

In `layoutSubviews()`, add `textView.refreshVisibleBandIfNeeded()` right after `fitTextViewToContent()`.

- [ ] **Step 7: Run to verify they pass**

Run the test command for `GlimmerVisibleBandTests` and `GlimmerStreamingPerformanceTests`.
Expected: PASS. About 130 rendered views; layout pass p95 at 5k words about 1.5 ms.

- [ ] **Step 8: The long-answer demo, and on-simulator verification**

Create `Examples/GlimmerDemo/LongAnswerDemo.swift`:

```swift
import Glimmer
import SwiftUI

/// About 5,000 words in one GlimmerText, to check scrolling a long answer by eye: no blank bands, no stutter.
struct LongAnswerDemo: View {
    private static let answer = Array(repeating: EngineGalleryDemo.sample, count: 20).joined(separator: "\n\n---\n\n")

    var body: some View {
        ScrollView {
            GlimmerText(Self.answer)
                .padding(16)
        }
        .navigationTitle("Long Answer")
    }
}
```

Register the file in `project.pbxproj` the same way as `StreamingLabDemo.swift`: a `PBXBuildFile`, a `PBXFileReference`, a group child, and a Sources build-phase entry, with IDs `A1F00140…` to `A1F00143…` in the same 24-character pattern. Add `NavigationLink("Long Answer (2.0)", destination: LongAnswerDemo())` below the Streaming Lab link in `ContentView.swift`.

Build the demo (`cd Examples/GlimmerDemo && xcodebuild -project GlimmerDemo.xcodeproj -scheme GlimmerDemo -destination 'platform=iOS Simulator,id=<udid>' -derivedDataPath ../../.build/demo-dd build`). Launch it on the simulator panel, open Long Answer (2.0), fling to the bottom and back to the top, and screenshot three positions: top, middle, bottom. Expected: text everywhere, and no blank band while or after scrolling. Repeat in the Streaming Lab: stream, and scroll during the stream.

- [ ] **Step 9: Run the engine suite and commit**

Run every engine test class. Expected: all pass.

```bash
git add Sources/Glimmer/Engine Tests/GlimmerTests/Engine Examples/GlimmerDemo
git commit -m "Engine: render only a band around the screen

On iOS 27 the text view overrides viewportBounds(for:) so TextKit renders
one screen above and below what is visible, not every paragraph of a long
answer. Scroll views above the view move the band through KVO, and every
layout pass refreshes it. At 5,000 words the layout pass after an append
drops from 9 ms to about 1.5 ms, and rendered views from 1,600 to 130.
Adds the Long Answer demo."
```

---

### Task 3: Streaming embeds keep their views

**Files:**
- Create: `Sources/Glimmer/Engine/Compose/GlimmerAttachmentReuse.swift`
- Modify: `Sources/Glimmer/Engine/Embeds/GlimmerEmbed.swift` (`continues(_:)`)
- Modify: `Sources/Glimmer/Engine/Embeds/GlimmerEmbedView.swift` (`update(to:)`)
- Modify: `Sources/Glimmer/Engine/Embeds/GlimmerBlockAttachment.swift` (mutable `embed`, `update(to:)`)
- Modify: `GlimmerCodeBlockView.swift`, `GlimmerTableView.swift`, `GlimmerImageEmbedView.swift`, `GlimmerRuleView.swift` (in-place updates)
- Modify: `Sources/Glimmer/Engine/Compose/GlimmerComposer.swift` (`Context.reuse`, `composeBlock(_:isFirst:reusing:)`, `appendEmbed`)
- Modify: `Sources/Glimmer/Engine/Stream/GlimmerStreamingDocument.swift` (per-block embed records, `embedUpdates` on the edit)
- Modify: `Sources/Glimmer/Engine/GlimmerView.swift` (apply embed updates before the text edit)
- Modify: `Tests/GlimmerTests/Engine/EngineTestSupport.swift` (`blockAttachments(in:)`)
- Test: `Tests/GlimmerTests/Engine/GlimmerStreamingDocumentTests.swift`, `Tests/GlimmerTests/Engine/GlimmerEmbedStreamingTests.swift`

**Interfaces:**
- Consumes: `GlimmerComposer.composeBlock(_:isFirst:)`, `GlimmerDocumentEdit`, `GlimmerBlockAttachment`, `GlimmerEmbedView`
- Produces:
  - `GlimmerEmbed.continues(_ previous: GlimmerEmbed) -> Bool`
  - `struct GlimmerEmbedUpdate { let attachment: GlimmerBlockAttachment; let embed: GlimmerEmbed }`
  - `GlimmerDocumentEdit.embedUpdates: [GlimmerEmbedUpdate]`
  - `final class GlimmerAttachmentReuse` with `init(_ candidates: [GlimmerEmbeddedAttachment])`, `attachment(for:) -> GlimmerBlockAttachment?`, `record(_:embed:at:)`, `updates`, `emitted: [GlimmerEmbeddedAttachment]`
  - `struct GlimmerEmbeddedAttachment { let attachment: GlimmerBlockAttachment; let embed: GlimmerEmbed; let offset: Int }` (offset within the block's fragment)
  - `GlimmerComposer.composeBlock(_:isFirst:reusing:)`
  - `GlimmerEmbedView.update(to:)`
  - `GlimmerBlockAttachment.update(to:)`
  - `GlimmerStreamingDocument.embeddedAttachments: [(offset: Int, attachment: GlimmerBlockAttachment, embed: GlimmerEmbed)]`, in document offsets

- [ ] **Step 1: Add the test helper**

Append to `EngineTestSupport.swift`:

```swift
/// The block attachments in `text`, in order.
func blockAttachments(in text: NSAttributedString) -> [GlimmerBlockAttachment] {
    var attachments: [GlimmerBlockAttachment] = []
    text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
        if let attachment = value as? GlimmerBlockAttachment { attachments.append(attachment) }
    }
    return attachments
}
```

- [ ] **Step 2: Write the failing tests**

Append to `GlimmerStreamingDocumentTests.swift`:

```swift
    func testGrowingCodeBlockKeepsItsAttachment() throws {
        let document = GlimmerStreamingDocument(composer: composer)
        _ = document.update(markdown: "Run:\n\n```swift\nlet a", isStreaming: true)
        let before = try XCTUnwrap(blockAttachments(in: document.text).first)
        let edit = try XCTUnwrap(document.update(markdown: "Run:\n\n```swift\nlet a = 1\nlet b", isStreaming: true))
        XCTAssertTrue(blockAttachments(in: document.text).first === before, "the growing code block keeps its attachment")
        let update = try XCTUnwrap(edit.embedUpdates.first)
        XCTAssertTrue(update.attachment === before)
        guard case .codeBlock(_, let code) = update.embed else { return XCTFail("expected a code block, got \(update.embed)") }
        XCTAssertEqual(code, "let a = 1\nlet b")
    }

    func testGrowingTableKeepsItsAttachment() throws {
        let document = GlimmerStreamingDocument(composer: composer)
        _ = document.update(markdown: "| a | b |\n|---|---|\n| 1 | 2 |", isStreaming: true)
        let before = try XCTUnwrap(blockAttachments(in: document.text).first)
        let edit = try XCTUnwrap(document.update(markdown: "| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |", isStreaming: true))
        XCTAssertTrue(blockAttachments(in: document.text).first === before)
        guard case .table(_, let rows, _) = edit.embedUpdates.first?.embed else { return XCTFail("expected a table update") }
        XCTAssertEqual(rows.count, 2)
    }

    func testChangedFenceLanguageGetsANewAttachment() throws {
        let document = GlimmerStreamingDocument(composer: composer)
        _ = document.update(markdown: "```py", isStreaming: true)
        let before = try XCTUnwrap(blockAttachments(in: document.text).first)
        _ = document.update(markdown: "```python\nx = 1", isStreaming: true)
        let after = try XCTUnwrap(blockAttachments(in: document.text).first)
        XCTAssertFalse(after === before, "a different language is a different code block")
        guard case .codeBlock(let language, _) = after.embed else { return XCTFail("expected a code block") }
        XCTAssertEqual(language, "python")
    }

    func testEmbeddedAttachmentsReportDocumentOffsets() {
        let document = GlimmerStreamingDocument(composer: composer)
        _ = document.update(markdown: "Intro.\n\n```\nx\n```\n\nMiddle.\n\n---", isStreaming: false)
        let offsets = document.embeddedAttachments.map(\.offset)
        let string = document.text.string as NSString
        XCTAssertEqual(offsets.count, 2)
        for offset in offsets { XCTAssertEqual(string.character(at: offset), 0xFFFC) }
    }
```

Create `Tests/GlimmerTests/Engine/GlimmerEmbedStreamingTests.swift`:

```swift
import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerEmbedStreamingTests: XCTestCase {
    private func noRevealView() -> (GlimmerView, UIWindow) {
        var configuration = GlimmerConfiguration(imageLoader: nil)
        configuration.reveal = .none
        let view = GlimmerView(configuration: configuration)
        return (view, hostInWindow(view, width: 390, height: 800))
    }

    func testStreamingCodeBlockKeepsItsView() throws {
        let (view, window) = noRevealView()
        view.update(markdown: "```swift\nlet a = 1", isStreaming: true)
        settle(view)
        let first = try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: view))
        let firstHeight = first.bounds.height
        view.update(markdown: "```swift\nlet a = 1\nlet b = 2\nlet c = 3", isStreaming: true)
        settle(view)
        let second = try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: view))
        XCTAssertTrue(first === second, "the view updates in place")
        XCTAssertEqual(second.code, "let a = 1\nlet b = 2\nlet c = 3")
        XCTAssertGreaterThan(second.bounds.height, firstHeight)
        _ = window
    }

    func testStreamingTableKeepsItsView() throws {
        let (view, window) = noRevealView()
        view.update(markdown: "| a | b |\n|---|---|\n| 1 | 2 |", isStreaming: true)
        settle(view)
        let first = try XCTUnwrap(findSubview(GlimmerTableView.self, in: view))
        view.update(markdown: "| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |", isStreaming: true)
        settle(view)
        let second = try XCTUnwrap(findSubview(GlimmerTableView.self, in: view))
        XCTAssertTrue(first === second)
        XCTAssertEqual(second.cellLabels.count, 3, "header plus two rows")
        _ = window
    }
}
```

- [ ] **Step 3: Run to verify they fail**

Run the test command for `GlimmerStreamingDocumentTests` and `GlimmerEmbedStreamingTests`.
Expected: compile errors (`embedUpdates`, `embeddedAttachments`, `code` not visible). Stub nothing; the next steps add them. After Step 5 compiles, the identity assertions FAIL until Step 8.

- [ ] **Step 4: Continuation and reuse types**

Append to `GlimmerEmbed.swift`:

```swift
extension GlimmerEmbed {
    /// Whether this embed is `previous` grown by streaming: more code under the same fence, more rows under the same
    /// header, or the same image or rule. Such an embed keeps its attachment and view.
    func continues(_ previous: GlimmerEmbed) -> Bool {
        switch (self, previous) {
        case let (.codeBlock(language, code), .codeBlock(oldLanguage, oldCode)):
            language == oldLanguage && code.hasPrefix(oldCode)
        case let (.table(header, _, alignments), .table(oldHeader, _, oldAlignments)):
            alignments == oldAlignments && header.map(\.string) == oldHeader.map(\.string)
        case let (.image(source, _), .image(oldSource, _)):
            source == oldSource
        case (.thematicBreak, .thematicBreak):
            true
        default:
            false
        }
    }
}
```

Create `Sources/Glimmer/Engine/Compose/GlimmerAttachmentReuse.swift`:

```swift
import Foundation

/// A block attachment and the embed it was composed with, at an offset within its block's fragment.
struct GlimmerEmbeddedAttachment {
    let attachment: GlimmerBlockAttachment
    let embed: GlimmerEmbed
    let offset: Int
}

/// An attachment kept across a re-compose whose embed grew. `GlimmerView` hands the embed to the attachment's view
/// before applying the text edit.
struct GlimmerEmbedUpdate {
    let attachment: GlimmerBlockAttachment
    let embed: GlimmerEmbed
}

/// The attachments of a block being re-composed, offered back to the composer in order, so a growing code block or
/// table keeps its attachment and with it its view. Also records every attachment the composer emits, which becomes
/// the next re-compose's candidates.
final class GlimmerAttachmentReuse {
    private var candidates: [GlimmerEmbeddedAttachment]
    private(set) var updates: [GlimmerEmbedUpdate] = []
    private(set) var emitted: [GlimmerEmbeddedAttachment] = []

    init(_ candidates: [GlimmerEmbeddedAttachment] = []) {
        self.candidates = candidates
    }

    /// The next candidate if `embed` continues it; nil if a new attachment is needed.
    func attachment(for embed: GlimmerEmbed) -> GlimmerBlockAttachment? {
        guard let candidate = candidates.first, embed.continues(candidate.embed) else { return nil }
        candidates.removeFirst()
        updates.append(GlimmerEmbedUpdate(attachment: candidate.attachment, embed: embed))
        return candidate.attachment
    }

    /// Notes an attachment the composer put at `offset` in the fragment it is building.
    func record(_ attachment: GlimmerBlockAttachment, embed: GlimmerEmbed, at offset: Int) {
        emitted.append(GlimmerEmbeddedAttachment(attachment: attachment, embed: embed, offset: offset))
    }
}
```

In `GlimmerStreamingDocument.swift`, add to `GlimmerDocumentEdit`:

```swift
    /// Attachments kept across the re-compose whose embeds grew, in document order.
    var embedUpdates: [GlimmerEmbedUpdate] = []
```

Change `range` and `replacement` to `var` only if the memberwise initializer needs it; keep `let` otherwise, and give `embedUpdates` its default.

- [ ] **Step 5: Mutable attachments and updatable views**

In `GlimmerEmbedView.swift`, add to the protocol:

```swift
    /// Shows `embed` in place: a code block or table that grew while streaming. Views ignore embeds of another kind.
    func update(to embed: GlimmerEmbed)
```

In `GlimmerBlockAttachment.swift`, change `let embed: GlimmerEmbed` to `private(set) var embed: GlimmerEmbed` and add:

```swift
    /// Moves the attachment to a grown embed and updates its view, if one was made. Main thread: it touches the view,
    /// and TextKit reads `embed` when it asks for a view.
    @MainActor
    func update(to embed: GlimmerEmbed) {
        self.embed = embed
        cachedView?.update(to: embed)
    }
```

In `GlimmerCodeBlockView.swift`: make `code` and `language` `private(set) var`, `highlighted` a `private var`, and store the highlighter (`private let highlighter: any GlimmerHighlighter`, set in `init`). The Copy action must read `self.code` at tap time: replace `pasteboard.string = code` with `pasteboard.string = self.code`. Add:

```swift
    func update(to embed: GlimmerEmbed) {
        guard case .codeBlock(let language, let code) = embed, code != self.code || language != self.language else { return }
        self.code = code
        self.language = language
        highlighted = Self.highlightedCode(code, language: language, theme: theme, highlighter: highlighter)
        textView.attributedText = highlighted
        languageLabel.text = language?.lowercased() ?? "code"
        cachedTextSize = nil
        setNeedsLayout()
    }
```

In `GlimmerTableView.swift`: store `alignments` (`private var alignments: [GlimmerTable.Alignment]`), make `cells` a `private var`, and move the label-building loop from `init` into a `private func rebuildCells(header:rows:)` that removes the old labels from `content`, pads rows as `init` does, rebuilds `cellLabels`, and calls `updateColors()`. `init` calls it. Then add:

```swift
    func update(to embed: GlimmerEmbed) {
        guard case .table(let header, let rows, let alignments) = embed else { return }
        let columns = max(header.count, rows.map(\.count).max() ?? 0, alignments.count)
        guard rows.count + 1 != cells.count || rows.map { $0.map(\.string) } != cells.dropFirst().map({ $0.prefix(columns).map(\.string) }) else { return }
        self.alignments = alignments
        rebuildCells(header: header, rows: rows)
        cachedLayout = nil
        setNeedsLayout()
    }
```

In `GlimmerImageEmbedView.swift` and `GlimmerRuleView.swift`, add `func update(to embed: GlimmerEmbed) {}`. `continues(_:)` only keeps them when nothing changed.

- [ ] **Step 6: The composer reuses and records attachments**

In `GlimmerComposer.swift`, add to `Context`:

```swift
        /// Attachments offered back while re-composing a block, and the record of the ones emitted. Nil composes fresh.
        var reuse: GlimmerAttachmentReuse?
```

Replace `composeBlock(_:isFirst:)` with a version that takes the reuse (the old signature stays and forwards):

```swift
    func composeBlock(_ block: GlimmerBlock, isFirst: Bool) -> NSAttributedString {
        composeBlock(block, isFirst: isFirst, reusing: nil)
    }

    /// Like `composeBlock(_:isFirst:)`, and offers `reuse`'s attachments back for embeds that continue them.
    func composeBlock(_ block: GlimmerBlock, isFirst: Bool, reusing reuse: GlimmerAttachmentReuse?) -> NSAttributedString {
        let output = NSMutableAttributedString()
        var context = Context()
        context.isDocumentStart = isFirst
        context.reuse = reuse
        // …the existing body of composeBlock, unchanged…
    }
```

Move the existing body into the new method. In `appendEmbed`, replace the attachment line with:

```swift
        let attachment = context.reuse?.attachment(for: embed)
            ?? GlimmerBlockAttachment(embed: embed, theme: theme, highlighter: highlighter, imageLoader: imageLoader)
        context.reuse?.record(attachment, embed: embed, at: output.length)
```

`record` runs before `output.append(NSAttributedString(attachment: attachment))`, so `output.length` is the attachment's offset in the fragment.

- [ ] **Step 7: The document keeps per-block records**

In `GlimmerStreamingDocument`, add:

```swift
    /// Each block's attachments, with the embeds they were composed with and their offsets in the block's fragment.
    private var blockAttachments: [[GlimmerEmbeddedAttachment]] = []

    /// Every block attachment in `text`, at its document offset, with its current embed.
    var embeddedAttachments: [(offset: Int, attachment: GlimmerBlockAttachment, embed: GlimmerEmbed)] {
        zip(blockOffsets, blockAttachments).flatMap { blockOffset, records in
            records.map { (blockOffset + $0.offset, $0.attachment, $0.embed) }
        }
    }
```

In `update(markdown:isStreaming:)`, compose each changed block with a reuse built from its previous records:

```swift
        var newAttachments = Array(blockAttachments[..<min(firstChanged, blockAttachments.count)])
        var embedUpdates: [GlimmerEmbedUpdate] = []
        var running = prefixLength
        for index in firstChanged..<parsed.blocks.count {
            let reuse = GlimmerAttachmentReuse(index < blockAttachments.count ? blockAttachments[index] : [])
            let fragment = composer.composeBlock(parsed.blocks[index], isFirst: index == 0, reusing: reuse)
            newFragments.append(fragment)
            newOffsets.append(running)
            newAttachments.append(reuse.emitted)
            embedUpdates += reuse.updates
            running += fragment.length
        }
```

(This replaces the existing loop over `firstChanged..<parsed.blocks.count`.) Pass `embedUpdates` into the `GlimmerDocumentEdit` before trimming. `trimmingUnchangedParagraphs` must keep it: its returned edit copies `embedUpdates` from the input edit. Assign `blockAttachments = newAttachments` next to `fragments = newFragments`. In the `guard firstChanged < max(…) else` early return, leave `blockAttachments` as it is.

Reuse must never hand out an attachment still in use by an unchanged block. Candidates come only from the recomposed block's own previous records, so they can't.

- [ ] **Step 8: The view applies embed updates first**

In `GlimmerView.update(markdown:isStreaming:revealID:)`, as the first statement inside `if let edit = …`:

```swift
            // Grown code blocks and tables update their views in place; the edit then re-lays them out.
            for update in edit.embedUpdates { update.attachment.update(to: update.embed) }
```

- [ ] **Step 9: Run to verify they pass**

Run the test command for `GlimmerStreamingDocumentTests`, `GlimmerEmbedStreamingTests`, `GlimmerStreamParityTests`, `GlimmerCodeBlockViewTests` and `GlimmerTableViewTests`.
Expected: PASS. Parity holds because `assertEquivalent` compares attachments by type.

- [ ] **Step 10: Run the engine suite and commit**

```bash
git add Sources/Glimmer/Engine Tests/GlimmerTests/Engine
git commit -m "Engine: keep a streaming code block's or table's view

A code block that gains lines, or a table that gains rows, keeps its
attachment across re-composes. Its view updates in place instead of being
rebuilt (and re-highlighted) on every chunk. A fence whose language changes
is a new code block."
```

---

### Task 4: Embeds reveal line by line and row by row

**Files:**
- Modify: `Sources/Glimmer/Engine/Embeds/GlimmerEmbed.swift` (`revealUnitLengths`)
- Modify: `Sources/Glimmer/Engine/Embeds/GlimmerEmbedView.swift` (`revealUnitRects()`, `visibleUnitCount`)
- Modify: `GlimmerCodeBlockView.swift` (TextKit 2 line metrics, units), `GlimmerTableView.swift` (row units), `GlimmerImageEmbedView.swift`, `GlimmerRuleView.swift`
- Modify: `Sources/Glimmer/Engine/Embeds/GlimmerBlockAttachment.swift` (`visibleUnitCount`)
- Modify: `Sources/Glimmer/Engine/Stream/GlimmerStreamingDocument.swift` (`embedUnits`)
- Modify: `Sources/Glimmer/Engine/Reveal/GlimmerRevealEngine.swift` (unit phrases)
- Modify: `Sources/Glimmer/Engine/Reveal/GlimmerRevealMask.swift` (unit rects, settled units)
- Modify: `Sources/Glimmer/Engine/Render/GlimmerTextView.swift` (`blockAttachment(atCharacter:)`, `embedUnitRects(atCharacter:)`, `invalidateEmbedLayout(atCharacter:)`)
- Modify: `Sources/Glimmer/Engine/GlimmerView.swift` (pass units to the engine; sync visible units)
- Test: `GlimmerRevealEngineTests.swift`, `GlimmerRevealMaskTests.swift`, `GlimmerEmbedStreamingTests.swift`

**Interfaces:**
- Consumes: Task 3's `GlimmerStreamingDocument.embeddedAttachments`, `GlimmerBlockAttachment.update(to:)`
- Produces:
  - `GlimmerEmbed.revealUnitLengths: [Int]` (empty for images and rules, which stay one phrase)
  - `GlimmerRevealEngine.Phrase.unit: Int?`
  - `textChanged(_:isStreaming:now:embedUnits: [Int: [Int]] = [:])`
  - `unitsRevealed: [Int: Int]`, `unitsSettled: [Int: Int]`
  - `GlimmerEmbedView.revealUnitRects() -> [CGRect]`, `visibleUnitCount: Int? { get set }`
  - `GlimmerBlockAttachment.visibleUnitCount: Int?` (main actor)
  - `GlimmerTextView.blockAttachment(atCharacter:) -> GlimmerBlockAttachment?`, `embedUnitRects(atCharacter:) -> [CGRect]?` (in text view coordinates), `invalidateEmbedLayout(atCharacter:)`
  - `GlimmerStreamingDocument.embedUnits: [Int: [Int]]`

The design, which every step follows:
- **Units.** A code block's units are its lines, and a table's units are its header row and each body row. The engine gives each unit its own phrase: the same one-character range at the attachment, a `unit` index, and a start time paced by the unit's text length. `revealedLength` stays at the attachment until its last known unit has started and the embed can no longer grow. It can't grow once text follows it or the stream has ended. A text phrase never runs into an embed that has units.
- **Height follows the reveal.** The frontier embed's `visibleUnitCount` is the number of units started. Its view is only as tall as those units, so the box grows one line or row at a time, and the revealed height (the bottom of the attachment's line) needs no special case. Embeds that are passed or not yet reached show everything (`nil`).
- **Mask.** A unit phrase's path is that unit's rect: full embed width, from the previous unit's bottom to its own. The last visible unit's rect runs to the embed's bottom edge, covering the bottom padding. Units that have finished fading join the settled path.
- A settled render is unchanged: at settle every count is `nil`.

- [ ] **Step 1: Write the failing engine tests**

Append to `GlimmerRevealEngineTests.swift`:

```swift
    /// Runs the engine to completion in 10 ms steps, returning every phrase in start order.
    private func allPhrases(_ engine: inout GlimmerRevealEngine, until limit: TimeInterval = 20) -> [GlimmerRevealEngine.Phrase] {
        var seen: [GlimmerRevealEngine.Phrase] = []
        var time = 0.0
        while !engine.isComplete, time < limit {
            engine.advance(to: time)
            for phrase in engine.phrases where !seen.contains(phrase) { seen.append(phrase) }
            time += 0.01
        }
        return seen
    }

    func testEmbedRevealsOneUnitAtATime() {
        let text = "Intro line here.\n\u{FFFC}\nAfter the code block ends." as NSString
        let embed = text.range(of: "\u{FFFC}").location
        var engine = GlimmerRevealEngine(options: GlimmerRevealOptions())
        engine.textChanged(text, isStreaming: false, now: 0, embedUnits: [embed: [12, 12, 12]])
        let phrases = allPhrases(&engine)
        let units = phrases.filter { $0.unit != nil }
        XCTAssertEqual(units.map(\.unit), [0, 1, 2])
        XCTAssertTrue(units.allSatisfy { $0.range == NSRange(location: embed, length: 1) })
        XCTAssertEqual(units.map(\.start), units.map(\.start).sorted())
        XCTAssertFalse(phrases.contains { $0.unit == nil && NSLocationInRange(embed, $0.range) }, "no text phrase covers the embed")
        let after = phrases.first { $0.unit == nil && $0.range.location > embed }
        XCTAssertGreaterThan(after?.start ?? 0, units.last?.start ?? .infinity, "text after the embed waits for its last unit")
        XCTAssertTrue(engine.isComplete)
    }

    func testEmbedAtTheEndWaitsForMoreUnits() {
        let text = "Code:\n\u{FFFC}" as NSString
        let embed = text.length - 1
        var engine = GlimmerRevealEngine(options: GlimmerRevealOptions())
        engine.textChanged(text, isStreaming: true, now: 0, embedUnits: [embed: [8, 8]])
        engine.advance(to: 5)
        XCTAssertEqual(engine.unitsRevealed[embed], 2)
        XCTAssertEqual(engine.revealedLength, embed, "the embed may still grow")
        engine.textChanged(text, isStreaming: true, now: 5, embedUnits: [embed: [8, 8, 8]])
        engine.advance(to: 10)
        XCTAssertEqual(engine.unitsRevealed[embed], 3)
        engine.textChanged(text, isStreaming: false, now: 10, embedUnits: [embed: [8, 8, 8]])
        engine.advance(to: 20)
        XCTAssertTrue(engine.isComplete)
        XCTAssertEqual(engine.settledLength, text.length)
    }

    func testSettledUnitsAreCountedPerEmbed() {
        let text = "\u{FFFC}\nTail words keep going here." as NSString
        var engine = GlimmerRevealEngine(options: GlimmerRevealOptions())
        engine.textChanged(text, isStreaming: false, now: 0, embedUnits: [0: [5, 5]])
        engine.advance(to: 0)
        XCTAssertEqual(engine.unitsRevealed[0], 1)
        engine.advance(to: GlimmerRevealOptions().fadeDuration + 0.01)
        XCTAssertGreaterThanOrEqual(engine.unitsSettled[0] ?? 0, 1)
        XCTAssertEqual(engine.settledLength, 0, "the embed character settles only with its last unit")
    }
```

- [ ] **Step 2: Run to verify they fail**

Run the test command for `GlimmerRevealEngineTests`. Expected: compile errors (`embedUnits:`, `unit`, `unitsRevealed`, `unitsSettled`).

- [ ] **Step 3: Unit phrases in the engine**

In `GlimmerRevealEngine`:

```swift
    struct Phrase: Equatable {
        var range: NSRange
        var start: TimeInterval
        /// For a phrase inside an embed: which reveal unit (code line, table row) it shows.
        var unit: Int? = nil
    }

    /// Embeds that reveal in units: attachment offset → each unit's text length.
    private(set) var embedUnits: [Int: [Int]] = [:]
    /// Units started, per embed offset.
    private(set) var unitsRevealed: [Int: Int] = [:]
    /// Units whose fade has finished, per embed offset.
    private(set) var unitsSettled: [Int: Int] = [:]
```

Change `textChanged` to take and store the units:

```swift
    mutating func textChanged(_ text: NSString, isStreaming: Bool, now: TimeInterval, embedUnits: [Int: [Int]] = [:]) {
        self.text = text
        self.isStreaming = isStreaming
        self.embedUnits = embedUnits
        // …existing clamping of revealedLength, settledLength and phrases, unchanged…
        unitsRevealed = unitsRevealed.filter { embedUnits[$0.key] != nil }.mapValues { $0 }
        for (offset, count) in unitsRevealed { unitsRevealed[offset] = min(count, embedUnits[offset]?.count ?? 0) }
        unitsSettled = unitsSettled.filter { embedUnits[$0.key] != nil }
        if nextPhraseStart == nil, revealedLength < text.length {
            nextPhraseStart = max(now, earliestNextStart ?? now)
        }
    }
```

In `advance(to:)`, handle a unit embed at `revealedLength` before chunking, and clamp text phrases before any unit embed:

```swift
        while let due = nextPhraseStart, due <= now {
            pacing.updateRate(backlog: text.length - revealedLength, isStreaming: isStreaming, now: due)
            if let units = embedUnits[revealedLength] {
                let shown = unitsRevealed[revealedLength, default: 0]
                if shown < units.count {
                    phrases.append(Phrase(range: NSRange(location: revealedLength, length: 1), start: due, unit: shown))
                    unitsRevealed[revealedLength] = shown + 1
                    nextPhraseStart = due + pacing.interval(forPhraseLength: max(1, units[shown]))
                    continue
                }
                // Every known unit has started. Move past the embed once it can no longer grow.
                guard revealedLength + 1 < text.length || !isStreaming else {
                    nextPhraseStart = nil
                    earliestNextStart = due
                    break
                }
                revealedLength += 1
                continue
            }
            guard var end = chunk(from: revealedLength) else {
                nextPhraseStart = nil
                earliestNextStart = due
                break
            }
            while end - revealedLength < pacing.minimumPhraseLength, end < text.length, let next = chunk(from: end) {
                end = next
            }
            // A text phrase stops before an embed that reveals in units.
            if let embed = embedUnits.keys.filter({ $0 > revealedLength && $0 < end }).min() { end = embed }
            let phrase = Phrase(range: NSRange(location: revealedLength, length: end - revealedLength), start: due)
            phrases.append(phrase)
            revealedLength = end
            nextPhraseStart = due + pacing.interval(forPhraseLength: phrase.range.length)
        }
        while let first = phrases.first, first.start + options.fadeDuration <= now {
            phrases.removeFirst()
            if let unit = first.unit {
                let offset = first.range.location
                unitsSettled[offset] = unit + 1
                let isLast = unit + 1 == embedUnits[offset]?.count
                settledLength = isLast && revealedLength > offset ? offset + 1 : offset
            } else {
                settledLength = NSMaxRange(first.range)
            }
        }
        if phrases.isEmpty { settledLength = revealedLength }
```

- [ ] **Step 4: Run the engine tests**

Run the test command for `GlimmerRevealEngineTests`. Expected: all pass, including the Plan 2 tests (no units means the old path).

- [ ] **Step 5: Write the failing view, mask and geometry tests**

Append to `GlimmerEmbedStreamingTests.swift`:

```swift
    private func revealingView(width: CGFloat = 390) -> (GlimmerView, ManualRevealClock, UIWindow) {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let clock = ManualRevealClock()
        view.clock = clock
        return (view, clock, hostInWindow(view, width: width, height: 800))
    }

    func testCodeBlockRevealsLineByLine() throws {
        let (view, clock, window) = revealingView()
        let markdown = "```swift\nlet a = 1\nlet b = 2\nlet c = 3\n```"
        view.update(markdown: markdown, isStreaming: true)
        settle(view)
        let code = try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: view))
        XCTAssertEqual(code.visibleUnitCount, 1, "the first line starts alone")
        let oneLine = code.bounds.height
        clock.advance(to: 0.4)
        settle(view)
        XCTAssertGreaterThan(code.visibleUnitCount ?? 0, 1)
        XCTAssertGreaterThan(code.bounds.height, oneLine, "the box grows with the revealed lines")
        view.update(markdown: markdown, isStreaming: false)
        clock.advance(to: 10)
        settle(view)
        XCTAssertNil(code.visibleUnitCount, "a settled code block shows every line")
        XCTAssertEqual(code.bounds.height, code.embedHeight(forWidth: code.bounds.width), accuracy: 0.5)
        _ = window
    }

    func testUnitPhraseFadesOverItsLine() throws {
        let (view, clock, window) = revealingView()
        view.update(markdown: "```\nfirst line\nsecond line\n```", isStreaming: true)
        clock.advance(to: 0.3)
        settle(view)
        let engine = try XCTUnwrap(view.engine)
        let unit = try XCTUnwrap(engine.phrases.last { $0.unit != nil })
        let rects = try XCTUnwrap(view.textView.embedUnitRects(atCharacter: unit.range.location))
        let covered = try XCTUnwrap(view.revealMask.phraseLayer(forUnit: try XCTUnwrap(unit.unit), at: unit.range.location)?.path?.boundingBox)
        XCTAssertTrue(covered.insetBy(dx: -1.5, dy: -2.5).contains(rects[try XCTUnwrap(unit.unit)]))
        _ = window
    }

    func testWidthChangeDuringAnEmbedRevealEndsIdenticalToSettled() throws {
        let markdown = "Intro.\n\n```\none\ntwo\nthree\nfour\n```\n\nOutro."
        let (view, clock, window) = revealingView(width: 390)
        view.update(markdown: markdown, isStreaming: true)
        clock.advance(to: 0.3)
        window.frame.size.width = 320
        view.frame.size.width = 320
        settle(view)
        view.update(markdown: markdown, isStreaming: false)
        clock.advance(to: 20)
        settle(view)
        let settled = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let settledWindow = hostInWindow(settled, width: 320, height: 800)
        settled.update(markdown: markdown)
        settle(settled)
        XCTAssertEqual(view.intrinsicContentSize.height, settled.intrinsicContentSize.height, accuracy: 0.5)
        XCTAssertNil(findSubview(GlimmerCodeBlockView.self, in: view)?.visibleUnitCount)
        _ = (window, settledWindow)
    }
```

`phraseLayer(forUnit:at:)` is added to the mask in Step 8. Because phrase layers are keyed by start offset, and every unit of one embed shares that offset, unit phrase layers are keyed by `(offset, unit)`.

- [ ] **Step 6: Units on embeds and their views**

Append to `GlimmerEmbed.swift`:

```swift
extension GlimmerEmbed {
    /// The UTF-16 length of each reveal unit: code lines, or the header row and each body row. Images and rules have
    /// none; each reveals as one phrase.
    var revealUnitLengths: [Int] {
        switch self {
        case .codeBlock(_, let code):
            code.split(separator: "\n", omittingEmptySubsequences: false).map { max(1, $0.utf16.count) }
        case .table(let header, let rows, _):
            ([header] + rows).map { row in max(1, row.reduce(0) { $0 + $1.length }) }
        case .image, .thematicBreak:
            []
        }
    }
}
```

Add to the `GlimmerEmbedView` protocol:

```swift
    /// Each reveal unit's rect (code lines, table rows) in this view's coordinates, top to bottom and full width. The
    /// last visible unit's rect runs to the bottom edge. A view without units returns its bounds.
    func revealUnitRects() -> [CGRect]
    /// How many units show while a reveal runs; nil shows all. The view's height follows it.
    var visibleUnitCount: Int? { get set }
```

`GlimmerImageEmbedView` and `GlimmerRuleView` get `var visibleUnitCount: Int?` (stored, ignored) and `func revealUnitRects() -> [CGRect] { [bounds] }`.

**Code block.** Replace the TextKit 1 `boundingRect` measure (Plan 1 deferred minor) with TextKit 2 line metrics from a standalone layout manager with an unbounded container:

```swift
    /// Bottom of each code line in the unwrapped text, cumulative, plus the widest line, both measured with a
    /// standalone TextKit 2 layout manager whose container is unbounded both ways.
    private var lineMetrics: (bottoms: [CGFloat], width: CGFloat)?

    private var lines: (bottoms: [CGFloat], width: CGFloat) {
        if let lineMetrics { return lineMetrics }
        let storage = NSTextContentStorage()
        let manager = NSTextLayoutManager()
        let container = NSTextContainer(size: .zero)
        container.lineFragmentPadding = 0
        manager.textContainer = container
        storage.addTextLayoutManager(manager)
        storage.attributedString = highlighted
        manager.ensureLayout(for: manager.documentRange)
        var bottoms: [CGFloat] = []
        var width: CGFloat = 0
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: []) { fragment in
            bottoms.append(ceil(fragment.layoutFragmentFrame.maxY))
            width = max(width, ceil(fragment.layoutFragmentFrame.width))
            return true
        }
        if bottoms.isEmpty { bottoms = [ceil(theme.codeFont.lineHeight)] }
        let metrics = (bottoms, width)
        lineMetrics = metrics
        return metrics
    }

    var visibleUnitCount: Int? {
        didSet { if visibleUnitCount != oldValue { setNeedsLayout() } }
    }

    private var visibleTextHeight: CGFloat {
        let bottoms = lines.bottoms
        let count = visibleUnitCount.map { min(max($0, 1), bottoms.count) } ?? bottoms.count
        return bottoms[count - 1]
    }

    func revealUnitRects() -> [CGRect] {
        let top = (theme.showsCodeBlockHeader ? Self.headerHeight : 0) + theme.embedPadding
        var rects: [CGRect] = []
        var previous: CGFloat = 0
        for (index, bottom) in lines.bottoms.enumerated() {
            let minY = index == 0 ? 0 : top + previous
            rects.append(CGRect(x: 0, y: minY, width: bounds.width, height: top + bottom - minY))
            previous = bottom
        }
        let visible = visibleUnitCount.map { min(max($0, 1), rects.count) } ?? rects.count
        if visible > 0 { rects[visible - 1].size.height = max(rects[visible - 1].height, bounds.maxY - rects[visible - 1].minY) }
        return rects
    }
```

`embedHeight(forWidth:)` becomes `(header) + theme.embedPadding * 2 + visibleTextHeight`. `textSize` becomes `CGSize(width: lines.width, height: lines.bottoms.last ?? 0)` (delete `cachedTextSize`). `update(to:)` sets `lineMetrics = nil`. In `layoutSubviews`, size `textView` to the full text height (`textSize.height + theme.embedPadding * 2`) so every line stays laid out, and let the view's `clipsToBounds` cut it at the visible height. Keep the `+ 2` width absorber only if a test shows the last glyph wrapping; the TextKit 2 width should not need it.

**Table.** Units are rows:

```swift
    var visibleUnitCount: Int? {
        didSet { if visibleUnitCount != oldValue { setNeedsLayout() } }
    }

    func revealUnitRects() -> [CGRect] {
        let heights = layout(forWidth: bounds.width).rowHeights
        var rects: [CGRect] = []
        var y: CGFloat = 0
        for height in heights {
            rects.append(CGRect(x: 0, y: y, width: bounds.width, height: height))
            y += height
        }
        let visible = visibleUnitCount.map { min(max($0, 1), rects.count) } ?? rects.count
        if visible > 0 { rects[visible - 1].size.height = max(rects[visible - 1].height, bounds.maxY - rects[visible - 1].minY) }
        return rects
    }
```

`embedHeight(forWidth:)` sums only the first `visibleUnitCount` row heights (all when nil).

**Attachment.** In `GlimmerBlockAttachment`:

```swift
    /// The units the view shows while a reveal runs; nil shows all. Kept here, so a view made later starts right.
    @MainActor
    var visibleUnitCount: Int? {
        get { visibleUnits }
        set {
            visibleUnits = newValue
            cachedView?.visibleUnitCount = newValue
        }
    }
    @MainActor private var visibleUnits: Int?
```

In `embedView()`, after creating the view, set `view.visibleUnitCount = visibleUnits`.

- [ ] **Step 7: The document and text view helpers**

In `GlimmerStreamingDocument`:

```swift
    /// Embeds that reveal in units: document offset → each unit's text length.
    var embedUnits: [Int: [Int]] {
        var units: [Int: [Int]] = [:]
        for record in embeddedAttachments {
            let lengths = record.embed.revealUnitLengths
            if !lengths.isEmpty { units[record.offset] = lengths }
        }
        return units
    }
```

In `GlimmerTextView`:

```swift
    // MARK: - Embeds

    /// The block attachment at `index`, or nil.
    func blockAttachment(atCharacter index: Int) -> GlimmerBlockAttachment? {
        guard index >= 0, index < textStorage.length else { return nil }
        return textStorage.attribute(.attachment, at: index, effectiveRange: nil) as? GlimmerBlockAttachment
    }

    /// The reveal-unit rects of the embed at `index`, in this view's coordinates, or nil when it has no view yet.
    func embedUnitRects(atCharacter index: Int) -> [CGRect]? {
        guard let view = blockAttachment(atCharacter: index)?.existingView, view.superview != nil else { return nil }
        return view.revealUnitRects().map { view.convert($0, to: self) }
    }

    /// Lays the embed at `index` out again after its height changed (its visible units).
    func invalidateEmbedLayout(atCharacter index: Int) {
        guard let manager = textLayoutManager, let range = textRange(for: NSRange(location: index, length: 1)) else { return }
        manager.invalidateLayout(for: range)
        manager.ensureLayout(for: range)
        textVersion &+= 1
    }
```

Add `@MainActor var existingView: (any GlimmerEmbedView)? { cachedView }` to `GlimmerBlockAttachment`.

- [ ] **Step 8: Mask unit phrases**

In `GlimmerRevealMask`: key phrase layers by a `PhraseKey: Hashable { let location: Int; let unit: Int? }` instead of `Int`. `phraseLayer(startingAt:)` keeps working for text phrases (`unit: nil`). Add:

```swift
    func phraseLayer(forUnit unit: Int, at location: Int) -> CAShapeLayer? {
        phraseLayers[PhraseKey(location: location, unit: unit)]
    }
```

In `update(in:engine:now:)`, when building a phrase layer's path:

```swift
            let segments: [CGRect]
            if let unit = phrase.unit, let rects = textView.embedUnitRects(atCharacter: phrase.range.location), unit < rects.count {
                segments = [rects[unit]]
            } else {
                let startsLine = textView.isLineStart(atCharacter: phrase.range.location)
                segments = textView.segmentRects(for: phrase.range).enumerated().map { index, rect in
                    index > 0 || startsLine ? Self.extendedToLeadingEdge(rect) : rect
                }
            }
```

For the settled part: when the first unsettled character is an embed with settled units, add those units' union to the settled-line path:

```swift
            var settledRects = settledOnLine.map(Self.extendedToLeadingEdge)
            if let settledUnits = engine.unitsSettled[firstUnsettled], settledUnits > 0,
               let rects = textView.embedUnitRects(atCharacter: firstUnsettled) {
                settledRects += rects.prefix(settledUnits)
            }
            settledLineLayer.path = Self.path(settledRects)
```

Include `engine.unitsSettled[firstUnsettled]` in `SettledKey` (a new `settledUnits: Int` field), so the path is rebuilt when a unit settles.

- [ ] **Step 9: The view feeds units and syncs visible counts**

In `GlimmerView`: keep `private var embedUnits: [Int: [Int]] = [:]`. Set it from `document.embedUnits` after every `document.update` (in `update` and `rebuildDocument`), and pass it to every `engine?.textChanged(…, embedUnits: embedUnits)` call. Add:

```swift
    /// Shows the frontier embed's started units, one more line or row per unit phrase. Embeds already passed, or not
    /// reached yet, show everything.
    private func syncEmbedUnits() {
        var changed = false
        for offset in embedUnits.keys {
            guard let attachment = textView.blockAttachment(atCharacter: offset) else { continue }
            let visible: Int? = engine.flatMap { engine in
                offset == engine.revealedLength ? max(1, engine.unitsRevealed[offset] ?? 0) : nil
            }
            guard attachment.visibleUnitCount != visible else { continue }
            attachment.visibleUnitCount = visible
            textView.invalidateEmbedLayout(atCharacter: offset)
            changed = true
        }
        guard changed else { return }
        fitTextViewToContent()
        revealMask.invalidateGeometry()
        revealedHeight = nil
    }
```

Call `syncEmbedUnits()` in `advanceReveal()` right after `current.advance(to: now)` and `engine = current` (move the assignment above it), before `revealMask.update`. Also call it in `endReveal()` after `engine = nil`, which resets every count to `nil`.

`height(forWidth:)` needs no change. The frontier embed's line box is its visible height, because `revealedLength` sits at its offset, and `lineRect(atCharacter: revealedLength - 1)` is the line before it. So while the frontier is an embed, the revealed height must include it: when `embedUnits[engine.revealedLength] != nil`, return `ceil(textView.lineRect(atCharacter: engine.revealedLength)?.maxY ?? 0)`, cached the same way.

- [ ] **Step 10: Run to verify they pass**

Run the test command for `GlimmerRevealEngineTests`, `GlimmerRevealMaskTests`, `GlimmerEmbedStreamingTests`, `GlimmerViewStreamingTests`, `GlimmerStreamParityTests`, `GlimmerCodeBlockViewTests` and `GlimmerTableViewTests`.
Expected: PASS. The parity suite proves that settled renders are unchanged.

- [ ] **Step 11: On-simulator check, engine suite, commit**

Build and run the demo, and open the Streaming Lab. Its "Ten steps" section has a code block inside item 2, and its `swift` block streams too. Record a run (`xcrun simctl io <udid> recordVideo`) and make a contact sheet (`ffmpeg -vf "fps=6,scale=300:-1,tile=6x3"`). Expected: the code box grows one line at a time with each line fading in, the table grows one row at a time, and nothing jumps.

Run every engine test class. Expected: all pass.

```bash
git add Sources/Glimmer/Engine Tests/GlimmerTests/Engine
git commit -m "Engine: reveal code blocks line by line and tables row by row

The reveal engine paces an embed's units (code lines, table rows) like
phrases, and the mask fades each unit's rect. While an embed is the reveal's
frontier its view shows only the started units, so the box grows one line
or row at a time. Code block metrics now come from TextKit 2 instead of a
TextKit 1 bounding rect."
```

---

### Task 5: Parse and compose off the main thread

**Files:**
- Create: `Sources/Glimmer/Engine/Stream/GlimmerDocumentWorker.swift`
- Modify: `Sources/Glimmer/Engine/Compose/GlimmerComposer.swift` (drop `@MainActor`)
- Modify: `Sources/Glimmer/Engine/Stream/GlimmerStreamingDocument.swift` (drop `@MainActor`, `@unchecked Sendable`)
- Modify: `Sources/Glimmer/Engine/GlimmerView.swift` (worker, request coalescing, synchronous settled path, `pendingDocument`, `lastApplyDuration`)
- Test: `Tests/GlimmerTests/Engine/GlimmerDocumentWorkerTests.swift`. `GlimmerViewStreamingTests.swift`, `GlimmerStreamParityTests.swift`, `GlimmerEmbedStreamingTests.swift` and `GlimmerStreamingPerformanceTests.swift` become async.

**Interfaces:**
- Consumes: Tasks 3–4's document (`embedUnits`, `embedUpdates`)
- Produces:
  - `actor GlimmerDocumentWorker` with `init(document: GlimmerStreamingDocument, extensions: [any GlimmerExtension])` and `func update(markdown: String, isStreaming: Bool) -> GlimmerDocumentResult`
  - `struct GlimmerDocumentResult: @unchecked Sendable { let edit: GlimmerDocumentEdit?; let embedUnits: [Int: [Int]]; let isStreaming: Bool }`
  - `GlimmerView.pendingDocument: Task<Void, Never>?` (internal; tests await it)
  - `GlimmerView.lastApplyDuration: Duration` (internal; the main-thread cost of applying the last result)

The rules this task follows:
- **Streaming updates** (`isStreaming == true`, or while a reveal still runs, or while earlier work is pending) go to the worker. They are applied on the main thread in request order. While one is in flight, newer requests coalesce: when it finishes, the latest markdown is processed next, and the intermediate ones are skipped. The document diff handles any jump.
- **A settled update** with no reveal running and nothing pending composes synchronously on the main thread, so a host can size the view in the same layout pass (collection-view self-sizing). It builds a fresh document, which then seeds a new worker.
- **A rebuild** (theme, configuration, Dynamic Type) composes synchronously with a new worker. Results from the old worker are dropped.
- Extensions' `preprocess` runs on the worker for streaming updates (spec §4.1: "Both run off-main").

- [ ] **Step 1: Write the failing tests**

Create `Tests/GlimmerTests/Engine/GlimmerDocumentWorkerTests.swift`:

```swift
import UIKit
import XCTest
@testable import Glimmer

/// Records which thread each preprocess ran on.
private final class ThreadRecorder: GlimmerExtension, @unchecked Sendable {
    private let lock = NSLock()
    private var mainThreadFlags: [Bool] = []
    var ranOnMain: [Bool] { lock.withLock { mainThreadFlags } }
    func preprocess(_ markdown: String) -> String {
        lock.withLock { mainThreadFlags.append(Thread.isMainThread) }
        return markdown
    }
}

@MainActor
final class GlimmerDocumentWorkerTests: XCTestCase {
    func testStreamingUpdatesComposeOffTheMainThread() async {
        let recorder = ThreadRecorder()
        let view = GlimmerView(configuration: GlimmerConfiguration(extensions: [recorder], imageLoader: nil))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: "Streaming **text** arrives", isStreaming: true)
        await view.pendingDocument?.value
        XCTAssertEqual(recorder.ranOnMain.last, false)
        XCTAssertEqual(view.textView.textStorage.string, "Streaming text arrives")
        _ = window
    }

    func testSettledConfigureIsSynchronous() {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: "A settled **answer**.")
        XCTAssertNil(view.pendingDocument)
        XCTAssertEqual(view.textView.textStorage.string, "A settled answer.")
        XCTAssertGreaterThan(view.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height, 0)
        _ = window
    }

    func testLatestUpdateWinsWhenUpdatesArriveFasterThanTheWorker() async {
        var configuration = GlimmerConfiguration(imageLoader: nil)
        configuration.reveal = .none
        let view = GlimmerView(configuration: configuration)
        let window = hostInWindow(view, width: 390, height: 800)
        var markdown = ""
        for word in ["one", "two", "three", "four", "five", "six"] {
            markdown += word + " "
            view.update(markdown: markdown, isStreaming: true)
        }
        await view.pendingDocument?.value
        XCTAssertEqual(view.textView.textStorage.string, "one two three four five six ")
        _ = window
    }

    func testRebuildWhileComposingNeverAppliesStaleText() async throws {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: "Before the theme change, streaming", isStreaming: true)
        var configuration = view.configuration
        configuration.theme.bodyFont = UIFont.systemFont(ofSize: 23)
        view.configuration = configuration
        await view.pendingDocument?.value
        let font = try XCTUnwrap(view.textView.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        XCTAssertEqual(font.pointSize, configuration.theme.scaled(for: view.traitCollection).bodyFont.pointSize, accuracy: 0.5)
        XCTAssertEqual(view.textView.textStorage.string, "Before the theme change, streaming")
        _ = window
    }
}
```

In `GlimmerViewStreamingTests`, `GlimmerStreamParityTests.testStreamedViewEndsIdenticalToASettledView`, `GlimmerEmbedStreamingTests` and `GlimmerStreamingPerformanceTests.streamTail`, make every test that calls `update(…, isStreaming: true)` `async`. Add `await view.pendingDocument?.value` after each streaming `update` whose effect the test then asserts. Settled `update(markdown:)` calls need no await.

In `streamTail`, measure the main-thread cost as `view.lastApplyDuration` after awaiting each update, instead of timing `update` itself:

```swift
            view.update(markdown: prefix, isStreaming: true)
            await view.pendingDocument?.value
            let update = view.lastApplyDuration
```

- [ ] **Step 2: Run to verify they fail**

Run the test command for `GlimmerDocumentWorkerTests`. Expected: compile errors (`pendingDocument`), then, once it exists as `nil`, `testStreamingUpdatesComposeOffTheMainThread` FAILS (`ranOnMain.last == true`).

- [ ] **Step 3: Make the composer and document portable**

Remove `@MainActor` from `struct GlimmerComposer` and from `final class GlimmerStreamingDocument`. Declare the document `final class GlimmerStreamingDocument: @unchecked Sendable` with this doc line added:

```swift
/// One owner at a time: it is built on the main thread for a synchronous configure, then handed to a
/// `GlimmerDocumentWorker`, which alone uses it from then on.
```

Fix every compile error by keeping main-actor work out of the composer: it must only create attachments, never views. `UIImage(systemName:)`, `NSAttributedString.size()` and `UIFont` are fine off the main thread. `GlimmerBlockAttachment` and `GlimmerInlineAttachment` initializers must stay nonisolated. Only `embedView()`, `chipView()`, `update(to:)` and `visibleUnitCount` are `@MainActor`.

- [ ] **Step 4: The worker**

Create `Sources/Glimmer/Engine/Stream/GlimmerDocumentWorker.swift`:

```swift
import Foundation

/// What a worker update produced, handed to the main thread once. `@unchecked` because the attributed string and the
/// attachments inside it are built by the worker and read by it afterwards only as identities (reuse and trimming
/// compare attachments by pointer); the main thread owns their contents from here on.
struct GlimmerDocumentResult: @unchecked Sendable {
    let edit: GlimmerDocumentEdit?
    let embedUnits: [Int: [Int]]
    /// The request's own flag: a newer request may already have ended the stream.
    let isStreaming: Bool
}

/// Runs a view's document off the main thread, one update at a time, in the order requested.
actor GlimmerDocumentWorker {
    private let document: GlimmerStreamingDocument
    private let extensions: [any GlimmerExtension]

    init(document: GlimmerStreamingDocument, extensions: [any GlimmerExtension]) {
        self.document = document
        self.extensions = extensions
    }

    func update(markdown: String, isStreaming: Bool) -> GlimmerDocumentResult {
        let source = extensions.reduce(markdown) { $1.preprocess($0) }
        let edit = document.update(markdown: source, isStreaming: isStreaming)
        return GlimmerDocumentResult(edit: edit, embedUnits: document.embedUnits, isStreaming: isStreaming)
    }
}
```

- [ ] **Step 5: The view schedules, coalesces and applies**

In `GlimmerView`, replace `private var document: GlimmerStreamingDocument` with:

```swift
    private var worker: GlimmerDocumentWorker
    private var requestedUpdate = 0
    private var appliedUpdate = 0
    /// The worker update in flight, if any. Tests await it.
    private(set) var pendingDocument: Task<Void, Never>?
    /// Main-thread time spent applying the last result: the §3 "applying one network update" metric.
    private(set) var lastApplyDuration: Duration = .zero
```

Initialize `worker` in `init` from a fresh document (`makeDocument()`, below). Replace the body of `update(markdown:isStreaming:revealID:)` after the three assignments with:

```swift
        if !isStreaming, engine == nil, pendingDocument == nil {
            // A settled answer: compose now, so the host can size it in this layout pass.
            composeSynchronously()
            return
        }
        requestedUpdate += 1
        if pendingDocument == nil {
            pendingDocument = Task { [weak self] in await self?.drainDocumentUpdates() }
        }
```

Add:

```swift
    private func makeDocument() -> GlimmerStreamingDocument {
        GlimmerStreamingDocument(composer: GlimmerComposer(
            theme: configuration.theme.scaled(for: traitCollection),
            highlighter: configuration.highlighter,
            imageLoader: configuration.imageLoader,
            extensions: configuration.extensions
        ))
    }

    /// Composes the whole current markdown on the main thread and restarts the worker from that document.
    private func composeSynchronously() {
        let document = makeDocument()
        _ = document.update(markdown: preprocessed(markdown), isStreaming: isStreaming)
        worker = GlimmerDocumentWorker(document: document, extensions: configuration.extensions)
        appliedUpdate = requestedUpdate
        textView.attributedText = document.text
        apply(GlimmerDocumentResult(edit: nil, embedUnits: document.embedUnits, isStreaming: isStreaming), replacedText: true)
    }

    /// Applies worker results in request order. When one lands, only the latest request is computed next.
    private func drainDocumentUpdates() async {
        while appliedUpdate < requestedUpdate {
            let request = requestedUpdate
            let worker = self.worker
            let result = await worker.update(markdown: markdown, isStreaming: isStreaming)
            // A rebuild replaced the worker meanwhile, and already composed this text.
            guard worker === self.worker else { continue }
            apply(result, replacedText: false)
            appliedUpdate = request
        }
        pendingDocument = nil
    }

    /// Everything after the document changed: embed updates, the text edit, fitting, the reveal and the height.
    private func apply(_ result: GlimmerDocumentResult, replacedText: Bool) {
        let started = ContinuousClock.now
        embedUnits = result.embedUnits
        if let edit = result.edit {
            for update in edit.embedUpdates { update.attachment.update(to: update.embed) }
            textView.apply(edit)
            if let engine, edit.range.location < engine.revealedLength {
                revealMask.invalidateGeometry()
                revealedHeight = nil
            }
        }
        if replacedText || result.edit != nil {
            if replacedText {
                revealedHeight = nil
                revealMask.invalidateGeometry()
            }
            fitTextViewToContent()
        }
        startRevealIfNeeded(isStreaming: result.isStreaming)
        engine?.textChanged(NSString(string: textView.textStorage.string), isStreaming: result.isStreaming,
                            now: clock.now, embedUnits: embedUnits)
        advanceReveal()
        reportHeightIfChanged()
        lastApplyDuration = ContinuousClock.now - started
    }
```

`startRevealIfNeeded` takes the result's `isStreaming` instead of reading the property. `rebuildDocument()` becomes: apply the scaled theme to the text view, `if revealOptions == nil { endReveal() }`, then `composeSynchronously()`. `composeSynchronously` replaces the worker, so in-flight results from the old one are dropped by the identity check.

Delete the old document-applying code from `update` and `rebuildDocument`; `apply` now does it.

- [ ] **Step 6: Run to verify they pass**

Run the test command for `GlimmerDocumentWorkerTests`, `GlimmerViewStreamingTests`, `GlimmerStreamParityTests`, `GlimmerEmbedStreamingTests` and `GlimmerStreamingPerformanceTests`.
Expected: PASS. The long-list case's main-thread apply drops from about 14 ms to below the 8 ms budget, because its re-compose now runs on the worker. Tighten that test's gate from 25 ms to `budget`.

- [ ] **Step 7: Run the engine suite and commit**

Run every engine test class. Expected: all pass.

```bash
git add Sources/Glimmer/Engine Tests/GlimmerTests/Engine
git commit -m "Engine: parse and compose streaming updates off the main thread

Each GlimmerView runs its document on a worker actor. Streaming updates are
healed, parsed, composed and trimmed there, then applied on the main thread
in order. Updates that arrive while one is in flight coalesce to the latest.
A settled answer still composes synchronously, so hosts can size it in one
layout pass, and a rebuild drops any stale result."
```

---

### Task 6: Settled answers configure from caches

**Files:**
- Create: `Sources/Glimmer/Engine/Stream/GlimmerDocumentCache.swift`
- Modify: `Sources/Glimmer/Engine/Theme/GlimmerTheme.swift` (`Hashable`)
- Modify: `Sources/Glimmer/Engine/Embeds/GlimmerBlockAttachment.swift`, `Extensions/GlimmerInlineAttachment.swift` (`freshCopy()`)
- Modify: `Sources/Glimmer/Engine/GlimmerView.swift` (`composeSynchronously` consults and fills the cache; the height cache)
- Test: `Tests/GlimmerTests/Engine/GlimmerDocumentCacheTests.swift`, `GlimmerStreamingPerformanceTests.swift`

**Interfaces:**
- Consumes: Task 5's `composeSynchronously()` and worker
- Produces:
  - `GlimmerDocumentCache` with `shared`, `init(capacity:)`, `text(for:) -> NSAttributedString?` (fresh attachments), `store(_:for:)`, `height(for:width:)`, `storeHeight(_:for:width:)`, `removeAll()`, `hits: Int`
  - `GlimmerDocumentCache.Key: Hashable` (source, theme, extension type names)
  - `GlimmerBlockAttachment.freshCopy()`, `GlimmerInlineAttachment.freshCopy()`

Why: spec §3 wants a settled answer configured on cell reuse in ≤ 4 ms (cached document and height), and §9 wants the caches dropped under memory pressure. A cached text never shares attachments between views: each checkout copies the attachments, so two cells showing the same answer each get their own embed views.

- [ ] **Step 1: Write the failing tests**

Create `Tests/GlimmerTests/Engine/GlimmerDocumentCacheTests.swift`:

```swift
import UIKit
import XCTest
@testable import Glimmer

@MainActor
final class GlimmerDocumentCacheTests: XCTestCase {
    private let answer = "# Title\n\nSome **text**.\n\n```swift\nlet x = 1\n```"

    override func setUp() async throws {
        GlimmerDocumentCache.shared.removeAll()
    }

    func testSecondConfigureOfTheSameAnswerComesFromTheCache() {
        let first = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let firstWindow = hostInWindow(first, width: 390, height: 800)
        first.update(markdown: answer)
        let hits = GlimmerDocumentCache.shared.hits
        let second = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let secondWindow = hostInWindow(second, width: 390, height: 800)
        second.update(markdown: answer)
        XCTAssertEqual(GlimmerDocumentCache.shared.hits, hits + 1)
        XCTAssertEqual(second.textView.textStorage.string, first.textView.textStorage.string)
        _ = (firstWindow, secondWindow)
    }

    func testTwoViewsOfOneAnswerNeverShareAnEmbedView() throws {
        let first = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let second = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let firstWindow = hostInWindow(first, width: 390, height: 800)
        let secondWindow = hostInWindow(second, width: 390, height: 800)
        first.update(markdown: answer)
        second.update(markdown: answer)
        settle(first)
        settle(second)
        let a = try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: first))
        let b = try XCTUnwrap(findSubview(GlimmerCodeBlockView.self, in: second))
        XCTAssertFalse(a === b)
        XCTAssertTrue(a.isDescendant(of: first))
        _ = (firstWindow, secondWindow)
    }

    func testMemoryWarningEmptiesTheCache() {
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: answer)
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        let key = GlimmerDocumentCache.Key(source: answer, theme: view.configuration.theme.scaled(for: view.traitCollection), extensions: [])
        XCTAssertNil(GlimmerDocumentCache.shared.text(for: key))
        _ = window
    }

    func testCachedHeightMatchesAMeasuredOne() {
        let first = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let firstWindow = hostInWindow(first, width: 390, height: 800)
        first.update(markdown: answer)
        let measured = first.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height
        let second = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let secondWindow = hostInWindow(second, width: 390, height: 800)
        second.update(markdown: answer)
        XCTAssertEqual(second.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height, measured, accuracy: 0.5)
        _ = (firstWindow, secondWindow)
    }
}
```

In `GlimmerStreamingPerformanceTests`, add:

```swift
    /// Spec §3: configuring a settled answer on cell reuse ≤ 4 ms, with the document and height cached.
    func testConfiguringACachedSettledAnswerStaysWithinBudget() {
        let answer = Array(repeating: StreamingFixtures.all.map(\.markdown).joined(separator: "\n\n"), count: 7).joined(separator: "\n\n")
        let warm = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let warmWindow = hostInWindow(warm, width: 390, height: 800)
        warm.update(markdown: answer)
        warm.layoutIfNeeded()
        let timer = ContinuousClock()
        var samples: [Duration] = []
        for _ in 0..<9 {
            let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
            let window = hostInWindow(view, width: 390, height: 800)
            samples.append(timer.measure {
                view.update(markdown: answer)
                view.layoutIfNeeded()
            })
            _ = window
        }
        print("PERF configure cached ~1,200 words: median \(samples.sorted()[4])")
        XCTAssertLessThan(samples.sorted()[4], configureBudget)
        _ = warmWindow
    }
```

with `private let configureBudget: Duration = .milliseconds(8)` next to `budget`. That is a Debug gate; Task 8 sets the Release one.

- [ ] **Step 2: Run to verify they fail**

Run the test command for `GlimmerDocumentCacheTests`. Expected: compile errors (`GlimmerDocumentCache`), then FAIL.

- [ ] **Step 3: Hashable theme and fresh attachment copies**

In `GlimmerTheme.swift`, add `extension GlimmerTheme: Hashable {}` in the same file. Every stored property is `UIFont`, `UIColor`, `[UIFont]`, `CGFloat` or `Bool`, all hashable, so the conformance synthesizes. If the compiler refuses, write `hash(into:)` and `==` over the stored properties explicitly.

In `GlimmerBlockAttachment`:

```swift
    /// A new attachment for the same embed, without a view: for a cached text shown by another view.
    func freshCopy() -> GlimmerBlockAttachment {
        GlimmerBlockAttachment(embed: embed, theme: theme, highlighter: highlighter, imageLoader: imageLoader)
    }
```

In `GlimmerInlineAttachment`: `func freshCopy() -> GlimmerInlineAttachment { GlimmerInlineAttachment(token: token, glimmerExtension: glimmerExtension, theme: theme) }`.

- [ ] **Step 4: The cache**

Create `Sources/Glimmer/Engine/Stream/GlimmerDocumentCache.swift`:

```swift
import UIKit

/// Composed text and heights of settled answers, so a cell showing an answer again skips parsing and composing and
/// knows its height before layout. Bounded (least recently used out), and emptied on a memory warning (spec §9).
@MainActor
final class GlimmerDocumentCache {
    static let shared = GlimmerDocumentCache()

    struct Key: Hashable {
        let source: String
        let theme: GlimmerTheme
        /// Extension type names: a different extension set composes differently.
        let extensions: [String]
    }

    private struct Entry {
        let text: NSAttributedString
        var heights: [CGFloat: CGFloat] = [:]
    }

    private let capacity: Int
    private var entries: [Key: Entry] = [:]
    private var recent: [Key] = []
    private(set) var hits = 0
    private var memoryWarning: NSObjectProtocol?

    init(capacity: Int = 64) {
        self.capacity = capacity
        memoryWarning = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.removeAll() }
        }
    }

    /// A copy of the cached text with fresh attachments, so no two views ever share an embed view.
    func text(for key: Key) -> NSAttributedString? {
        guard let entry = entries[key] else { return nil }
        hits += 1
        touch(key)
        let copy = NSMutableAttributedString(attributedString: entry.text)
        copy.enumerateAttribute(.attachment, in: NSRange(location: 0, length: copy.length)) { value, range, _ in
            if let block = value as? GlimmerBlockAttachment {
                copy.addAttribute(.attachment, value: block.freshCopy(), range: range)
            } else if let inline = value as? GlimmerInlineAttachment {
                copy.addAttribute(.attachment, value: inline.freshCopy(), range: range)
            }
        }
        return copy
    }

    func store(_ text: NSAttributedString, for key: Key) {
        entries[key] = Entry(text: NSAttributedString(attributedString: text))
        touch(key)
    }

    func height(for key: Key, width: CGFloat) -> CGFloat? {
        entries[key]?.heights[width]
    }

    func storeHeight(_ height: CGFloat, for key: Key, width: CGFloat) {
        entries[key]?.heights[width] = height
    }

    func removeAll() {
        entries.removeAll()
        recent.removeAll()
    }

    private func touch(_ key: Key) {
        recent.removeAll { $0 == key }
        recent.append(key)
        if recent.count > capacity { entries[recent.removeFirst()] = nil }
    }
}
```

- [ ] **Step 5: The view uses it**

In `GlimmerView`, add `private var cacheKey: GlimmerDocumentCache.Key?` (the key of the settled text on screen, or nil) and a `private var viewHoldsWorkerText = true`.

`composeSynchronously()` becomes:

```swift
    private func composeSynchronously() {
        let theme = configuration.theme.scaled(for: traitCollection)
        let source = preprocessed(markdown)
        let key = GlimmerDocumentCache.Key(source: source, theme: theme,
                                           extensions: configuration.extensions.map { String(reflecting: type(of: $0)) })
        if !isStreaming, let cached = GlimmerDocumentCache.shared.text(for: key) {
            // The worker starts empty. Its first result replaces the whole text (see `apply`).
            worker = GlimmerDocumentWorker(document: makeDocument(), extensions: configuration.extensions)
            viewHoldsWorkerText = false
            cacheKey = key
            appliedUpdate = requestedUpdate
            textView.attributedText = cached
            apply(GlimmerDocumentResult(edit: nil, embedUnits: [:], isStreaming: false), replacedText: true)
            return
        }
        let document = makeDocument()
        _ = document.update(markdown: source, isStreaming: isStreaming)
        if !isStreaming { GlimmerDocumentCache.shared.store(document.text, for: key) }
        cacheKey = isStreaming ? nil : key
        worker = GlimmerDocumentWorker(document: document, extensions: configuration.extensions)
        viewHoldsWorkerText = true
        appliedUpdate = requestedUpdate
        textView.attributedText = document.text
        apply(GlimmerDocumentResult(edit: nil, embedUnits: document.embedUnits, isStreaming: isStreaming), replacedText: true)
    }
```

Cached text needs its embed units only for a reveal, and a cached text is settled, so an empty map is correct.

While the view shows a cached text, the worker's document is empty, so its first edit would be relative to nothing. That first result must replace the whole text instead. Add to `GlimmerDocumentWorker.swift`:

```swift
/// A worker's whole text, handed to the main thread once (see `GlimmerDocumentResult` for the `@unchecked`).
struct GlimmerTextBox: @unchecked Sendable {
    let text: NSAttributedString
}
```

and to the actor: `func text() -> GlimmerTextBox { GlimmerTextBox(text: NSAttributedString(attributedString: document.text)) }`. In `drainDocumentUpdates`, after the identity `guard`, replace `apply(result, replacedText: false)` with:

```swift
            if viewHoldsWorkerText {
                apply(result, replacedText: false)
            } else {
                // The view shows a cached text the worker never composed: take its whole text instead of an edit.
                let full = await worker.text().text
                guard worker === self.worker else { continue }
                textView.attributedText = full
                viewHoldsWorkerText = true
                cacheKey = nil
                apply(GlimmerDocumentResult(edit: nil, embedUnits: result.embedUnits, isStreaming: result.isStreaming), replacedText: true)
            }
```

In `fitTextViewToContent()`, use a cached height at a new width instead of measuring:

```swift
        if textView.bounds.width != bounds.width {
            // A new width re-wraps everything: measure it in full once, unless this settled text's height is cached.
            let cached = cacheKey.flatMap { GlimmerDocumentCache.shared.height(for: $0, width: bounds.width) }
            let fullHeight = cached ?? textView.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height
            textView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: fullHeight + slack(forContentHeight: fullHeight))
            if let cached {
                contentHeight = (textView.textVersion, cached)
                return
            }
        } else if contentHeight?.version == textView.textVersion {
            return
        }
```

At the end of `fitTextViewToContent()`, store what it measured for a settled text: `if let cacheKey, engine == nil { GlimmerDocumentCache.shared.storeHeight(height, for: cacheKey, width: textView.bounds.width) }`. Any edit clears `cacheKey` (in `apply`, when `result.edit != nil`).

- [ ] **Step 6: Run to verify they pass**

Run the test command for `GlimmerDocumentCacheTests`, `GlimmerStreamingPerformanceTests`, `GlimmerDocumentWorkerTests` and `GlimmerViewStreamingTests`.
Expected: PASS. Read the `PERF configure cached` line. If the median is over the 8 ms Debug gate, find the dominant cost with `ContinuousClock` around `attributedText =`, `layoutIfNeeded` and `fitTextViewToContent`, and record what it is in the ledger before changing anything.

- [ ] **Step 7: Run the engine suite and commit**

```bash
git add Sources/Glimmer/Engine Tests/GlimmerTests/Engine
git commit -m "Engine: configure settled answers from a document and height cache

A settled answer's composed text and heights are cached by source, theme and
extension set. Showing it again copies the text with fresh attachments (so
no two views share an embed view) and skips parsing, composing and measuring.
The cache empties on a memory warning."
```

---

### Task 7: Streaming loose ends

**Files:**
- Modify: `Sources/Glimmer/Engine/Stream/GlimmerTailHealer.swift` (`_`/`__`, a setext underline being typed)
- Modify: `Sources/Glimmer/Engine/Reveal/GlimmerRevealStore.swift` (a prefix fingerprint)
- Modify: `Sources/Glimmer/Engine/GlimmerView.swift` (record and check the fingerprint)
- Modify: `Sources/Glimmer/Engine/Reveal/GlimmerRevealClock.swift` (`isolated deinit`)
- Modify: `Sources/Glimmer/Engine/Reveal/GlimmerPhraseChunker.swift` (closing quotes and brackets)
- Test: `GlimmerTailHealerTests.swift`, `GlimmerPhraseChunkerTests.swift`, `GlimmerViewStreamingTests.swift`, and a new `GlimmerRevealStoreTests.swift` (move `testStoreIsMonotonicAndBounded` out of `GlimmerViewStreamingTests`)

**Interfaces:**
- Consumes: the healer, store, clock and chunker from Plan 2
- Produces: `GlimmerRevealStore.record(_:text:for:)`, `revealedLength(for:text:) -> Int?`, `static func prefixHash(of: NSString, length: Int) -> Int`

These are the Plan 2 review's deferred minors that affect streaming.

- [ ] **Step 1: Write the failing tests**

Add to the `cases` table in `GlimmerTailHealerTests`:

```swift
        ("Hello __wor", "Hello __wor__"),
        ("a _b", "a _b_"),
        ("snake_case_name", "snake_case_name"),
        ("Title\n-", "Title\n"),
        ("Title\n---", "Title\n"),
        ("text\n\n---", "text\n\n---"),
```

Append to `GlimmerPhraseChunkerTests`:

```swift
    func testPunctuationBeforeAClosingQuoteEndsAPhrase() {
        let text = "He said \"stop now.\" Then more words follow here" as NSString
        let end = GlimmerPhraseChunker.phraseEnd(in: text, from: 0, isStreaming: true, minWords: 3, maxWords: 8)
        XCTAssertEqual(end, (text as NSString).range(of: "Then").location)
    }
```

Create `Tests/GlimmerTests/Engine/GlimmerRevealStoreTests.swift`. Move `testStoreIsMonotonicAndBounded` into it, updated to the new signatures (pass one fixed `text` for every call), and add:

```swift
    func testRegeneratedAnswerUnderTheSameIDStartsOver() {
        let store = GlimmerRevealStore(capacity: 4)
        let first = "The first generation of this answer." as NSString
        store.record(20, text: first, for: "m")
        store.record(30, text: first, for: "m")
        XCTAssertEqual(store.revealedLength(for: "m", text: first), 30, "the same answer keeps growing")
        let regenerated = "A regenerated answer that says otherwise." as NSString
        XCTAssertNil(store.revealedLength(for: "m", text: regenerated))
        store.record(5, text: regenerated, for: "m")
        XCTAssertEqual(store.revealedLength(for: "m", text: regenerated), 5, "a new generation restarts at its own length")
    }
```

Append to `GlimmerViewStreamingTests`:

```swift
    func testReleasedSystemClockNeverFires() async {
        var fired = false
        var clock: GlimmerSystemRevealClock? = GlimmerSystemRevealClock()
        clock?.wake(at: CACurrentMediaTime() + 0.05) { fired = true }
        clock = nil
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(fired)
    }
```

- [ ] **Step 2: Run to verify they fail**

Run the test command for `GlimmerTailHealerTests`, `GlimmerPhraseChunkerTests`, `GlimmerRevealStoreTests` and `GlimmerViewStreamingTests`. Expected: the new cases FAIL, and the store test has compile errors.

- [ ] **Step 3: Healer**

In `openDelimiters(in:)`, before `case "*":`, add underscore emphasis. Intraword underscores never open or close (CommonMark: `snake_case` is literal):

```swift
            case "_" where next(1) == "_":
                if !isIntraword(at: index, length: 2) { toggle("__") }
                index += 2
                atLineStart = false
                continue
            case "_":
                if !isIntraword(at: index, length: 1) { toggle("_") }
```

with a local helper inside `openDelimiters`:

```swift
        func isIntraword(at position: Int, length: Int) -> Bool {
            let before = position > 0 ? characters[position - 1] : " "
            let after = position + length < characters.count ? characters[position + length] : " "
            return (before.isLetter || before.isNumber) && (after.isLetter || after.isNumber)
        }
```

Add a step to `heal(_:fenceScan:)` after `holdBackTableHeader`: `tail = holdBackSetextUnderline(tail)`, with:

```swift
    /// A line of only `-` or `=` right under paragraph text is a setext underline, or the start of a list item or
    /// rule; shown early it would flip the paragraph above into a heading and back. Hold it back until the next line.
    private static func holdBackSetextUnderline(_ tail: String) -> String {
        var lines = tail.components(separatedBy: "\n")
        guard lines.count >= 2, let last = lines.last,
              last.contains(#/^ {0,3}(-+|=+) *$/#),
              !lines[lines.count - 2].trimmingCharacters(in: .whitespaces).isEmpty else { return tail }
        lines.removeLast()
        return lines.joined(separator: "\n") + "\n"
    }
```

- [ ] **Step 4: Chunker**

In `phraseEnd`, closing quotes and brackets keep the punctuation state of the character before them:

```swift
            } else {
                inWord = true
                if character.count == 1, "\"'”’)]»".contains(character) {
                    // A closer after punctuation ("stop.") keeps the sentence end.
                } else {
                    lastWordEndsWithPunctuation = character.count == 1 && ",.;:!?".contains(character)
                }
            }
```

- [ ] **Step 5: Store fingerprint and clock**

In `GlimmerRevealStore`, store `(length: Int, prefixHash: Int)` per id. The hash always covers the first `min(length, 1_024)` characters of the text at the stored length, so a lookup can recompute it from the current text:

```swift
    /// A fingerprint of an answer's opening: its first `min(length, 1_024)` characters.
    static func prefixHash(of text: NSString, length: Int) -> Int {
        text.substring(to: min(length, 1_024, text.length)).hashValue
    }

    /// The revealed length recorded for `id`, if `text` opens the way that answer did.
    func revealedLength(for id: String, text: NSString) -> Int? {
        guard let entry = entries[id], entry.prefixHash == Self.prefixHash(of: text, length: entry.length) else { return nil }
        return entry.length
    }

    /// Records `length` for `id`. It only grows while `text` is the same answer; a regenerated answer starts over.
    func record(_ length: Int, text: NSString, for id: String) {
        var stored = length
        if let entry = entries[id], entry.prefixHash == Self.prefixHash(of: text, length: entry.length) {
            stored = max(entry.length, length)
        }
        entries[id] = (stored, Self.prefixHash(of: text, length: stored))
        recent.removeAll { $0 == id }
        recent.append(id)
        if recent.count > capacity { entries[recent.removeFirst()] = nil }
    }
```

`clear(_:)` stays. In `GlimmerView`, `advanceReveal()` calls `GlimmerRevealStore.shared.record(current.revealedLength, text: textView.textStorage.string as NSString, for: revealID)`, and `startRevealIfNeeded` calls `revealedLength(for: $0, text: textView.textStorage.string as NSString)`. Each call hashes at most 1,024 characters.

In `GlimmerSystemRevealClock`, add:

```swift
    isolated deinit {
        task?.cancel()
    }
```

- [ ] **Step 6: Run to verify they pass, run the engine suite, commit**

Run the four test classes, then every engine test class. Expected: all pass.

```bash
git add Sources/Glimmer/Engine Tests/GlimmerTests/Engine
git commit -m "Engine: heal underscores and setext underlines, resume only the same answer

The healer closes _ and __ emphasis (never intraword) and holds back a line of
dashes or equals signs that would flip the paragraph above into a heading.
The reveal store fingerprints each answer's opening, so a regenerated answer
under the same id starts over. Phrases end after a closing quote or bracket
that follows punctuation. A released system clock cancels its wake-up."
```

---

### Task 8: Release performance run

**Files:**
- Modify: `Tests/GlimmerTests/Engine/GlimmerStreamingPerformanceTests.swift` (Release budgets)
- Create: `docs/superpowers/perf/2026-09-26-glimmer-2-plan-3-results.md`

**Interfaces:**
- Consumes: every earlier task
- Produces: gated §3 numbers for the simulator in Release, and a results document the Plan 5 on-device harness compares against

- [ ] **Step 1: Budgets per build configuration**

At the top of `GlimmerStreamingPerformanceTests`, replace the budget constants with:

```swift
    // Spec §3 budgets are for Release on an iPhone 16 Pro Max; Debug gates are looser but still catch regressions
    // that grow with the answer.
    #if DEBUG
    private let budget: Duration = .milliseconds(8)
    private let layoutBudget: Duration = .milliseconds(4)
    private let configureBudget: Duration = .milliseconds(8)
    #else
    private let budget: Duration = .milliseconds(2)
    private let layoutBudget: Duration = .milliseconds(2)
    private let configureBudget: Duration = .milliseconds(4)
    #endif
```

`testFindingLateTextStaysCheap` keeps 0.2 ms in both.

- [ ] **Step 2: Run the performance tests in Release**

```bash
DEST='platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0'
xcodebuild -scheme Glimmer -configuration Release -destination "$DEST" test ENABLE_TESTABILITY=YES \
  -only-testing:GlimmerTests/GlimmerStreamingPerformanceTests 2>&1 | tee .build/perf-release.log | grep -E "PERF|error:|Executed"
```

Expected: every test passes. If one fails, the budget is not met in Release. Find the dominant cost with `ContinuousClock` splits (as in Plan 2's fix pass) and fix it test-first. The task is not done while a §3 gate fails, unless a ledger ruling explains why the budget can't be met on the simulator and what the on-device harness (Plan 5) must confirm.

- [ ] **Step 3: Record the results**

Create `docs/superpowers/perf/2026-09-26-glimmer-2-plan-3-results.md` with one table per build configuration (Debug and Release, iOS 27.0 simulator, iPhone 17 Pro Max). Rows are:

- update apply p95: mixed, revealing, and long-list answers
- layout pass p95
- late segment lookup median
- configure cached median

Columns are the §3 budget, the measured value, and pass/fail. Take the values from the `PERF` lines of the last Debug engine-suite run and of `.build/perf-release.log`. Add one line on what Plan 5's on-device harness must still show: hitches while streaming and scrolling on an iPhone 16 Pro Max.

- [ ] **Step 4: Run the engine suite and commit**

Run every engine test class in Debug. Expected: all pass.

```bash
git add Tests/GlimmerTests/Engine/GlimmerStreamingPerformanceTests.swift docs/superpowers/perf
git commit -m "Engine: gate the §3 budgets in Release and record Plan 3's numbers"
```

---

## Out of scope for this plan

- **Interaction and accessibility** (spec §6): copy serialization, `markdownSource(for:)`, the selection clamp, the link and edit menus, data detectors, VoiceOver, and embed accessibility. That is Plan 4, together with the compose and visual minors from the Plan 1 and Plan 2 reviews:
  - bullet versus number color
  - a `headingFont(level:)` guard
  - the table grid's implicit animations
  - `language()` splitting on tabs
  - the attribute-key and emoji test gaps
- **Release** (spec §10, §12 phase 7): deleting 1.x, rebuilding the demo (benchmark screen, `CADisableMinimumFrameDurationOnPhone`, pause, resume and light/dark in the lab), the on-device `XCTHitchMetric` harness, the README, and the `2.0.0` tag. That is Plan 5.
- `height(forWidth:)` still lays the text view out at a queried width while a reveal runs. The revealed line's bottom at another width can only come from layout at that width. It stays; Plan 4 revisits it only if a host shows a problem.
- The per-item list composition the Plan 2 review asked about: after Task 5, a long list re-composes on the worker, not on the main thread. Task 8's long-list gate is the check.

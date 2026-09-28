# Glimmer 2.0 — Plan 6: Performance on the Device Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the measured causes of dropped frames and slow configures on an iPhone 16 Pro Max, so streaming below a long answer while scrolling stays smooth and a cached answer's first frame is a third of today's cost.

**Architecture:** Four targeted changes, each aimed at a cost the device probe measured:
- The text view is sized once to a tall fixed height, so a streaming answer never resizes it.
- The band re-renders in quarter-screen steps. After a configure, the first frame renders only the screen and the rest of the band follows a frame later.
- A phrase start asks TextKit about the current line only, and the reveal store hashes an answer's prefix once per text version.
- A streaming code block finds its changed lines by comparing colour runs, not attributed strings.

The benchmark gains a flick-speed scroll, and everything is measured again on the device.

**Tech Stack:** Swift 6, iOS 18+, UIKit, TextKit 2, Core Animation, XCTest, XCUITest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-26-glimmer-2-perf-and-parity-design.md` (Part A), with the engine spec `docs/superpowers/specs/2026-09-25-glimmer-2-engine-design.md` (§3). The measurements this plan answers to are in `docs/superpowers/perf/2026-09-26-glimmer-2-plan-5-device-results.md` and the addendum's §1.

## Global Constraints

- The branch is `glimmer-2`, with `2.0.0` tagged at `3075244`. Commit after every task. **Do not add `Co-Authored-By` trailers. Do not push, and do not move or push the tag.**
- Swift 6 language mode, iOS 18 minimum, no package dependencies. TextKit 2 only: never read `layoutManager`.
- No force unwrapping (`!`) and no force casts in library code. Tests may force-unwrap.
- In tests, write `CGFloat.greatestFiniteMagnitude`, never `.greatestFiniteMagnitude`, in `CGSize(width: <literal>, …)`.
- Library test command, with a passing run ending in `** TEST SUCCEEDED **`. Kill xcodebuild once the log shows `Test Suite 'Selected tests' passed|failed`, and run one xcodebuild at a time.
  ```bash
  DEST='platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0'
  xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/<TestClass> 2>&1 | tail -5
  ```
  For Release, add `-configuration Release ENABLE_TESTABILITY=YES`.
- Demo: after adding or moving a demo file, run `xcodegen generate` in `Examples/GlimmerDemo`. Demo UI tests:
  ```bash
  xcodebuild -project Examples/GlimmerDemo/GlimmerDemo.xcodeproj -scheme GlimmerDemo \
    -destination 'id=69D2BAC9-1BB2-4A2A-A361-3150710B8462' -derivedDataPath .build/demo-dd test
  ```
- **Device:** "WW 16", an iPhone 16 Pro Max, UDID `00008140-00044C9001F3001C`, team `RUV7V2TGVX`. Every device step first checks `xcrun devicectl device info lockState --device 00008140-00044C9001F3001C` for `passcodeRequired: false`.
  - If the phone is locked, record "device: locked" in the ledger for that step and continue. Task 5 measures everything on the device once it is unlocked.
  - Never enter a passcode or any credential.
  - These are the device commands:
  ```bash
  DEV=00008140-00044C9001F3001C
  # The package's performance tests, hosted by the demo app, in Release:
  xcodebuild test -project Examples/GlimmerDemo/GlimmerDemo.xcodeproj -scheme GlimmerDevicePerf -configuration Release \
    -destination "id=$DEV" -derivedDataPath .build/device-dd -allowProvisioningUpdates ENABLE_TESTABILITY=YES
  # The benchmark alone, with nothing driving the app (build and install the Release app first):
  xcodebuild build -project Examples/GlimmerDemo/GlimmerDemo.xcodeproj -scheme GlimmerDemo -configuration Release \
    -destination "id=$DEV" -derivedDataPath .build/device-dd -allowProvisioningUpdates
  xcrun devicectl device install app --device $DEV .build/device-dd/Build/Products/Release-iphoneos/GlimmerDemo.app
  xcrun devicectl device process launch --device $DEV --console --terminate-existing dk.wu.GlimmerDemo \
    --benchmark --benchmark-autostart --benchmark-exit
  ```
  macOS has no `timeout`. Stop `devicectl` yourself once `BENCHMARK done` prints.

## Review Focus

These are the five inputs the spec implies but no test yet exercises, ordered from most likely to bite a real user down. Each has a test in the task that owns the code.

1. **A host that sizes the view by its intrinsic size**, as Auto Layout, a stack view or a self-sizing cell does. It must still get the content's height, never the tall text view's. Test: Task 1 `testIntrinsicSizeIsTheContentNotTheTextView`.
2. **VoiceOver focusing a settled answer** must frame the text, not a million-point view. Test: Task 1 `LaunchUITests.testTheAnswersAccessibilityFrameHugsItsText`.
3. **A width change mid-stream (rotation, split view)** must re-wrap the text, keep the text view tall, and report the new content height. Test: Task 1 `testAWidthChangeMidStreamReportsTheNewContentHeight`.
4. **Scrolling right after a configure, before the band widens,** must still render the text that scrolls in. Test: Task 2 `testScrollingBeforeTheBandWidensStillRendersTheScreen`.
5. **A streaming code block whose colours change on earlier lines** (a `*/` arriving) must end identical to a fresh highlight under the faster diff. Test: Task 4 `testStreamedCodeMatchesAFreshHighlightAtEveryStep`.

---

### Task 1: The text view never resizes while an answer streams

**Files:**
- Modify: `Sources/Glimmer/Engine/GlimmerView.swift` (`fitTextViewToContent`, `height(forWidth:)`; delete `slack(forContentHeight:)`)
- Modify: `Sources/Glimmer/Engine/Render/GlimmerTextView.swift` (`contentHeight`, `accessibilityFrame`)
- Test: `Tests/GlimmerTests/Engine/GlimmerViewTests.swift`, `Examples/GlimmerDemo/UITests/LaunchUITests.swift`

**Interfaces:**
- Produces:
  - `static var GlimmerView.textViewHeight: CGFloat` (internal; 1,000,000 by default, lowered by tests).
  - `var GlimmerTextView.contentHeight: CGFloat` (internal; set by `GlimmerView`, read by `accessibilityFrame`).

The spec addendum's A1: the text view gets a height it will not outgrow, and only a width change or text taller than
that height changes its frame. The view already reports the content's height and clips to its bounds.

- [ ] **Step 1: Write the failing tests**

Append to `GlimmerViewTests`:

```swift
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
        let stack = UIStackView(arrangedSubviews: [view])
        stack.axis = .vertical
        let window = hostInWindow(stack, width: 390, height: 800)
        view.update(markdown: "A short answer.\n\nWith two paragraphs.")
        stack.layoutIfNeeded()
        let content = view.textView.laidOutHeight()
        XCTAssertEqual(view.intrinsicContentSize.height, content, accuracy: 1)
        XCTAssertEqual(view.frame.height, content, accuracy: 1)
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

    private func physicalFootprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }
```

Append to `Examples/GlimmerDemo/UITests/LaunchUITests.swift` (inside the class):

```swift
    /// VoiceOver frames the text it focuses: the answer's text view must not report the tall frame it lays out in.
    @MainActor
    func testTheAnswersAccessibilityFrameHugsItsText() {
        let app = XCUIApplication()
        app.launchArguments = ["--engine-gallery"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Engine Gallery"].waitForExistence(timeout: 15))
        let answer = app.textViews.firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        XCTAssertLessThan(answer.frame.height, 20_000, "\(answer.frame)")
        XCTAssertGreaterThan(answer.frame.height, 500)
    }
```

- [ ] **Step 2: Run to verify**

Run the test command for `GlimmerViewTests`. Expected:
- `testStreamingNeverResizesTheTextView` FAILS (the slack band resizes the text view as the answer grows).
- `testTextTallerThanTheTextViewGrowsIt` and `testAWidthChangeMidStreamReportsTheNewContentHeight` fail to compile (`GlimmerView.textViewHeight` doesn't exist).
- `testIntrinsicSizeIsTheContentNotTheTextView` and `testATallTextViewCostsNoMemory` are expected to pass already. They guard the change.

Comment out the two tests that don't compile to see the first test's RED, then restore them.

Run the demo test command for `LaunchUITests`. Expected: the accessibility-frame test passes today. The text view is only content plus slack tall, and the test guards Step 3.

- [ ] **Step 3: One tall height, set once per width**

In `GlimmerView`, add:

```swift
    /// The text view's height. Tall enough that an answer never outgrows it, so streaming never resizes the text view:
    /// on an iPhone 16 Pro Max a resize cost up to 9 ms plus the commit after it, the main cause of dropped frames.
    /// The view reports and clips to the content's height; the text container is unbounded and TextKit renders only
    /// the band near the screen, so the extra height costs nothing. Text taller than this doubles it.
    static var textViewHeight: CGFloat = 1_000_000

    /// Sizes the text view for `width`, as tall as `textViewHeight` or twice the content if that is taller.
    private func sizeTextView(width: CGFloat, contentHeight: CGFloat) {
        var height = max(Self.textViewHeight, textView.bounds.height)
        while height < contentHeight { height *= 2 }
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        if textView.frame != frame { textView.frame = frame }
    }
```

Rewrite `fitTextViewToContent()`:

```swift
    /// Keeps the text view tall enough for the document and records the document's height. The frame changes only
    /// for a new width, or for text taller than the text view (see `textViewHeight`).
    private func fitTextViewToContent() {
        guard bounds.width > 0 else { return }
        // The text view may already have this width (a size query during a reveal resized it) while the height on
        // record is for another width: that is a width change too.
        let widthChanged = textView.bounds.width != bounds.width || contentHeight?.width != bounds.width
        guard widthChanged || contentHeight?.version != textView.textVersion else { return }
        // A settled answer shown before, whole (a new width, or a replaced text): its height is known.
        if widthChanged || layoutChangedFrom == 0,
           let cached = cacheKey.flatMap({ GlimmerDocumentCache.shared.height(for: $0, width: bounds.width) }) {
            sizeTextView(width: bounds.width, contentHeight: cached)
            layoutChangedFrom = 0
            contentHeight = (textView.textVersion, bounds.width, cached)
            textView.contentHeight = cached
            return
        }
        if widthChanged {
            // A new width re-wraps everything: measure it in full once.
            let fullHeight = textView.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height
            sizeTextView(width: bounds.width, contentHeight: fullHeight)
            layoutChangedFrom = 0
        }
        let height = textView.laidOutHeight(from: layoutChangedFrom)
        layoutChangedFrom = Int.max
        sizeTextView(width: textView.bounds.width, contentHeight: height)
        contentHeight = (textView.textVersion, textView.bounds.width, height)
        textView.contentHeight = height
        if let cacheKey, engine == nil { GlimmerDocumentCache.shared.storeHeight(height, for: cacheKey, width: textView.bounds.width) }
    }
```

In `height(forWidth:)`, in the revealing branch, replace the resize:

```swift
            if textView.bounds.width != width {
                let fullHeight = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
                sizeTextView(width: width, contentHeight: fullHeight)
            }
```

Delete `slack(forContentHeight:)`, and update the doc comment above `fitTextViewToContent` to the one above.

In `GlimmerTextView`, add:

```swift
    /// The laid-out text's height, set by `GlimmerView`; the frame is much taller (see `GlimmerView.textViewHeight`).
    var contentHeight: CGFloat = 0

    /// VoiceOver frames the text, not the tall frame it is laid out in.
    override var accessibilityFrame: CGRect {
        get {
            let height = contentHeight > 0 ? min(contentHeight, bounds.height) : bounds.height
            return UIAccessibility.convertToScreenCoordinates(CGRect(x: 0, y: 0, width: bounds.width, height: height), in: self)
        }
        set {}
    }
```

- [ ] **Step 4: Run to verify they pass**

Run the test command for `GlimmerViewTests`, `GlimmerViewStreamingTests`, `GlimmerVisibleBandTests`, `GlimmerRevealMaskTests` (or whichever classes cover the mask; `grep -l RevealMask Tests/GlimmerTests/Engine/*Tests.swift`), `GlimmerInteractionTests` and `GlimmerAccessibilityTests`. Expected: PASS.

Run the demo test command for `LaunchUITests`. Expected: PASS, including `testTheAnswersAccessibilityFrameHugsItsText`.

If any check shows the tall text view is not harmless, switch `sizeTextView` to geometric growth and ledger a ruling. Harm here means an Auto Layout host getting the wrong size, a VoiceOver frame the override can't fix, or memory. Geometric growth starts the height at twice the content and doubles it when the content outgrows it.

The spec also asks that nothing lays out beyond the text on iOS 18–26, where the band doesn't exist. Check
`xcrun simctl list runtimes`. If no iOS 18–26 runtime is installed (the Sept 2026 notes say none is), ledger a ruling:
unverified, because only iOS 27 runtimes exist here, and on those versions TextKit's viewport is the text view's
visible bounds, which only the text occupies. Cost if wrong: extra layout on older systems.

- [ ] **Step 5: On the simulator, then on the device**

Build the demo, and screenshot the gallery and the streaming lab mid-stream. Nothing may look different from before.

If the phone is unlocked, run the benchmark alone on the device and ledger its `BENCHMARK` line. Expected: fewer hitches than Plan 5's 4–9.

- [ ] **Step 6: Engine suite and commit**

```bash
git add Sources/Glimmer/Engine Tests/GlimmerTests/Engine Examples
git commit -m "Engine: size the text view once, so streaming never resizes it

Resizing the text view as an answer outgrew its slack cost up to 9 ms on an
iPhone 16 Pro Max, plus the commit after it: most of the dropped frames.
The text view is now a fixed 1,000,000 pt tall (doubled for text taller
than that); the view still reports and clips to the content's height, and
VoiceOver frames the text."
```

---

### Task 2: Render in smaller steps

**Files:**
- Modify: `Sources/Glimmer/Engine/Render/GlimmerTextView.swift` (visible band)
- Modify: `Sources/Glimmer/Engine/GlimmerView.swift` (`composeSynchronously`)
- Test: `Tests/GlimmerTests/Engine/GlimmerVisibleBandTests.swift`

**Interfaces:**
- Produces:
  - `static let GlimmerTextView.bandRefreshStep: CGFloat = 0.25` (screens).
  - `private(set) var GlimmerTextView.rendersScreenOnly: Bool`.
  - `func GlimmerTextView.renderScreenFirst()`.

The spec addendum's A2: the band re-renders after a quarter screen of travel, and a configure's first frame renders
only the screen.

- [ ] **Step 1: Write the failing tests**

Append to `GlimmerVisibleBandTests`:

```swift
    func testTheBandRefreshesAfterAQuarterScreen() throws {
        let (view, scrollView, window) = scrolled()
        let before = try XCTUnwrap(view.textView.renderedBand)
        scrollView.contentOffset = CGPoint(x: 0, y: 800 * 0.3)
        view.textView.refreshVisibleBandIfNeeded()
        let after = try XCTUnwrap(view.textView.renderedBand)
        XCTAssertNotEqual(after, before, "0.3 screens of travel re-renders")
        _ = window
    }

    func testAConfigureRendersTheScreenFirstAndTheBandNextFrame() throws {
        let scrollView = UIScrollView()
        let window = hostInWindow(scrollView, width: 390, height: 800)
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 100_000)
        scrollView.addSubview(view)
        scrollView.contentSize = view.frame.size
        view.update(markdown: long)
        view.layoutIfNeeded()
        view.textView.layoutIfNeeded()
        let first = try XCTUnwrap(view.textView.renderedBand)
        XCTAssertLessThanOrEqual(first.height, 801, "the first frame renders the screen")
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let full = try XCTUnwrap(view.textView.renderedBand)
        XCTAssertGreaterThan(full.height, 1_500, "the band follows")
        _ = window
    }

    func testScrollingBeforeTheBandWidensStillRendersTheScreen() throws {
        let scrollView = UIScrollView()
        let window = hostInWindow(scrollView, width: 390, height: 800)
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 100_000)
        scrollView.addSubview(view)
        scrollView.contentSize = view.frame.size
        view.update(markdown: long)
        view.layoutIfNeeded()
        view.textView.layoutIfNeeded()
        // The reader flings before the band has widened.
        scrollView.contentOffset = CGPoint(x: 0, y: 600)
        view.textView.refreshVisibleBandIfNeeded()
        let band = try XCTUnwrap(view.textView.renderedBand)
        XCTAssertTrue(band.contains(CGRect(x: 0, y: 600, width: 390, height: 800).intersection(view.textView.bounds)))
        _ = window
    }
```

- [ ] **Step 2: Run to verify they fail**

Run the test command for `GlimmerVisibleBandTests`. Expected:
- `testTheBandRefreshesAfterAQuarterScreen` FAILS (the threshold is half a screen).
- `testAConfigureRendersTheScreenFirstAndTheBandNextFrame` FAILS (the first band is three screens).
- `testScrollingBeforeTheBandWidensStillRendersTheScreen` passes today (the band is already three screens). It guards the screen-first mode.

- [ ] **Step 3: Smaller steps and a screen-first configure**

In `GlimmerTextView`, replace the band's properties and methods from `bandOverscan` to `refreshVisibleBandIfNeeded` with:

```swift
    /// How far past the screen, in screen heights, TextKit still renders. Enough that a fling lands on rendered text
    /// before the next band update.
    static let bandOverscan: CGFloat = 1
    /// How far, in screen heights, the screen may travel from where the band was centred before it re-renders.
    /// Smaller steps bring in less new text each time: on an iPhone 16 Pro Max a half-screen step cost up to 6.7 ms.
    static let bandRefreshStep: CGFloat = 0.25

    /// The rect TextKit rendered last, in this view's coordinates, or nil while it renders its own viewport.
    private(set) var renderedBand: CGRect?
    /// After a configure, TextKit renders only the screen until the first frame is on screen, then the whole band:
    /// the first frame's layout and drawing are a third of a full band's.
    private(set) var rendersScreenOnly = false
    private var bandWidening: CADisplayLink?

    /// Renders only the screen until the next frame has been presented, then the whole band.
    func renderScreenFirst() {
        rendersScreenOnly = true
        guard bandWidening == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(widenBand))
        link.add(to: .main, forMode: .common)
        bandWidening = link
    }

    @objc private func widenBand() {
        bandWidening?.invalidate()
        bandWidening = nil
        guard rendersScreenOnly else { return }
        rendersScreenOnly = false
        textLayoutManager?.textViewportLayoutController.layoutViewport()
    }

    private var overscan: CGFloat { rendersScreenOnly ? 0 : Self.bandOverscan }

    /// This view's part within `overscan` screens of its window's bounds, full width. It is zero-height off screen
    /// or outside a window (a cell sized before it is shown renders nothing), and nil before the view has a width.
    func visibleBand() -> CGRect? {
        guard bounds.width > 0 else { return nil }
        guard let window else { return CGRect(x: 0, y: 0, width: bounds.width, height: 0) }
        let screen = convert(window.bounds, from: window)
        let band = screen.insetBy(dx: 0, dy: -window.bounds.height * overscan).intersection(bounds)
        guard !band.isNull else { return CGRect(x: 0, y: 0, width: bounds.width, height: 0) }
        return CGRect(x: 0, y: band.minY, width: bounds.width, height: band.height)
    }

    /// Re-renders once the screen has travelled `bandRefreshStep` screens from where the band was centred, or, while
    /// only the screen is rendered, as soon as any of the screen is not.
    func refreshVisibleBandIfNeeded() {
        guard let window, let rendered = renderedBand else { return }
        let screen = convert(window.bounds, from: window).intersection(bounds)
        guard !screen.isNull else { return }
        let margin = max(0, overscan - Self.bandRefreshStep)
        let needed = screen.insetBy(dx: 0, dy: -window.bounds.height * margin).intersection(bounds)
        if !rendered.contains(needed) { textLayoutManager?.textViewportLayoutController.layoutViewport() }
    }
```

`CADisplayLink`'s target is retained by the link and invalidated after one tick, so it doesn't leak. Add
`isolated deinit { bandWidening?.invalidate() }` if the class has no deinit yet. Otherwise invalidate it in the
existing one.

In `GlimmerView.composeSynchronously()`, call `textView.renderScreenFirst()` immediately before each of the two places
it sets `textView.attributedText`: the cached branch and the composed branch.

- [ ] **Step 4: Run to verify they pass**

Run the test command for `GlimmerVisibleBandTests`, `GlimmerViewTests` and `GlimmerStreamingPerformanceTests`. Expected: PASS. The configure perf test's cached median should fall; ledger the new number.

- [ ] **Step 5: On the device**

If the phone is unlocked, run `GlimmerDevicePerf`. Ledger the cached-configure `PERF` line. Expected: under the Plan 5 baseline of 26–27 ms. Also run the benchmark alone and ledger its `BENCHMARK` line.

- [ ] **Step 6: Engine suite and commit**

```bash
git add Sources/Glimmer/Engine Tests/GlimmerTests/Engine
git commit -m "Engine: render the band in quarter-screen steps, the screen first after a configure

Each band refresh now brings in a quarter screen of new text, not half. A
configure's first frame lays out and draws only the screen, and the rest of
the band follows once that frame is on screen."
```

---

### Task 3: Cheaper phrase starts

**Files:**
- Modify: `Sources/Glimmer/Engine/Render/GlimmerTextView.swift` (`settledLine(upTo:)`)
- Modify: `Sources/Glimmer/Engine/Reveal/GlimmerRevealMask.swift` (settled computation)
- Modify: `Sources/Glimmer/Engine/Reveal/GlimmerRevealStore.swift` (hash once per text version)
- Modify: `Sources/Glimmer/Engine/GlimmerView.swift` (pass the text version to the store)
- Test: `Tests/GlimmerTests/Engine/GlimmerTextViewTests.swift`, `Tests/GlimmerTests/Engine/GlimmerStreamingPerformanceTests.swift`, the reveal store's tests

**Interfaces:**
- Produces:
  - `func GlimmerTextView.settledLine(upTo index: Int) -> (top: CGFloat, rects: [CGRect])?`
  - `func GlimmerRevealStore.record(_ length: Int, text: NSString, version: Int, for id: String)`

The spec addendum's A3. On the device a phrase start cost about 1.1 ms. Most of that was a line lookup plus a
512-character segment query for the settled line, and re-hashing up to 1,024 characters twice for resume.

- [ ] **Step 1: Write the failing tests**

Append to `GlimmerTextViewTests`:

```swift
    func testSettledLineMatchesTheWideQuery() {
        let textView = GlimmerTextView()
        let window = hostInWindow(textView, width: 390, height: 4_000)
        textView.attributedText = GlimmerComposer(theme: .default).compose(GlimmerParser.parse(
            StreamingFixtures.all.map(\.markdown).joined(separator: "\n\n")
        ))
        textView.layoutIfNeeded()
        let string = textView.textStorage.string as NSString
        var checked = 0
        for index in stride(from: 1, to: textView.textStorage.length - 1, by: 7) where string.character(at: index - 1) != 0x0A {
            guard let line = textView.settledLine(upTo: index), let lineTop = textView.lineRect(atCharacter: index)?.minY else { continue }
            let wide = textView.segmentRects(for: NSRange(location: max(0, index - 512), length: min(index, 512)))
                .filter { $0.minY >= lineTop - 0.5 }
            XCTAssertEqual(line.top, lineTop, accuracy: 0.5, "top at \(index)")
            XCTAssertEqual(line.rects.count, wide.count, "rects at \(index)")
            for (a, b) in zip(line.rects, wide) {
                XCTAssertEqual(a.minX, b.minX, accuracy: 0.5)
                XCTAssertEqual(a.maxX, b.maxX, accuracy: 0.5)
                XCTAssertEqual(a.minY, b.minY, accuracy: 0.5)
            }
            checked += 1
        }
        XCTAssertGreaterThan(checked, 100)
        _ = window
    }
```

Append to the reveal store's test class (`grep -l GlimmerRevealStore Tests/GlimmerTests/Engine/*Tests.swift`):

```swift
    func testRecordingTheSameTextVersionAgainKeepsTheLongestLength() {
        let store = GlimmerRevealStore()
        let text = NSString(string: String(repeating: "word ", count: 400))
        store.record(100, text: text, version: 7, for: "m")
        store.record(300, text: text, version: 7, for: "m")
        store.record(200, text: text, version: 7, for: "m")
        XCTAssertEqual(store.revealedLength(for: "m", text: text), 300)
        let other = NSString(string: "different " + (text as String))
        store.record(50, text: other, version: 8, for: "m")
        XCTAssertEqual(store.revealedLength(for: "m", text: other), 50, "a new text starts over")
    }
```

(If `GlimmerRevealStore` has no public-in-module `init()`, use the initializer its existing tests use.)

Append to `GlimmerStreamingPerformanceTests`:

```swift
    /// Spec addendum A3: a phrase start costs ≤ 0.5 ms on an iPhone 16 Pro Max. Each clock step here starts or
    /// settles phrases, as a wake does.
    func testPhraseStartsStayCheap() async {
        #if DEBUG
        let gate: Duration = .microseconds(900)
        #else
        let gate: Duration = .microseconds(350)
        #endif
        let prose = Array(repeating: StreamingFixtures.all[0].markdown, count: 6).joined(separator: "\n\n")
        let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil))
        let clock = ManualRevealClock()
        view.clock = clock
        let window = hostInWindow(view, width: 390, height: 800)
        view.update(markdown: String(prose.prefix(2_000)), isStreaming: true, revealID: "phrase-starts")
        await view.pendingDocument?.value
        settle(view)
        var samples: [Duration] = []
        var time = 0.0
        while view.engine != nil, time < 30 {
            guard let due = clock.scheduled else { break }
            time = due
            let start = threadCPUTime()
            clock.advance(to: time)
            samples.append(threadCPUTime() - start)
        }
        let median = samples.sorted()[samples.count / 2]
        print("PERF phrase start median \(median) over \(samples.count) wakes")
        XCTAssertGreaterThan(samples.count, 20)
        XCTAssertLessThan(median, gate)
        _ = window
    }
```

- [ ] **Step 2: Run to verify they fail**

Run the test command for `GlimmerTextViewTests`, the store's test class and `GlimmerStreamingPerformanceTests/testPhraseStartsStayCheap`. Expected:
- Compile errors for `settledLine(upTo:)` and `record(_:text:version:for:)`.
- With those stubbed out (comment out), the perf test FAILS or sits at its gate. Ledger its median; Plan 6's addendum puts it at about 0.7 ms on the simulator in Release.

Restore the tests.

- [ ] **Step 3: The settled line from one line's query**

In `GlimmerTextView`, add under `lineRect(atCharacter:)`:

```swift
    /// The visual line holding `index`: its top, and the rects of its text before `index`, bidi-correct. One fragment
    /// lookup and a segment query over that line alone, instead of `lineRect` plus a 512-character window.
    func settledLine(upTo index: Int) -> (top: CGFloat, rects: [CGRect])? {
        guard index >= 0, index < textStorage.length, let manager = textLayoutManager, let content = manager.textContentManager,
              let location = content.location(content.documentRange.location, offsetBy: index),
              let characterRange = textRange(for: NSRange(location: index, length: 1)) else { return nil }
        manager.ensureLayout(for: characterRange)
        guard let fragment = manager.textLayoutFragment(for: location) else { return nil }
        let paragraphStart = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        let offset = index - paragraphStart
        guard let line = fragment.textLineFragments.first(where: { NSLocationInRange(offset, $0.characterRange) }) else { return nil }
        let top = fragment.layoutFragmentFrame.minY + line.typographicBounds.minY + textContainerInset.top
        let lineStart = paragraphStart + line.characterRange.location
        return (top, index > lineStart ? segmentRects(for: NSRange(location: lineStart, length: index - lineStart)) : [])
    }
```

The test compares `top` against `lineRect(atCharacter:)`, the segment frame the mask used before. If the two differ by
the text container inset (because the segment frames already include it), drop `+ textContainerInset.top`. The test
decides which is right.

In `GlimmerRevealMask.update`, replace the settled block's first lines:

```swift
            let lineTop = textView.lineRect(atCharacter: firstUnsettled)?.minY ?? bounds.height
            settledLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: lineTop)
            let lineStart = max(0, firstUnsettled - 512)
            let settledOnLine = textView.segmentRects(for: NSRange(location: lineStart, length: firstUnsettled - lineStart))
                .filter { $0.minY >= lineTop - 0.5 }
```

with:

```swift
            let line = textView.settledLine(upTo: firstUnsettled)
            let lineTop = line?.top ?? bounds.height
            settledLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: lineTop)
            let settledOnLine = line?.rects ?? []
```

- [ ] **Step 4: The store hashes once per text version**

In `GlimmerRevealStore`, change the entries to `[String: (length: Int, prefixHash: Int, version: Int)]` and add the
versioned record. Keep the old `record(_:text:for:)` as a wrapper that passes `version: -1` (always hash) for callers
without a version.

```swift
    /// Records how far `id` revealed. `version` identifies `text`: while it is unchanged, and the prefix the hash
    /// covers is already hashed, nothing is hashed again. On a device each hash cost about 0.2 ms, on every wake.
    func record(_ length: Int, text: NSString, version: Int, for id: String) {
        if let entry = entries[id], entry.version == version, version >= 0 {
            let stored = max(entry.length, length)
            // The hash covers the first min(length, 1,024) characters: re-hash only while that prefix still grows.
            let hash = min(stored, 1_024) > min(entry.length, 1_024) ? Self.prefixHash(of: text, length: stored) : entry.prefixHash
            entries[id] = (stored, hash, version)
        } else {
            var stored = length
            if let entry = entries[id], entry.prefixHash == Self.prefixHash(of: text, length: entry.length) {
                stored = max(entry.length, length)
            }
            entries[id] = (stored, Self.prefixHash(of: text, length: stored), version)
        }
        recent.removeAll { $0 == id }
        recent.append(id)
        if recent.count > capacity { entries[recent.removeFirst()] = nil }
    }
```

Update `revealedLength(for:text:)` for the tuple's new field (it reads `length` and `prefixHash` as before).

In `GlimmerView.advanceReveal()`, pass the text view's version:

```swift
            GlimmerRevealStore.shared.record(current.revealedLength, text: textView.textStorage.string as NSString,
                                             version: textView.textVersion, for: revealID)
```

`textView.textVersion` changes on every edit and restyle (it keys the measurement caches). A new version therefore
re-hashes, and an unchanged one skips.

- [ ] **Step 5: Run to verify they pass**

Run the test command for `GlimmerTextViewTests`, the store's test class, every class that tests the reveal or the
mask (`grep -lE "RevealMask|RevealEngine|ViewStreaming|RevealStore" Tests/GlimmerTests/Engine/*Tests.swift`), and
`GlimmerStreamingPerformanceTests`. Expected: PASS.

Then run `GlimmerStreamingPerformanceTests/testPhraseStartsStayCheap` in Release. Expected: PASS at 0.35 ms. Ledger
the medians. If Release misses 0.35 ms but lands under 0.5 ms, rule on it with the numbers and set the Release gate
to the measured median rounded up to 0.05 ms. The device decides against the spec's 0.5 ms.

- [ ] **Step 6: On the device, engine suite, commit**

If the phone is unlocked, run `GlimmerDevicePerf` and ledger the phrase-start median. Expected: ≤ 0.5 ms.

Run the engine suite, then commit:

```bash
git add Sources/Glimmer/Engine Tests/GlimmerTests/Engine
git commit -m "Engine: a phrase start asks about one line, and hashes only new text

The settled line comes from one fragment lookup and a segment query over
that line, instead of a line lookup and a 512-character window; the reveal
store re-hashes an answer's prefix only when its text version changes."
```

---

### Task 4: A streaming code block's apply under 2 ms

**Files:**
- Modify: `Sources/Glimmer/Engine/Embeds/GlimmerCodeBlockView.swift` (`update(to:)`)
- Modify: `Tests/GlimmerTests/Engine/GlimmerStreamingPerformanceTests.swift` (the simulator's Release gate)
- Test: `Tests/GlimmerTests/Engine/GlimmerCodeBlockViewTests.swift`

**Interfaces:**
- Produces: `static func GlimmerCodeBlockView.colorRuns(of: NSAttributedString) -> [ColorRun]`, where `struct ColorRun: Equatable { let range: NSRange; let color: UIColor? }`.

The spec addendum's A4. Colour is the only attribute that varies inside highlighted code: font and paragraph style are
set once over the whole text. So the first changed line is where the text first differs, or the first colour run
differs, whichever comes first. Comparing runs is much cheaper than comparing attributed strings.

- [ ] **Step 1: Write the failing tests**

Append to `GlimmerCodeBlockViewTests`:

```swift
    func testStreamedCodeMatchesAFreshHighlightAtEveryStep() {
        let theme = GlimmerTheme.default
        let highlighter = GlimmerBasicHighlighter()
        let code = """
        /* A header comment
           that spans lines */
        let greeting = "Hello, world" // trailing
        func count(to limit: Int) -> Int {
            var total = 0 /* inline */ + 42
            return total
        }
        """
        let view = GlimmerCodeBlockView(code: "", language: "swift", theme: theme, highlighter: highlighter)
        var end = code.startIndex
        while end < code.endIndex {
            end = code.index(end, offsetBy: 3, limitedBy: code.endIndex) ?? code.endIndex
            let prefix = String(code[..<end])
            let fresh = GlimmerCodeHighlighting.highlightedCode(prefix, language: "swift", theme: theme, highlighter: highlighter)
            view.update(to: .codeBlock(language: "swift", code: prefix, highlighted: fresh))
            XCTAssertTrue(view.textView.textStorage.isEqual(to: fresh), "after \(prefix.count) characters")
        }
    }

    func testColorRunsDescribeTheHighlight() {
        let theme = GlimmerTheme.default
        let text = GlimmerCodeHighlighting.highlightedCode("let x = 1 // c", language: "swift", theme: theme, highlighter: GlimmerBasicHighlighter())
        let runs = GlimmerCodeBlockView.colorRuns(of: text)
        XCTAssertEqual(runs.first?.range.location, 0)
        XCTAssertEqual(runs.map(\.range.length).reduce(0, +), text.length)
        XCTAssertTrue(runs.contains { $0.color == theme.syntaxCommentColor })
    }
```

In `GlimmerStreamingPerformanceTests`, lower the simulator's Release `embedStreamingBudget` to 1.5 ms (the device's
stays 3 ms until Task 5), so the gate turns red on today's 1.94 ms:

```swift
    #if targetEnvironment(simulator)
    private let embedStreamingBudget: Duration = .microseconds(1_500)
```

- [ ] **Step 2: Run to verify they fail**

Run the test command for `GlimmerCodeBlockViewTests`. Expected:
- A compile error for `colorRuns(of:)`.
- With that test commented out, `testStreamedCodeMatchesAFreshHighlightAtEveryStep` passes today. It guards the new diff.

Run `GlimmerStreamingPerformanceTests/testStreamingALongCodeBlockStaysWithinBudget` in Release. Expected: FAIL (about 1.94 ms p95 against 1.5 ms).

- [ ] **Step 3: Diff by text and colour runs**

In `GlimmerCodeBlockView`, add:

```swift
    /// A span of one colour in highlighted code.
    struct ColorRun: Equatable {
        let range: NSRange
        let color: UIColor?
    }

    /// The highlighted code's colour runs from the last update.
    private var runs: [ColorRun] = []

    static func colorRuns(of text: NSAttributedString) -> [ColorRun] {
        var runs: [ColorRun] = []
        text.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            runs.append(ColorRun(range: range, color: value as? UIColor))
        }
        return runs
    }
```

At the end of `init`, set `runs = Self.colorRuns(of: highlighted)`. Replace `update(to:)`'s body after the
`self.highlighted = …` assignment:

```swift
        let newRuns = Self.colorRuns(of: self.highlighted)
        // The first change: where the text first differs, or where a colour run first differs (a closing `*/`
        // recolours earlier lines). Font and paragraph style never vary inside code.
        let textChange = (old.string as NSString).commonPrefix(with: code, options: .literal).utf16.count
        let firstRunChange = zip(runs, newRuns).firstIndex { $0 != $1 }.map { min(runs[$0].range.location, newRuns[$0].range.location) }
            ?? min(runs.last.map(NSMaxRange) ?? 0, newRuns.last.map(NSMaxRange) ?? 0)
        let change = min(textChange, firstRunChange)
        // Replace from the start of the line holding the change to the end.
        let newString = code as NSString
        let lineStart = change == 0 ? 0 : {
            let newline = newString.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: min(change, newString.length)))
            return newline.location == NSNotFound ? 0 : NSMaxRange(newline)
        }()
        runs = newRuns
        let edit = GlimmerDocumentEdit(
            range: NSRange(location: lineStart, length: old.length - lineStart),
            replacement: self.highlighted.attributedSubstring(from: NSRange(location: lineStart, length: self.highlighted.length - lineStart))
        )
        textView.apply(edit)
        metricsStorage.performEditingTransaction {
            metricsStorage.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        let unchangedLines = old.string.utf16.prefix(lineStart).reduce(0) { $0 + ($1 == 0x0A ? 1 : 0) }
        measureLines(fromLine: unchangedLines, at: lineStart)
        setNeedsLayout()
```

(`zip(...).firstIndex` doesn't exist on `Zip2Sequence`. Write it as
`(0..<min(runs.count, newRuns.count)).first { runs[$0] != newRuns[$0] }.map { … }`.)

The runs' `UIColor` values compare with `==` (`isEqual`), which is correct for the theme's dynamic colours. It costs
one comparison per run: a few hundred for a 150-line block.

- [ ] **Step 4: Run to verify they pass**

Run the test command for `GlimmerCodeBlockViewTests`, `GlimmerCodeHighlightingTests` and `GlimmerEmbedStreamingTests`. Expected: PASS.

Run `GlimmerStreamingPerformanceTests` in Release. Expected: PASS, with the long code block's apply ≤ 1.5 ms p95. If
it lands between 1.5 and 2 ms, measure the split before ruling:
- the code view's `update(to:)`;
- the outer `textView.apply`;
- `fitTextViewToContent`.

Time each with `ContinuousClock` in a throwaway test, ledger the numbers, and set the simulator gate to the measured
p95 rounded up to 0.25 ms.

- [ ] **Step 5: On the device, engine suite, commit**

If the phone is unlocked, run `GlimmerDevicePerf` and ledger the long code block's apply. Expected: ≤ 2 ms p95.

Run the engine suite, then commit:

```bash
git add Sources/Glimmer/Engine Tests/GlimmerTests/Engine
git commit -m "Engine: a streaming code block finds its changed lines by colour runs

Colour is the only attribute that varies in highlighted code, so the first
changed line is where the text or a colour run first differs; comparing
runs replaces comparing attributed strings, and the long code block's apply
drops under 2 ms."
```

---

### Task 5: A flick in the benchmark, the device run, and the results

**Files:**
- Modify: `Examples/GlimmerDemo/App/BenchmarkDemo.swift`
- Modify: `Tests/GlimmerTests/Engine/GlimmerStreamingPerformanceTests.swift`, `Examples/GlimmerDemo/UITests/BenchmarkHitchUITests.swift` (device gates)
- Modify: `docs/superpowers/perf/2026-09-26-glimmer-2-plan-5-device-results.md` → add a Plan 6 section; `README.md` (performance table)

**Interfaces:**
- Consumes: everything above.

The spec addendum's verification:
- The benchmark adds a flick-speed scroll beside its eased scroll, because the Plan 5 reviewer found the eased scroll
  gentler than a reader.
- The device measures every item.
- Device gates move to the new baselines, with the spec's goals as targets.

- [ ] **Step 1: The flick**

In `BenchmarkDemo`, track the scroll view's offset and range:

```swift
    @State private var offsetY: CGFloat = 0
    @State private var maxOffsetY: CGFloat = 0
```

On the `ScrollView`, after `.scrollPosition($position)`:

```swift
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, new in offsetY = new }
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentSize.height - $0.containerSize.height }) { _, new in maxOffsetY = new }
```

Replace the reader's scroll task in `start()` with a flick up and back, then the eased round trip:

```swift
        Task { @MainActor in
            // A reader flicks back through the earlier answer (about 3,000 pt, fast then decelerating), returns, then
            // scrolls through the whole earlier answer and back while this one streams.
            try? await Task.sleep(for: .seconds(6))
            isFollowing = false
            withAnimation(.easeOut(duration: 1.2)) { position.scrollTo(y: max(0, offsetY - 3_000)) }
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 1.2)) { position.scrollTo(y: maxOffsetY) }
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeInOut(duration: 2)) { position.scrollTo(edge: .top) }
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.easeInOut(duration: 2)) { position.scrollTo(edge: .bottom) }
            try? await Task.sleep(for: .seconds(2))
            isFollowing = true
        }
```

An ease-out over 1.2 s across 3,000 pt starts at about 5,000 pt/s and decelerates, which is a flick's profile. Update
the struct's doc comment to mention the flick. Build the demo and run the demo test command for
`BenchmarkHitchUITests`. Expected: PASS on the simulator, printing `BENCHMARK done …`.

- [ ] **Step 2: The device run**

With the phone unlocked:
- Run `GlimmerDevicePerf`, and ledger every `PERF` line.
- Run the benchmark alone three times with `devicectl`, and ledger each `BENCHMARK` line.
- Run `BenchmarkHitchUITests` on the device, and ledger the `BENCHMARK` line and the XCTHitchMetric values:
  `xcrun xcresulttool get test-results metrics --path <xcresult>`.

If the phone is locked:
- Push a notification to Willi with PushNotification, one line: "Unlock WW 16 for Glimmer's Plan 6 device run".
- Start a background watcher that runs the three steps above when `lockState` shows `passcodeRequired: false`. Poll
  every 30 s for up to 3 hours, following Plan 5's watcher.
- Continue with Step 3 using the numbers already ledgered. Finish the doc when the watcher reports.

- [ ] **Step 3: Device gates at the new baselines**

Set the device gates in `GlimmerStreamingPerformanceTests` (the `#else` branches of `targetEnvironment(simulator)`) to
this run's device numbers with about 30% headroom:
- cached configure;
- reveal per frame;
- streaming embed apply (the spec's 2 ms if the device met it);
- the phrase-start gate (add a device branch: the spec's 0.5 ms if met).

In `BenchmarkHitchUITests`, lower the ratio gate from 5 to the spec addendum's 1 ms/s. If the device's three
hands-off runs don't all meet 1 ms/s, set it to their worst ratio plus 0.5, and ledger a ruling with the numbers.

Run the demo test command and the engine suite on the simulator. Expected: PASS (the simulator gates are unchanged).

Where the phone is unlocked, run `GlimmerDevicePerf` and `BenchmarkHitchUITests` on the device again. Expected: PASS.

- [ ] **Step 4: The results**

Add a "Plan 6" section at the top of `docs/superpowers/perf/2026-09-26-glimmer-2-plan-5-device-results.md`, and
rename the file to `2026-09-26-glimmer-2-device-results.md` with `git mv`, updating the README's link to it. The
section has a before/after table of the device numbers:
- hitches and hitch-time ratio;
- cached configure;
- reveal per frame;
- phrase start;
- apply for the mixed, list, code and table cases.

Mark each against the spec and the addendum's goals, with a short paragraph per change saying what it moved. Update
the README's performance table to the new device numbers.

- [ ] **Step 5: Commit**

```bash
git add -A Examples Tests/GlimmerTests/Engine docs README.md
git commit -m "Demo: a flick in the benchmark; Plan 6 device results

The benchmark flicks back through the earlier answer before its eased round
trip. The device gates move to the new iPhone 16 Pro Max baselines, and the
results doc records what each Plan 6 change moved."
```

## Out of scope

- A reuse cache of laid-out text views: the spec's 4 ms configure. It's a separate decision, per the addendum's non-goals.
- Part B (1.x parity): Plan 7.
- The attribution probe. It stays throwaway in the `probe/perf-spike` worktree. If Task 5's device run still shows
  hitches, re-apply it to name them (see the addendum's §1 method) before any further change.

# Glimmer 2.0 Plan 6b: redraws, passes and embeds

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut the flick benchmark's hitch-time ratio on an iPhone 16 Pro Max from about 7 ms/s toward the addendum's 1 ms/s. The approach: stop UIKit redrawing unchanged text, run one viewport pass per change instead of two, lay out text before it scrolls in, and build code blocks off the critical path.

**Architecture:**
- **Surface reuse.** `GlimmerTextView` answers iOS 27's rendering-surface cache hooks with the fragment view UIKit already drew, keyed by `NSTextLayoutFragment` as WWDC26 session 370 recommends. UIKit then skips its redraw.
- **One pass per band move.** A band move marks UIKit's canvas for layout, so exactly one viewport pass runs in the commit. The canvas is found as the superview of the surfaces UIKit hands us.
- **Preload.** A budgeted idle-frame preload lays out paragraphs ahead of the band in the scroll direction, as Texture's preload range does.
- **Code blocks.** Their first-appearance cost is measured, then moved off the frame that shows them.

**Tech Stack:** Swift 6, UIKit, TextKit 2, iOS 27 SDK; package floor iOS 26 (Willi, Sept 26).

**Spec:** `docs/superpowers/specs/2026-09-26-glimmer-2-perf-and-parity-design.md` Part A (goal: benchmark hitch-time ratio ≤ 1 ms/s). Evidence for this plan is in `docs/superpowers/perf/2026-09-26-glimmer-2-device-results.md` ("What the flick's hitches are"), plus these sources:
- WWDC26 "Elevate your app's text experience with TextKit" (session 370, ~10:36: "use NSTextLayoutFragment as a key to cache rendering surfaces");
- Apple's TextKit 2 sample, which redraws only new or resized fragment layers;
- Texture's preload and display ranges;
- STTextView's viewport handling.

## Global Constraints

- **Package floor iOS 26** (was 18). The demo app's deployment target is 26 too.
- **iOS 27 SDK hooks are declared by Objective-C selector,** so they compile at the iOS 26 floor. They forward to `UITextView`'s own implementation, as the header's "Requires a call to super" asks.
- **No private API calls.** Finding the canvas as a surface's `superview` and calling public `UIView` methods on it is allowed. Swizzling or calling private selectors is not.
- **Commits have no Co-Authored-By trailer.** Don't push or tag.
- **Measure on the device.** Every device number comes from WW 16 (iPhone 16 Pro Max, iOS 27.0) in Release, hands-off (`devicectl process launch --console`).
  - A/B runs alternate A, B, A, B.
  - Low Power Mode invalidates a run: 60 Hz shows as about 1,080 frames instead of about 2,120.
- **Escape hatch.** `GlimmerConfiguration.reusesDrawnText` (default `true`) turns surface reuse off.

## Review Focus

1. **Stale pixels after an appearance change.** A light/dark switch while a long answer is on screen must redraw every visible fragment in the new colours. Test: Task 2 `testADarkModeSwitchRedrawsReusedText`.
2. **A fragment that keeps its instance but changes.** An embed that grows (`invalidateEmbedLayout`) must redraw its fragment, not show the old height's pixels. Test: Task 2 `testAnEmbedThatGrowsIsRedrawn`.
3. **iOS 26.** UIKit never calls the hooks there. Rendering, scrolling and the band must still work: the one-pass path falls back to `layoutViewport()` when no canvas is known. Test: Task 3 `testTheBandMovesBeforeAnySurfaceIsKnown`.
4. **Fast scroll right after a configure.** With preload running in idle frames, a fling that outruns the preload must still render the screen (the viewport pass lays out whatever is missing). Test: Task 4 `testAFlingPastThePreloadStillRendersTheScreen`.
5. **Selection and link highlighting on reused text.** Selecting text and pressing a link must still show their highlights. UITextView draws selection in its own views and link highlights through rendering attributes, which call `setNeedsDisplay` on the canvas directly. Test: Task 2 `testPressingALinkRedrawsItsFragment`.

---

### Task 1: iOS 26 floor

**Files:**
- Modify: `Package.swift` (`platforms`)
- Modify: `Examples/GlimmerDemo/project.yml` (`deploymentTarget`), then `xcodegen generate`
- Modify: `README.md` (requirements line)

- [ ] **Step 1:** In `Package.swift`, replace `.iOS(.v18)` with `.iOS(.v26)`. In `project.yml`, set `deploymentTarget: iOS: "26.0"`. Run `cd Examples/GlimmerDemo && xcodegen generate`.
- [ ] **Step 2:** Build the package and demo, and run the engine suite. Expected: PASS.
  - Availability checks for iOS 18–25 are now always true, so they become dead code. Remove only those the compiler warns about.
  - Keep the iOS 27 checks.
- [ ] **Step 3:** Update the README's requirements line to "iOS 26 or later (the visible band needs iOS 27)", then commit: `Package: iOS 26 floor`.

### Task 2: Reuse the fragment views UIKit already drew

**Files:**
- Modify: `Sources/Glimmer/Engine/Render/GlimmerTextView.swift` (the hooks, the cache, clearing it)
- Modify: `Sources/Glimmer/Engine/Render/GlimmerLayoutFragment.swift` (a cached `renderingSurfaceBounds`)
- Modify: `Sources/Glimmer/Engine/GlimmerConfiguration.swift` (`reusesDrawnText`), `Sources/Glimmer/Engine/GlimmerView.swift` (pass it on)
- Test: `Tests/GlimmerTests/Engine/GlimmerSurfaceReuseTests.swift` (new)

**Interfaces:**
- Produces:
  - `GlimmerTextView.reusesDrawnText: Bool`
  - `GlimmerTextView.forgetDrawnSurfaces()`
  - `GlimmerConfiguration.reusesDrawnText: Bool = true`

A test sees a redraw as a change of the fragment view's `layer.contents`. A reused, undisturbed view keeps the same contents object. A redrawn view gets a new one after `CATransaction.flush()`.

- [ ] **Step 1: Write the failing tests** (`GlimmerSurfaceReuseTests`, `@MainActor`). A helper collects the `_UITextLayoutFragmentView` subviews by class name (test-only) with their `ObjectIdentifier(layer.contents)`:

```swift
private func drawnContents(in textView: UITextView) -> [ObjectIdentifier: ObjectIdentifier] {
    var result: [ObjectIdentifier: ObjectIdentifier] = [:]
    func walk(_ view: UIView) {
        for sub in view.subviews {
            if NSStringFromClass(type(of: sub)).contains("TextLayoutFragmentView"), let contents = sub.layer.contents {
                result[ObjectIdentifier(sub)] = ObjectIdentifier(contents as AnyObject)
            }
            walk(sub)
        }
    }
    walk(textView)
    return result
}

/// A long settled answer, on screen and drawn.
private func shown(reuse: Bool = true) -> (GlimmerView, UIWindow) { … hostInWindow 390×800, update(markdown: long), layout, CATransaction.flush() … }

func testAnUnchangedPassRedrawsNothing() {
    let (view, window) = shown()
    let before = drawnContents(in: view.textView)
    view.textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
    CATransaction.flush()
    let after = drawnContents(in: view.textView)
    XCTAssertFalse(before.isEmpty)
    XCTAssertEqual(before.filter { after[$0.key] == $0.value }.count, before.count, "every fragment kept its pixels")
    _ = window
}

func testWithoutReuseAPassRedrawsTheBand() { /* same with reuse: false; XCTAssertLessThan(kept, before.count / 2) */ }

func testADarkModeSwitchRedrawsReusedText() {
    let (view, window) = shown()
    let before = drawnContents(in: view.textView)
    window.overrideUserInterfaceStyle = .dark
    view.layoutIfNeeded(); CATransaction.flush()
    let after = drawnContents(in: view.textView)
    XCTAssertEqual(before.filter { after[$0.key] == $0.value }.count, 0, "every visible fragment redrew in dark")
    _ = window
}

func testAnEmbedThatGrowsIsRedrawn() { /* streaming code block: record the contents of the fragment holding it, grow it one line (update), flush; that fragment's contents changed */ }

func testPressingALinkRedrawsItsFragment() { /* set a highlight rendering attribute on the link's range via textLayoutManager.addRenderingAttribute(.foregroundColor, …) as UIKit's press does, flush: that fragment's contents changed */ }
```

- [ ] **Step 2: Run them to verify they fail.** Expected:
  - `testAnUnchangedPassRedrawsNothing` fails: every fragment redraws, which is UIKit's behaviour today.
  - `testWithoutReuseAPassRedrawsTheBand` doesn't compile until `reusesDrawnText` exists.
  - The dark-mode, embed and link tests may already pass. They guard the change.
- [ ] **Step 3: Implement.** In `GlimmerTextView`:

```swift
/// Whether a viewport pass hands UIKit back the fragment views it already drew (iOS 27; WWDC26: key rendering
/// surfaces by NSTextLayoutFragment). UIKit otherwise redraws every fragment in the band on every pass.
var reusesDrawnText = true
private let drawnSurfaces = NSMapTable<NSTextLayoutFragment, UIView>.weakToWeakObjects()
private var drawnSizes: [ObjectIdentifier: CGSize] = [:]

/// Forgets every drawn surface, so the next pass redraws: after changes that keep a fragment but change its pixels.
func forgetDrawnSurfaces() { drawnSurfaces.removeAllObjects(); drawnSizes.removeAll() }

// Declared by selector: the iOS 27 SDK's delegate methods, compiled at the iOS 26 floor. UIKit calls them only on 27.
@objc(textViewportLayoutController:retrieveCachedRenderingSurfaceForKey:)
func retrieveDrawnSurface(_ controller: NSTextViewportLayoutController, key: AnyObject) -> AnyObject? {
    if reusesDrawnText, let fragment = key as? NSTextLayoutFragment, let view = drawnSurfaces.object(forKey: fragment),
       view.superview != nil, !view.isHidden, drawnSizes[ObjectIdentifier(fragment)] == fragment.renderingSurfaceBounds.size {
        return view
    }
    return Self.callUITextView(#selector(retrieveDrawnSurface(_:key:)), on: self, controller, key)
}

@objc(textViewportLayoutController:cacheRenderingSurface:forKey:)
func cacheDrawnSurface(_ controller: NSTextViewportLayoutController, surface: AnyObject, key: AnyObject) {
    if reusesDrawnText, let fragment = key as? NSTextLayoutFragment, let view = surface as? UIView {
        drawnSurfaces.setObject(view, forKey: fragment)
        drawnSizes[ObjectIdentifier(fragment)] = fragment.renderingSurfaceBounds.size
    }
    Self.callUITextView(#selector(cacheDrawnSurface(_:surface:key:)), on: self, controller, surface, key)
}
```

`callUITextView` looks up `UITextView`'s implementation with `class_getMethodImplementation`, checking `instancesRespond(to:)` first, and calls it through an `@convention(c)` cast. Two overloads: one returning `AnyObject?` for retrieve, one returning `Void` for cache. Never skip the cache forward: without it UIKit asserts "elementView should have been created and stored".

Clear the cache:
- in `invalidateEmbedLayout(atCharacter:)`, before `invalidateLayout(for:)`;
- whenever `attributedText` is set, since it's a new document;
- in `apply(theme:)`.

Keep `drawnSizes` bounded: prune entries for fragments no longer in `drawnSurfaces` every 512 inserts.

In `GlimmerLayoutFragment`, cache `renderingSurfaceBounds` once the fragment is laid out, and clear it in `invalidateLayout()`:

```swift
private var cachedSurfaceBounds: CGRect?
override var renderingSurfaceBounds: CGRect {
    if let cachedSurfaceBounds { return cachedSurfaceBounds }
    let bounds = quoteBarRects().reduce(super.renderingSurfaceBounds.insetBy(dx: -(Self.pillHorizontalInset + 1), dy: -2)) { $0.union($1) }
    if state == .layoutAvailable { cachedSurfaceBounds = bounds }
    return bounds
}
override func invalidateLayout() { cachedSurfaceBounds = nil; super.invalidateLayout() }
```

Add `GlimmerConfiguration.reusesDrawnText` (default `true`, documented as the escape hatch). `GlimmerView` sets `textView.reusesDrawnText` in its initializer.

- [ ] **Step 4: Run the tests to verify they pass.** Then run the engine suite and `GlimmerStreamingPerformanceTests`. Expected: PASS.
  - If the link test fails, clear the cache from `textViewportLayoutControllerReceivedSetNeedsLayout` when rendering attributes change. Record a ruling.
- [ ] **Step 5: Commit** `Engine: reuse the fragment views UIKit already drew`.

### Task 3: One viewport pass per band move

**Files:** Modify `GlimmerTextView.swift`. Test `GlimmerVisibleBandTests.swift`.

**Interfaces:** Produces `GlimmerTextView.viewportPasses: Int`, a diagnostics counter that the benchmark HUD reads too.

`refreshVisibleBandIfNeeded()` calls `layoutViewport()` directly. The canvas then runs a second, full pass in the commit (measured: 297 history passes against 151 when deferred). Instead, mark the canvas for layout: exactly one pass then runs in the commit, and it calls `viewportBounds(for:)`, which returns the new band. The canvas is the `superview` of the surfaces UIKit hands to `cacheDrawnSurface`.

- [ ] **Step 1: Failing tests.**
  - `testABandMoveRunsOnePass`: scroll 0.3 screens, then `layoutIfNeeded()` and `CATransaction.flush()`. Assert `viewportPasses` grew by exactly 1 and the band moved.
  - `testTheBandMovesBeforeAnySurfaceIsKnown`: a fresh view whose first refresh happens before any pass. The band must still move (the fallback).
  - `viewportPasses` is incremented in an override of `textViewportLayoutControllerWillLayout(_:)`, which is public on iOS 27 and requires super.
- [ ] **Step 2:** Run the tests. Expected: `testABandMoveRunsOnePass` fails with 2 passes.
- [ ] **Step 3: Implement.**
  - Keep `private weak var canvasView: UIView?`, set from `(surface as? UIView)?.superview` in `cacheDrawnSurface`.
  - In `refreshVisibleBandIfNeeded()` and `widenBand()`: `if let canvasView { canvasView.setNeedsLayout() } else { layoutViewport() }`.
  - Deferring through the text view's own `setNeedsLayout()` doesn't work: measured, the canvas never laid out.
- [ ] **Step 4:** Run the band tests, the reveal/mask tests and the engine suite. Expected: PASS.
- [ ] **Step 5: Commit** `Engine: a band move runs one viewport pass`.

### Task 4: Lay out ahead of the band in idle frames

**Files:**
- Modify: `GlimmerTextView.swift` (a preloader)
- Modify: `GlimmerView.swift` (start and stop it with the band; take the scroll direction from the viewport tracker)
- Test: `GlimmerVisibleBandTests.swift`

**Interfaces:** Produces `GlimmerTextView.preloadedRange: ClosedRange<CGFloat>?`, in text view coordinates: what TextKit has laid out around the band.

Each band move lays out the newly visible text inside the pass: a median of 2.5 ms, up to 20 ms during the flick-back. Texture keeps a preload range that runs 2.5 screens ahead and 1.5 behind in the scroll direction. Here a `CADisplayLink` does the same work in idle frames. On each tick it calls `enumerateTextLayoutFragments(from:options: [.ensuresLayout])` for fragments beyond the band's edge in the scroll direction (and a quarter as far the other way), stopping after 2 ms of main-thread time. It stops once the preload spans 1.5 screens ahead and 0.5 behind, and restarts after a band move or an edit.

- [ ] **Step 1: Failing tests.**
  - `testIdleFramesPreloadAheadOfTheBand`: configure a long answer, pump the run loop 0.3 s. `preloadedRange` extends ≥ 1.5 screens below the band.
  - `testAFlingPastThePreloadStillRendersTheScreen`: scroll 6 screens at once. After the pass, `renderedBand` contains the screen.
  - `testPreloadStaysWithinItsBudget`: each tick's main-thread CPU stays under 3 ms (Debug).
- [ ] **Step 2:** Run them. Expected: the first fails (`preloadedRange` doesn't exist); the fling test guards.
- [ ] **Step 3: Implement the preloader.**
  - Track the frontier as `NSTextLocation`s at the preload's top and bottom.
  - Direction comes from the sign of the last scroll delta that `GlimmerViewportTracker` reported (default: down).
  - Stop on `window == nil`, and while `rendersScreenOnly`: the first frame belongs to the screen.
- [ ] **Step 4:** Run the band tests and the engine suite. Expected: PASS.
- [ ] **Step 5: Commit** `Engine: lay out ahead of the band in idle frames`.

### Task 5: A code block's first appearance off the critical path

**Files:**
- Modify: `Sources/Glimmer/Engine/Embeds/GlimmerCodeBlockView.swift`, `GlimmerBlockAttachment.swift`
- Maybe create: `Sources/Glimmer/Engine/Embeds/GlimmerEmbedViewPool.swift`
- Test: `GlimmerCodeBlockViewTests.swift`

On the device, a streamed code block's view takes 4.3–10 ms to build, inside one apply.

- [ ] **Step 1: Measure the split first.** Write a throwaway test that times `GlimmerCodeBlockView.init` and its first `layoutIfNeeded` on an empty block, piece by piece:
  - the inner `GlimmerTextView`;
  - the metrics TextKit stack;
  - the header (label and copy button, including the SF Symbol);
  - the first highlight.

  Record the numbers in the ledger (Release sim; on the device if unlocked).
- [ ] **Step 2: Write the failing test** for the fix the split points to. The default fix is a pool: `GlimmerEmbedViewPool` keeps one pre-built code block view per theme. It is filled in an idle frame once a view starts streaming. `embedView()` takes the pooled view and applies the embed with `update(to:)`.
  - Test `testAStreamedCodeBlockTakesAPrebuiltView`: stream a fence into a view that has idled one frame. The attachment's view is the pooled instance, and its apply's main-thread CPU is under 2 ms (Release sim).
  - If the split shows one piece dominates and can be made lazy, e.g. the copy button's symbol image, make that piece lazy instead. Record a ruling.
- [ ] **Step 3:** Implement. Also register iOS 27's `registerTextAttachmentViewProviderReusePolicy(.onScrollingOutOfViewport, forTextAttachmentViewProviderType: GlimmerEmbedViewProvider.self)` behind `#available(iOS 27, *)`, as a cheap guard against provider churn.
- [ ] **Step 4:** Run the code block, embed and streaming tests and the engine suite. Expected: PASS.
- [ ] **Step 5: Commit** `Engine: a streamed code block takes a prebuilt view`.

### Task 6: Device verification, tuning and results

**Files:**
- Modify: `Tests/GlimmerTests/Engine/GlimmerStreamingPerformanceTests.swift` and `Examples/GlimmerDemo/UITests/BenchmarkHitchUITests.swift` (device gates)
- Modify: `docs/superpowers/perf/2026-09-26-glimmer-2-device-results.md` (a "Plan 6b" section) and `README.md` (performance table)

- [ ] **Step 1: A/B on the device.** Plan 6 (c282718) against this branch: three alternating hands-off benchmark runs each. Ledger every `BENCHMARK` line.
- [ ] **Step 2: Try two options and keep each only if it lowers the median ratio:**
  - `bandRefreshStep` 0.5 against 0.25 (the Plan 6 reviewer's recommendation);
  - `layer.drawsAsynchronously = true` on the surfaces in `cacheDrawnSurface` (public; WebKit's accelerated drawing is built on it).

  Record a ruling for each, with its numbers.
- [ ] **Step 3: If the median is still above 1 ms/s, re-attribute.** Re-apply the probe (scratchpad `probe6`) and name what's left. Record it in the results doc as the next step, rather than guessing at a fix.
- [ ] **Step 4: Gates.**
  - The device benchmark gate moves to the new worst rested run + 0.5 ms/s, or to 1 ms/s if every run meets it.
  - `GlimmerDevicePerf` gates stay unless a baseline moved by more than 30%.
- [ ] **Step 5: Results.** Add a "Plan 6b" section: before/after table, what each change moved, what's left. Update the README table. Commit `Demo: Plan 6b device results`.

## Out of scope

- **Coalescing streamed edits per frame.** Several edits in one frame already share one pass per commit, and the benchmark applies about 3 updates a second, so there's nothing to measure. Revisit if a faster stream shows edit-driven passes.
- **The code block's tint-colour cascade.** Re-adding a code block view restyles its inner text view and runs that view's own viewport pass. Measured at 58 passes and about 15 ms in a whole run: not a hitch source.
- **Off-main bitmap rendering** (Texture/YYText/Telegram) and private-API deferral of UIKit's passes. Reconsider only if Task 6's attribution shows the public fixes have plateaued.
- **Part B (1.x parity):** Plan 7.

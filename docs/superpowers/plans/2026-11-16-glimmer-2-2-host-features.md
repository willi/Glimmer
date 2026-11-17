# Glimmer 2.2.0: host features for SuperMe chat — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the eight general features SuperMe's agent chat needs before it can render with `GlimmerView`, and release them as Glimmer 2.2.0.

**Architecture:** All additions are additive public API on `GlimmerView`, `GlimmerInlineToken` and the document cache, plus one source-compatibility change (iOS 27-only overrides declared by selector so the package builds with the iOS 26 SDK). No existing public API changes shape.

**Tech Stack:** Swift 6, UIKit, TextKit 2, XCTest. iOS 26 floor.

**Spec:** `/Users/willi/work/SuperMe/superme-ios/docs/superpowers/specs/2026-11-16-glimmer-2-chat-design.md` (section "1. Glimmer 2.2.0 additions"). Read it first.

## Global Constraints

- Work on branch `feature/2-2-host-features` off `main` (9cc6f96) in `/Users/willi/work/Glimmer`.
- Follow `AGENTS.md`: failing test first; every public declaration doc-commented; no force unwraps or casts in library code; one type per file; copy round-trips checked with `assertEquivalent`; named pasteboards in tests.
- XCTest only, `@MainActor final class …Tests: XCTestCase`, `@testable import Glimmer`, files in `Tests/GlimmerTests/Engine/`.
- Test command: `DEST='platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0'; xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/<Class>`. Run one xcodebuild at a time; if it hangs after printing the result, kill it.
- Must compile with Xcode 26.5 (iOS 26 SDK) and Xcode 27.x (iOS 27 SDK).
- No new public API beyond what this plan names. Additive only: existing call sites compile unchanged.
- Commits: short imperative summary, no Co-Authored-By trailer. Do not push branches or tags; Willi pushes.

## Review Focus

- **A chip shared through the document cache**: two views showing the same cached answer must each get their own chip view (one `UIView` cannot live in two hierarchies). Test in Task 6.
- **A tappable chip during a reveal**: while revealing, VoiceOver reads one label; the chip must not be tappable before it is revealed. Test in Task 1.
- **`fittingWidth` on text with an inline image or chip**: the attachment's width counts toward its line. Test in Task 2.
- **`finishReveal()` while a streamed update is still on the worker**: the late result must not restart the reveal. Test in Task 5.
- **`attributedString(for:)` on an answer whose only content is an image**: returns an empty string, no crash. Test in Task 7.

---

### Task 0: Build with the iOS 26 SDK

**Files:**
- Modify: `Sources/Glimmer/Engine/Render/GlimmerTextView.swift:431-441` (viewport will/did layout), `:604-615` (`viewportBounds(for:)`)
- Create: `.github/workflows/build.yml`
- Modify: `README.md` Requirements (line 10)

**Interfaces:**
- Produces: nothing public. Behaviour on iOS 27 is unchanged.

- [ ] **Step 1: Read the exact Objective-C selectors from the iOS 27 SDK**

Run: `grep -n "viewportBoundsForTextViewportLayoutController\|textViewportLayoutControllerWillLayout\|textViewportLayoutControllerDidLayout\|viewportBounds" /Applications/Xcode-27.2.0.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/UIKit.framework/Headers/UITextView.h`
Expected: the three method declarations. Use their selectors verbatim in Step 2; if a method is declared in another header, grep `UIKit.framework/Headers` for it.

- [ ] **Step 2: Declare the three overrides by selector**

Replace each `@available(iOS 27.0, *) override func …` with an `@objc(<selector from Step 1>)` method under a new Swift name (`glimmerViewportLayoutWillLayout(_:)`, `glimmerViewportLayoutDidLayout(_:)`, `glimmerViewportBounds(for:)`), typed with `NSTextViewportLayoutController` (available on iOS 26). Call UITextView's implementation through `class_getMethodImplementation(UITextView.self, selector)` + `unsafeBitCast`, exactly as `retrieveDrawnSurface` does (`:372-399`). Keep the runtime `isOperatingSystemAtLeast(27)` guard in the bounds method and return the superclass value below 27. Extend the comment at `:369-371` to cover the three methods.

- [ ] **Step 3: Run the viewport and diagnostics tests on the iOS 27 simulator**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerDiagnosticsTests -only-testing:GlimmerTests/GlimmerVisibleBandTests`
Expected: PASS. Viewport passes are still counted and the visible band still limits rendering, so the selector-declared methods are still called.

- [ ] **Step 4: Add the iOS 26 SDK build workflow**

`.github/workflows/build.yml`: on `push` and `pull_request`; job on `macos-26`; `DEVELOPER_DIR=/Applications/Xcode_26.5.app/Contents/Developer`; run `xcodebuild -scheme Glimmer -destination 'generic/platform=iOS Simulator' build`. A second job on the same runner with the newest Xcode 27 on the image runs the same build. (SuperMe's `.github/workflows/swift.yml:196-230` shows the runner and `DEVELOPER_DIR` pattern.)

- [ ] **Step 5: README Requirements**

Change "Xcode 27 or later (the iOS 27 SDK) to build" to: builds with Xcode 26.5 or later; on iOS 27 the visible-band rendering needs nothing extra, because the iOS 27 methods are declared by selector.

- [ ] **Step 6: Run the full suite, then commit**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test`
Expected: PASS.
```bash
git add Sources/Glimmer/Engine/Render/GlimmerTextView.swift .github/workflows/build.yml README.md
git commit -m "Engine: build with the iOS 26 SDK"
```
Tell Willi the workflow only proves the 26.5 build once he pushes the branch.

---

### Task 1: Tappable chips

**Files:**
- Modify: `Sources/Glimmer/Engine/Extensions/GlimmerExtension.swift:4-40` (`GlimmerInlineToken`)
- Modify: `Sources/Glimmer/Engine/Compose/GlimmerComposer+Inlines.swift:256-261` (`.chip` case of `appendToken`)
- Modify: `Sources/Glimmer/Engine/Extensions/GlimmerInlineAttachment.swift:38-60` (`chipView()`)
- Create: `Sources/Glimmer/Engine/Extensions/GlimmerChipTapView.swift`
- Create: `Sources/Glimmer/Engine/Extensions/GlimmerTokenTapping.swift` (superview walk, like `Embeds/GlimmerImageTapping.swift`)
- Test: `Tests/GlimmerTests/Engine/GlimmerExtensionTests.swift`

**Interfaces:**
- Produces:
  - `GlimmerInlineToken.isTappable: Bool` (public var, default `false`). Applies to `.chip` only; `.text(tappable:)` keeps its own flag.
  - `GlimmerInlineToken.url: URL?` (public var, default `nil`): where the token leads when rendered as plain attributed text (Task 7). Ignored by `GlimmerView`.
  - `GlimmerInlineToken.init(range:kind:payload:displayText:source:accessibilityLabel:presentation:isTappable: Bool = false, url: URL? = nil)` — the two new parameters are last, with defaults, so existing calls compile.
  - `GlimmerChipTapView` (internal `UIView`): hosts the extension's chip view, owns a `UITapGestureRecognizer`, `func handleTap()`.

- [ ] **Step 1: Write the failing tests**

In `GlimmerExtensionTests`, add a private `TappableCitations` extension (copy the existing private `CitationExtension`, set `isTappable: true`, keep the `UILabel` with `accessibilityIdentifier = "citation"`).

```swift
func testTappingATappableChipCallsOnTokenTap() {
    let view = GlimmerView(configuration: GlimmerConfiguration(extensions: [TappableCitations()], imageLoader: nil, reveal: .none))
    view.update(markdown: "See [1].")
    let window = hostInWindow(view, width: 320)
    var tapped: GlimmerInlineToken?
    view.onTokenTap = { tapped = $0 }
    let host = findSubview(GlimmerChipTapView.self, in: view)
    XCTAssertNotNil(host)
    host?.handleTap()
    XCTAssertEqual(tapped?.displayText, "[1]")
    _ = window
}

func testATappableChipIsAVoiceOverLink() {
    let text = GlimmerComposer(theme: .default, extensions: [TappableCitations()]).compose(GlimmerParser.parse("See [1]."))
    var linkRange: NSRange?
    text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, range, _ in
        if let url = value as? URL, GlimmerTokenBox.isTokenLink(url) { linkRange = range }
    }
    let range = try XCTUnwrap(linkRange)
    XCTAssertEqual((text.string as NSString).substring(with: range), "[1]")
    XCTAssertNotNil(text.attribute(.glimmerSpokenOnly, at: range.location, effectiveRange: nil))
    XCTAssertNotNil(text.attribute(.glimmerToken, at: range.location, effectiveRange: nil))
}

func testAnUntappableChipHasNoLinkAndNoTapHost() {
    // existing CitationExtension (isTappable false): no .link, no .glimmerToken, no GlimmerChipTapView
}

func testCopyingATappableChipWritesItsSourceOnce() {
    // view.markdownSource() for "See [1]." with TappableCitations == "See [1]."; plainText() == "See [1]."
}

func testATappableChipCannotBeTappedBeforeItIsRevealed() {
    // streaming view with ManualRevealClock (GlimmerViewStreamingTests.streamingView pattern); before the clock
    // reaches the chip, GlimmerChipTapView.gestureRecognizerShouldBegin returns false (acceptsTaps false).
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerExtensionTests`
Expected: FAIL to compile (`isTappable`, `GlimmerChipTapView` undefined).

- [ ] **Step 3: Implement**

- Token: add the two properties and init parameters.
- Composer `.chip`: unchanged attachment character; when `token.isTappable`, also append spoken-only text (`token.accessibilityLabel ?? token.displayText`, the same spoken-only attributes the inline-image alt text uses at `GlimmerComposer+Inlines.swift:140-151`) carrying `.glimmerToken = GlimmerTokenBox(token)` and `.link = GlimmerTokenBox.link(kind: token.kind, at: output.length)`. The serializer already skips spoken-only text for copy; confirm with the copy test.
- `chipView()`: when `token.isTappable`, wrap the extension view (or the default label) in `GlimmerChipTapView`, sized to it; set the inner view's `accessibilityElementsHidden = true` and the host's `isAccessibilityElement = false`, so VoiceOver reaches the chip only through the spoken link (as tappable images do). `GlimmerChipTapView.handleTap()` finds the `GlimmerView` through `glimmerTokenTapHandler` (superview walk, like `GlimmerImageTapping.swift:5-18`) and calls its `onTokenTap` with the token. `acceptsTaps` follows the reveal exactly as `GlimmerInlineImageView` does (`:61-67`).

- [ ] **Step 4: Run the tests, plus the accessibility and mentions suites**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerExtensionTests -only-testing:GlimmerTests/GlimmerAccessibilityTests -only-testing:GlimmerTests/GlimmerMentionsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Glimmer/Engine/Extensions Sources/Glimmer/Engine/Compose/GlimmerComposer+Inlines.swift Tests/GlimmerTests/Engine/GlimmerExtensionTests.swift
git commit -m "Extensions: tappable chips"
```

---

### Task 2: Fitting width

**Files:**
- Create: `Sources/Glimmer/Engine/Render/GlimmerTextMeasurer.swift`
- Modify: `Sources/Glimmer/Engine/GlimmerView.swift` (public method near `sizeThatFits`, `:128`)
- Test: `Tests/GlimmerTests/Engine/GlimmerViewSizingTests.swift` (new)

**Interfaces:**
- Produces:
  - `GlimmerView.fittingWidth(maximum: CGFloat) -> CGFloat` (public, `@MainActor`): the width of the longest laid-out line at `maximum`, including the text container's insets and line-fragment padding, never above `maximum`. A text containing a `GlimmerBlockAttachment` (code block, table, standalone image, rule) returns `maximum`.
  - `GlimmerTextMeasurer` (internal, `@MainActor final class`): `init(text: NSAttributedString, width: CGFloat, insets: UIEdgeInsets, lineFragmentPadding: CGFloat)`; `var longestLineWidth: CGFloat`; `var lineBottoms: [CGFloat]` (each line fragment's bottom, in order, including the top inset). Uses its own `NSTextContentStorage` + `NSTextLayoutManager` + `NSTextContainer` and `enumerateTextLayoutFragments(options: [.ensuresLayout])`, as `GlimmerCodeBlockView`'s metrics manager does (`Embeds/GlimmerCodeBlockView.swift:31-39, 157-167`). Used by Tasks 2 and 3.

- [ ] **Step 1: Write the failing tests**

```swift
func testShortTextFitsNarrowerThanTheMaximum() {
    let view = settledView("Hi")
    let width = view.fittingWidth(maximum: 320)
    XCTAssertGreaterThan(width, 0)
    XCTAssertLessThan(width, 100)
}

func testWrappedTextFillsTheMaximum() {
    let width = settledView(String(repeating: "word ", count: 80)).fittingWidth(maximum: 320)
    XCTAssertGreaterThan(width, 280)
    XCTAssertLessThanOrEqual(width, 320)
}

func testTheLongestLineWins() {
    let short = settledView("a").fittingWidth(maximum: 320)
    let both = settledView("a\n\nthe longer line here").fittingWidth(maximum: 320)
    XCTAssertEqual(both, settledView("the longer line here").fittingWidth(maximum: 320), accuracy: 0.5)
    XCTAssertGreaterThan(both, short)
}

func testACodeBlockTakesTheMaximum() {
    XCTAssertEqual(settledView("```\nx\n```").fittingWidth(maximum: 320), 320)
}

func testAnInlineChipCountsTowardItsLine() {
    // "Hi [1]" with GlimmerExtensionTests' CitationExtension is wider than "Hi"
}
```
`settledView(_:)` is a private helper: `GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil, reveal: .none))`, `update(markdown:)`, hosted at width 320.

- [ ] **Step 2: Run to verify they fail**

Run: `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/GlimmerViewSizingTests`
Expected: FAIL to compile.

- [ ] **Step 3: Implement `GlimmerTextMeasurer` and `fittingWidth(maximum:)`**

`fittingWidth` checks the text storage for a `GlimmerBlockAttachment` first, then measures a copy of the text storage with `GlimmerTextMeasurer` using `textView.textContainerInset` and `textContainer.lineFragmentPadding`. Cache the result per `(textView.textVersion, maximum)`.

- [ ] **Step 4: Run to verify they pass**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Glimmer/Engine/Render/GlimmerTextMeasurer.swift Sources/Glimmer/Engine/GlimmerView.swift Tests/GlimmerTests/Engine/GlimmerViewSizingTests.swift
git commit -m "Sizing: fitting width of the longest line"
```

---

### Task 3: Capped height

**Files:**
- Modify: `Sources/Glimmer/Engine/GlimmerView.swift`
- Test: `Tests/GlimmerTests/Engine/GlimmerViewSizingTests.swift`

**Interfaces:**
- Consumes: `GlimmerTextMeasurer.lineBottoms` (Task 2).
- Produces: `GlimmerView.height(forWidth width: CGFloat, notExceeding maximum: CGFloat) -> CGFloat` (public, `@MainActor`): the full height when it fits under `maximum`; otherwise the bottom of the last whole line (an embed counts as one line) that fits, plus the bottom inset; `0` when not even the first line fits. Never a cut line.

- [ ] **Step 1: Write the failing tests**

```swift
func testACapAboveTheFullHeightReturnsTheFullHeight() {
    let view = settledView("a<br>b")
    let full = view.sizeThatFits(CGSize(width: 320, height: .greatestFiniteMagnitude)).height
    XCTAssertEqual(view.height(forWidth: 320, notExceeding: full + 50), full)
}

func testACapKeepsOnlyWholeLines() {
    let twoLines = settledView("a<br>b").sizeThatFits(CGSize(width: 320, height: .greatestFiniteMagnitude)).height
    let threeLines = settledView("a<br>b<br>c").sizeThatFits(CGSize(width: 320, height: .greatestFiniteMagnitude)).height
    let cap = (twoLines + threeLines) / 2
    XCTAssertEqual(settledView("a<br>b<br>c<br>d").height(forWidth: 320, notExceeding: cap), twoLines, accuracy: 0.5)
}

func testACapBelowTheFirstLineReturnsZero() {
    XCTAssertEqual(settledView("a<br>b").height(forWidth: 320, notExceeding: 2), 0)
}
```

- [ ] **Step 2: Run to verify they fail**

Expected: FAIL to compile.

- [ ] **Step 3: Implement** with `height(forWidth:)` (`:550`) for the full height and `GlimmerTextMeasurer(width:).lineBottoms` when it exceeds the cap.

- [ ] **Step 4: Run to verify they pass**, then **Step 5: Commit** `git commit -m "Sizing: height of whole lines under a cap"`.

---

### Task 4: Size readiness

**Files:**
- Modify: `Sources/Glimmer/Engine/GlimmerView.swift` (`update` `:95-115`, `drainDocumentUpdates` `:463-486`, `reportHeightIfChanged` `:623-629`)
- Test: `Tests/GlimmerTests/Engine/GlimmerViewStreamingTests.swift`

**Interfaces:**
- Produces: `GlimmerView.isLayoutSettled: Bool` (public, read-only): `false` while an update is waiting for or running on the worker (`pendingDocument != nil`), `true` otherwise. When it turns `true`, `onHeightChange` is called, even if the height did not change.

- [ ] **Step 1: Write the failing tests**

```swift
func testASettledUpdateIsSettledAtOnce() {
    let view = GlimmerView(configuration: GlimmerConfiguration(imageLoader: nil, reveal: .none))
    view.update(markdown: "Hello")
    XCTAssertTrue(view.isLayoutSettled)
}

func testAStreamedUpdateSettlesWhenComposedAndReportsIt() async {
    let view = streamingView(width: 320)
    var reports = 0
    view.onHeightChange = { reports += 1 }
    view.update(markdown: "Hello", isStreaming: true, revealID: nil)
    XCTAssertFalse(view.isLayoutSettled)
    await view.pendingDocument?.value
    XCTAssertTrue(view.isLayoutSettled)
    XCTAssertGreaterThan(reports, 0)
}

func testSettlingReportsEvenWhenTheHeightIsUnchanged() async {
    // stream "Hello" and await; reset reports; update the same text with isStreaming: false (goes through the
    // worker while the reveal engine exists); await; reports == 1 and the height is unchanged.
}
```

- [ ] **Step 2: Run to verify they fail**, **Step 3: Implement** (end of `drainDocumentUpdates`: after `pendingDocument = nil`, report the height and call `onHeightChange` if the report did not), **Step 4: Run** `-only-testing:GlimmerTests/GlimmerViewStreamingTests` → PASS, **Step 5: Commit** `git commit -m "Engine: report when a streamed update's layout is settled"`.

---

### Task 5: Reveal control after a stream ends

**Files:**
- Modify: `Sources/Glimmer/Engine/GlimmerView.swift` (`update` `:95`, `startRevealIfNeeded` `:350-361`, `endReveal` `:384-394`, `GlimmerText` passthrough is not needed)
- Test: `Tests/GlimmerTests/Engine/GlimmerViewStreamingTests.swift`

**Interfaces:**
- Consumes: `GlimmerRevealStore.shared.revealedLength(for:text:)` and `record(_:text:version:owner:for:)` (existing).
- Produces:
  - `GlimmerView.finishReveal()` (public): ends a running reveal now, shows all text, records the full length for the current `revealID`, and reports the height. Until the next `update` with `isStreaming: true` or a new `revealID`, no reveal restarts (a worker result that lands later applies without one).
  - `GlimmerView.isRevealing: Bool` (public, read-only): `true` while a reveal engine runs (`engine != nil`). Hosts and their tests use it to tell a revealing answer from a shown one.
  - `GlimmerView.update(markdown: String, isStreaming: Bool, revealID: String?, revealsFinishedText: Bool)` (public). With `isStreaming: false` and `revealsFinishedText: true`, a settled text still composes synchronously (`isLayoutSettled` stays `true`) and then reveals from the stored progress for `revealID` (or from 0), draining within `GlimmerRevealOptions.drainDuration`. If the stored progress covers the whole text, nothing reveals. Ignored when the reveal is `.none`, Reduce Motion is on, or `revealID` is nil. The existing three-argument `update` calls it with `false`.

- [ ] **Step 1: Write the failing tests** (use the file's `streamingView(width:)` and `ManualRevealClock`; clear the store id in each test)

```swift
func testFinishRevealShowsEverythingAtOnceAndRecordsIt() async { /* stream a 40-word answer, advance the clock a little,
   finishReveal(): engine nil, textView.layer.mask nil, height == full height; a second view streaming the same text
   with the same revealID has engine?.revealedLength == length (it resumes complete) */ }

func testALateWorkerResultDoesNotRestartAFinishedReveal() async { /* stream, send update(isStreaming: false) (goes to
   the worker), call finishReveal() before awaiting pendingDocument, await it: engine stays nil */ }

func testFinishedTextRevealsWhenAsked() { /* new view, update(text, isStreaming: false, revealID: "f",
   revealsFinishedText: true): isLayoutSettled true, engine != nil, engine.revealedLength < length; advancing the clock
   by drainDuration + fadeDuration + 0.1 ends the reveal (engine nil) */ }

func testFinishedTextResumesStoredProgress() async { /* view A streams with revealID "r" and advances partway, recording
   n > 0; view B update(text, isStreaming: false, revealID: "r", revealsFinishedText: true): engine.revealedLength == n */ }

func testFinishedTextWithoutTheFlagShowsAtOnce() { /* existing behaviour: engine nil */ }

func testFinishedTextDoesNotRevealWithRevealNone() { /* configuration reveal: .none → engine nil */ }

func testIsRevealingFollowsTheEngine() { /* false before streaming; true once a streamed update applies; false after
   finishReveal() */ }
```

- [ ] **Step 2: Run to verify they fail**, **Step 3: Implement** (a `revealFinished` flag cleared by a streaming update or a new `revealID`, checked in `startRevealIfNeeded`; `startRevealIfNeeded` gains a parameter to start from finished text after `composeSynchronously()`), **Step 4: Run** `-only-testing:GlimmerTests/GlimmerViewStreamingTests -only-testing:GlimmerTests/GlimmerRevealStoreTests` → PASS, **Step 5: Commit** `git commit -m "Reveal: finish now, and reveal finished text from stored progress"`.

---

### Task 6: Document cache for Hashable extensions, highlighters and loaders

**Files:**
- Create: `Sources/Glimmer/Engine/Stream/GlimmerCacheIdentity.swift` (internal, generalising `Embeds/GlimmerImagePolicyKey.swift`)
- Modify: `Sources/Glimmer/Engine/Stream/GlimmerDocumentCache.swift:9-30` (`Key`, `supports(_:)`), `Sources/Glimmer/Engine/GlimmerView.swift:428-436` (key construction)
- Modify: `README.md` Extensions (~:212) and Image caching (~:120)
- Test: `Tests/GlimmerTests/Engine/GlimmerDocumentCacheTests.swift`

**Interfaces:**
- Produces: `struct GlimmerCacheIdentity: Hashable, Sendable` (internal) wrapping either a type name (the built-ins as today) or an `any Hashable & Sendable` value compared by type then `==` (the `GlimmerImagePolicyKey` pattern). `Key.extensions: [GlimmerCacheIdentity]`, `Key.highlighter: GlimmerCacheIdentity`, `Key.imageLoader: GlimmerCacheIdentity?`. `supports(_:)` is true when every extension, the highlighter and the loader are built-ins (as today) or `Hashable`. No public API; the README documents the rule: "Make an extension, highlighter or image loader `Hashable` to let views with equal configurations share composed answers. Two that compare equal must render equally."

- [ ] **Step 1: Write the failing tests**

```swift
private struct Tagged: GlimmerExtension, Hashable { let tag: String }
private struct Untagged: GlimmerExtension {}

func testEqualHashableExtensionsShareComposedAnswers() { /* two views, extensions [Tagged(tag: "a")], same settled
   markdown: GlimmerDocumentCache.shared.hits rises by 1 */ }
func testDifferentHashableValuesDoNotShare() { /* Tagged("a") then Tagged("b"): hits unchanged */ }
func testANonHashableExtensionIsStillNotCached() { /* Untagged: hits unchanged */ }
func testAHashableLoaderIsCached() { /* a Hashable GlimmerImageLoader stub: hits rise */ }
func testViewsSharingACachedAnswerGetTheirOwnChipViews() { /* GlimmerExtensionTests' chip extension made Hashable;
   two hosted views with the same answer: their chip views are different instances, each in its own view */ }
```
Call `GlimmerDocumentCache.shared.removeAll()` in `setUp`.

- [ ] **Step 2: Run to verify they fail**, **Step 3: Implement**, **Step 4: Run** `-only-testing:GlimmerTests/GlimmerDocumentCacheTests -only-testing:GlimmerTests/GlimmerImagePolicyTests` → PASS, **Step 5: Commit** `git commit -m "Cache: share answers composed with Hashable extensions and loaders"`.

---

### Task 7: Markdown to an attributed string

**Files:**
- Create: `Sources/Glimmer/Engine/GlimmerView+AttributedString.swift`
- Create: `Sources/Glimmer/Engine/Embeds/GlimmerHideImagesPolicy.swift` (internal policy: every image `.hide`)
- Modify: `README.md` (new "Plain attributed text" section after SwiftUI)
- Test: `Tests/GlimmerTests/Engine/GlimmerAttributedStringTests.swift` (new); `GlimmerReadmeExampleTests.swift`

**Interfaces:**
- Consumes: `GlimmerInlineToken.url` (Task 1).
- Produces: `@MainActor public static func attributedString(for markdown: String, configuration: GlimmerConfiguration = .default, traitCollection: UITraitCollection = .current) -> AttributedString` on `GlimmerView`. For short, non-interactive text shown in SwiftUI `Text`:
  - the configuration's extensions preprocess and scan as usual (`prepared(_:isStreaming: false)`), theme scaled for `traitCollection`;
  - every image is hidden (compose with `GlimmerHideImagesPolicy`, which also closes the space it leaves);
  - a code block becomes its code as a paragraph in `theme.codeFont`; a table becomes one line per row, cells joined by a tab; a thematic break is dropped;
  - a chip or token becomes its `displayText`, linked to `token.url` when set; internal `glimmer-token:` / `glimmer-image:` links and spoken-only text are removed;
  - every run carries both UIKit (`font`, `foregroundColor`) and SwiftUI (`font` as `Font(uiFont)`, `foregroundColor` as `Color(uiColor)`) attributes, plus `link`, `strikethroughStyle` and `underlineStyle`.

- [ ] **Step 1: Write the failing tests**

```swift
func testTextKeepsEmphasisAndLinks() {
    let text = GlimmerView.attributedString(for: "Hello **world** [x](https://a.example)")
    XCTAssertEqual(String(text.characters), "Hello world x")
    let x = try XCTUnwrap(text.range(of: "x"))
    XCTAssertEqual(text[x].link, URL(string: "https://a.example"))
    let world = try XCTUnwrap(text.range(of: "world"))
    XCTAssertTrue(text[world].uiKit.font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
    XCTAssertTrue(text.runs.allSatisfy { $0.swiftUI.font != nil })
}

func testImagesAndTheirSpaceAreDropped() {
    XCTAssertEqual(String(GlimmerView.attributedString(for: "Led by ![Acme](https://a.example/a.png) Acme.").characters), "Led by Acme.")
}

func testAnswerOfOnlyAnImageIsEmpty() {
    XCTAssertEqual(GlimmerView.attributedString(for: "![a](https://a.example/a.png)").characters.count, 0)
}

func testACodeBlockBecomesMonospacedText() { /* "```\nlet x = 1\n```": contains "let x = 1" in a monospaced font */ }
func testATableBecomesTabbedRows() { /* "| a | b |\n|---|---|\n| 1 | 2 |" → "a\tb\n1\t2" */ }
func testAChipBecomesLinkedText() { /* token with url → displayText linked to url */ }
func testATappableTextTokenLosesItsInternalLink() { /* GlimmerMentions "@grace": text "@grace", no glimmer-token link */ }
```

- [ ] **Step 2: Run to verify they fail**, **Step 3: Implement** (compose with `GlimmerComposer(theme:highlighter:imageLoader: nil, imagePolicy: GlimmerHideImagesPolicy(), extensions:)`, then walk the result replacing block attachments and token runs as above, then convert to `AttributedString` setting the attribute scopes per run), **Step 4: Run** → PASS, **Step 5: Commit** `git commit -m "API: compose markdown into an attributed string"`.

---

### Task 8: Release 2.2.0

**Files:**
- Modify: `README.md` (Installation `from: "2.2.0"`; Streaming: `finishReveal()` and `revealsFinishedText`; Accessibility: tappable chips are links; Sizing: `fittingWidth(maximum:)`, `height(forWidth:notExceeding:)`, `isLayoutSettled`)
- Modify: `Tests/GlimmerTests/Engine/GlimmerReadmeExampleTests.swift` (one compiled example per new README sample)

- [ ] **Step 1: Add the README samples and their compiled tests**
- [ ] **Step 2: Run the full suite**
Run: `xcodebuild -scheme Glimmer -destination "$DEST" test` → PASS.
- [ ] **Step 3: Run the demo** (`Examples/GlimmerDemo`, `xcodegen generate` if files changed): Gallery and Streaming Lab show no crash or console errors from Glimmer.
- [ ] **Step 4: Commit**

```bash
git add README.md Tests/GlimmerTests/Engine/GlimmerReadmeExampleTests.swift
git commit -m "Docs: 2.2.0 host features"
```

- [ ] **Step 5: Merge, then tag what was merged**

Ask Willi to push the branch, open the PR, confirm both jobs of the build workflow are green (Xcode 26.5 and 27), and merge. Then tag the merged `main` (a squash merge changes the SHA, so never tag the branch):
```bash
git switch main && git pull --ff-only
git tag -a 2.2.0 -m "Glimmer 2.2.0: tappable chips, host sizing, reveal control, iOS 26 SDK builds, cache for custom configurations, attributed text"
git rev-parse '2.2.0^{commit}'
```
Willi pushes the tag. The printed SHA is SuperMe's pin.

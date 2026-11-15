# Image-Loading Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a host app decide, through one `Hashable` policy on `GlimmerConfiguration`, which images Glimmer loads. A
blocked image becomes ordinary text or nothing and never causes a request.

**Architecture:** The composer asks the policy while it builds text, so a blocked image is text and reserves no space.
The single caller of `GlimmerImageLoader` asks again before each load, and the built-in loader asks on each redirect.
The settled-document cache and in-flight downloads are keyed by the policy.

**Tech Stack:** Swift 6 (strict concurrency), UIKit and TextKit 2, URLSession, XCTest, vendored cmark-gfm.

**Spec:** `docs/superpowers/specs/2026-11-14-image-loading-policy-design.md`

## Global Constraints

- With `imagePolicy == nil`, behaviour is exactly what it is today. Every existing test stays green unchanged.
- No host names in library code.
- Swift 6 language mode, strict concurrency. No force unwraps or force casts in library code.
- Every public declaration has a doc comment. Comments say why, not what.
- TextKit 2 only: never read `layoutManager`.
- One xcodebuild at a time. Kill it once the log shows `Test Suite 'Selected tests' passed` or `failed`.
- Test command: `DEST='platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0'`, then
  `xcodebuild -scheme Glimmer -destination "$DEST" test -only-testing:GlimmerTests/<Class>`.
- Commits: present tense, `Engine: …`, body says why. No `Co-Authored-By` trailer. Do not push.

## Review Focus

Inputs the spec implies and a person is likely to hit. Each has a test in the task named.

1. An answer that starts with a blocked image and then a heading: no gap above the heading (Task 1, test 8).
2. A policy set or changed on a view that already shows images: the shown images go away (Task 1, test 16).
3. A blocked image inside a link: its alt text is the link's text and still opens the link (Task 1, test 5).
4. A table cell whose only content is a hidden image: an empty cell, same column count (Task 1, test 11).
5. A redirect chain whose second hop is refused: the first hop is requested, the second never (Task 3, test 1).

## File Structure

| File | Responsibility |
|---|---|
| Create `Sources/Glimmer/Engine/GlimmerImagePolicy.swift` | `GlimmerImagePolicy`, `GlimmerImageDecision` (public) |
| Create `Sources/Glimmer/Engine/GlimmerImageCandidate.swift` | `GlimmerImageCandidate` (public) |
| Create `Sources/Glimmer/Engine/Embeds/GlimmerImagePolicyKey.swift` | A policy as a `Hashable & Sendable` key |
| Create `Sources/Glimmer/Engine/Embeds/GlimmerImageGate.swift` | A policy bound to one image, for load-time checks |
| Modify `GlimmerConfiguration.swift`, `GlimmerView.swift` | The setting, and passing it to the composer and cache key |
| Modify `Compose/GlimmerComposer.swift`, `Compose/GlimmerComposer+Inlines.swift` | The compose-time decision |
| Modify `Stream/GlimmerStreamingDocument.swift`, `Stream/GlimmerDocumentCache.swift` | First-block rule, cache key |
| Modify `Compose/GlimmerInlineImageAttachment.swift`, `Compose/GlimmerInlineImageView.swift`, `Embeds/GlimmerBlockAttachment.swift`, `Embeds/GlimmerImageEmbedView.swift`, `Embeds/GlimmerImageViewLoader.swift` | Carrying the gate to the one load site |
| Modify `Embeds/GlimmerImageRequest.swift`, `Embeds/GlimmerImageCache.swift` | Redirect check, policy-keyed downloads |
| Create `Tests/GlimmerTests/Engine/GlimmerImagePolicyTests.swift` | Tasks 1 and 2 |
| Modify `Tests/GlimmerTests/Engine/GlimmerImageCacheTests.swift`, `ImageTestServer.swift` | Task 3 |
| Modify `README.md` | The "Image policy" section |

---

### Task 1: Policy API and the compose-time decision

**Files:** create `GlimmerImagePolicy.swift`, `GlimmerImageCandidate.swift`, `GlimmerImagePolicyKey.swift`,
`GlimmerImagePolicyTests.swift`; modify `GlimmerConfiguration.swift`, `GlimmerView.swift`, `GlimmerComposer.swift`,
`GlimmerComposer+Inlines.swift`, `GlimmerStreamingDocument.swift`, `GlimmerDocumentCache.swift`, `README.md`.

**Interfaces — produces:**

- The three public types exactly as in spec §4, plus
  `public init(url: URL, alt: String, title: String? = nil, origin: Origin)` on `GlimmerImageCandidate`.
- `GlimmerConfiguration.imagePolicy: (any GlimmerImagePolicy)?`, an `init` parameter directly after `imageLoader`,
  default `nil`.
- `GlimmerComposer.imagePolicy: (any GlimmerImagePolicy)?`, declared directly after `imageLoader`, default `nil`.
- `struct GlimmerImagePolicyKey: Hashable, Sendable { let policy: any GlimmerImagePolicy }`. Two keys are equal when
  the policies have the same type and compare equal.
- `GlimmerDocumentCache.Key.imagePolicy: GlimmerImagePolicyKey?`, default `nil`.

- [ ] **Step 1: Write the failing tests** in `GlimmerImagePolicyTests.swift` (`@MainActor final class`).

Fixtures:

```swift
private struct Answer: GlimmerImagePolicy {            // the same answer for every image
    var answer: GlimmerImageDecision
    func decision(for image: GlimmerImageCandidate) -> GlimmerImageDecision { answer }
}
private struct AllowHosts: GlimmerImagePolicy {
    var hosts: Set<String>
    func decision(for image: GlimmerImageCandidate) -> GlimmerImageDecision {
        hosts.contains(image.url.host() ?? "") ? .load : .showAltText
    }
}
/// Remembers what it was asked and can change its answer, which a real policy must never do.
private final class PolicyState: @unchecked Sendable { /* NSLock; var answer; private(set) var seen: [GlimmerImageCandidate] */ }
private struct Scripted: GlimmerImagePolicy { let state: PolicyState /* == and hash by ObjectIdentifier(state) */ }
private final class RecordingLoader: GlimmerImageLoader, @unchecked Sendable { /* var requested: [URL]; returns UIImage() */ }

private func compose(_ markdown: String, policy: (any GlimmerImagePolicy)?, extensions: [any GlimmerExtension] = []) -> NSAttributedString {
    GlimmerComposer(theme: .default, imagePolicy: policy, extensions: extensions).compose(GlimmerParser.parse(markdown))
}
/// A 390 × 3000 window (everything in the rendered band), `reveal: .none`, updated and settled.
private func shown(_ markdown: String, policy: (any GlimmerImagePolicy)?, loader: (any GlimmerImageLoader)?,
                   extensions: [any GlimmerExtension] = []) -> (GlimmerView, UIWindow)
/// Inline image attachments and `.image` block attachments, including those inside table cells.
private func imageAttachments(in text: NSAttributedString) -> [NSTextAttachment]

private let everyKind = """
Inline ![one](https://a.example/1.png) and [![two](https://a.example/2.png)](https://a.example/page).

- item ![three](https://a.example/3.png)

> quote ![four](https://a.example/4.png)

| Head |
|---|
| ![five](https://a.example/5.png) |

Reference ![six][ref] and :octocat:

![seven](https://a.example/7.png)

[ref]: https://a.example/6.png
"""
```

Tests (`u` stands for `https://a.example/i.png`; `hide` and `alt` for `Answer(answer: .hide / .showAltText)`):

| # | Name | Arrange | Assert |
|---|---|---|---|
| 1 | `testABlockingPolicyLoadsNothingForAnyKindOfImage` | `shown(everyKind, policy: alt, loader, extensions: [GlimmerEmojiShortcodes()])` | `loader.requested == []`; `imageAttachments(in: textStorage).isEmpty`; `plainText()` contains `one` … `seven` and `:octocat:` |
| 2 | `testABlockingPolicyLoadsNothingWhileStreaming` | same view; `update(markdown: prefix, isStreaming: true)` + `settle` for every 40-character prefix, then the whole text with `isStreaming: false`; `await waitUntil { view.plainText().contains("seven") }` | as test 1 |
| 3 | `testOnlyAllowedURLsAreRequested` | `AllowHosts(["ok.example"])`; `"Inline ![a](https://ok.example/a.png) and ![b](https://bad.example/b.png).\n\n![c](https://ok.example/c.png)\n\n![d](https://bad.example/d.png)"`; wait for 2 requests, settle | `Set(loader.requested)` is exactly the two `ok.example` URLs; count is 2 |
| 4 | `testThePolicySeesEveryImageWithItsURLAltTitleAndOrigin` | `Scripted`; compose `"![Alt](https://a.example/i.png \"Title\") ![Dog](dog) :octocat:"` with emoji shortcodes | `state.seen` contains `(u, "Alt", "Title", .markdown)`, one whose `url.absoluteString == "dog"` (no scheme), and one with `alt == ":octocat:"`, `origin == .extensionToken(kind: "emoji")` |
| 5 | `testAltTextRendersAsTheTextAroundIt` | `alt`; `"**See ![the chart](u) now** and [![docs](u)](https://a.example/page)"` | string is `"See the chart now and docs"`; font and colour at `the chart` equal those at `See`; `.link` at `docs` is `https://a.example/page`; no attachment; no `.glimmerSource` on `the chart` |
| 6 | `testEmptyAltTextRendersNothing` | `alt`; `"A ![](u) b"` | string is `"A  b"`; no attachment |
| 7 | `testHiddenImagesLeaveNoBlankLine` | `hide`; `"Before\n\n![a](u) ![b](u)\n\nAfter"` | `assertEquivalent` with `compose("Before\n\nAfter", policy: hide)` |
| 8 | `testALeadingBlockedImageLeavesNoGapAboveAHeading` | `hide`; `"![x](u)\n\n# Title"`, composed whole and through a `GlimmerStreamingDocument` | both `assertEquivalent` with `"# Title"` |
| 9 | `testABlockedStandaloneImageIsAnOrdinaryParagraph` | `alt`; `"![Chart](u)"` | `assertEquivalent` with `compose("Chart", policy: alt)` |
| 10 | `testABlockedListItemKeepsItsMarker` | `hide`; `"- ![](u)\n- two"` | string equals that of `compose("-\n- two", policy: hide)` |
| 11 | `testAHiddenImageLeavesAnEmptyTableCell` | `hide`; `"| a | b |\n|---|---|\n| ![](u) | x |"` | the table embed's first row has 2 cells; the first has length 0 |
| 12 | `testABlockedEmojiImageShowsItsShortcode` | `alt`; `"Hi :octocat:!"` with emoji shortcodes | string is `"Hi :octocat:!"`; no attachment; `GlimmerMarkdownSerializer.markdown` of it is `"Hi :octocat:!"` |
| 13 | `testAnUnparseableURLUnderAPolicyShowsItsAltText` | `Answer(answer: .load)`; `"See ![the chart]() now"` | string is `"See the chart now"`; colour at `the chart` equals that at `See` |
| 14 | `testWithNoPolicyImagesStillLoad` | `shown("Inline ![a](https://a.example/a.png).\n\n![b](https://a.example/b.png)", policy: nil, loader)`; wait for 2 | `Set(loader.requested)` is those two URLs |
| 15 | `testABlockedImageCopiesAsWhatIsShown` | `alt`; `"See ![the chart](u)."` | `markdownSource()` is `"See the chart."`; composing that is `assertEquivalent` with the original |
| 16 | `testSettingAPolicyOnALiveViewRemovesItsImages` | test 14's view, then `view.configuration.imagePolicy = alt`, settle | `imageAttachments` is empty; `plainText()` contains `a` and `b`; no new requests |
| 17 | `testAViewWithAPolicyDoesNotReuseTextComposedWithoutOne` | `GlimmerDocumentCache.shared.removeAll()`; view 1 `.init(imageLoader: nil)`, view 2 `.init(imageLoader: nil, imagePolicy: alt)`, both `update(markdown: "![Photo](https://example.com/photo.png)")` | view 2 has no block attachment; its `plainText()` is `"Photo"` |
| 18 | `testEqualPoliciesShareSettledText` | `removeAll()`; two views, each `.init(imageLoader: nil, imagePolicy: AllowHosts(["ok.example"]))`, same markdown | `GlimmerDocumentCache.shared.hits` grows by 1 |

- [ ] **Step 2: Run them and watch them fail.** `-only-testing:GlimmerTests/GlimmerImagePolicyTests`. Expected: build
  failure, `GlimmerImagePolicy` and `imagePolicy` are not defined.

- [ ] **Step 3: Add the public types** and `GlimmerConfiguration.imagePolicy`. The policy's doc comment states its
  contract: called from any thread, more than once per image, must be quick and always give the same answer; equal
  policies decide equally. Each `GlimmerImageDecision` case documents what is shown.

- [ ] **Step 4: Add `GlimmerImagePolicyKey`.** Equality opens the existential through a protocol extension
  (`(other as? Self) == self`); hashing forwards to the policy's `hash(into:)`.

- [ ] **Step 5: Make the composer decide.** In `GlimmerComposer` and its `+Inlines` extension:

  - `func imageDecision(url: URL?, alt: String, title: String?, origin: GlimmerImageCandidate.Origin) -> GlimmerImageDecision`:
    no policy gives `.load`; a policy and a `nil` URL give `.showAltText`; otherwise the policy's answer.
  - `standaloneImage(_:)` returns `(url: URL, alt: String, title: String?)?`, and `nil` unless the decision is `.load`.
  - `appendInlines`, `appendText`, `appendToken` and `appendInlineImage` return `@discardableResult Bool`: whether the
    policy kept an image from showing. Containers OR their children's results.
  - `appendInlineImage(source:alt:title:origin:markdown:spoken:attributes:reuse:to:)`. With no policy it is unchanged,
    including the dimmed alt text for an unparseable URL. Under a policy: `.load` as today; `.showAltText` appends
    `alt` with `attributes` and nothing else; `.hide` appends nothing.
  - `appendToken`, `.image(url)` case, origin `.extensionToken(kind: token.kind)`: when not loaded, `.showAltText`
    takes the existing `.text(tappable: false)` path and `.hide` appends nothing.
  - `appendTextParagraph`: when an image was kept from showing, `marker == nil`, and what the inlines appended is only
    spaces, tabs and `\u{2028}`, remove it and return without the `\n`.
  - `func startsDocument(index: Int, precedingLength: Int) -> Bool`:
    `index == 0 || (imagePolicy != nil && precedingLength == 0)`. `compose(_:)` and the block loop in
    `GlimmerStreamingDocument` (`isFirst: index == 0`) call it, the latter with `running`.

- [ ] **Step 6: Wire the view and the cache.** `GlimmerView.makeDocument()` passes `configuration.imagePolicy`.
  `composeSynchronously()` puts `configuration.imagePolicy.map(GlimmerImagePolicyKey.init)` in the cache key.
  `GlimmerDocumentCache.supports` is unchanged.

- [ ] **Step 7: Add the README section** "Image policy" after "Image caching", and one bullet in the configuration
  list. It covers: why (model-written markdown), a five-line example policy using `images.example.com`, what the
  policy receives, what each answer shows, that every image URL is asked about whatever its scheme, that a blocked
  image copies as shown, and the policy's contract.

- [ ] **Step 8: Run the policy tests, then the whole suite.** `-only-testing:GlimmerTests/GlimmerImagePolicyTests`,
  then `xcodebuild -scheme Glimmer -destination "$DEST" test`. Expected: both pass.

- [ ] **Step 9: Commit**, in two commits: the spec and this plan (`Docs: image-loading policy design and plan`), then
  the code (`Engine: let the host decide which images load`).

---

### Task 2: Ask again before each load

**Files:** create `Embeds/GlimmerImageGate.swift`; modify `GlimmerComposer.swift`, `GlimmerComposer+Inlines.swift`,
`GlimmerInlineImageAttachment.swift`, `GlimmerInlineImageView.swift`, `GlimmerBlockAttachment.swift`,
`GlimmerImageEmbedView.swift`, `GlimmerImageViewLoader.swift`, `GlimmerImageRequest.swift`,
`GlimmerImagePolicyTests.swift`.

**Interfaces — consumes:** `GlimmerComposer.imagePolicy`, the fixtures of Task 1.

**Interfaces — produces:**

- `struct GlimmerImageGate: Sendable { let policy: any GlimmerImagePolicy; let candidate: GlimmerImageCandidate; func permits(_ url: URL) -> Bool }`.
  `permits` asks the policy about the candidate with `url` in place of its own, and is true only for `.load`.
- `struct GlimmerImageRefused: Error {}`, in the same file.
- `GlimmerImageRequest.gate: GlimmerImageGate?` (internal, default `nil`).
- `GlimmerImageViewLoader.init(source:loader:contentMode:gate:)`, `gate` defaulting to `nil`.

- [ ] **Step 1: Write the failing tests.**

```swift
func testARefusingGateNeverCallsTheLoader() async {
    let loader = RecordingLoader()
    let gate = GlimmerImageGate(policy: Answer(answer: .hide), candidate: .init(url: u, alt: "", origin: .markdown))
    let viewLoader = GlimmerImageViewLoader(source: u, loader: loader, contentMode: .aspectFit, gate: gate)
    var result: Result<UIImage, Error>?
    viewLoader.load(size: CGSize(width: 10, height: 10), scale: 2) { result = $0 }
    let finished = await waitUntil { result != nil }
    XCTAssertTrue(finished)
    XCTAssertEqual(loader.requested, [])
}

/// Both image views pass their policy on: an answer that changes after composing still stops the load.
func testThePolicyIsAskedAgainBeforeTheLoad() {
    let state = PolicyState(answer: .load)
    let loader = RecordingLoader()
    let view = GlimmerView(configuration: .init(imageLoader: loader, imagePolicy: Scripted(state: state), reveal: .none))
    view.update(markdown: "Inline ![a](https://a.example/a.png).\n\n![b](https://a.example/b.png)")
    state.answer = .hide                       // composed, but not in a window: no attachment view exists yet
    let window = hostInWindow(view, width: 390, height: 800)
    settle(view)
    XCTAssertEqual(imageAttachments(in: view.textView.textStorage).count, 2)
    XCTAssertEqual(loader.requested, [])
    _ = window
}
```

- [ ] **Step 2: Run them and watch them fail.** Expected: build failure, `GlimmerImageGate` is not defined.

- [ ] **Step 3: Add `GlimmerImageGate`** and thread it to the load site:
  - The composer builds a gate for every image it decides to load under a policy, and none without one.
  - `GlimmerInlineImageAttachment` and `GlimmerInlineImageView` gain `gate: GlimmerImageGate? = nil`.
    `GlimmerBlockAttachment` gains `imageGate: GlimmerImageGate? = nil`, which `appendEmbed` receives and the embed
    view factory hands to `GlimmerImageEmbedView`. Both `freshCopy()` methods keep the gate.
  - `GlimmerImageViewLoader.load` starts with the gate: when it refuses `source`, it completes with
    `.failure(GlimmerImageRefused())` and does nothing else. Otherwise it sets `request.gate`.

- [ ] **Step 4: Run** `GlimmerImagePolicyTests`, `GlimmerImageViewLoaderTests`, `GlimmerInlineImageTests`,
  `GlimmerImageEmbedViewTests`, `GlimmerDocumentCacheTests`. Expected: pass.

- [ ] **Step 5: Commit.** `Engine: ask the image policy again before each load`.

---

### Task 3: Redirects and shared downloads

**Files:** modify `Embeds/GlimmerImageRequest.swift`, `Embeds/GlimmerImageCache.swift`, `ImageTestServer.swift`,
`GlimmerImageCacheTests.swift`, `README.md`.

**Interfaces — consumes:** `GlimmerImageRequest.gate`, `GlimmerImageGate.permits(_:)`, `GlimmerImagePolicyKey`.

**Interfaces — produces:**

- `public func permitsRedirect(to url: URL) -> Bool` on `GlimmerImageRequest`: `true` with no gate.
- `ImageTestServer.setReply(_ reply: Reply, forPath path: String)`: a request whose first line starts
  `GET <path> ` gets that reply, and others the default. Status 302 is written with the reason `Found`.

- [ ] **Step 1: Write the failing tests** in `GlimmerImageCacheTests.swift`.

```swift
private struct AllowPaths: GlimmerImagePolicy {
    var paths: Set<String>
    func decision(for image: GlimmerImageCandidate) -> GlimmerImageDecision { paths.contains(image.url.path()) ? .load : .hide }
}
private func request(_ url: URL, policy: (any GlimmerImagePolicy)?) -> GlimmerImageRequest   // sets `gate` from the policy
/// `/image.png` → 302 `/hop.png` → 302 `/moved.png` → the PNG. The redirects carry only a `Location` header.
private func redirectingServer(delay: TimeInterval = 0) async throws -> (ImageTestServer, URL)
```

| # | Name | Policy | Assert |
|---|---|---|---|
| 1 | `testARefusedRedirectIsNeverRequested` | `AllowPaths(["/image.png", "/hop.png"])` | the load throws; some request starts `GET /hop.png`; none starts `GET /moved.png` |
| 2 | `testAPermittedRedirectLoads` | all three paths | an image is returned |
| 3 | `testWithNoPolicyARedirectIsFollowed` | `nil` | an image is returned |
| 4 | `testAPolicedRequestDoesNotRideOnAnUnpolicedDownload` | server delay 0.2; start a `nil`-policy load, wait for `requestCount == 1`, then load with `AllowPaths(["/image.png"])` on the same cache | the policed load throws; the unpoliced one returns an image |

- [ ] **Step 2: Run them and watch them fail.** Expected: build failure, `setReply(_:forPath:)` is not defined; after
  adding the server method, tests 1 and 4 fail and 2 and 3 pass.

- [ ] **Step 3: Check redirects in `GlimmerImageCache`.**
  - `downloads` is keyed by `private struct DownloadKey: Hashable, Sendable { let url: URL; let policy: GlimmerImagePolicyKey? }`.
  - With a gate, the download uses `session.data(from:delegate:)` and a private `URLSessionTaskDelegate` whose
    `urlSession(_:task:willPerformHTTPRedirection:newRequest:)` returns `nil` unless
    `request.permitsRedirect(to:)` allows the new URL. The 3xx response then fails the existing status check.
  - With no gate the call stays `session.data(from: request.url)`.

- [ ] **Step 4: Add `permitsRedirect(to:)`** with a doc comment for authors of custom loaders.

- [ ] **Step 5: Extend the README section** with the redirect rule: the built-in loader asks the policy about each
  redirect and a refused one fails the load, leaving the placeholder; a custom loader that follows redirects itself
  must call `permitsRedirect(to:)`, or its redirects are not checked.

- [ ] **Step 6: Run** `GlimmerImageCacheTests`, then the whole suite. Expected: pass. A performance gate that fails
  under load is rerun once the machine is quiet before it is believed.

- [ ] **Step 7: Commit.** `Engine: check redirects against the image policy`.

---

## Not in this plan

Pushing the branch and opening the pull request wait for Willi's word. The PR description then carries what spec §8
lists: every load site and how it consults the policy, the redirect behaviour, and what else loads remote resources
(nothing, per spec §6).

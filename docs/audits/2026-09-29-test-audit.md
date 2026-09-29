# Glimmer repository test audit — 2026-09-29

## Fixes applied

The findings below are the original audit snapshot. The follow-up changes repair all actionable findings and preserve the identified keeper contracts. Validation results are recorded separately below.

| Finding | Resolution |
|---|---|
| Image cancellation fixture | Starts a positive-size laid-out view, requires the loader to enter, then drops the view and checks cancellation. |
| Vacuous single-paragraph stability | Fixtures now stream a completed paragraph plus a growing tail, with independent expected plain text. The helper requires a nonempty compared prefix, worker completion and final settled parity. |
| Open-paragraph token hold-back | Existing shortcode/mention tests now drive GlimmerView across partial/completed tokens and assert actual visible text. |
| Incomplete style comparison | Compares boundaries from both snapshots; the existing color-only control now catches both removed and newly inserted styles. |
| Shallow attachment equality | Round-trip and parity comparisons inspect code, table cells/styles/alignment, images and tokens recursively. Document-only consumers apply returned embed updates before comparing. |
| False-positive negative controls | Two checker controls match only the intended assertion, and were first observed failing against the old helpers. |
| Worker races | Existing tests observe a worker entering preprocessing, hold it while updates/reconfiguration arrive, then release it and check the final result. No production hook added. |
| Table cache self-comparison | Consolidated into independently expected 300→200→300 geometry at the rendered table boundary. Existing performance gate owns speed. |
| Counter-only invalidation | Replaced with a primed same-width short→long content measurement and fresh-view height comparison. |
| Inline-image activation | Existing UI test activates the inline link and checks its own expected URL. |
| Empty benchmark measurement | Benchmark requires more than 60 recorded frames after the measurement interval, before evaluating its device-only hitch ratio. |
| SwiftUI menu wiring | Hosted test checks callback input, returned actions, replacement/removal and reuse of the renderer. |
| Diagnostics OS scope | iOS 27 callback test explicitly skips older runtimes. The earlier report's iOS 26 failure prediction remains unverified. |
| Phrase-start benchmark repeatability | Clears its reveal ID before/after and unwraps a nonempty sample list before reading its median. |
| Grapheme coverage | Exercises forced phrase cuts next to emoji modifiers, ZWJ families, combining marks and flags in streaming/settled modes. |
| No-reveal coverage | Checks complete rendered text and full measured height after worker completion. |
| Overstated names | Spec-corpus tests now say they produce blocks, with explicit smoke-only documentation; custom-loader cache test now names isolation/bypass accurately. |
| Fenced shortcode content | Checks code payload and plain-text copy instead of attachment existence alone. |
| Redundant implementation probes | Removed private class-name inventory, internal key-byte inventory, private color-run probe and duplicate launch/pool warmup checks. Keeper coverage retained; color-run helper/type are private. |
| Pool negative control | Requires successful preparation and confirms the prepared object is actually consumed before checking no replacement. |
| Dead production wrappers | Migrated reveal-store tests to version/owner calls and fence tests to healing; removed the obsolete overloads and store unknown-owner sentinel path. |

The footnote reference-classification test remains: its input classification cases complement the late-definition integration tests, and the audit did not establish that those cases were redundant. README compilation examples, real HTTP caching tests, rendering/viewport architecture checks and timing gates remain intact.

Independent preservation reviews covered the three implementation groups. The OpenClaw-specific `autoreview` and testing scripts are not installed in this Swift repository; local independent reviews and XcodeBuildMCP checks provide the applicable validation instead. The audit and fixes were reviewed before PR preparation.

## Final validation — fixes

All runtime checks below used iPhone 17 Pro Max / iOS 27.0. The screenshot tour is the one intentional opt-in UI skip. Evidence filenames identify local XcodeBuildMCP logs; the logs and result bundles are not checked into the repository.

| Check | Result | Evidence |
|---|---|---|
| Focused repaired suites | 112 passed, 0 failed, 0 skipped | `test_sim_2026-09-29T08-00-14-565Z_pid78737_d09d9aa1.log` |
| Full Debug package suite | 447 passed, 0 failed, 0 skipped | `test_sim_2026-09-29T08-03-08-520Z_pid80583_702dd31e.log` |
| Full demo UI suite | 14 passed, 0 failed, 1 skipped | `test_sim_2026-09-29T08-04-33-556Z_pid81255_b9dd1cea.log` |
| Release performance gates | 10 passed, 0 failed, 0 skipped | `test_sim_2026-09-29T08-11-22-662Z_pid84220_feca0fa3.log` |
| Phrase-start repeat, no relaunch | Both iterations passed (66 measured wakes each; 114 µs and 147 µs medians). Tool summary deduplicates to one test. | `test_sim_2026-09-29T08-43-50-070Z_pid86736_fe3e1a3f.log` |

Controls observed before/against the repairs:

- The new stable-prefix and attachment-payload controls both failed against the original helpers (0 passed, 2 failed).
- The new plain-to-link style-change control failed against the old one-sided style comparison (0 passed, 1 failed).
- Five deliberate production mutations produced six expected test failures: accepting a stale worker result; ignoring text-version measurement invalidation; ignoring table-width cache invalidation; removing image-load deinit cancellation; and disabling extension hold-back (both mentions and emoji failed).
- Every temporarily mutated production file was restored byte for byte before the passing full suite. These mutations are not in the final diff.
- Independent reviewers found and verified repairs for the two additional checker weaknesses; no remaining actionable findings were reported.

The Release device benchmark built, but Xcode could not launch it because the connected iPhone was locked. After waiting for an unlock, the run was canceled; no physical-device performance result is claimed. No iOS 26 simulator runtime was installed, so the diagnostics availability guard is compiled and its iOS 27 path tested, with iOS 26 runtime behavior unverified.

Final scoped code diff: production +6/−16 lines; tests/support +329/−147 lines, plus this report. `git diff --check` passes. The validation above applies to the code changes in this PR.

## Original read-only audit snapshot

Audited commit: `312db48df12163df976eb421b15e9d25971cd2cb`.

Applied the installed [OpenClaw test-audit skill](https://github.com/openclaw/openclaw/blob/main/.agents/skills/test-audit/SKILL.md), using read-only discovery, production-owner and history checks, parallel review lanes, and Glimmer's own iOS validation tools. This is an audit, not a pruning campaign: no production or test changes, commits, pushes, or PRs were made. The only repository addition is this report.

## Scope and result

All **49 test files, 468 test methods, and four Swift support files** were read. These total **7,366 lines**. The CommonMark/GFM fixture loader and fixture routing were inspected; this does not claim an example-by-example conformance adjudication. Reviewed owners include the parser/composer/serializer, streaming/reveal, TextKit/rendering, image pipeline, public UIKit/SwiftUI surfaces, demo and benchmark. Checked root instructions, Package.swift, demo project.yml, generated schemes, relevant callers and git history. No additional scoped AGENTS.md or tracked CI workflows were found.

The strongest findings are assertion/fixture repairs, not grounds for mass deletion:

| Priority | Finding | Evidence |
|---|---|---|
| P1 | Image cancellation fixture never starts loading and currently fails | `GlimmerTextViewTests.swift:134-140`; reproduced on iOS 27.0 |
| P2 | Three single-paragraph streaming-stability tests compare zero stable characters | `EngineTestSupport.swift:217-223`; emoji, mention and inline-image callers |
| P2 | Worker tests do not establish the in-flight race named by their fixtures | `GlimmerDocumentWorkerTests.swift:39-68`; four methods pass, but ordering gap confirmed in source |
| P2 | Table cache test proves deterministic output, not reuse | `GlimmerTableViewTests.swift:182-185` |
| P2 | Replacement measurement test only checks an implementation counter | `GlimmerAccessibilityTests.swift:157-162` |
| P2 | Inline-image UI test does not activate the inline link | `ExamplesUITests.swift:102-107` |
| P2 | Device hitch gate accepts an inactive monitor reporting zero frames | `BenchmarkHitchUITests.swift:24-27` |

Additional improvements and small cleanup candidates are detailed below. Static findings have not been mutation-tested. A passing test is not evidence that the identified missing scenario is covered.

## Validation actually run

XcodeBuildMCP discovered the booted iPhone 17 Pro Max, iOS 27.0, UUID `C7203908-BD02-4B89-90E6-1D041BDDFD46`. Its package test route works with the repository directory as workspace-path:

```sh
xcodebuildmcp simulator test \
  --workspace-path . \
  --scheme Glimmer \
  --simulator-id C7203908-BD02-4B89-90E6-1D041BDDFD46 \
  --extra-args \
    '-only-testing:GlimmerTests/GlimmerTextViewTests/testImageLoadIsCancelledWhenTheViewGoesAway' \
    '-only-testing:GlimmerTests/GlimmerDocumentWorkerTests' \
  --output json
```

Result: **4 passed, 1 failed, 0 skipped**. The four DocumentWorker tests passed. `testImageLoadIsCancelledWhenTheViewGoesAway` failed its start assertion at line 136 and cancellation assertion at line 140, taking 4.284 seconds. This confirms fixture drift: loading now begins after a positive-size layout, but the test never provides one. It does not demonstrate a production cancellation failure.

Result bundle:
`$HOME/Library/Developer/XcodeBuildMCP/workspaces/Glimmer-81d8de8a50cf/result-bundles/test_sim_2026-09-29T07-42-55-718Z_pid70896_34be6d95.xcresult`

Build/test log:
`$HOME/Library/Developer/XcodeBuildMCP/workspaces/Glimmer-81d8de8a50cf/logs/test_sim_2026-09-29T07-42-55-718Z_pid70896_866b82be.log`

The full package suite, UI suite, Release performance gates, physical-device benchmark, and iOS 26 runtime were **not run**. All commands in the lane evidence below are proposed follow-up validation unless explicitly included above. `git diff --check` passed. Production LOC delta: 0. Test/support LOC delta: 0.

## Cross-cutting evidence: vacuous streaming stability

Exact affected tests:

- `GlimmerEmojiShortcodesTests.testShortcodesStreamWithoutMovingShownText`, line 78.
- `GlimmerMentionsTests.testMentionsStreamWithoutMovingShownText`, line 173.
- `GlimmerInlineImageTests.testInlineImagesStreamWithoutMovingShownText`, line 184 (helper call at line 185).

`assertStreamingKeepsShownTextInPlace` compares `ShownText` snapshots. `ShownText.init` sets `stableLength` to the end of the last newline, or zero when there is none. All three fixtures are a single paragraph, and composition removes the final newline. Their stable prefix therefore stays empty, style comparisons have no runs, and there are no stable glyph rectangles to compare. Earlier characters can move or restyle without these tests detecting it. The helper also leaves its wait loop on timeout without asserting worker completion, and never requires final expected content.

Actual proof: these calls exercise the pipeline for crashes, but provide no meaningful stable-prefix assertion in the supplied fixtures. Production path: public `GlimmerView.update` -> document worker -> extension `prepared`/hold-back -> parse/compose -> view edits. Demo and public SwiftUI hosts use the same path. There is no production caller of the test helper itself.

Remaining proof: shortcode and mention hold-back unit tests, inline attachment reuse tests, and multiline `GlimmerStreamStabilityTests` protect narrower or different contracts. They do not replace integration proof that an incomplete inline token never restyles text already shown. The helper's multiline regression suite is valuable and should remain.

History: `3d431db` introduced this helper specifically to protect text before the final paragraph and caught a real stray table-pipe flicker; `2f72cac` added style checks. `834be1e` added shortcode support/stream coverage. The helper's original boundary is deliberate; its reuse with single-paragraph inputs is the mismatch.

Recommendation: retain the three contracts and repair their fixtures/assertions. For committed-paragraph stability, include a completed paragraph and continue streaming afterward, requiring a nonempty observed stable prefix. To protect hold-back within the open paragraph, assert visible text/token styles at critical partial-token transitions, allowing legitimate line reflow. Require worker completion and an independent final-content assertion. No production seam or deletion is needed. Validate EmojiShortcodes, Mentions, InlineImage and StreamStability suites, then verify a deliberate hold-back/restyling mutation is caught before claiming the repaired test proves the regression.

## Parser, composition, extension and copy lane

Read all 12 assigned files: 144 methods. Most are retained. Their distinct contracts include C dependency linkage/local patches, independent expected block trees, attributed typography/layout, UTF-16 boundaries, extension scanning and hosting, footnote ordering, copy serialization and actual named-pasteboard writes.

### Limited conformance oracle — retain but clarify or strengthen

`GlimmerConformanceTests.testCommonMarkExamplesNeverLoseContent` (line 5) and `testGFMExtensionExamplesNeverLoseContent` (line 11) call `assertNoContentLoss` (line 33). It only asserts the top-level parsed array is nonempty when fixture HTML is nonempty. Dropping words or nested children while retaining one block still passes. `testEveryNodeKindIsReachable` checks aggregate node-kind reachability, not each fixture's output. Thus this suite is parser smoke/reachability coverage, not proof of full content preservation or CommonMark conformance.

Production owner: `GlimmerParser.parse/parseWithLines`, called by settled/streaming composition; the adapter maps vendored cmark nodes into Glimmer's immutable tree. Read the adapter and local vendoring changes. History: `3eb5a72` introduced spec fixture runs; later footnote changes updated kind reachability. Stronger limited proof is in the 18 independent expected-value Parser tests and downstream composer cases, but they do not validate all spec examples.

Recommendation: preserve fixture execution; name its limited guarantee accurately or add independent per-example semantic expectations/normalized node content while accounting for intentional HTML and footnote differences. Do not treat nonempty output as conformance. No production deletion unlocked. Focused validation: GlimmerConformanceTests and GlimmerParserTests. This is a coverage limitation, not a claim the parser currently drops content.

### Additional precise improvements

- `GlimmerEmojiShortcodesTests.testShortcodesSkipCode` line 39 checks the inline-code literal independently, but the fenced-code half only checks for an attachment character. Inspect the code payload/plain-text copy to prove `:rocket:` survives inside the fence. `GlimmerComposer` sends fenced code directly to highlighting/embed creation; the existing assertion does not distinguish transformed contents. Keep the contract and strengthen the same case; no new production hook.
- `EngineTestSupport.assertEquivalent` lines 55-84 compares attachment classes, not attachment payloads. Surrounding `.glimmerSource` comparisons already catch many source changes, so this is not a wholesale invalidation of round-trip tests. It can miss payload-only differences with unchanged metadata, such as corrupted composed table cell attributes. Keep differential/round-trip tests; compare embed semantics where that is the claimed contract or rely on explicit owner tests that inspect cells/code/image fields.
- `GlimmerFootnoteTests.testAFootnoteDefinitionTurnsOnFullReparses` directly checks the reference-definition predicate. Real late-definition, numbering and smooth-reveal tests provide important integration proof. Consolidation is possible only if those retain the input-classification cases; no automatic deletion recommendation.

### Retained apparent false positives

- Full composition versus block composition is a real incremental composition boundary: streaming uses individual blocks and requires terminators/first-block spacing to agree with settled composition. Preserve it despite shared helpers.
- Compose -> serialize -> compose equivalence is the repository's explicit copy contract, supplemented by exact expected markdown, plain text and named-pasteboard output. It is not merely invoking one function twice.
- CMarkLinkTests independently guard module/linkage, extension registration and the locally patched escaped-text flag. Vendored dependency behavior and shipping patches justify these small low-level tests.
- Emoji table count/sentinel entries check resource packaging and completeness, not a copied whole inventory. The throwing loader is called by real table initialization; it is not test-only dead code.
- Mention drawing checks actual pixels with a positive and negative control, protecting UIKit's link restyling behavior. Typed token callbacks and native UI routes remain distinct boundaries.

| File | Methods | Disposition |
|---|---:|---|
| CMarkLinkTests.swift | 3 | Retain dependency/linkage/local-patch contracts |
| GlimmerParserTests.swift | 18 | Retain independently expected parse structure/regressions |
| GlimmerConformanceTests.swift | 3 | Retain smoke/reachability; clarify limited oracle |
| GlimmerComposerTests.swift | 35 | Retain typography, structure, nesting, source and break regressions |
| GlimmerComposerBlockTests.swift | 6 | Retain incremental boundary, numbering and spacing contracts |
| GlimmerCodeHighlightingTests.swift | 3 | Retain thread placement and independently expected recoloring |
| GlimmerEmojiShortcodesTests.swift | 12 | Repair single-paragraph stability; strengthen fenced payload assertion |
| GlimmerExtensionTests.swift | 6 | Retain token hosting/style/Unicode integration |
| GlimmerFootnoteTests.swift | 16 | Retain numbering, late definition, copy and reveal lifecycle |
| GlimmerMentionsTests.swift | 15 | Repair single-paragraph stability; retain scan, pixels and callbacks |
| GlimmerInteractionTests.swift | 8 | Retain actual copy/menu/selection/configuration contracts |
| GlimmerMarkdownSerializerTests.swift | 19 | Retain exact output and round-trip contract |

Support files reviewed: EngineTestSupport.swift (263 lines), ImageTestServer.swift (90), SpecExamples.swift (52), StreamingFixtures.swift (58). The HTTP server delivers real loopback responses; it does not replace URLSession caching with a mock implementation. ManualRevealClock is an appropriate deterministic clock, and threadCPUTime measures actual calling-thread work. Broad fixed waits are possible flake/latency improvements but not independent grounds to delete behavioral tests.

## Suggested follow-up order

1. Repair the confirmed image lifecycle fixture; preserve the cancellation assertion.
2. Repair vacuous stability, worker race, measurement and UI/benchmark assertions using current public/protocol boundaries. Demonstrate each claimed regression with a failing control.
3. Consolidate literal/class inventories and redundant smoke/helper probes only after their named keepers pass.
4. Migrate retained cases off the two obsolete production wrappers before removing those wrappers.
5. Verify iOS 26 diagnostics behavior and repeatability of the phrase-start benchmark. Run appropriate complete simulator/UI/Release/device gates after actual changes.

The following lane reports retain detailed candidate evidence, history, non-test callers, keeper coverage, deletion scope and proposed validation. Their read-only runtime disclaimers describe each lane; the parent run above supersedes the image-cancellation prediction.


---

## Rendering and image lane — detailed evidence

Scope: 15 complete test files / 161 `test...` methods, HEAD 312db48. Read root AGENTS.md and installed test-audit skill; no nested AGENTS found. Read all assigned test bodies and their embed/render owners, image pipeline, pool, native table cell handling, support helpers; checked production call sites, overlapping tests, and git history for candidates. No source/test edits and no runtime tests. No checked-in `.github/workflows` directory: Package.swift discovers the package target; project.yml routes the demo UI/device targets. iOS-only simulator validation is required; macOS swift test is inappropriate.

## Findings (high confidence)

### 1. Repair the stale cancellation fixture (P1; parent run confirmed failure)
- Exact test: `GlimmerTextViewTests.testImageLoadIsCancelledWhenTheViewGoesAway`, Tests/GlimmerTests/Engine/GlimmerTextViewTests.swift:131-140 (problem setup at 134-136).
- It creates a zero-frame image view and waits for its loader to start, without giving it bounds or a layout pass. Since 312db48, GlimmerImageEmbedView starts loading only in layoutSubviews (Sources/Glimmer/Engine/Embeds/GlimmerImageEmbedView.swift:85-89), and GlimmerImageViewLoader.load rejects zero dimensions (:18-20). Static evidence therefore predicts two failed waits and no cancellation exercised, even with correct product behavior.
- Actual detection: previously cancellation on view release; now only an obsolete eager-loading assumption. Credible missed regression: removing `GlimmerImageViewLoader`'s deinit cancellation cannot be distinguished because this fixture never creates a task.
- Production entry/callers: GlimmerView composition -> GlimmerBlockAttachment.embedView -> factory -> image attachment view, UIKit layout -> size-aware loader. Inline images also own the same coordinator.
- Stronger remaining proof: ImageViewLoaderTests covers cancelling an older size; ImageCacheTests covers consumer/cache cancellation. Neither proves view deallocation cancels the task. Keep this lifecycle contract and fix setup, do not delete it.
- History: introduced 59f4a8f1, “keep embed and chip views across layout passes and cancel dropped image loads”; invalidated by 312db48, “cache images and configure inline image shapes,” which explicitly removes init-started task and moves loading to layout. HEAD's commit states 140 Debug/30 Release tests, not full-suite proof.
- Recommendation: assign positive frame/bounds, call layoutIfNeeded, require successful start, then release it and assert cancellation. Validate on current baseline first to distinguish fixture drift from an owner lifetime bug.
- Deletion unlocked: none; retain SuspendingImageLoader and production cancellation.
- Validation: `xcodebuild -scheme Glimmer -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0' test -only-testing:GlimmerTests/GlimmerTextViewTests/testImageLoadIsCancelledWhenTheViewGoesAway -only-testing:GlimmerTests/GlimmerImageViewLoaderTests`.

### 2. The table cache test does not prove caching (P2)
- Exact test: `GlimmerTableViewTests.testLayoutIsCachedPerWidth`, Tests/GlimmerTests/Engine/GlimmerTableViewTests.swift:182-185.
- `XCTAssertEqual(table.layout(forWidth: 300), table.layout(forWidth: 300))` is a deterministic self-comparison. Removing cachedLayout, naturalRowWidths and measuredRows and recomputing every query would still pass. The second assertion only proves a one-column table differs at widths 300 and 200.
- Production entry/callers: GlimmerTableView.layout drives embedHeight, revealUnitRects and layoutSubviews (owner lines 198-244). Actual caching is private and needed for repeated TextKit measurements.
- Stronger proof: `testShortTableFillsTheWidth` checks expected 300 pt; `testIncrementalLayoutMatchesAFreshTable` checks cache invalidation after a row widens columns; `GlimmerStreamingPerformanceTests.testStreamingALongTableStaysWithinBudget` owns per-row main-thread cost. Existing performance test does not specifically guarantee identical-width hit cost, so do not claim full cache-hit coverage.
- History: a1f6414b added table embed and cached layout, with this original test; f3eecd3 subsequently added incremental row caches and stronger update proof.
- Recommendation: remove the self-equality assertion and consolidate meaningful width invalidation into the short-table case (wide -> narrow -> wide, independently expected widths/geometry). Let the existing table performance contract own speed unless a distinct measured repeated-query regression is demonstrated.
- Deletion unlocked: this test method only; no table cache code is dead.
- Risk/validation: preserve width invalidation coverage, run GlimmerTableViewTests and the Release streaming-table performance gate.

### 3. The measurement-invalidation regression only observes its implementation counter (P2)
- Exact test: `GlimmerAccessibilityTests.testReplacingTheTextStillForgetsWhatWasMeasured`, Tests/GlimmerTests/Engine/GlimmerAccessibilityTests.swift:157-162.
- It does not measure anything before or after replaceText; it only requires `textVersion` to change. A regression ignoring the version when returning fittedSize would pass. A behavior-preserving change that clears caches directly would fail.
- Production entry/callers: GlimmerTextView.replaceText -> setText increments textVersion; sizeThatFits caches `(version,width,height)` (:169-177). GlimmerView uses replaceText for cached configure, worker handoff and full replacement (:435,447,466) and uses textVersion for content height/reveal caches. Counter has real production consumers; never delete it merely to remove test coupling.
- Stronger proof: view width/reveal-height tests and DocumentCacheTests.testCachedHeightMatchesAMeasuredOne test adjacent contracts, not replacement after a populated same-width fittedSize cache. Rewrite this contract instead of deleting.
- History: b9c01f0c removed the main-actor attributedText override to prevent UIKit accessibility trapping on background reads; this test guarded explicit replacement invalidation after that change.
- Recommendation: put a short document through the real replacement path, query its height to prime the cache, replace with a multi-line document at the same width, and assert new height matches a fresh view and exceeds the original. Move to TextViewTests with measurement tests.
- Deletion unlocked: counter assertion/method relocation only; no production removal.
- Risk/validation: test same-width replacement because a changed width naturally misses the cache; run GlimmerAccessibilityTests and GlimmerTextViewTests.

### 4. Delete/consolidate the class-name factory inventory (P3)
- Exact test: `GlimmerTextViewTests.testFactoryBuildsEveryEmbedKind`, Tests/GlimmerTests/Engine/GlimmerTextViewTests.swift:67-79.
- Asserts four private concrete class names copied from a switch. Renaming any embed view breaks it without changing behavior. It can detect only incorrect class selection, not usable layout, content, or interaction.
- Production callers: GlimmerBlockAttachment.embedView calls GlimmerEmbedViewFactory.makeView, reached by NSTextAttachmentViewProvider.loadView. Factory remains production code.
- Stronger remaining owner-boundary proof: TextViewTests.testCodeBlockAttachmentHostsAFullWidthView; TextViewTests.testEmbedsResizeWhenWidthChanges (rule); EmbedStreamingTests.testStreamingTableKeepsItsView and TableViewTests.testTableLinkActionsReachTheHostAndKeepNativeFallback; ImageTapTests.testTappingAStandaloneImageCallsOnImageTap and TextViewTests.testEmbedViewsSurviveHeightQueriesAndFrameChanges (image). All reach the actual factory through attachment rendering and assert behavior.
- History: 61ad68ef introduced the TextKit 2 view and view-backed attachments; it was an early smoke inventory before later integration coverage.
- Recommendation: delete this inventory, retaining actual per-kind rendering/interaction proof.
- Deletion unlocked: 14 test lines; no factory/helper deletion (real production caller).
- Risk/validation: low; run TextViewTests, EmbedStreamingTests and ImageTapTests.

### 5. Consolidate a private color-run helper probe into existing streaming proof (P3)
- Exact test: `GlimmerCodeBlockViewTests.testColorRunsDescribeTheHighlight`, Tests/GlimmerTests/Engine/GlimmerCodeBlockViewTests.swift:199-205.
- Asserts only first run starts at zero, run lengths sum to total, and a comment color exists. It does not validate actual ranges or show that changed earlier lines redraw; can pass with wrongly partitioned/ordered runs.
- Production callers: GlimmerCodeBlockView init and update call colorRuns (owner :80,:222) to find the earliest changed line. Helper remains necessary production code, but only this test calls it externally.
- Stronger remaining owner proof: `testStreamedCodeMatchesAFreshHighlightAtEveryStep` exercises real incremental color-run diff for Swift and plain text at every 3-character prefix; `testStreamedCodeThatShrinksOrChangesLanguageMatchesAFreshHighlight` covers shrinking/language replacement; GlimmerCodeHighlightingTests.testAClosingCommentRecolorsEarlierLines goes through GlimmerView and independently checks comment/keyword colors. These compare final text-storage state, not run representation.
- History: f9a7bcf5 introduced color-run optimization and this probe alongside per-step parity, explicitly to reduce long-code apply p95 (1.96 -> 1.26 ms). 95355618 later expanded shrink/language regression coverage.
- Recommendation: delete this lower-value helper probe after confirming owner tests; make colorRuns/ColorRun private if no other callers remain. Preserve streaming/fresh parity: it has a distinct incremental-edit implementation under test and is not a self-comparison.
- Deletion unlocked: 8 test lines and narrowed helper/type access; no production algorithm deletion.
- Risk/validation: low; run GlimmerCodeBlockViewTests and GlimmerCodeHighlightingTests; Release long-code performance gate if production algorithm changes (none proposed).

## Minor consolidation / keep rather than over-prune

- EmbedViewPoolTests.testAStreamingViewPreparesACodeBlockView (:13) repeats the successful warmup assertion already required by testAStreamedCodeBlockTakesThePreparedView (:22); can fold the first into the second. Real pooling/lifecycle guards remain valuable. `testTakingOutsideAStreamPreparesNoReplacement` (:46) discards warmup success at :51; require it (and ideally verify the prepared view was consumed) so disabled prep cannot make the negative control vacuous. Introduced by a0f7494 to avoid unnecessary replacements for settled answers; actual caller is factory takeCodeBlockView, GlimmerView triggers preparation. No production deletion from this consolidation; hasCodeBlockView/peekCodeBlockView still support other distinct tests. Focused suite: GlimmerEmbedViewPoolTests.
- Do not call `testStreamedCodeMatchesAFreshHighlightAtEveryStep` a mocked result test: provided attributed text is the input to an incremental TextKit update. Detecting wrong diff location/failed prefix replacement is independent from correctness of highlighting that input.
- Do not delete image identity assertions: shared UIImage identity plus real loopback HTTP counts prove actual request/preparation sharing and cache freshness. They are meaningful cache/performance contracts, not identity copiers.
- Preserve off-main-thread accessibility tests and compiled localization-key checks. They guard Swift isolation traps and translated resource packaging. XCUITest remains the stronger VoiceOver runtime route, but cannot replace all targeted off-main reads.
- Preserve SurfaceReuse/VisibleBand internals-oriented probes: UIKit platform contracts include not redrawing retained surfaces, avoiding stale pixels, limiting first render, passing real screen bands through nested scrollers, and releasing display links. Histories include fbab023 (new text inked under reuse), 2c5950e (preload link released with window), 6c50dba (quote bars end at text). Known fragile platform details deserve explicit OS routing rather than deletion.
- Test-only diagnostic readers/counters identified: GlimmerEmbedViewPool.hasCodeBlockView/peekCodeBlockView; GlimmerTextView.preloadLinksCreated/screenFirstRenders. They do not alone justify deletion of underlying product behavior. Prefer observable pooling/viewport work before removing seams. `viewportPasses` has production GlimmerDiagnostics use via the global aggregate.

## Per-file inventory

| File prefix `Tests/GlimmerTests/Engine/Glimmer` | Test count | Conclusion |
| --- | ---: | --- |
| AccessibilityTests.swift | 16 | Retain platform/VO/localization contracts; rewrite counter-only replacement measurement test. |
| CodeBlockViewTests.swift | 18 | Retain token, copy/reveal, incremental parity; consolidate colorRuns helper probe. |
| EmbedStreamingTests.swift | 5 | Retain all; real host streaming identity, geometry, reveal, resized settlement. |
| EmbedViewPoolTests.swift | 5 | Retain lifecycle/performance contract; consolidate duplicate preparation test and require warmup in negative control. |
| ImageCacheTests.swift | 16 | Retain all; real HTTP/decode/cache/cancellation/perf boundaries. |
| ImageEmbedViewTests.swift | 4 | Retain all; loading/failure, no-loader, fixed/capped height are independent product contracts. |
| ImageTapTests.swift | 9 | Retain all; host callbacks, internal links, linked-image suppression, thread-safe traits, plainText API. |
| ImageViewLoaderTests.swift | 4 | Retain all; sizing, request coalescing/growth, stale result rejection. |
| InlineImageTests.swift | 14 | Retain geometry, public shape/default/traits, source copying and isolation; repair single-paragraph stability as described above. |
| LayoutFragmentTests.swift | 7 | Retain geometry and fragment provider contract; quote endings/nesting/negative decorations have distinct cases. |
| SurfaceReuseTests.swift | 9 | Retain all; real UIKit rendered pixels/redraw/lifecycle guards. |
| TableViewTests.swift | 16 | Retain geometry/link/AX/streaming cases; rewrite/consolidate misleading cache self-comparison. |
| TextViewTests.swift | 11 | Repair zero-frame cancellation fixture; delete class-name inventory; retain TK2/container/measurement/embed lifetime contracts. |
| TextViewEditTests.swift | 5 | Retain all; incremental text-layout preservation and geometry regressions. |
| VisibleBandTests.swift | 22 | Retain platform/perf contracts; no high-confidence deletions. |

Validation actually run: read-only rg/cat/sed/git log/git blame/git show. Runtime pass/fail claims are not made. Suggested commands are follow-up validation, not results. Production/test LOC changed: 0/0. No PR/commit/merge.


---

## Streaming and reveal lane — detailed evidence

Reviewed 13 complete test files (117 test methods; 1,797 lines), full production Stream/Reveal owners and GlimmerView, shared support and fixtures, Package.swift and demo device test routing, relevant git history. No edits to repository, runtime tests, mutation tests, or simulator checks. No scoped AGENTS.md found. Package routes these into GlimmerTests; StreamingPerformance also compiles into GlimmerDevicePerfTests. No .github directory.

## High-confidence findings

### P2: worker race regression fixture never starts the worker
- Exact test: Tests/GlimmerTests/Engine/GlimmerDocumentWorkerTests.swift:58-68, testRebuildWhileComposingNeverAppliesStaleText. Companion: testLatestUpdateWinsWhenUpdatesArriveFasterThanTheWorker, lines 39-54.
- Actual detection: synchronous reconfiguration preserves text/font; companion detects batching multiple calls before queued work starts. Neither establishes an in-flight old worker.
- Why: @MainActor test queues the MainActor Task at GlimmerView.swift:112, then changes configuration without suspension. composeSynchronously sets appliedUpdate=requestedUpdate (line 444). First await is test line 65. When drainDocumentUpdates finally runs, its while condition (line 453) is false. Therefore removing stale-worker guards at GlimmerView.swift:458/464 would not fail this test. Companion queues all six updates before first await, so worker only begins with final value.
- Non-test callers: public GlimmerView.update, configuration didSet/rebuildDocument, drainDocumentUpdates; GlimmerText and demo hosts exercise these entry points.
- Stronger proof: no other found test deliberately holds an old compose in flight across rebuild. Retain coverage and repair fixture, using a test-owned GlimmerExtension/preprocess gate to observe worker entry, enqueue rebuild/updates while old work is held, then release it. Avoid new production hooks. Verify the stale-guard mutation fails.
- History: both tests introduced unchanged by 3efc39d (2026-09-26), whose commit explicitly promises coalescing while a request is in flight and dropping stale rebuild results.
- Deletion unlocked: none; this is a missing-real-race fix, not removal.
- Risk/validation: medium concurrency risk; xcodebuild -scheme Glimmer -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0' test -only-testing:GlimmerTests/GlimmerDocumentWorkerTests -only-testing:GlimmerTests/GlimmerViewStreamingTests.

### P3: two legacy convenience entry points are kept alive only by tests
- Exact tests: GlimmerRevealStoreTests.testStoreIsMonotonicAndBounded (8-16), testRegeneratedAnswerUnderTheSameIDStartsOver (18-28), and GlimmerTailHealerTests.testOpenFenceDetection (60-64).
- Production seams: GlimmerRevealStore.swift:31-34 record(_:text:for:) forwards version=-1/owner=nil. Every non-test record call is GlimmerView.swift:315-318 and passes real version+owner. GlimmerTailHealer.swift:63-68 openFence(in:) has only three test calls; production healer uses private openFence(in:scan:) at line 28. Complete-repo Swift reference search confirms.
- Actual proof: store tests protect valuable monotonic progress, bounded eviction and regeneration, but through a fallback never used by production; openFence test independently checks four-backtick opener, closed fence, and non-fence classification through obsolete wrapper.
- Stronger proof/recommendation: retain store contracts against the version/owner entry point (cover both same version and new versions); retain fence inputs as heal/incremental document cases. Existing same-version and cross-owner tests at RevealStoreTests:30,49, ViewStreamingTests.testRevealIDResumesWithoutReplaying:87, tail table and StreamParity provide additional coverage but do NOT justify simply deleting all distinct cases.
- History: c45cb95 added version-aware record for phrase-start performance but retained old convenience method; f9883c8 and de460be added owner/serial correctness. openFence originally production-used (a0e731f / Plan 2), then 4870f26 introduced incremental FenceScan and bypassed convenience wrapper.
- Deletion unlocked: old store overload and optional/unknown-owner sentinel handling after confirming all calls migrated; old openFence convenience wrapper. Do not remove real store or fence algorithm.
- Risk/validation: low-to-medium; focused RevealStore, TailHealer, StreamingDocument, StreamParity, ViewStreaming suites and phrase-start performance test after store simplification.

## Lower-priority fixture observations (not deletion candidates)
- GlimmerDocumentCacheTests.testCachedAttachmentsUseTheCurrentLoaderInstance:50 uses RecordingImageLoader. GlimmerDocumentCache.supports rejects all custom loaders (production lines 22-27), so no cache is populated or hit. This is STILL valuable: removing the supports guard would cache first loader and fail the test. Rename to custom-loader isolation/bypass; do not discard as a no-op or demand a cache hit. History 10f8f52 explicitly fixed custom dependency isolation.
- GlimmerViewStreamingTests.testNoRevealShowsTextImmediately:75-85 only asserts nil mask and engine; it never asserts text or nonzero/full height. Strengthen that existing test to verify content at worker completion. Other no-reveal view/worker tests protect rendering, so this is not a standalone high-priority finding.
- GlimmerPhraseChunkerTests.testNeverSplitsGraphemes:44-47 puts emoji at start and only checks full end of a four-word nonstreaming input. This protects UTF-16 end offsets, not forced cuts near graphemes. Current linguistic tests have boundary checks but many inspect only first cut. Improve fixtures at actual candidate boundaries rather than deleting language coverage.
- GlimmerStreamingPerformanceTests.testPhraseStartsStayCheap:223 uses shared reveal ID phrase-starts without clearing, and indexes samples at 235 before nonempty/count assertion at 237. Same-process repetition resumes progress left by previous run, so samples may be insufficient/empty and can crash before useful assertion. Clear ID in setup/defer and guard samples before indexing. Static finding, not runtime reproduced.
- Parent owns shared stability helper finding: single-paragraph inputs compare zero stable characters. StreamStability fixtures are all multiline and do compare committed text; retain this suite and its helper positive controls. Broader helper still silently accepts worker timeout (no completion assertion).

## Retained false positives
- Fresh full parse/compose as oracle against incremental document is valid differential proof of incremental edits, not self-comparison. StreamingDocument.testEveryPrefix also applies edits independently to a mirror; StreamParity broadens corpus and checks pixels through real view, so these are distinct risks.
- Pacing equations/defaults are a specified timing contract, and engine/unit tests plus view integration protect distinct orchestration paths. Mask layer/fade assertions enforce actual Core Animation rendering/continuity contracts. Do not remove for touching internal state.
- Performance tests protect explicit shipping budgets and measured historical regressions. Static timing, legitimate retries, and diagnostics are not deletion reasons. Keep main-thread CPU measurement and device routing.
- Cache attachment identity tests enforce independent ownership; weak lifetime tests guard retention. Stateful extensions/highlighters protect configuration isolation. Keep.
- RevealStore serial uniqueness guards a documented reused-address regression (de460be); retain.

## Complete inventory
| File prefix (all Glimmer*Tests.swift) | Methods | Conclusion |
|---|---:|---|
| DocumentCache | 10 | Retain cache/isolation/lifetime contracts; misleading custom-loader test name only |
| DocumentWorker | 4 | Retain; repair two purported in-flight fixtures |
| Pacing | 7 | Retain timing/default/drain contracts |
| PhraseChunker | 18 | Retain boundaries/international regressions; strengthen grapheme fixture |
| RevealEngine | 14 | Retain schedule/settlement/embed lifecycle contracts |
| RevealMask | 7 | Retain actual CA geometry/fade/invalidation contracts |
| RevealStore | 5 | Retain contracts; retire test-only legacy record overload |
| StreamParity | 4 | Retain incremental oracle and independent pixel/view proof |
| StreamStability | 3 | Retain multiline corpus/helper positive controls; see parent helper gap |
| StreamingDocument | 15 | Retain edit mirror, reuse, separator/reference and finalization regressions |
| StreamingPerformance | 10 | Retain measured gates; isolate shared phrase-start ID and empty samples |
| TailHealer | 8 | Retain healing cases; move openFence cases to healing boundary and remove wrapper |
| ViewStreaming | 12 | Retain view integration/reveal/clock lifecycle; strengthen none content assertion |

Read-only LOC delta: production 0, tests/support 0. No PR or commit created.


---

## Demo and public surface lane — detailed evidence

Read-only; no source/test changes, no runtime tests. Read test-audit/SKILL.md and root AGENTS.md. No scoped AGENTS.md found. Complete assigned test files read: 9 files, 46 test methods, 742 lines. Production owners read include GlimmerView, GlimmerText, GlimmerTheme/attribute keys/diagnostics, FrameMonitor/FrameHitchCounter/BenchmarkDemo, app launch/navigation/gallery, image and reveal demo, plus relevant interaction/menu/image/compose/serializer overlap and example tab/export paths. Git histories inspected.

## Findings to repair

1. **P2 — inline-image UI test promises activation but never performs it.** `Examples/GlimmerDemo/UITests/ExamplesUITests.swift:102-107`, `testTappingAnImageShowsItsURL` (starts line 92). Actual detection: standalone image tap opens correct URL, inline image is announced once as a link. It cannot detect broken UIKit delegate routing for the inline link because it never taps `inline`. Non-test owner/callers: `TappableImageExample` passes `onImageTap` through `GlimmerText`; `GlimmerView.textView(_:primaryActionFor:defaultAction:)` routes image links to `imageLinkAction` and `tapImageLink`. Existing stronger local proof: `GlimmerImageTapTests.testWithAHandlerAnInlineImagesAltTextIsALinkThatTapsIt` directly calls `tapImageLink`, so it cannot protect native activation routing. Fix the existing UI test to activate inline and assert octocat URL, retaining the uniqueness assertion. History: demo UI test introduced dbf661f; current alt-text accessibility shape originates in 83f1cf1 and later integration. No production/support deletion unlocked. Risk low, UI activation needs live runtime. Validation: `xcodebuild -project Examples/GlimmerDemo/GlimmerDemo.xcodeproj -scheme GlimmerDemo -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0' test -only-testing:GlimmerDemoUITests/ExamplesUITests/testTappingAnImageShowsItsURL`.

2. **P2 — hitch gate accepts a broken monitor with zero frames.** `Examples/GlimmerDemo/UITests/BenchmarkHitchUITests.swift:24-27`, `testStreamingBelowALongAnswerDoesNotHitch`. Actual detection: benchmark summary says done; on device a parseable ratio below 4.5. `FrameHitchCounter.hitchTimeRatio` returns 0 when no first/last ticks exist. Removing display-link registration from `FrameMonitor.start` would produce `done frames=0 ... ratio=0.00ms/s`, accepted by the explicit gate. `XCTHitchMetric` records samples, but no baseline is checked in this repository, so there is no checked-in independent rejection for this instrumentation failure. Non-test callers: BenchmarkDemo and PerformanceDemo each use FrameMonitor; BenchmarkDemo produces summary after streaming/sleeps regardless of recorded frames. Stronger remaining proof: three FrameHitchCounterTests independently verify arithmetic but do not verify registration. Strengthen same UI gate by checking meaningful nonzero frame count/measurement activity after measurement (never add accessibility queries while measuring). History: 52bb1f5 introduced frame monitor/device harness, d703b8f hands-off benchmark; 3075244 and 74d2952 adjusted device gates, 121cf16 records later baseline. No source deletion unlocked. Risk: choose a robust activity condition, not device-specific exact counts. Validate the one benchmark on unlocked physical iPhone in Release per AGENTS.md, using -allowProvisioningUpdates; simulator deliberately has no performance threshold.

3. **Platform follow-up — verify iOS 27 diagnostics expectations on supported iOS 26.** `Tests/GlimmerTests/Engine/GlimmerDiagnosticsTests.swift:8-15`, `testViewportPassesCountEveryTextViewsPasses`. Actual detection: one text view records viewport callbacks and aggregate SPI is at least its count. `GlimmerTextView.swift:424-428` is the only increment and lies inside `@available(iOS 27.0, *) textViewportLayoutControllerWillLayout`. Package.swift and demo target support iOS 26; this test is unconditionally runnable there and requires >0. Static finding, not reproduced. Non-test callers: BenchmarkDemo reads GlimmerDiagnostics.viewportPasses at benchmark start/end; SPI is useful production diagnostics, not test-only. No stronger proof for runtime diagnostics. Keep but gate/assert according to supported runtime contract (iOS26 currently lacks this counter). History 0af32b8 introduced SPI/test and explicitly described iOS26 as compile-verified. No source deletion unlocked. Validate focused diagnostics test on both available iOS26 and iOS27 simulators.

4. **P2 improvement — wrapper menu test checks presence, not delivery or updates.** `Tests/GlimmerTests/Engine/GlimmerTextTests.swift:8-18`, `testMenuHooksReachTheView`. Actual detection: SwiftUI creates GlimmerView and gives both callback fields a non-nil value. Supplying non-nil no-op closures or retaining initial callbacks across a SwiftUI update passes. Non-test callers: EngineGalleryDemo and AdvancedDemo use `GlimmerText.editMenuActions`; public linkMenuActions is wrapper API (no in-repo demo consumer). `GlimmerText.updateUIView` is owner. Stronger lower-level tests `GlimmerInteractionTests.testEditMenuAddsHostActions` and `testLinkMenuKeepsTheDefaultAndAddsHostItems` invoke host callbacks but install them directly on GlimmerView, so cannot cover wrapper update propagation. Extend this existing hosted test to verify selection/URL receipt, returned menu item, and replacement/removal after SwiftUI update, rather than add duplicates at every layer. History 5c0fa25 added wrapper hooks and this test for gallery/export menus. No production deletion unlocked; preserve wrapper regression coverage. Validate GlimmerTextTests plus GlimmerInteractionTests on explicit simulator OS.

## High-confidence consolidation/deletion candidates

5. **P3 — frozen internal key inventory.** `Tests/GlimmerTests/Engine/GlimmerThemeTests.swift:57-68`, `testAttributeKeysAreNamespaced`. Detects changing eleven raw-value strings, including consistent behavior-preserving changes. Keys are internal in `Sources/Glimmer/Engine/Theme/GlimmerAttributeKeys.swift`; production consumers use symbols, no raw-string bridge/persistence/public ABI consumer found. Literal search finds only key definitions, this test, and implementation plans. Stronger retained proof: composer semantic tagging/traits; serializer `testMarkdownRoundTrips`, `testListsAndQuotesComeBackAsMarkdown`, `testEmphasisDelimitersHugTheText`; renderer quote/inline-code and accessibility behavior tests. History ae90ad8 scaffolded theme/keys; 94076ee/895ee04/7d1fbb2 grew inventory along with structure. Plans describe implementation, no external exact-byte contract found. Delete this one test; do not delete production keys, all used. Removes 13 test LOC only, no production/support seam. Risk low; if external untracked raw-key consumers exist reconsider (keys not public). Validate GlimmerThemeTests, GlimmerComposerTests, GlimmerMarkdownSerializerTests, GlimmerLayoutFragmentTests, GlimmerAccessibilityTests.

6. **P3 — duplicate gallery launch smoke.** `Examples/GlimmerDemo/UITests/LaunchUITests.swift:5-10`, `testEngineGalleryOpens`. Detects default gallery launch/title only. Non-test path: GlimmerDemoApp launch-argument route to EngineGalleryDemo. Stronger remaining owner-boundary proof: `testTaskCheckboxesReadTheirState` and `testTheAnswersAccessibilityFrameHugsItsText` each repeat exactly same arguments, launch, and title existence assertion before meaningful live UI checks. History 2c81830 initial UI target smoke; 7d1fbb2 added stronger speech path; 65ed20c added frame check. Delete redundant method only (7 LOC including annotation/spacing); preserve runtime accessibility checks. No production/support deletion. Risk minimal in full LaunchUITests suite, standalone smoke-filter callers outside repo unknown; no in-repo separate routing. Validate LaunchUITests.

## Retained false positives / boundaries

- README examples: keep all five, including four without runtime assertions. `import Glimmer` instead of `@testable` independently checks public usability; f39606c explicitly says README snippets compile against public API alone. Do not claim those methods prove stream completion or visual SwiftUI correctness. Runtime scenarios already have substantive view/reveal tests.
- Theme defaults/clamping/Dynamic Type tests are public styling/platform contracts; UIFontMetrics comparison is independent platform oracle, not calling Glimmer's own expected-value helper. Seven remain after inventory deletion.
- GlimmerViewTests (15): preserve rendering, zero-height, extension preprocessing, URL wrapping, actual trait propagation, host sizing, streamed frame stability, overflow growth, memory budgets and Auto Layout invalidation. They assert internal frame choices, but comments/history 65ed20c tie architecture directly to measured resize hitches; performance/memory invariants are legitimate. `textViewHeight` is mutable only for overflow test, but removing it without equivalent feasible overflow proof is not justified in this audit.
- FrameHitchCounterTests (3) are independent metric arithmetic/platform contracts and test actual shared code compiled into app and UI-test target. They are not mocks of observed behavior.
- Diagnostics SPI has an actual app caller; retain after availability repair.
- Screenshot tour is opt-in manual review evidence, not automated pixel validation. Keep; current static ID/section manifest legitimately drives known screens but requires maintenance as demos grow.
- Table-link UI test overlaps unit table tests on purpose: validates native touch/accessibility routing in light/dark/large text; unit helper invocations cannot substitute.
- Launch dark/background pixel test has actual regression history 28dd0ee and checks rendered screen; don't remove because screenshot-based. It sets launch state rather than physically toggling Dark, so description should not be overread as toggle-control coverage.

## File inventory and disposition

| File | Test methods | Disposition |
|---|---:|---|
| BenchmarkHitchUITests.swift | 1 | Retain, repair measurement validity check |
| ExamplesUITests.swift | 8 | Retain, repair inline activation; screenshot tour explicitly manual |
| FrameHitchCounterTests.swift | 3 | Retain independent metric arithmetic |
| LaunchUITests.swift | 4 | Consolidate away 1 launch-only duplicate; retain 3 runtime regressions |
| GlimmerReadmeExampleTests.swift | 5 | Retain public API compile contract |
| GlimmerTextTests.swift | 1 | Retain, improve delivery/update proof |
| GlimmerViewTests.swift | 15 | Retain behavior/architecture/platform contracts |
| GlimmerDiagnosticsTests.swift | 1 | Retain, repair iOS availability |
| GlimmerThemeTests.swift | 8 | Retain 7; delete 1 internal literal inventory |

## Routing and execution limits

Package.swift includes all Tests/GlimmerTests by implicit target source discovery with fixtures resources; explicit iOS minimum 26. Demo project.yml includes UITests and Shared in GlimmerDemoUITests, and generated GlimmerDemo.xcscheme selects this target in Debug with parallelizable=NO. GlimmerDevicePerfTests compiles only GlimmerStreamingPerformanceTests plus EngineTestSupport and StreamingFixtures, hosted in demo; its scheme selects Release. UI hitch test is in GlimmerDemo scheme, not device-performance unit scheme. No tracked .github/CI workflows or xctestplans found; git ls-files yml/yaml returns only demo project.yml. No test execution or mutation proof claimed. Production/test LOC changed: 0/0; no commits or PRs.

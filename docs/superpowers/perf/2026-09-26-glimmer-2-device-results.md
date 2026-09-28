# Glimmer 2.0 — device performance results

Measured on "WW 16", an iPhone 16 Pro Max on iOS 27.0 (24A435), in Release. The newest results come first: Plan 6b,
then Plan 6, then Plan 5.

## Plan 8

Plan 8 gave each code block its own scroll tracking, so a block taller than the screen renders the lines on screen as
it scrolls. The flick benchmark on WW 16 (iPhone 16 Pro Max, Release, 120 Hz, Sept 27) stays inside Plan 6b's range:

| Run | Frames | Hitches (frame monitor) | Worst interval | Ratio (frame monitor) | XCTHitchMetric |
|---|---|---|---|---|---|
| 1 | 2,109 | 5 | 19.2 ms | 2.46 ms/s | 6.86 ms/s |
| 2 | 2,137 | 6 | 26.0 ms | 3.31 ms/s | 2.60 ms/s |

A first run at 1,066 frames was at 60 Hz (Low Power Mode) and is left out.

## Plan 6b

Measured on 2026-09-26. Every run is the flick benchmark launched hands-off, alternating builds.

| Metric | Goal | Plan 6 | Plan 6b | Result |
|---|---|---|---|---|
| Hitch-time ratio | addendum: ≤ 1 ms/s | 5.9, 10.0, 5.3 ms/s | 2.8, 2.7, 1.9 ms/s (1.9–3.5 over seven runs) | better, not met |
| Hitches per run | spec: 0 | 10–19 | 3–8 | better |
| Worst frame gap | — | 23–25 ms | 17–25 ms | — |
| Main thread per streamed code block update, rest of the frame, p95 | — | 5.0 ms | 2.9 ms | better |
| Reveal work per frame | spec: ~0 | 0.17 ms | 0.15 ms | — |
| Cached configure | spec: ≤ 4 ms | 21.3 ms | 20.3 ms | miss |

What each change moved:
- **Reusing the fragment views UIKit already drew.**
  - On iOS 27, UIKit asks the text view for a cached rendering surface for every fragment on every viewport pass.
    WWDC26's TextKit session recommends keying those surfaces by `NSTextLayoutFragment`.
  - Handing back the view already drawn for the same fragment skips UIKit's redraw. The fragment's size and its
    rendering attributes (UIKit's link and find tints) must also be unchanged.
  - Before, every pass redrew every fragment in the band. On the simulator, redraws of already-drawn fragments fell
    from about 8,000 to about 870 per run.
  - `GlimmerConfiguration.reusesDrawnText` turns it off.
- **One viewport pass per band move.** Calling `layoutViewport()` ran one pass at once and UIKit's canvas ran another
  in the commit. The band now marks the canvas for layout instead. The canvas is the superview of the surfaces UIKit
  hands over.
- **Laying out ahead of the band in idle frames.** For up to 2 ms a frame, 1.5 screens ahead in the scroll direction
  and 0.5 behind, as Texture's preload range does. The flick's return no longer lays text out in the frame it
  arrives: its hitch slices went from 16–18 ms to 3–6 ms.
- **A prepared code block view.** While an answer streams, one code block view is built and laid out once on an idle
  turn. The next fence takes it: 0.3–0.9 ms on the device, against 4.3–10 ms fresh.
- **Two options were tried and rejected:**
  - half-screen band steps: 4.1–5.6 ms/s, against 2.2–3.5 interleaved;
  - `drawsAsynchronously` on the fragment views: 3.7–8.0 ms/s.
- **iOS 26 floor.** The iOS 27 hooks are declared by Objective-C selector, so the package builds for iOS 26. iOS 26
  never calls them.

### What's left

A throwaway probe on this build attributed the remaining hitches. They fall almost all in frames that apply a streamed
update, not in the flick.
- **Glimmer's apply:** 1.5–3.5 ms, including the reveal's height report.
- **Five to seven milliseconds outside Glimmer's code.** Most likely SwiftUI re-laying out the scroll view's content as
  the answer grows, then Core Animation's commit.
- **Two viewport passes for the streaming answer.** UIKit resizes the answer's canvas to the new text between them.
  Each pass costs about 2 ms.

The next steps these point to:
- Report height changes to SwiftUI at most once per frame while streaming.
- Keep the canvas from resizing on every update, for example by growing it in larger steps.
- Profile the unattributed part with Instruments on the device.

### Gates

- The device benchmark gate moves from 8 to 4.5 ms/s: the worst of seven rested runs (3.5) plus 0.5, rounded up to
  the next half.
- `GlimmerDevicePerf` passes on the device with its gates unchanged.

## Plan 6

Measured on 2026-09-26, the same device and build configuration. "Before" is Plan 5's device run, or where marked, the
same benchmark run in the same session on Plan 5's engine.

| Metric | Goal | Before | After | Result |
|---|---|---|---|---|
| Hitch-time ratio, Plan 5's benchmark (eased scroll), same session | spec: 0 hitches | 1.81, 5.03, 2.32 ms/s | 1.41, 1.86, 1.87 ms/s | better, not met |
| Hitch-time ratio, with the new flick | addendum: ≤ 1 ms/s | 6.15, 6.28, 6.09 ms/s | 6.12, 6.58, 7.25 ms/s (5.1–5.7 in other runs) | miss: unchanged |
| Configuring a cached settled answer | spec: ≤ 4 ms | 27.0 ms | 21.3–21.7 ms | better, miss |
| Main-thread work per reveal frame | spec: ~0 | 0.18–0.73 ms | 0.17 ms | better |
| Starting a phrase (the harness's median) | addendum: ≤ 0.5 ms | about 1.1 ms (probe) | 0.22 ms | pass |
| Applying one update, p95: 5,000-word answer | spec: ≤ 2 ms | 0.48 ms | 0.49–0.62 ms | pass |
| … a 500-item list | ≤ 2 ms | 0.21 ms | 0.20–0.23 ms | pass |
| … a 150-line code block | addendum: ≤ 2 ms | 1.97–2.20 ms | 1.01–1.02 ms | pass |
| … a 40-row table | ≤ 2 ms | 0.43 ms | 0.52–0.56 ms | pass |

The rest of the main thread per update (TextKit's layout and drawing), p95: code block 8.7 → 5.0–5.3 ms, list 2.4 →
1.5–1.6 ms, revealing 5.5 → 5.2–5.3 ms, answer 2.5 → 2.5–2.6 ms, table 1.7 → 1.3–1.4 ms.

The addendum's configure goal, a first frame a third of the probe's 57 ms end to end, wasn't measured again end to
end. The harness's configure measures part of it: 27 → 21.5 ms.

What each change moved:
- **The text view is sized once.** It's 1,000,000 pt tall and doubles only past that, so streaming never resizes it.
  Resizing cost up to 9.4 ms per update on the device. The accessibility frame still hugs the text.
- **The band refreshes in quarter-screen steps, and a configure renders the screen first.** Each refresh lays out
  less. A cached configure lays out only the screen, by swapping the text at a short height and then growing the view,
  and renders the rest of the band a frame later. Configure went from 27 to 21.5 ms.
- **A phrase start asks about one line.** The settled part of the line comes from the one line fragment holding the
  first unsettled character. Before, it came from the segment rects of a 512-character window. The reveal store
  hashes the answer's opening again only when the text changed. On the simulator, a phrase start went from 0.225 to
  0.079 ms. On the device the reveal's work per frame is 0.17 ms.
- **A streaming code block diffs by colour runs.** The first changed line is where the text or a colour run first
  differs, instead of a comparison of attributed paragraphs. The long code block's apply halved, from about 2.1 to
  1.0 ms.
- **The benchmark flicks.** Before its eased round trip, it flicks back about 3,000 pt with an ease-out (about
  5,000 pt/s at the start) and returns. The Plan 5 reviewer found the eased scroll gentler than a reader. The flick
  makes the benchmark harsher, so its ratios aren't comparable with Plan 5's 2.3 ms/s. The table compares both engines
  on both benchmarks.

### What the flick's hitches are

A throwaway probe on the device attributed the main thread's time in every hitching frame:

- **Every TextKit viewport pass redraws every fragment in the band.** UIKit's
  `-[_UITextLayoutCanvasView textViewportLayoutController:renderingSurfaceForTextLayoutFragment:]` calls
  `setNeedsDisplay` on each fragment's view during each viewport pass, whether or not the fragment changed. That's
  18,789 calls in one 30-second run: 8,617 redraws of fragments already drawn, against 506 first draws.
  - In the flick's return, the answer's band grows as it scrolls back in. Each pass redraws about 44 fragments: 4–5 ms
    of Glimmer's drawing, in a 16–18 ms slice of main-thread work.
  - Each streamed edit is a pass too, which is most of the "rest of the main thread" per update above.
  - Plan 6's changes made each pass cheaper to reach, not cheaper to draw. That's why the flick didn't move.
- **A streamed code block's first appearance builds its view on the main thread.** It costs 4.3–9.4 ms inside one
  apply: the view's own TextKit stack and its first measurement.
- **Band refreshes while following the stream.** A refresh costs 1.2–4.7 ms, plus the redraws above.

Avoiding the full-band redraw needs a decision beyond this plan. The options are rendering fragments outside UIKit's
canvas, or suppressing redraws of unchanged fragments. Either works around UIKit rather than with it.

### Gates

The device gates moved to the new baselines:
- cached configure ≤ 28 ms (21.5 ms measured);
- reveal per frame ≤ 0.5 ms (0.17 ms measured; Plan 5 saw fourfold run-to-run variance);
- streaming embed apply ≤ 2 ms (the spec);
- phrase start ≤ 0.5 ms (the addendum's goal);
- the benchmark's hitch-time ratio < 8 ms/s. This is a regression bound at the flick's baseline, not the addendum's
  1 ms/s. The flick sits in Apple's "warning" band (5–10 ms/s).

`GlimmerDevicePerf` passes 10/10 on the device. `BenchmarkHitchUITests` wasn't run on the device this time: the phone
asked for Face ID to enable UI Automation. So `XCTHitchMetric` has no Plan 6 number. The frame monitor's hands-off runs
above are the measurement.

## Plan 5

Measured on 2026-09-26, before Plan 6, on the device and build the spec's §3 budgets are written for. Simulator
numbers (iOS 27.0, iPhone 17 Pro Max, on an Apple silicon Mac under a load average of 5.7–8.4) are alongside for
comparison.

### Spec §3

| Metric | Budget | iPhone 16 Pro Max | Simulator | Result |
|---|---|---|---|---|
| Applying one network update on main, p95: 5,000-word answer | ≤ 2 ms | 0.48 ms | 0.65 ms | pass |
| … the same answer while revealing | ≤ 2 ms | 0.52 ms | 0.80 ms | pass |
| … a 500-item list | ≤ 2 ms | 0.21 ms | 0.77 ms | pass |
| … a 150-line code block streamed a line at a time | ≤ 2 ms | 1.97–2.20 ms (three runs) | 1.94 ms | borderline: at the budget, not under it |
| … a 40-row table streamed a row at a time | ≤ 2 ms | 0.43 ms | 0.56 ms | pass |
| Starting a phrase: its segment lookup at the end of 5,000 words | ≤ 0.2 ms | 0.010 ms | 0.011 ms | pass |
| Main-thread work per reveal frame, between updates | ~0 | 0.73 ms of CPU per 120 Hz frame | 0.31–0.42 ms (Debug) | miss (see below) |
| Configuring a cached settled answer (~1,200 words) | ≤ 4 ms | 27.0 ms (uncached 59.2 ms) | 14.2–15.9 ms | miss |
| Hitches while streaming and scrolling | 0 | hitch-time ratio 2.3 ms/s; 5–9 short drops in 30 s (worst 20 ms) | not measurable | near miss: "good" by Apple's scale (see below) |

Rest of the main thread per update, p95 (TextKit's layout and drawing, plus the reveal's wake-ups):

| Case | iPhone 16 Pro Max | Simulator | Gate |
|---|---|---|---|
| 5,000-word answer | 2.5 ms | 6.5 ms | 18 ms |
| … revealing | 5.5 ms | 15.8 ms | 26 ms |
| 500-item list | 2.4 ms | 7.9 ms | 18 ms |
| Long code block | 8.7 ms | 17.9 ms | 26 ms |
| Long table | 1.7 ms | 2.5 ms | 18 ms |

What Plan 5 changed, on the simulator:
- The streaming code block's apply went from 3.4 ms to 1.94 ms. Highlighting moved to the worker, and unchanged
  lines are counted over UTF-16.
- The streaming table's apply went from 3.3 ms to 0.56 ms. Rows that didn't change keep their labels and
  measurements.

### Hitches

The benchmark streams about 1,000 words at a seeded Gemini cadence below a settled 5,000-word answer. While it
streams, the screen scrolls itself up through the whole earlier answer and back down, as a reader would. A 120 Hz
display link counts frames that arrive more than one and a half frame durations late.

| Run | Frames | Hitches (frame monitor) | Worst interval | XCTHitchMetric |
|---|---|---|---|---|
| Self-scrolling, under XCUITest, which leaves the app alone while measuring | 2,123 | 9 | 20.2 ms | 15 hitches, 125 ms in total, **2.3 ms per s** |
| Self-scrolling, launched alone (`devicectl process launch --console`) | 2,135 | 5 | 16.7 ms | — |
| Following the bottom only, launched alone | 2,148 | 4 | 16.7 ms | — |
| First harness: XCUITest swipes and element queries during the stream | 1,880 | 19 | 1,028 ms | 9 hitches, 1.08 s in total, 25.4 ms per s |

**The hitch-time ratio is 2.3 ms per second.** Apple's scale calls under 5 ms/s good (not noticeable), 5–10 a warning,
and over 10 critical. Streaming while scrolling through a 5,000-word answer is smooth by that measure. The spec asks
for zero hitches, and there are a handful of short ones: the worst is 20 ms, where 8.3 ms was due, so one or two
missed frames. They coincide with phrase starts and embeds growing by a line or row (see the misses below).

**The last row measured the harness.** Every XCUITest swipe and element query snapshots the app's whole
accessibility tree. For a screen holding a 5,000-word answer, that stalled the main thread for about a second. The UI
test now leaves the app alone while it measures, and the stall is gone.

The stall is also a finding for VoiceOver. It suggests UIKit's accessibility for a long `UITextView` lays out far
more than the visible band. VoiceOver asks for elements lazily rather than snapshotting everything, so it may not hit
the same cost, but VoiceOver on a long answer should be tried on a device.

### The misses

- **Configuring a cached settled answer: 27 ms against 4 ms.** The cache saves parsing, composing and measuring
  (uncached is 59 ms). What remains is TextKit's first layout and drawing of the screen, and building the first
  screen's embed views. The options, for a follow-up:
  - lay out less than a screen first and the rest on the next frame;
  - reuse text views, and their layout, across cells;
  - create embed views lazily as they scroll in, which the band already does below the screen.
- **A reveal's main thread between updates: 0.73 ms of CPU per frame.** The clock wakes only to start phrases, not
  every frame, so this is phrase-start work averaged over frames: about 5 ms per phrase start. Each start fits within
  a 120 Hz frame, which is why the benchmark shows single-frame drops at most rather than stalls. To profile: the
  mask's geometry for the new phrase, and the height report each start makes.
- **Hitches: a handful of one- or two-frame drops in 30 s (2.3 ms/s).** They coincide with the costs above: phrase
  starts, and embeds growing by a line or row.

### How the harness gates

The spec's numbers are targets; the tests gate at what the device measures today, with headroom, so they turn red on a
regression rather than on the known distance to the spec. On the simulator the gates are unchanged. On the device:

- cached configure ≤ 36 ms (baseline 26–27 ms);
- reveal main-thread CPU ≤ 1.0 ms per frame (baseline 0.18–0.73 ms);
- streaming code or table apply ≤ 3 ms p95 (baseline up to 2.2 ms);
- the benchmark's hitch-time ratio under 5 ms/s, Apple's "good" (baseline 2.3–2.4 ms/s).

With those gates, `GlimmerDevicePerf` passes 9/9 on the device. The benchmark passes at `done frames=2146 hitches=5
worst=18.0ms ratio=2.37ms/s`.

### What the numbers mean

- **Apply** is the main thread's work to apply one streamed update: the text edit, measuring, embed updates and the
  reveal's bookkeeping. Parse, compose and syntax highlighting run on the view's worker.
- **Rest of the main thread** is the main thread's CPU for the same update, minus the apply: TextKit's layout and
  drawing, which Core Animation runs while the test waits on the worker.
- **Main-thread work per reveal frame** is the main thread's CPU while a reveal runs with no network updates, divided
  by the 120 Hz frames in that time. It's measured after TextKit's one-time first layout.
- **Configure** is showing a settled answer again, taking its text and height from the cache.

### To run on the device

Unlock the phone. The first UI-test run on a device asks for Face ID ("Enable UI Automation").

```bash
xcodebuild test -project Examples/GlimmerDemo/GlimmerDemo.xcodeproj -scheme GlimmerDevicePerf -configuration Release \
  -destination 'id=00008140-00044C9001F3001C' -derivedDataPath .build/device-dd -allowProvisioningUpdates ENABLE_TESTABILITY=YES
xcodebuild test -project Examples/GlimmerDemo/GlimmerDemo.xcodeproj -scheme GlimmerDemo -configuration Release \
  -destination 'id=00008140-00044C9001F3001C' -derivedDataPath .build/device-dd -allowProvisioningUpdates \
  -only-testing:GlimmerDemoUITests/BenchmarkHitchUITests
# The benchmark alone, with nothing driving the app:
xcrun devicectl device process launch --device 00008140-00044C9001F3001C --console --terminate-existing \
  dk.wu.GlimmerDemo --benchmark --benchmark-autostart --benchmark-exit
```

Read `XCTHitchMetric` from the result bundle with `xcrun xcresulttool get test-results metrics --path <xcresult>`.

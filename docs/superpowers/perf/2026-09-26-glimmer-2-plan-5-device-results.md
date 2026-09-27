# Glimmer 2.0 — Plan 5 performance results

Measured on 2026-09-26 on "WW 16", an iPhone 16 Pro Max on iOS 27.0 (24A435), in Release. That is the device and build
the spec's §3 budgets are written for. Simulator numbers (iOS 27.0, iPhone 17 Pro Max, on an Apple silicon Mac under
a load average of 5.7–8.4) are alongside for comparison.

## Spec §3

| Metric | Budget | iPhone 16 Pro Max | Simulator | Result |
|---|---|---|---|---|
| Applying one network update on main, p95: 5,000-word answer | ≤ 2 ms | 0.48 ms | 0.65 ms | pass |
| … the same answer while revealing | ≤ 2 ms | 0.52 ms | 0.80 ms | pass |
| … a 500-item list | ≤ 2 ms | 0.21 ms | 0.77 ms | pass |
| … a 150-line code block streamed a line at a time | ≤ 2 ms | 1.97 ms | 1.94 ms | pass, barely |
| … a 40-row table streamed a row at a time | ≤ 2 ms | 0.43 ms | 0.56 ms | pass |
| Starting a phrase: its segment lookup at the end of 5,000 words | ≤ 0.2 ms | 0.010 ms | 0.011 ms | pass |
| Main-thread work per reveal frame, between updates | ~0 | 0.73 ms of CPU per 120 Hz frame | 0.31–0.42 ms (Debug) | miss (see below) |
| Configuring a cached settled answer (~1,200 words) | ≤ 4 ms | 27.0 ms (uncached 59.2 ms) | 14.2–15.9 ms | miss |
| Hitches while streaming and scrolling | 0 | 4 one-frame drops in 30 s (worst 16.7 ms) | not measurable | near miss (see below) |

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

## Hitches

The benchmark streams about 1,000 words at a seeded Gemini cadence below a settled 5,000-word answer. A 120 Hz display
link counts frames that arrive more than one and a half frame durations late.

| Run | Frames | Hitches | Worst interval | XCTHitchMetric |
|---|---|---|---|---|
| Launched alone (`devicectl process launch --console`), following the bottom | 2,148 | 4 | 16.7 ms | — |
| Under XCUITest, with swipes and element queries during the stream | 1,880 | 19 | 1,028 ms | 9 hitches, 1.08 s in total, 25.4 ms per s |

**Read the first row.** Each of its four hitches is one missed 120 Hz frame (16.7 ms where 8.3 ms was due). That is
close to the spec's zero, but not zero. On the simulator, the same run reported 1 hitch (worst 35.1 ms) out of about
1,066 frames, which says little, because the simulator doesn't pace frames like a phone.

**The second row measures the harness.** Every XCUITest swipe and element query snapshots the app's whole
accessibility tree. For a screen holding a 5,000-word answer, that stalled the app's main thread for about a second.
The UI test now leaves the app alone while it measures: the app scrolls itself up through the earlier answer and back
down, and the test reads the summary only after the frame monitor stops. That version passes on the simulator. Its
device run is waiting for the phone to be unlocked.

The stall is also a finding for VoiceOver. It suggests UIKit's accessibility for a long `UITextView` lays out far
more than the visible band. VoiceOver asks for elements lazily rather than snapshotting everything, so it may not hit
the same cost, but a person using VoiceOver on a long answer should be tested on a device.

## The misses

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
- **Hitches: four one-frame drops in 30 s.** They coincide with the costs above: phrase starts, and embeds growing
  by a line or row.

The package's tests gate on the simulator. On the device, `GlimmerDevicePerf` reports these two misses as failures
(`testConfiguringACachedSettledAnswerStaysWithinBudget` at 27 ms against its 24 ms regression gate, and
`testARevealBetweenUpdatesCostsAlmostNothingPerFrame` at 0.73 ms against 0.5 ms). That is the harness doing its job.

## What the numbers mean

- **Apply** is the main thread's work to apply one streamed update: the text edit, measuring, embed updates and the
  reveal's bookkeeping. Parse, compose and syntax highlighting run on the view's worker.
- **Rest of the main thread** is the main thread's CPU for the same update, minus the apply: TextKit's layout and
  drawing, which Core Animation runs while the test waits on the worker.
- **Main-thread work per reveal frame** is the main thread's CPU while a reveal runs with no network updates, divided
  by the 120 Hz frames in that time. It's measured after TextKit's one-time first layout.
- **Configure** is showing a settled answer again, taking its text and height from the cache.

## To run on the device

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

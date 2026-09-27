# Glimmer 2.0 — Plan 5 performance results

Measured on 2026-09-26. The spec's §3 budgets are for an iPhone 16 Pro Max in a Release build. The device harness is
built and signed (see [To run on the device](#to-run-on-the-device)), but its first run could not start because the
phone was locked. The numbers below are the iOS 27.0 simulator's (iPhone 17 Pro Max) on an Apple silicon Mac, in
Release, under a load average of 5.7–8.4 from other sessions.

## Spec §3 on the simulator (Release)

| Metric | Budget | Measured | Result |
|---|---|---|---|
| Main-thread work per reveal frame | ~0 | 0.31–0.42 ms of CPU per 120 Hz frame (Debug) | pass (gate 0.5 ms) |
| Applying one network update on main, p95: 5,000-word answer | ≤ 2 ms | 0.65 ms | pass |
| … the same answer while revealing | ≤ 2 ms | 0.80 ms | pass |
| … a 500-item list | ≤ 2 ms | 0.77 ms | pass |
| … a 150-line code block streamed a line at a time | ≤ 2 ms | 1.94 ms | pass |
| … a 40-row table streamed a row at a time | ≤ 2 ms | 0.56 ms | pass |
| Starting a phrase (its segment lookup at the end of 5,000 words) | ≤ 0.2 ms | 0.011 ms | pass |
| Configuring a cached settled answer (~1,200 words) | ≤ 4 ms | 14.2–15.9 ms (uncached 33.4–37.7 ms) | miss on the simulator |
| Hitches while streaming and scrolling (`XCTHitchMetric`) | 0 | not measurable on the simulator | device only |

What Plan 5 changed, on the same machine:
- The streaming code block's apply went from 3.4 ms to 1.94 ms. Highlighting moved to the worker, and the unchanged
  lines are counted over UTF-16.
- The streaming table's apply went from 3.3 ms to 0.56 ms. Rows that didn't change keep their labels and
  measurements.

Rest of the main thread per update, p95, which is TextKit's layout and drawing plus the reveal's wake-ups:

| Case | p95 | Gate |
|---|---|---|
| 5,000-word answer | 6.5 ms | 18 ms |
| … revealing | 15.8 ms | 26 ms |
| 500-item list | 7.9 ms | 18 ms |
| Long code block | 17.9 ms | 26 ms |
| Long table | 2.5 ms | 18 ms |

## The benchmark on the simulator

`BenchmarkHitchUITests` passes on the simulator, where it records but doesn't assert hitches. Its frame monitor
reported `done frames=989 hitches=14 worst=1097.9ms`. `XCTHitchMetric` recorded no measurements (the result
bundle's metrics are empty).

Neither says anything about a phone. The simulator's display link doesn't pace like a device's: 989 frames over a
run of about 30 s is roughly 33 frames per second, not 120. And XCUITest's swipes and element queries stall the app
while they run. The benchmark's hitch gate applies only on a device.

## What the numbers mean

- **Apply** is the main thread's work to apply one streamed update: the text edit, measuring, embed updates and the
  reveal's bookkeeping. Parse, compose and syntax highlighting run on the view's worker. This is the spec's
  "applying one network update on main".
- **Rest of the main thread** is the main thread's CPU for the same update, minus the apply. It covers TextKit's
  layout and drawing, which Core Animation runs while the test waits on the worker. It is framework time, so it's
  gated as a regression bound, not a spec budget.
- **Main-thread work per reveal frame** is the main thread's CPU while a reveal runs with no network updates, divided
  by the 120 Hz frames in that time. It's measured after TextKit's one-time first layout. Core Animation animates the
  phrase fades; the main thread only starts phrases when the clock wakes it.
- **Configure** is showing a settled answer again, which takes its text and height from the cache. On the
  simulator, TextKit's first layout and drawing of the screen, and building the first screen's embed views, dominate
  it. That's why it misses 4 ms there. If the device misses too, the options are to lay out less than a screen first,
  or to reuse text views across cells.

## To run on the device

The device is "WW 16", an iPhone 16 Pro Max on iOS 27.0 (24A435), UDID `00008140-00044C9001F3001C`. Release builds and
signing (team `RUV7V2TGVX`) succeeded. The run stopped at `Unlock WW 16 to Continue`. With the phone unlocked:

```bash
xcodebuild test -project Examples/GlimmerDemo/GlimmerDemo.xcodeproj -scheme GlimmerDevicePerf -configuration Release \
  -destination 'id=00008140-00044C9001F3001C' -derivedDataPath .build/device-dd -allowProvisioningUpdates ENABLE_TESTABILITY=YES
xcodebuild test -project Examples/GlimmerDemo/GlimmerDemo.xcodeproj -scheme GlimmerDemo -configuration Release \
  -destination 'id=00008140-00044C9001F3001C' -derivedDataPath .build/device-dd -allowProvisioningUpdates \
  -only-testing:GlimmerDemoUITests/BenchmarkHitchUITests
```

The first command prints `PERF` lines for every row of the §3 table except hitches. The second prints
`BENCHMARK done frames=… hitches=… worst=…ms`, and fails on the device if the frame monitor saw a hitch. Its
`XCTHitchMetric` measurements are in the result bundle: `xcrun xcresulttool get test-results metrics --path <xcresult>`.

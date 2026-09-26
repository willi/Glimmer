# Glimmer 2.0 — Plan 3 performance results

Measured on 2026-09-26 with `GlimmerStreamingPerformanceTests` on the iOS 27.0 simulator (iPhone 17 Pro Max) on an
Apple silicon Mac. Another session's app held about 110% CPU on a different simulator throughout, and the load average
was 6.6–7.5, so absolute numbers run high.

The fixture is the "long answer": about 5,000 words of mixed markdown (31,057 characters). It streams its last 1,200
characters in 30-character chunks, while a scroll view follows the bottom. The long-list case is 500 items in one
tight list. The configure case is about 1,200 words.

## What each number measures

- **Apply**: the main-thread work to apply one streamed update (the edit, measuring, and the reveal's bookkeeping).
  Parse and compose run on the view's worker. This is the spec §3 metric "applying one network update on main".
- **Rest of main thread**: the main thread's CPU for the same update, minus the apply. That covers TextKit's layout
  and drawing (which Core Animation runs while the test awaits the worker) and the reveal's wake-ups. It is framework
  time, so it is gated as a regression bound, not a spec budget. Rendering every paragraph (no visible band) costs well
  over 30 ms.
- **Late segment lookup**: finding the glyph rects of the last character of the long answer. This is most of starting
  a phrase (§3 ≤ 0.2 ms).
- **Configure, cached**: showing a settled answer again, which takes its text and height from the cache. The uncached
  configure is measured the same way beside it.

## Debug

| Metric | Gate | Measured | Result |
|---|---|---|---|
| Apply p95, mixed answer | ≤ 8 ms | 0.96 ms | pass |
| Apply p95, mixed answer revealing | ≤ 8 ms | 1.01 ms | pass |
| Apply p95, long list | ≤ 8 ms | 0.53 ms | pass |
| Rest of main thread p95, mixed | ≤ 18 ms | 7.6 ms | pass |
| Rest of main thread p95, revealing | ≤ 26 ms | 20.1 ms | pass |
| Rest of main thread p95, long list | ≤ 18 ms | 6.2 ms | pass |
| Late segment lookup median | ≤ 0.2 ms | 0.013 ms | pass |
| Configure cached median | < 0.7 × uncached, ≤ 24 ms | 18.6 ms (uncached 38.4 ms) | pass |

## Release

| Metric | Gate | Measured | Result |
|---|---|---|---|
| Apply p95, mixed answer | ≤ 2 ms (§3) | 1.01 ms | pass |
| Apply p95, mixed answer revealing | ≤ 2 ms (§3) | 1.01 ms | pass |
| Apply p95, long list | ≤ 2 ms (§3) | 0.56 ms | pass |
| Rest of main thread p95, mixed | ≤ 18 ms | 7.5 ms | pass |
| Rest of main thread p95, revealing | ≤ 26 ms | 17.9 ms | pass |
| Rest of main thread p95, long list | ≤ 18 ms | 5.3 ms | pass |
| Late segment lookup median | ≤ 0.2 ms (§3) | 0.010 ms | pass |
| Configure cached median | < 0.7 × uncached, ≤ 24 ms | 15.8 ms (uncached 38.1 ms) | pass |

The configure numbers above were taken under load. With a quieter machine (load average about 6, earlier the same
day) a cached configure measured 9.7 ms against 32.2 ms uncached.

## Before and after Plan 3 (5,000-word answer, Debug)

| | Before Plan 3 | After |
|---|---|---|
| Layout pass after an append (timer, before the worker) | 30 ms | 3–5 ms (visible band) |
| Late segment lookup | 2 ms | 0.013 ms (unbounded container) |
| Apply p95 | 2.6 ms | ~1 ms (compose on the worker, incremental measuring) |
| Long-list main thread per update (CPU p95) | 20 ms | 6 ms |
| Settled configure, 1,200 words | 32 ms | 10–19 ms (cache) |

## Still to show on a device (Plan 5)

- **Hitches while streaming and scrolling** (§3: zero), with `XCTHitchMetric` on an iPhone 16 Pro Max in Release.
- **Configuring a cached settled answer in ≤ 4 ms** (§3). On the simulator, a cached configure is dominated by
  TextKit's first layout of the screen and by building the first screen's embed views (about 10 ms). If the device
  misses the budget, the options are to lay out less than a screen first, or to reuse text views across cells.
- **Revealing main-thread cost.** An embed that grows by a line or row makes TextKit re-lay out and redraw the box and
  the text after it: about 18–20 ms p95 of main-thread CPU on the simulator, spread across a phrase interval
  (70–230 ms) rather than inside one frame. The device harness decides whether that ever drops a frame.

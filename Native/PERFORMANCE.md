# Simulator performance verification — 2026-09-27

The user's roughly 2 FPS report exposed real CPU stalls. The initial sampled main thread repeatedly sorted every nearby actor inside a collapsed SwiftUI disclosure group. After making that menu lazy and caching its numeric sort, a second sample exposed repeated vertex-label hashing/trigonometry, appearance JSON serialization, and synchronous simulator Metal buffer allocation.

The final implementation:

- Constructs Nearby and the floating minimap only when expanded; caches Nearby results per validated state.
- Replaces per-vertex hash lookups with a 256-bit label mask and hoists transform constants. The preserved reference comparison passes 666 original/random/interpolated poses and 657,864 bit-identical vertex positions/colors. The repeatable isolated benchmark measured 4.23× faster animation on its recorded final run.
- Decodes scene actors and computes appearance keys once per validated state revision, preserving animation timing and visibility.
- Reuses GPU vertex/index buffers only after their last command completes, with a 32 MiB retired-buffer cap per renderer, three in-flight commands and a 24 MB per-frame upload budget. A real-Metal blocked-read test verifies no overwrite before completion, exact GPU readbacks, and subsequent reuse.
- Keeps changing diagnostic counters out of SwiftUI observation.

## Observed application runs

These are two observed simulator runs, not a deterministic matched benchmark. Both had 25 loaded terrain chunks and approximately 140,000 triangles. The earlier run already included the Nearby fix; the original user-reported 2 FPS was not independently measured as a presentation rate. The later run also includes the animation, GPU-buffer and scene-cache fixes.

| Measurement | Earlier intermediate build | Final simulator build |
| --- | ---: | ---: |
| Profile interval used | 10–467.7 seconds | 10–80.2 seconds |
| Median scene update | 33.48 ms | 3.41 ms |
| Median of rolling CPU encode medians | 2.17 ms | 0.55 ms |
| Median main-thread display callbacks | 22.43/sec | 59.50/sec |
| Median render-command completions | 52.72/sec | 60.00/sec |
| Median scene snapshots | 24.21/sec | 28.52/sec |
| Median resident memory | 371.1 MB | 375.5 MB |
| Cumulative late CPU submissions at end | 3,515 | 1 |
| Skipped submissions / deferred uploads | 0 / 0 | 0 / 0 |

The final capture records 662 geometry-buffer allocations and 208,258 reuses. Session recovery is securely saved; no game credentials are in the profile. These rates are instrumentation of callbacks/submissions, not a physical headset presentation measurement. Scene animation has a 30 Hz target; Compositor Services continues presenting with predicted viewer poses independently. The user selected simulator verification for now. Physical table tracking, device frame deadlines and a long hardware soak remain pending.

Evidence under `$SCAPE_WORKSPACE`:

- `Artifacts/profile-before-animation-buffer-fix.json` and `Artifacts/profile-final-simulator.json`
- `Artifacts/native-performance-sample.txt`, `native-performance-after.txt`, `native-performance-pooled.txt`
- `Artifacts/immersive-optimized-simulator.png` shows the board below eye level and controls beside it.
- `Build/PerformanceChecks/Artifacts/animation.log` and `pool.log`
- `Build/SceneChecks/Artifacts/scene-cache.log`
- `Artifacts/NativeUI-20260927-171325.xcresult` and `ui-latest.log`: panels, immersive entry/exit, actual force-quit/relaunch, explicit logout; zero failures, 28.528 seconds.

Reproduce the low-level checks with `bash scripts/test-native-performance.sh` and `bash scripts/test-native-scene-cache.sh`. Run `bash scripts/run-native-simulator.sh --tablescape-immersive --tablescape-profile` for a bounded ten-minute diagnostic capture, following the export instructions in README. Simulator signing must remain enabled with its private application identifier so Keychain-backed restart recovery works.

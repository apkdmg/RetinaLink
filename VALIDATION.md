# RetinaLink 0.2.9 build 30 — validation, 17 October 2026

## Outcome and limits

**The iMac upload path is faster and byte-exact. Stable native 5K60 across desktop workloads has not been achieved.** The blocking operation behind a sustained slow source run is now identified: the source app waits for reusable Core Animation drawables before it can draw. The internal WindowServer/driver reason for holding those drawables remains unresolved. The earlier rare 245 ms iMac submission stall was not reproduced in an unprofiled final trial, so its exact cause is not claimed to be fixed.

All installation, motion tests, reconnection and log collection used the existing authorized SSH session. The machines remain a 2023 M2 Max Studio on macOS 27.0.1 and a 2014 Retina iMac on Big Sur 11.7.8 / Radeon R9 M290X. Native dimensions, encrypted pairing, the SSH Ethernet route and physical Viewer vsync are retained. Screen Sharing remained connected. No security or sharing settings were changed. Other capture clients remain a limitation of the environment.

The final iMac executable and Host are build 30. Earlier builds 23–29 are diagnostic/test controls. Requested refresh, generated frames, completed capture samples, GPU completions and positive presentation timestamps are kept distinct. No camera-based input-to-photon or physical frame-identity measurement was made.

## Upload improvements, isolated on the actual iMac

A standalone universal probe feeds the production DisplayView uncompressed, native 5K test packets at 60 Hz, with three bounded GPU credits. It removes capture, networking and LZ4 decoding. Full phases upload all 920 tiles; sparse phases upload two. A small tile alternates each frame. Packet preparation is timed separately. Each phase is bounded and the app exits normally afterward.

Build 27 repeats the old per-tile path around the coalesced path; each run has full/sparse/full phases of 15 seconds. Discard three seconds after each phase starts and its last second. Full-frame GPU execution in the two full phases was:

| Control | First full phase | Last full phase |
|---|---:|---:|
| Old per-tile, cached, A | 6.53 ms | 6.56 ms |
| Coalesced, cached, B | 3.67 ms | 3.58 ms |
| Old per-tile, cached, C | 6.25 ms | 6.52 ms |

Coalescing reduces 920 blits to 23 horizontal rectangles for a full 5K frame, roughly **44% less GPU time** in this workload. It never joins across an unchanged hole or tile-row boundary. Sparse frames retain small transfers. CPU staging was similar in this first comparison; this is not a CPU-speed or overall-FPS claim.

Build 29 then holds coalescing constant, caches the staging destination pointer once and compares 30-second full-frame runs with different CPU cache policies:

| Staging memory | CPU upload setup | GPU execution |
|---|---:|---:|
| Cached, A | 6.01 ms | 3.75 ms |
| Write-combined, B | 4.75 ms | 3.76 ms |
| Cached, C | 6.04 ms | 3.81 ms |

Write-combined staging takes about **21% less CPU setup time** against both controls. CPU only writes this memory; it is not read back or reused before GPU completion. Build 30 defaults to coalescing and write-combined memory. `--tile-blits` and `--cached-upload` provide independent controls.

These are stage-cost improvements, not proof of end-to-end 60 fps. Several standalone runs reported 60 rendered updates/s but zero positive presentation timestamps for an initial phase or an entire control. Build 29 recorded visible window, visible occlusion state, active Space and awake display even during one such run. A separate system query confirmed the iMac's single active, built-in 5120 × 2880 screen at scale 2, console user opsounimas, and nominal thermal state. That query's reported refresh value is zero, not a claim that the panel has a zero-Hz mode. The zero-timestamp runs cannot support a physical-presentation claim. Positive-counter runs did reach about 60 fps, but they are not substituted for slower or invalid-presentation trials.

## Capture gaps: stronger controls and corrected inference

The preceding release compared separate capture-only and encode-only runs at about 60 and 55 captures/s. That correlation did not isolate encoding as the cause. This release uses one continuous capture stream and one source, switching processing in 30-second phases:

| Phase | Complete captures/s | Source draws/s | Processing |
|---|---:|---:|---:|
| Release capture buffers | 59.18 | 59.17 | 0 ms |
| Hold buffer for about 6.7 ms | 59.39 | 59.35 | 6.70 ms |
| GPU encode captured surface + pack | 59.91 | 59.91 | 6.70 ms |
| GPU encode independent copied surface + pack | 60.00 | 59.98 | 6.66 ms |
| GPU encode captured surface again | 59.95 | 59.95 | 6.75 ms |
| CPU-only pack cached output | 56.87 | 56.88 | 2.04 ms |
| Release capture buffers again | 57.68 | 57.63 | 0 ms |

No frames are transmitted during this probe; it is not a display-throughput result. There was no mailbox coalescing. Capture tracks source production even when no work is done. Holding the input or GPU-encoding it did not, by itself, lower the rate in this matched trial. Deep-copy correctness and row stride were tested separately.

A subsequent source probe reproduces slow production while the application is active and visible. Over the steady interval it draws **20.14 frames/s**. Mean draw gap is **49.65 ms**, with **48.75 ms inside drawable acquisition**, **0.020 ms CPU encoding**, and **0.331 ms GPU execution**. A 30-second, five-millisecond stack sample places 4,382 of 4,437 main-thread samples in the semaphore wait under MTKView.currentDrawable → CAMetalLayer.nextDrawable. That identifies the immediate blocking operation; it does not identify which OS component or other client retains the surfaces.

An 85-second native/no-presentation-counter/unsynced/native source control produced **21.57 / 19.63 / 42.51 / 20.21 draws/s**. Removing the source's optional presentation callback did not solve it. Disabling vsync only in that test source shortened acquisition wait from roughly 46–50 ms to 18 ms; restoring it reversed the effect. Physical Viewer vsync was never disabled. This is evidence of source presentation/resource pacing, not a production fix or an ordinary-desktop FPS result. Source positive presentation timestamps are unavailable on this virtual display, so draw/GPU counters are not labeled actual source presentations.

A separate on/off/on/off ScreenCaptureKit control keeps the same virtual display and source alive. Source draws averaged **22.37 / 27.00 / 20.42 / 23.57 per second**, with mean drawable waits **44.36 / 36.45 / 48.02 / 41.30 ms**. Stopping our capture improves some headroom but does not restore 60, and the wait persists while it is stopped. This rules out our live encoder/transport as the sole cause; it does not prove ScreenCaptureKit has no contribution or that the private virtual-display implementation is faultless.

Apple documents [nextDrawable](https://developer.apple.com/documentation/quartzcore/cametallayer/nextdrawable()) as waiting for an available drawable. The present investigation has not established the internal cause of the exhausted pool. Direct WindowServer sampling requires privileges; ordinary sampling was refused, and a noninteractive sudo attempt required a password. No credentials or system permissions were changed.

## iMac presentation/submission and acknowledgement tails

The production helper `commandBuffer.present(drawable)` registers a deferred operation. Timing its CPU call only measures registration. Apple describes this [scheduled-handler mechanism](https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Render-Ctx/Render-Ctx.html). Build 25 explicitly times drawable.present() from a scheduled handler. That alternative call averaged roughly 0.05 ms, with a maximum below 0.6 ms in the matched full/sparse/full test. However, it changed observed scheduling and presentation rate, so it is not a transparent measurement of the original helper. It remains opt-in and is excluded from release tests. This corrects the earlier implication that a quick registration call excludes all deferred presentation work.

The old 264.7 ms ACK / 244.7 ms pre-GPU-start outlier is still unexplained internally. New production-path traces can show different tails. In the source-profile run a 238 ms ACK cycle included only 12.75 ms of Viewer work and 225.26 ms of transport/unclassified endpoint residual. The same run included process sampling, so its tails must not be treated as unperturbed production measurements. The residual includes SSH/TLS and endpoint scheduling; it is not pure wire RTT. In a later unprofiled candidate trial, maximum iMac GPU-start delay was 9.01 ms, receiver work 16.52 ms, and ACK cycle 41.46 ms. No 245 ms presentation/submission outlier recurred there.

A transparent compositor-pulse on/off test improved after the pulse was removed as well as while it ran. It did not show a causal reversal and is not enabled. A Screen Sharing minimize/restore trial did not restore source frame rate; the connection was kept alive. A repeated AnyDesk quit comparison is **inconclusive**: normal Quit left a user-owned capture child running, its termination occurred late, and reopening required clearing stale user helpers and reopening via Finder. The root service and its settings were left intact. Its normal user-process set and background capture restarted, but the GUI automation could not confirm the window. That interval is excluded as a clean capture-off comparison and is not used to attribute a speed gain to AnyDesk.

## Final release tests

The supplied build 30 is tested with no experimental probe flags and frame tracing disabled. The automatic one-second snapshots still run. First five and final two seconds are excluded from the aggregate summaries. The scroll test polls over SSH every two seconds; native window motion collects afterward.

| Workload | Duration | Capture/s | Delivered/s | Positive presentation fps | Host encode + pack | ACK cycle |
|---|---:|---:|---:|---:|---:|---:|
| Bitmap-text scroll | 180 s | 16.12 | 16.11 | 16.11 | 7.65 ms | 19.59 ms |
| Real AppKit window motion | 45 s | 19.28 | 19.21 | 19.18 | 4.01 ms | 7.88 ms |

**These sustained results are poor and do not meet the requested 60 fps.** Capture is the limiting rate: both runs have zero credit-limit skips, with iMac GPU-start maxima of 0.24 / 0.15 ms and receiver-total maxima of 12.63 / 5.96 ms. Maximum presentation gaps are 116.7 / 100.0 ms, following missing source/capture images rather than a comparably large receiver-work interval. Idle capture callbacks contain no image to recover. The system was much slower than the earlier 0.2.8 session; a same-session previous-release control is recorded below before attributing this difference to code.

Back-to-back 45-second current-session controls measured **0.2.8: 16.74 captures/s and 16.76 presentation fps; 0.2.9: 16.92 captures/s and 16.95 presentation fps**, both with zero backpressure skips. This does not show the final low rate to be a new-release regression. On this less-demanding sparse/delta workload, Viewer upload setup was **1.74 → 1.34 ms** and GPU execution **3.97 → 3.45 ms**; ACK cycle was **20.62 → 19.57 ms**. Overall FPS remained source-limited. The source/system state differs materially from the earlier 56-fps session; no large end-to-end gain is inferred.

This variability is why the faster isolated upload costs are not advertised as stable desktop 60 fps. Large, less-compressible motion can also exceed this 1-Gbps link independently of these source waits.

## Correctness, delivery and next diagnostic boundary

Final Host self-tests pass on the Studio. Final Viewer self-tests pass over SSH on the actual AMD iMac. GPU texture readback compares every BC7 byte at 1440p, 4K and 5K for per-tile/coalesced paths and cached/write-combined memory. Cases include unordered full updates, adjacent runs, unchanged holes, row boundaries, partial bottom rows, queued deltas, staging reuse and sequence rejection. Existing authentication, encrypted loopback, malformed frame, chunked packing, retained ownership, reference BC7 decode and capture-mailbox checks continue to pass. No image-quality, authentication or transport-format change is made in this release.

Builds are ad-hoc signed and not notarized. Release artifacts preserve the tested executables, source, a Git history bundle, selected timing-only data and checksums. Previous releases remain intact. Exact current commit and installed/supplied executable hashes are in BUILD_INFO.json. Normal diagnostics are bounded to 120 samples, optional frame traces to 250,000 events. Experimental sources use bounded metadata only; no captured pixels, pairing codes or packet payloads are in the performance evidence.

Further exact attribution needs WindowServer/driver-side evidence or a properly controlled environment with other capture clients inactive. The app cannot create genuine new source images that WindowServer has not produced. Repeating the same source under lower system load, with a privileged read-only compositor trace if authorized, is a more informative next step than increasing frame credits or buffering stale frames. The private CGVirtualDisplay API remains an OS compatibility risk, and this work has not proved direct-monitor-equivalent latency.

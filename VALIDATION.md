# RetinaLink 0.2.9 build 32 — validation, 17 October 2026

## Outcome and limits

**The iMac upload path is faster and byte-exact. A major capture slowdown was caused by this agent’s own UI capture helper; stopping it restored near-60-fps scrolling. Strictly stable native 5K60 across desktop workloads has not been achieved.** Source-side Core Animation drawable waits were identified, and the UI helper is a demonstrated contributor to the severe slow state. The internal OS policy behind residual gaps remains unresolved. The earlier rare 245 ms iMac submission stall was not reproduced in an unprofiled final trial, so its exact cause is not claimed to be fixed.

All installation, motion tests, reconnection and log collection used the existing authorized SSH session. The machines remain a 2023 M2 Max Studio on macOS 27.0.1 and a 2014 Retina iMac on Big Sur 11.7.8 / Radeon R9 M290X. Native dimensions, encrypted pairing, the SSH Ethernet route and physical Viewer vsync are retained. Screen Sharing remained connected. No security or sharing settings were changed. Other capture clients remain a limitation of the environment.

The final iMac executable and Host are build 32, with all experimental presentation plans disabled. Builds 23–31 supply diagnostic/control evidence; build 30 also supplied the earlier sustained measurements. Requested refresh, generated frames, completed capture samples, GPU completions and positive presentation timestamps are kept distinct. No camera-based input-to-photon or physical frame-identity measurement was made.

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

## Diagnostic interference found late in validation

The low 16–20 fps tests below were taken while the agent-owned SkyComputerUseService UI bridge was active. Resetting its JavaScript session did not stop the helper. In `ui-bridge-reset-029`, terminating only that verified helper at about 21 seconds, while retaining the same Host stream, Viewer, scrolling source, AnyDesk and Screen Sharing connections, changed reported presentation rate from **16.43 fps before** to **58.18 fps afterward** over the measured phase windows. Direct live Host samples rose to about 50 and then 60 complete captures/s, with no missing-source timestamp gaps in the 60-fps sample. WindowServer load also fell. The helper remained off for subsequent SSH-only tests and will restart only if UI automation is used again.

This identifies a significant observer effect in the severe slow state, rather than a new 0.2.9 regression or a reason to blame the Ethernet switch. It does not prove that this helper caused every earlier presentation tail. The before/after phase rates use retained Viewer history: an overlapping next-test runner restarted Host before the quiet collector fetched its final snapshot, so that test's Host snapshot is marked invalid and not used for phase averages. The harness now publishes `collectionFinished` only after all evidence has been collected; callers should await the runner rather than merely the scene-finished timestamp.

## SSH-only sustained release measurements

With the UI bridge off, frame tracing disabled, and Screen Sharing still connected and visible:

| Build/workload | Duration | Capture/s | Delivered/s | Positive presentation fps | Host encode + pack | ACK cycle |
|---|---:|---:|---:|---:|---:|---:|
| 30 — bitmap-text scroll | 180 s | 58.99 | 58.95 | 58.10 | 5.84 ms | 25.25 ms |
| 30 — real AppKit window positions | 45 s | 51.92 | 51.92 | 50.95 | 3.51 ms | 8.64 ms |
| 32 — final bitmap-text scroll | 90 s | 56.96 | 56.95 | 55.90 | 5.83 ms | 24.76 ms |
| 32 — final real AppKit window positions | 45 s | 55.51 | 55.48 | 54.32 | 3.51 ms | 8.65 ms |

The three-minute scroll run's one-second presentation values ranged 48–61 fps; window boundaries explain values slightly above the nominal panel rate. Native window position calls averaged about 59.93/s, which is not proof of 60 new composited images. Thus the severe slowdown is resolved, but neither rate nor gap tails establish strictly stable 60 fps across workloads. The iMac retains a native 5120 × 2880 drawable. No duplicate images are inserted to inflate these figures.

A subsequent visible/minimized comparison with the UI helper stopped after each brief action measured 57.74 captures/s and 57.11 presentation fps before minimizing, versus 59.73 captures/s and 58.97 presentation fps while minimized. WindowServer load fell and the Screen Sharing client became idle. The planned post-restore steady window was too short after helper cleanup, so this is not a complete reversed comparison and is not used as proof of a permanent FPS gain. The window was restored, its connection retained, and the UI helper stopped again. This is useful headroom, not proof of fixed 60 fps.



## Residual presentation loss and rejected changes

A clean 75-second build-30 trace with the UI helper absent matched all **4,081** sent frames. It measured **59.61 complete captures/s, 59.60 GPU-completion acknowledgements/s and 58.69 positive presentation fps**. Maximum ACK cycle was **46.37 ms**, body assembly **26.68 ms**, GPU start delay **19.15 ms**, GPU execution **10.04 ms** and post-receive Viewer work **32.32 ms**. Presentation gaps had p95 **16.71 ms**, p99 **33.34 ms** and maximum **50.01 ms**. Source display-timestamp gaps had p99 **16.67 ms** and maximum **33.34 ms**; idle callbacks contained no missing image to recover.

Exactly **62 original frame drawables returned a zero presentation timestamp**, with no missing callbacks. Apple's [presentedTime documentation](https://developer.apple.com/documentation/metal/mtldrawable/presentedtime) identifies zero with an unpresented/dropped drawable. GPU work had completed promptly. For example, frame 473 completed GPU work about 13.6 ms before frame 472 became visible, yet frame 474 was shown next and 473 returned zero. This localizes this loss after GPU execution, in presentation/compositor selection, rather than slow BC7 decoding. It does not identify the internal OS scheduling decision. A build-31 trace additionally instruments surface-size changes and the separate resize-redraw path: no extra redraw presentations occurred during streaming, so those were not hiding the missing original-frame presentations.

Repeated 45-second three/two/three-drawable controls produced capture/render rates of about **58.24 / 59.74 / 58.61**, with positive presentation rates **57.34 / 58.63 / 57.61**. The displayed fraction did not improve with two drawables. Mean GPU-start delay fell from 3.97 to 0.13 ms, but the wait moved to drawable acquisition (0.33 to 5.67 ms), and receiver time rose from 13.62 to 16.18 ms. Default three-drawable rendering is retained.

Build 32 tests immediate/24-ms-target/immediate presentation in one continuous stream, 25 seconds per phase, with the first five and final two seconds of each phase excluded. Displayed fractions were **98.29% / 98.37% / 97.69%**. This small, variable difference does not establish a useful pacing gain. Mean commit-to-display time increased from **28.04 / 26.42 ms** in the controls to **35.91 ms** with timed presentation. All 15 nonpresented timed frames completed GPU work **13.3–20.5 ms before their requested target**, so merely allowing more GPU execution time was not the demonstrated problem. The experiment is bounded, opt-in, and automatically returns to immediate presentation; it is disabled in normal operation.

The final build-32 untraced runs retained zero credit-limit skips. Scroll/window-motion ACK maxima were **44.1 / 22.8 ms**, GPU-start maxima **16.73 / 7.36 ms**, and presentation-gap maxima **50.0 / 50.1 ms**. The old 245 ms iMac submission outlier did not recur. Source-image gaps and post-GPU selection still prevent a strict stable-60 claim. No interpolation, artificial duplicate-frame counter or silent resolution reduction is used.

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

A separate on/off/on/off ScreenCaptureKit control keeps the same virtual display and source alive. Source draws averaged **22.37 / 27.00 / 20.42 / 23.57 per second**, with mean drawable waits **44.36 / 36.45 / 48.02 / 41.30 ms**. Stopping our capture improves some headroom but does not restore 60, and the wait persists while it is stopped. This rules out our live encoder/transport as the sole cause; it does not prove ScreenCaptureKit has no contribution or that the private virtual-display implementation is faultless. This test preceded discovery of the UI helper interference described above.

Apple documents [nextDrawable](https://developer.apple.com/documentation/quartzcore/cametallayer/nextdrawable()) as waiting for an available drawable. The present investigation has not established the internal cause of the exhausted pool. Direct WindowServer sampling requires privileges; ordinary sampling was refused, and a noninteractive sudo attempt required a password. No credentials or system permissions were changed.

## iMac presentation/submission and acknowledgement tails

The production helper `commandBuffer.present(drawable)` registers a deferred operation. Timing its CPU call only measures registration. Apple describes this [scheduled-handler mechanism](https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Render-Ctx/Render-Ctx.html). Build 25 explicitly times drawable.present() from a scheduled handler. That alternative call averaged roughly 0.05 ms, with a maximum below 0.6 ms in the matched full/sparse/full test. However, it changed observed scheduling and presentation rate, so it is not a transparent measurement of the original helper. It remains opt-in and is excluded from release tests. This corrects the earlier implication that a quick registration call excludes all deferred presentation work.

The old 264.7 ms ACK / 244.7 ms pre-GPU-start outlier is still unexplained internally. New production-path traces can show different tails. In the source-profile run a 238 ms ACK cycle included only 12.75 ms of Viewer work and 225.26 ms of transport/unclassified endpoint residual. The same run included process sampling, so its tails must not be treated as unperturbed production measurements. The residual includes SSH/TLS and endpoint scheduling; it is not pure wire RTT. In a later unprofiled candidate trial, maximum iMac GPU-start delay was 9.01 ms, receiver work 16.52 ms, and ACK cycle 41.46 ms. No 245 ms presentation/submission outlier recurred there.

A transparent compositor-pulse on/off test improved after the pulse was removed as well as while it ran. It did not show a causal reversal and is not enabled. A Screen Sharing minimize/restore trial did not restore source frame rate; the connection was kept alive. A repeated AnyDesk quit comparison is **inconclusive**: normal Quit left a user-owned capture child running, its termination occurred late, and reopening required clearing stale user helpers and reopening via Finder. The root service and its settings were left intact. Its normal user-process set and background capture restarted, but the GUI automation could not confirm the window. That interval is excluded as a clean capture-off comparison and is not used to attribute a speed gain to AnyDesk.

## Earlier release tests with UI-bridge interference

The supplied build 30 is tested with no experimental probe flags and frame tracing disabled. The automatic one-second snapshots still run. First five and final two seconds are excluded from the aggregate summaries. The scroll test polls over SSH every two seconds; native window motion collects afterward.

| Workload | Duration | Capture/s | Delivered/s | Positive presentation fps | Host encode + pack | ACK cycle |
|---|---:|---:|---:|---:|---:|---:|
| Bitmap-text scroll | 180 s | 16.12 | 16.11 | 16.11 | 7.65 ms | 19.59 ms |
| Real AppKit window motion | 45 s | 19.28 | 19.21 | 19.18 | 4.01 ms | 7.88 ms |

**These sustained results are poor and were later found to include UI-bridge interference; the SSH-only tests above supersede them as the release-use measurement.** Capture is the limiting rate: both runs have zero credit-limit skips, with iMac GPU-start maxima of 0.24 / 0.15 ms and receiver-total maxima of 12.63 / 5.96 ms. Maximum presentation gaps are 116.7 / 100.0 ms, following missing source/capture images rather than a comparably large receiver-work interval. Idle capture callbacks contain no image to recover. The system was much slower than the earlier 0.2.8 session; a same-session previous-release control is recorded below before attributing this difference to code.

Back-to-back 45-second current-session controls measured **0.2.8: 16.74 captures/s and 16.76 presentation fps; 0.2.9: 16.92 captures/s and 16.95 presentation fps**, both with zero backpressure skips. This does not show the final low rate to be a new-release regression. On this less-demanding sparse/delta workload, Viewer upload setup was **1.74 → 1.34 ms** and GPU execution **3.97 → 3.45 ms**; ACK cycle was **20.62 → 19.57 ms**. Overall FPS remained source-limited. The source/system state differs materially from the earlier 56-fps session; no large end-to-end gain is inferred.

This variability is why the faster isolated upload costs are not advertised as stable desktop 60 fps. Large, less-compressible motion can also exceed this 1-Gbps link independently of these source waits.

## Correctness, delivery and next diagnostic boundary

Final build-32 Host self-tests pass on the Studio. Final build-32 Viewer self-tests pass over SSH on the actual AMD iMac. GPU texture readback compares every BC7 byte at 1440p, 4K and 5K for per-tile/coalesced paths and cached/write-combined memory. Cases include unordered full updates, adjacent runs, unchanged holes, row boundaries, partial bottom rows, queued deltas, staging reuse and sequence rejection. Existing authentication, encrypted loopback, malformed frame, chunked packing, retained ownership, reference BC7 decode and capture-mailbox checks continue to pass. No image-quality, authentication or transport-format change is made in this release.

The reproduction scene builder was also checked with the active Xcode SDK; this machine’s separately installed Command Line Tools SDK is newer than its selected Swift compiler, so the builder now honors RETINALINK_SDK and otherwise uses the active Xcode SDK.

Builds are ad-hoc signed and not notarized. Release artifacts preserve the tested executables, source, a Git history bundle, selected timing-only data and checksums. Previous releases remain intact. Exact current commit and installed/supplied executable hashes are in BUILD_INFO.json. Normal diagnostics are bounded to 120 samples, optional frame traces to 250,000 events. Experimental sources use bounded metadata only; no captured pixels, pairing codes or packet payloads are in the performance evidence.

Further exact attribution needs WindowServer/driver-side evidence or a properly controlled environment with other capture clients inactive. The app cannot create genuine new source images that WindowServer has not produced. Repeating the same source under lower system load, with a privileged read-only compositor trace if authorized, is a more informative next step than increasing frame credits or buffering stale frames. The private CGVirtualDisplay API remains an OS compatibility risk, and this work has not proved direct-monitor-equivalent latency.

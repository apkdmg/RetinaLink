# RetinaLink 0.2.8 build 22 — validation, 17 October 2026

## Outcome

**Lossless packing and total Host processing are faster. Stable native 5K60 across desktop workloads has not been achieved.** The installed release is 0.2.8 build 22 on both Macs. Tests, deployment, automatic reconnection and log collection were performed through the existing SSH session; no manual log copying was needed.

The measured machines are a 2023 M2 Max Mac Studio running macOS 27.0.1 and a Late-2014 Retina iMac running Big Sur 11.7.8 with AMD Radeon R9 M290X. Tests retain native 5120 × 2880 capture, a 5120 × 2880 fullscreen iMac drawable, vsync and encrypted five-digit pairing. Data crosses the wired LAN through the existing SSH reverse tunnel. Screen Sharing remained connected. Background system/capture activity was not fully controlled.

## Processing improvement

These 90-second trials use build 19 on both endpoints and the same fullscreen Core Animation bitmap-text scroll. Each trace analysis excludes the first five and final two seconds. The serial control is repeated after the parallel candidate because system frame rates vary.

| Packing | Capture/s | Presented fps | Encode + pack | Lossless pack | Viewer unpack |
|---|---:|---:|---:|---:|---:|
| Serial, pass A | 46.77 | 45.61 | 8.69 ms | 4.69 ms | 3.03 ms |
| Parallel | 55.58 | 54.49 | 6.09 ms | 2.59 ms | 2.55 ms |
| Serial, pass B | 55.56 | 54.48 | 7.93 ms | 4.66 ms | 3.12 ms |

Against the later control, packing takes about **44% less time**, total encode + pack about **23% less**, and Viewer unpacking about **18% less**. Presented FPS is essentially unchanged in that comparable pair. The slower first control must not be used to imply an isolated FPS improvement.

Large frames are split into four independently compressed LZ4 chunks, with parallel compression/decompression and owned output buffers. Small frames use the existing serial path. A capability in the greeting gates the new format, so older Viewers receive the original packets. BC7 tile bytes and image-quality settings are unchanged; the outer packet bytes naturally differ. In the matched pair payload throughput was 447.4 versus 444.9 Mbps at almost identical delivered rates, so the chunking did not introduce a large bandwidth penalty for this workload. High-entropy content can differ.

Viewer callbacks now retain only identity/dimensions after upload rather than full decoded 5K buffers. GPU dirty flags use boolean stores instead of read/modify/write. The latter preserves output and static suppression but has no demonstrated isolated FPS gain. The capture configuration and bounded three-frame protocol remain unchanged from 0.2.7.

## Where capture gaps originate

A 90-second capture-only trial that immediately releases buffers reached **59.96 complete samples/s**. It encoded and displayed no frames. A separate 90-second trial that captures, encodes and packs but discards packets reached **54.97 complete samples/s**, with no sent frames or ACK-dependent credits. Thus the capture-rate reduction can occur with networking and Viewer processing removed.

The complete-frame source timestamps themselves contain 33.3 ms gaps. Idle callbacks contain no image to recover. Apple's [idle status documentation](https://developer.apple.com/documentation/screencapturekit/scframestatus/idle) identifies these as cases without a new display image. This localizes the missing-frame problem to capture/frame-production pacing under Host processing load; it is not simply a backlog of valid images waiting on the application's capture callback queue. It does **not** establish the exact WindowServer, driver, surface-lifetime or competing-capture cause.

In the final real AppKit-window trial the source issued **59.96 position changes/s**, but capture averaged **44.95/s**, with **zero credit-limit skips** and an **8.7 ms average ACK cycle**. Issuing positions is not independent proof that WindowServer presented all of them. It does show why increasing network throughput or the credit count cannot solve that run.

## Where acknowledgement tails originate

Per-frame metadata links packing, body receipt, decoding, drawable acquisition, GPU work, presentation and ACKs by sequence number. Elapsed intervals are measured on each machine independently, avoiding reliance on synchronized wall clocks.

- In `trace18-quiet-b`, one ACK cycle took **264.7 ms**. Viewer work accounted for **254.4 ms**; the pre-submit-to-GPU-start interval was **244.7 ms**, while actual GPU execution was **4.4 ms** and its completion callback followed promptly. The old trace location includes CPU presentation/submission calls, so this frame does not prove that all 244.7 ms was GPU scheduling. It does isolate the large delay to the iMac presentation/submission path rather than LAN transfer.
- In `trace18-quiet-a`, another **74.6 ms** cycle contained **48.1 ms** of Viewer body assembly and only **10.0 ms** of post-receive Viewer work. Transfer/TLS/SSH and endpoint scheduling can therefore create a different kind of tail.
- Build 20 separates presentation-call time and command-commit time from GPU-start timing. In its default scroll trial presentation calls averaged **0.030 ms** (maximum **0.185 ms**) and commit calls **0.012 ms** (maximum **0.097 ms**). Completion callbacks averaged **0.068 ms** after GPU end. The earlier 245 ms outlier did not recur in that trial; its exact internal cause remains unresolved.

The transport residual subtracts Viewer elapsed work from Host ACK-cycle elapsed time. It includes TLS/SSH, transfer and unclassified endpoint overhead, including Host ACK application time. It is not pure network RTT and does not identify the company switch as the cause.

Quiet/poll/quiet scrolling trials averaged **54.45 / 54.15 / 51.66 presented fps**. Two-second SSH polling did not show a consistent penalty. Viewer GPU callbacks were consistently prompt. Raising the requested animation rate to 60 did not establish an improvement: build 20's explicit-source-hint trial averaged 49.50 presented fps versus 57.71 in the preceding default trial. Source/system variability remains material.

An opt-in minimum-presentation-duration experiment in build 21 averaged **57.68 presented fps** against **58.65 delivered/s**, versus **57.71** against **59.08** in the earlier unpaced trial. It did not establish better sustained output or frame-gap tails and is excluded from release 22. The default vsynced presentation policy is preserved.

## Final release tests, with frame tracing disabled

| Workload | Duration | Capture/s | Delivered/s | Presented fps | Encode + pack | ACK cycle |
|---|---:|---:|---:|---:|---:|---:|
| Native AppKit window motion | 45 s | 44.95 | 44.89 | 43.67 | 4.17 ms | 8.70 ms |
| Fullscreen bitmap-text scroll | 180 s | 56.42 | 56.31 | 55.44 | 6.06 ms | 25.45 ms |

The three-minute run's one-second presentation samples ranged **39.9–60.1 fps**. Counter-window boundaries explain occasional values slightly above 60; they are not a faster panel. Payload averaged about **455 Mbps**. Worst automatic per-frame stage values recorded during active scrolling were **48.6 ms body assembly**, **16.78 ms submission-to-GPU-start**, **0.33 ms completion-callback delay**, **0.07 ms presentation call**, and **33.4 ms post-receive receiver total**. These maxima need not belong to the same frame. The earlier 245 ms presentation/submission outlier did not recur in this final run.

The highest complete traced default scrolling trial averaged **57.71 presented fps**, with **59.09 complete captures/s**, over 90 seconds. It must not replace the longer release result or the slower real-window result when evaluating the 60 fps target.

One-second counters use their own sampling windows, so delivered/rendered/presented rates can differ slightly at boundaries. These final results are averages of active one-second samples excluding the first five and final two seconds. Frame-trace results above instead count individual matched sequences within that interval. Requested refresh rates, source callback counts, complete capture samples, GPU completions and positive presentation callbacks are distinct measurements. Static desktops intentionally send few updates. No camera-based input-to-photon measurement was made.

## Correctness and delivery

Final Host self-tests pass on the Studio; final Viewer self-tests pass over SSH on the actual iMac GPU. Coverage includes authentication/rejection, old/new greeting compatibility, bounded credits, serial and parallel frame parsing, exact tile bytes at 1440p/4K/5K, retained packet ownership, incompressible/mixed chunks, malformed lengths and compressed-input rejection, 5K private-texture upload/readback, queued deltas, bottom-edge pixels, independent BC7 decode, row-major/tile-major equality and bounded mailbox behavior. The dirty-flag/flat-block comparison checks 230,400 varied blocks against the original GPU encoder. New tests verify that brief timing spikes survive averaging and maxima reset each interval.

Both final app signatures are verified. Viewer is universal Intel/Apple silicon. Builds are ad-hoc signed and not notarized. The supplied and installed Viewer executable hashes are compared in delivery metadata. Existing releases are preserved. Privacy, firewall, sharing and network settings were not changed.

BC7 remains lossy. Fullscreen high-detail motion can exceed the bandwidth of these text scenes. Thunderbolt, colour-reference accuracy, thermal endurance and direct-monitor-equivalent latency have not been established. The private virtual-display API remains an operating-system compatibility risk.

Use the parent **RetinaLink SSH Tunnel.command**. Host resides in this release folder; Viewer is installed at `~/Applications/RetinaLink-0.2.8/RetinaLink Viewer.app`. Both use existing pairing and automatic connection settings. Keep the iMac unlocked.

Automatic diagnostics remain bounded to 120 records and now include per-interval maxima for ACKs, body assembly, presentation calls, submission-to-GPU-start and completion callbacks. Opt-in frame traces are metadata-only and capped at 250,000 events. `Tools/README.md` documents capture/encode-only probes, trace analysis and automated SSH testing. `Performance/` contains raw aggregate samples, manifests, selected compressed metadata traces and correctness logs. The analyzer can read either `.jsonl` or `.jsonl.gz`.

The local Git history starts with tested 0.2.7 commit `2659ee5`. Delivery metadata identifies the release commit; the included Git bundle preserves history without publishing it to a remote service.

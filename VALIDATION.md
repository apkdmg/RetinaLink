# RetinaLink 0.2.7 build 16 — validation, 17 October 2026

## Result

**The capture path is faster, but sustained 5K60 across the tested desktop workloads remains unresolved.** Final matched fullscreen scrolling runs averaged **51.24 and 53.87 presented fps** on 0.2.7, versus **49.01** on Host 0.2.6. Encode + pack fell from **10.07 ms to 7.90 ms**, about **22% less time**. Native resolution and compression quality are preserved.

The actual machines are an M2 Max Mac Studio / macOS 27.0.1 and a Late-2014 iMac / AMD R9 M290X / Big Sur 11.7.8. Both final apps are installed as 0.2.7 build 16. SSH was used for deployment, automatic reconnection, native GPU correctness tests and collection of diagnostics. No manual log copying was required.

## Final matched Host comparison

All three runs use Viewer 0.2.7 build 16, native fullscreen 5120 × 2880 with vsync, the same Core Animation scrolling scene and encrypted protocol through the existing SSH tunnel over Ethernet. Each run lasts 60 seconds. Host 0.2.6 is tested between two runs of final Host 0.2.7 to expose run-to-run variation. The 0.2.7 Viewer retains the same frame parsing, texture upload, rendering and presentation counting as 0.2.6.

| Host | Complete captures/s | Presented fps | Viewer payload Mbps | Encode + pack |
|---|---:|---:|---:|---:|
| 0.2.7 build 16, pass A | 52.11 | 51.24 | 416.19 | 7.90 ms |
| 0.2.6 build 10, control | 49.99 | 49.01 | 398.61 | 10.07 ms |
| 0.2.7 build 16, pass B | 55.06 | 53.87 | 437.86 | 7.89 ms |

The final 45-second moving-card scene averaged **58.10 presented fps**, with 58.73 captures/s and 3.35 ms encode + pack. It moves a rasterized text card within a fullscreen compositor window.

The additional 90-second native AppKit-window test averaged **48.86 presented fps**, with 49.75 captures/s. It moves a real 1000 × 700-point titled window around the native 5K virtual desktop, issuing position changes through a display link. The source's issued-update counter is separate from actual iMac presentations. See `final-027-native-window` and its source code.

## Capture and CPU work

The new GPU buffer layout changes storage order only. At every supported resolution, compressed tile bytes are checked against the old row-major layout, including tile boundaries and partial bottom rows. In the instrumented scrolling comparison, tile gathering fell from about **1.70 ms to 0.55–0.58 ms**. Reusable packing fell from about **6.00 ms to 4.6 ms**, without changing packet bytes in the correctness workloads. The final scrolling runs spend about 1.7–1.8 ms in the encoder GPU itself; GPU submission/waiting is reported separately.

ScreenCaptureKit now follows the 60 Hz virtual display's native capture clock, using a zero minimum interval for the target-60 profile. The target-30 profiles retain 1/30. The surface pool is five, bounded by the internal 3–8 range. The latest-frame mailbox, three-frame transport limit and ordered delta-frame semantics remain bounded. The extra capture surfaces trade memory for scheduling headroom. A surface-pool setting is distinct from encoded-frame queueing.

Host uses scoped latency-critical activity, and both endpoints hold a display-sleep assertion during the stream. These assertions are released on stop and do not change system preferences or override manual locking. Latency-critical scheduling was investigated in a 45-second candidate trial; its overall FPS benefit cannot be isolated from background variation, though its timer/I/O purpose fits a live capture session.

Apple documents [minimumFrameInterval](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/minimumframeinterval) as a throttle and [queueDepth](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/queuedepth) as the capture-frame pool limit. The chosen values are exercised on the actual machines here; documentation alone is not frame-rate evidence.

## Why this is not a stable-60 claim

- A 30-second candidate build 14 trial averaged **59.93 complete captures/s** and **59.17 presented fps**. That source also registered a 60 Hz display-link callback. A larger pool of eight did not establish an improvement. These short runs do not establish sustained performance.
- A three-minute candidate build 15 scrolling run, without the source display-link callback, averaged **55.27 captures/s** and **54.29 presented fps**. It varied substantially despite encode + pack remaining around 7.9 ms.
- A capture-only diagnostic that immediately released screen buffers reached about 58.9 captures/s with an unthrottled capture clock. It delivered no frames to Viewer and is not a displayed-FPS measurement.
- During the approved 30-second AnyDesk pause, capture averaged about **59.4/s**, but delivery averaged about **48/s** as ACK cycles varied up to **130.1 ms**. Viewer body assembly also slowed. These timings cover transport, decryption, scheduling and receiver processing; they do not isolate the network hardware as the cause. AnyDesk was reopened after 30.2 seconds; Screen Sharing and SSH stayed connected. Reopening the app does not guarantee automatic restoration of an incoming AnyDesk capture session.
- Changing a source through a 60 Hz callback did not guarantee 60 captured or presented frames. The explicit-source trial was slower; its callback rate is not treated as actual screen presentation.

The telemetry identifies more than one limit: missing new capture frames in some periods, and delivery/ACK stalls in others. Background AnyDesk and Apple Screen Sharing activity varied and was not fully controlled. A target, source callback, GPU completion, capture sample and physical presentation are separate measurements. ACK is not input-to-photon latency.

## Correctness, installation and limits

Final Host self-tests pass on the M2 Max. Final Viewer self-tests pass directly on the actual iMac GPU through SSH. Checks cover authentication/rejection, framing, compressed/shared buffers, 5K GPU-private upload/readback, queued deltas, unchanged tiles, bottom-edge pixels, BC7 reference decode and bounded mailbox behavior. Host additionally checks 230,400 varied flat/non-flat blocks against the original encoder, row-major/tile-major byte equality at all three resolutions, full-5K reusable packing and independent packet ownership after scratch reuse.

Both supplied app bundles pass strict code-signature verification. Viewer is universal x86_64/arm64; its installed executable is compared with the supplied copy in `SHA256SUMS.txt`. Builds are ad-hoc signed and not notarized. Saved encrypted five-digit pairing is retained. System privacy, firewall, sharing and network settings were not changed. Prior releases are preserved.

BC7 remains lossy. Fullscreen high-detail motion can require more bandwidth than the text scenes, and these measurements do not establish a guarantee for all content. No camera-based latency test, thermal endurance test, colour-reference validation or verified Thunderbolt comparison was performed. Native 5K is verified through the virtual display mode, capture-buffer dimensions and the iMac's 5120 × 2880 drawable. A static desktop deliberately sends few updates.

## Evidence and operation

`Performance/` contains raw timing samples, test manifests, correctness logs and test sources. `endpoints.json` and `variant.json` identify final test builds and arguments where present. The earlier experiment build numbers are 12 (capture telemetry/probe), 13 (optional tile layout), 14 (optional reusable packer and pool comparison), 15 (optimized capture defaults), and final 16 (installed release with scoped activity/display-sleep handling).

Use **RetinaLink SSH Tunnel.command** from the parent outputs folder. Host is supplied here, and Viewer is installed at `~/Applications/RetinaLink-0.2.7/RetinaLink Viewer.app` on the iMac. Viewer uses saved 127.0.0.1 / Automatic settings and the existing encrypted code. The “Local test” label refers to the tunnel entrance; the data crosses the Ethernet LAN. Logs are collected automatically and the iMac must remain logged in and unlocked.

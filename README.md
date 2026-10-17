# RetinaLink 0.2.10

RetinaLink extends a Mac Studio desktop to the native 5120 × 2880 panel of a 2014 5K iMac over an IP network. Host requires Apple silicon and macOS 13+. Viewer includes Intel macOS 10.15+ and Apple silicon macOS 11+ binaries. The tested receiver is Big Sur 11.7.8 with an AMD Radeon R9 M290X.

**The receiver is preserving frames that its Metal callbacks incorrectly mark with zero or repeated presentation timestamps. A separate Instruments display trace retained all 887 interior app frames, at 59.05 updates/s in that profiled interval. Stable native 5K60 across desktop workloads remains unresolved because genuine upstream timing gaps remain.** See `VALIDATION.md` for the display/callback comparison, rejected pacing experiments and final checks.

Final build-38 SSH tests complete **59.97–59.98 updates/s** in two native-5K scrolling workloads, with no credit skips or coalesced captures. Native-window motion averages **59.15 GPU-completed updates/s**, with some gaps already at capture. These are completed-update rates, not independently measured physical display FPS.

## Changes in 0.2.10 build 38

- When all transfer credits are busy, Host retains the latest pending capture and resumes on acknowledgement. It no longer throws that image away and waits for another capture. This also preserves the final changed image when the desktop becomes static; retention remains bounded to one replaceable pending image.
- Diagnostics separate GPU-completed updates from **API presentation timing**. Unique timestamp and positive callback rates are labeled as API metadata rather than physical display FPS. Zero/repeated timestamps are reported as timing anomalies; they do not prove a displayed frame was lost on this iMac.
- The capture texture's Core Video wrapper stays alive until GPU completion, as required by Core Video. This is ownership hardening, not a measured FPS gain.
- Optional physical refresh-clock traces expose an approximately five-second refresh-prediction correction cycle associated with callback anomalies. An independent Metal System Trace shows individual display intervals for zero-timestamp frames and separate intervals for repeated-timestamp pairs.
- Single-presentation, timed-refresh and submission-pacing experiments did not establish a useful production improvement. They remain disabled; normal operation uses native vsynced presentation and three bounded frames in flight.

The prior coalesced BC7 uploads and write-combined staging improvements are retained. Their isolated GPU/CPU gains are independent of this presentation investigation. No interpolated or forced duplicate images are inserted to increase counters.

## Changes in 0.2.9 build 32

- Adjacent changed BC7 tiles on the same tile row are uploaded as a single rectangle. A full 5K frame uses 23 blits instead of 920. Unchanged holes and row boundaries remain separate, and every compressed pixel byte is preserved.
- CPU-write-only staging buffers use write-combined memory, and their destination pointer is acquired once per upload. GPU completion still owns staging-buffer reuse; transport remains bounded to three frames.
- GPU readback regression tests cover the original and coalesced upload paths, both memory modes, all three resolutions, unordered tiles, sparse holes, bottom edges and queued updates.
- Optional traces also account for resize redraws and bounded presentation-timing experiments. Neither two-drawable nor delayed-presentation experiments established a suitable production gain, so normal vsynced presentation remains the default.
- Capture timestamp diagnostics retain signed callback/display offsets. Virtual-display timestamps were often ahead of delivery; clamping them to zero had hidden this detail.
- Additional opt-in, bounded probes isolate buffer holding, source versus copied-surface encoding, capture on/off and standalone iMac presentation. They are disabled in normal use. No experiment that merely increases requested rates or reports GPU completions as presentations is enabled.

The lossless parallel packet format from 0.2.8 is retained, with legacy-peer fallback. See the preceding release for its packing comparison.

The native capture clock, five-surface ScreenCaptureKit pool, bounded latest-frame mailbox and negotiated three-frame transport limit from 0.2.7 remain. BC7 tile bytes, native resolution, encrypted pairing and the default vsynced rendering policy are preserved. Physical-display vsync remains enabled; the source-vsync and deferred-presentation experiments are diagnostic options only.

## Use on these two Macs

The installed iMac Viewer is `~/Applications/RetinaLink-0.2.10/RetinaLink Viewer.app`. The Studio Host is in the supplied `RetinaLink-0.2.10` folder. Use **RetinaLink SSH Tunnel.command** from the parent outputs folder to start the tunnel and apps. It reuses the existing SSH session when available. If SSH needs a password, enter it locally in Terminal.

The current tunnel connects the iMac's `127.0.0.1:58473` to the Studio Host. Viewer uses **127.0.0.1** and **Automatic** networking, with the existing five-digit code. The app's “Local test” path label describes the tunnel entrance; traffic still crosses the Ethernet LAN. The tunnel is a workaround for the measured direct transport slowdown on this setup, not a claim that every network needs SSH.

The helper starts Host with `--autostart` and Viewer with `--autoconnect --fullscreen`. It does not replace existing running copies. If an app is already open but manually stopped, use its Start hosting or Connect button. Explicit Disconnect or closing Viewer's display stops automatic retries; reopening via the helper restores automatic mode.

Keep the iMac logged in and unlocked. Its default Retina scale, normally “looks like 2560 × 1440”, gives a 5120 × 2880 fullscreen drawable. Escape exits fullscreen. Move windows using the Studio's keyboard and mouse. Audio and input forwarding are not included.

## Ordinary network connections

Both Macs may use the same wired LAN, Wi-Fi, or a reachable Thunderbolt Bridge IP link. Host listens on TCP 58473 and advertises `_retinalink._tcp` through Bonjour. If discovery fails, enter the Host's IP manually. A plain USB cable does not inherently create this network link. Thunderbolt hardware has not been tested here.

Profiles are native 5K target 60 fps, native 5K target 30 fps, and an explicit 2560 × 1440 target-30 Wi-Fi preview. There is no silent downscaling. A target is not a measured delivered frame rate.

Pairing modes are a saved five-digit code, a per-launch long random code, and explicit unencrypted no-code testing. Use the same mode on both ends. Short codes are convenient but easy to guess; long codes provide stronger pairing. There is no automatic downgrade after an authentication failure. The current setup remains encrypted.

## Diagnostics and remote testing

Timing snapshots are saved automatically in `~/Library/Logs/RetinaLink/Host.json` and `Viewer.json` on their respective Macs. They contain at most 120 records, with restricted file permissions. They contain no screen images or pairing codes. `--diagnostics-path /absolute/file.json` selects an alternate location. During development, the Studio uses the workspace's `work/host-live.json`.

`--trace-path /absolute/file.jsonl` enables a separate metadata trace, capped at 250,000 events and written in batches. It contains no screen images, pairing codes, packet payloads or window titles. Leave it off for ordinary use. See `Tools/README.md` for automated tests.

An SSH reader can fetch these logs without UI automation or clipboard copying. Copy diagnostics remains available for convenience. Useful launch options are `--autostart` for Host and `--autoconnect --fullscreen` for Viewer. Existing saved pairing settings are reused.

- Delivered updates count GPU-completion acknowledgements.
- Rendered updates count completed Viewer GPU commands.
- Presentation timing reports unique API timestamps and positive callbacks separately from GPU completions. These driver timestamps can repeat or be zero for displayed frames on this iMac; neither API rate is physical display FPS. A separate system display trace is needed to investigate actual retained frames.
- ACK time includes transport and receiver work; it is not input-to-photon latency.
- Capture reports complete samples, unchanged encoded images, credit-limit skips and inactive samples. A static desktop should not send 60 duplicate images per second.

## Permissions and limits

Host uses ScreenCaptureKit for actual capture authorization. If denied, it keeps the connection and offers Retry capture after permission is granted. If macOS requires a restart, reopen the same Host app. Builds are ad-hoc signed and not notarized, so updates can require app-specific reauthorization. The code does not change system privacy settings.

BC7 texture compression is lossy despite native resolution. Fine coloured detail and gradients can change; this is not a reference-colour display pipeline. Fullscreen motion costs more than a small moving window. One Viewer is supported. There is no audio, clipboard sync, separate cursor channel or remote input. Protected content and login/FileVault screens are not provided. The virtual display uses the undocumented CGVirtualDisplay API and may break after macOS changes.

## Build and verify

Run `bash build.sh` with full Xcode installed. `RETINALINK_BUILD_DIR` chooses the output directory and `RETINALINK_SDK` selects a compatible SDK. `RETINALINK_SIGN_IDENTITY` can select an existing signing identity; the default is ad-hoc signing. Build products include Host arm64 and Viewer universal arm64/x86_64.

Run the app executable with `--self-test` for authentication, framing, GPU upload/readback, packet ownership and codec/layout regression checks. Host also supports `--permission-test` for simulated authorization-denial recovery and `--transport-test` for large-message integrity tests. These correctness tests do not prove desktop frame rate. The physical-iMac tests and their exclusions are documented in `VALIDATION.md`.

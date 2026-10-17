# RetinaLink 0.2.7

RetinaLink extends a Mac Studio desktop to the native 5120 × 2880 panel of a 2014 5K iMac over an IP network. Host requires Apple silicon and macOS 13+. Viewer includes Intel macOS 10.15+ and Apple silicon macOS 11+ binaries. The tested receiver is Big Sur 11.7.8 with an AMD Radeon R9 M290X.

**0.2.7 reduces capture-side encoding and packing time by about 22% in the final comparison. Sustained 5K60 across the tested desktop workloads has not been achieved.** Final native 5K scrolling runs averaged 51.2 and 53.9 presented fps, versus 49.0 with Host 0.2.6. The moving-card run averaged 58.1; native AppKit window motion averaged 48.9. See `VALIDATION.md` for complete methods and limitations.

## Changes in 0.2.7 build 16

- The GPU writes compressed blocks in tile order. Host gathers each changed tile with one contiguous copy, reducing measured tile gathering from about 1.7 ms to 0.6 ms per fullscreen scrolling frame.
- Frame packing reuses raw, compressed and LZ4 scratch buffers. Returned network packets own their bytes. Measured packet packing fell from about 6.0 ms to 4.6 ms.
- The native 60 Hz virtual display supplies the capture clock without a second 1/60 throttle. Target-30 profiles retain their explicit throttle. Capture dimensions and resolution checks remain in place.
- The ScreenCaptureKit surface pool increases from three to five. The capture mailbox continues to retain only the newest waiting image; encoded deltas remain ordered and the negotiated in-flight limit remains three.
- Host requests latency-critical activity while streaming. Both endpoints prevent idle display sleep during a connected stream and release their activity on stop. Manual locking and sleeping remain available.
- Automatic diagnostics now separate capture status/timestamp gaps, GPU work, GPU submission/waiting, tile gathering and packet packing.

The compressed image bytes, native resolution, BC7 quality algorithm, encrypted pairing and Viewer rendering path are preserved. Row-major/tile-major equality is tested at 1440p, 4K and 5K, including partial bottom tiles. Reusable packing is compared with the original packets and checked for output retention across scratch-buffer reuse.

## Use on these two Macs

The installed iMac Viewer is `~/Applications/RetinaLink-0.2.7/RetinaLink Viewer.app`. The Studio Host is in the supplied `RetinaLink-0.2.7` folder. Use **RetinaLink SSH Tunnel.command** from the parent outputs folder to start the tunnel and apps. It reuses the existing SSH session when available. If SSH needs a password, enter it locally in Terminal.

The current tunnel connects the iMac's `127.0.0.1:58473` to the Studio Host. Viewer uses **127.0.0.1** and **Automatic** networking, with the existing five-digit code. The app's “Local test” path label describes the tunnel entrance; traffic still crosses the Ethernet LAN. The tunnel is a workaround for the measured direct transport slowdown on this setup, not a claim that every network needs SSH.

The helper starts Host with `--autostart` and Viewer with `--autoconnect --fullscreen`. It does not replace existing running copies. If an app is already open but manually stopped, use its Start hosting or Connect button. Explicit Disconnect or closing Viewer's display stops automatic retries; reopening via the helper restores automatic mode.

Keep the iMac logged in and unlocked. Its default Retina scale, normally “looks like 2560 × 1440”, gives a 5120 × 2880 fullscreen drawable. Escape exits fullscreen. Move windows using the Studio's keyboard and mouse. Audio and input forwarding are not included.

## Ordinary network connections

Both Macs may use the same wired LAN, Wi-Fi, or a reachable Thunderbolt Bridge IP link. Host listens on TCP 58473 and advertises `_retinalink._tcp` through Bonjour. If discovery fails, enter the Host's IP manually. A plain USB cable does not inherently create this network link. Thunderbolt hardware has not been tested here.

Profiles are native 5K target 60 fps, native 5K target 30 fps, and an explicit 2560 × 1440 target-30 Wi-Fi preview. There is no silent downscaling. A target is not a measured delivered frame rate.

Pairing modes are a saved five-digit code, a per-launch long random code, and explicit unencrypted no-code testing. Use the same mode on both ends. Short codes are convenient but easy to guess; long codes provide stronger pairing. There is no automatic downgrade after an authentication failure. The current setup remains encrypted.

## Diagnostics and remote testing

Timing snapshots are saved automatically in `~/Library/Logs/RetinaLink/Host.json` and `Viewer.json` on their respective Macs. They contain at most 120 records, with restricted file permissions. They contain no screen images or pairing codes. `--diagnostics-path /absolute/file.json` selects an alternate location. During development, the Studio uses the workspace's `work/host-live.json`.

An SSH reader can fetch these logs without UI automation or clipboard copying. Copy diagnostics remains available for convenience. Useful launch options are `--autostart` for Host and `--autoconnect --fullscreen` for Viewer. Existing saved pairing settings are reused.

- Delivered updates count GPU-completion acknowledgements.
- Rendered updates count completed Viewer GPU commands.
- Presentation counts timestamped drawable presentations on supported macOS versions. An occluded, sleeping or locked display can render without presenting.
- ACK time includes transport and receiver work; it is not input-to-photon latency.
- Capture reports complete samples, unchanged encoded images, credit-limit skips and inactive samples. A static desktop should not send 60 duplicate images per second.

## Permissions and limits

Host uses ScreenCaptureKit for actual capture authorization. If denied, it keeps the connection and offers Retry capture after permission is granted. If macOS requires a restart, reopen the same Host app. Builds are ad-hoc signed and not notarized, so updates can require app-specific reauthorization. The code does not change system privacy settings.

BC7 texture compression is lossy despite native resolution. Fine coloured detail and gradients can change; this is not a reference-colour display pipeline. Fullscreen motion costs more than a small moving window. One Viewer is supported. There is no audio, clipboard sync, separate cursor channel or remote input. Protected content and login/FileVault screens are not provided. The virtual display uses the undocumented CGVirtualDisplay API and may break after macOS changes.

## Build and verify

Run `bash build.sh` with full Xcode installed. `RETINALINK_BUILD_DIR` chooses the output directory and `RETINALINK_SDK` selects a compatible SDK. `RETINALINK_SIGN_IDENTITY` can select an existing signing identity; the default is ad-hoc signing. Build products include Host arm64 and Viewer universal arm64/x86_64.

Run the app executable with `--self-test` for authentication, framing, GPU upload/readback, packet ownership and codec/layout regression checks. Host also supports `--permission-test` for simulated authorization-denial recovery and `--transport-test` for large-message integrity tests. These correctness tests do not prove desktop frame rate. The physical-iMac tests and their exclusions are documented in `VALIDATION.md`.

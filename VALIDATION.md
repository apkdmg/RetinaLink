# Published 0.8.8 build 76 — 21 October 2026

**[RetinaLink 0.8.8 is public](https://github.com/apkdmg/RetinaLink/releases/tag/v0.8.8).** Its six release assets and both signed public update feeds pass anonymous HTTPS size/SHA-256 verification; both appcast and update-archive signatures verify with the existing Sparkle identity. Host PKG, Viewer DMG, role-specific update ZIPs, matching GPLv3 source and checksums are available. The immutable release tag points to clean application commit `b2f00bd0f4bf8bde1bf6a9314e29ba03ba5f7147`.

Build 76 contains the same application source as the installed build-75 compression comparison below, with an incremented build number so test installations can receive the public update. It includes the Viewer physical-session fix from the internal build-74 tests. The matching source archive includes the pinned Sparkle source and vendored dependencies; it excludes local test data and unrelated untracked files.

The final notarized Host passes complete self-tests, including exact compression round trips and GPU upload checks. Both app roles pass session-state, pairing-recovery and wake-recovery checks; update-relay, saved-display, account-recovery and display-removal regressions pass. All **124 offline policy tests** pass when modules run in separate Python processes (aggregate discovery has an existing `test_usb_link` module-name collision). A first saved-display trial could not bind its fixed stream-test port because an unrelated Codex HTTPS connection occupied port 58582; the same checks pass using available ports 62281/62282. This was isolated test infrastructure, not a production reconnect failure.

The exact stapled Viewer archive bundled in Host was copied to a disposable directory on the actual macOS 11.7.11 Radeon R9 M290X iMac. Signature, Gatekeeper, full self-tests and Viewer session tests pass. The disposable copy was removed. Publication did not replace either installed app; the performance evidence remains the build-75 hardware comparison below. Existing bundle identifiers, designated requirements, developer team, pairing namespace, updater keys/feeds and minimum OS versions match build 75. No new physical login/logout or panel-presentation measurement is claimed.

Apple accepted and tickets were stapled for:

| Artifact | Apple submission |
| --- | --- |
| Viewer app | `19bcb189-3f54-45f1-afe2-62e399292e78` |
| Host app | `41d1e15b-7d66-4857-9ae7-96d47069f017` |
| Host PKG | `56ddb9f4-ae8b-4b34-8b98-0cecadc257eb` |
| Viewer DMG | `317a71e2-18b2-4fb9-8d76-8f37e8d1831a` |

Installer verification checks the exact accepted app payload, bundled Viewer ticket, DMG layout and disposable drag-copy signature. Public asset hashes are in the release's `v0.8.8-SHA256SUMS`. Local publication evidence is in `work/github-publication-0.8.8-build76/`, including `release-validation.json`, `public-verification-final.json`, `public-feed-signatures.json`, final signed-app and actual-iMac logs. Accepted artifacts are in `work/release-0.8.8-build76/`, `work/pkg-0.8.8-build76/`, `work/dmg-0.8.8-build76-viewer/` and `outputs/`.

# Lossless BC7 packing installed and measured — 21 October 2026 (0.8.8 build 75)

**The optimized build is installed on both Macs. Native-5K full-screen motion improves from 25.51 to 35.27 delivered updates/s (+38.30%) with approximately 27.69% fewer bytes per frame and no additional image loss.** The existing BC7 encoder is unchanged; the new packing step restores its bytes exactly. BC7 itself remains the existing lossy image codec. Heavy full-screen motion still does not reach 60 updates/s.

The comparison uses the same signed build 75 on both Macs, the same 5120 × 2880 full-screen Metal gradient, three frame credits, and 60-second runs. The control uses Host `--no-shuffled-packing`; the enabled run uses the default. Each contains 53 settled one-second samples, excluding startup/final edges. Both use authenticated TLS over IPv6 on the same USB cable. The Host PID and connection remain constant within each run, every observation identifies USB, and independent counters show corresponding traffic on Studio `en9` and iMac `en7` (about 22.8 GB over each complete collection interval). No SSH polling or UI capture helper runs during motion. An interrupted trial during post-install reconnection is explicitly discarded.

| Full-screen 5K measurement | Compression disabled | Compression enabled |
| --- | ---: | ---: |
| Mean delivered updates/s | 25.506 | 35.274 |
| One-second delivered range | 24.0–26.0 | 34.2–36.0 |
| Application throughput | 2,864.96 Mbps | 2,865.01 Mbps |
| Approximate MB per delivered frame¹ | 14.041 | 10.153 |
| Mean capture callbacks/s | 59.740 | 59.974 |
| Mean encode + pack | 11.268 ms | 11.251 ms |
| Mean acknowledgement interval | 106.375 ms | 73.798 ms |
| Captures coalesced/s | 34.245 | 24.698 |
| New-format frames / encoded frames in settled samples | 0 / 1,352 | 1,869 / 1,869 |

¹ Estimated from mean application throughput divided by delivered updates; send/ack interval boundaries make this an approximation. Separately, the identical synthetic fixture falls from **14,034,418 to 10,138,189 bytes (27.76%)**, with byte-for-byte reconstruction. Full-frame text/window fixtures retain the original format and their **259,733 / 125,600 byte** packets. At the measured link throughput, 60 full-screen updates/s would require about 6.0 MB/frame, versus about 10.15 MB now. The improvement uses the existing available throughput more efficiently; it does not increase the USB signaling rate or measured link capacity.

The adaptive path also passes two further 60-second native-5K trials:

| Desktop workload with optimization enabled | Mean delivered updates/s | Throughput | New-format frames / encoded frames |
| --- | ---: | ---: | ---: |
| Native moving window | 59.432 | 376.60 Mbps | 0 / 3,150 |
| Core Animation bitmap-text scrolling | 59.748 | 483.82 Mbps | 0 / 3,226 |

Both retain their original compression path and a continuous USB connection. Earlier build-74 runs of these scenes measured 59.54 and 59.89 updates/s; the new results remain near 60. The freshly repeated pre-install build-74 full-screen control measured 25.96 updates/s at 2.916 Gbps. The stronger comparison above uses identical installed binaries and IPv6 for both conditions.

**Measurement boundary:** “delivered” is the Host count of Viewer acknowledgements after successful GPU completion. These runs do not establish physical panel presentation FPS or camera-measured input-to-photon latency. Protected-account per-stage Viewer logs were not collected; the additional CPU decode benchmark is separate from the live rendering measurement.

Encoding 3 retains the bounded four-chunk LZ4 envelope, applying independent modulo-64-bit block differences and reversible bit-plane transposition within each tile. There is no previous-frame dependency, resolution change, chroma reduction or change to the image encoder. Four tile samples choose it only for dense updates with at least 10% estimated savings. Older Viewers, small updates and already-compressible desktop content retain their original formats. The optional `Hello.shuffledPacking` capability prevents sending the new format to old Viewers. During installation, the new Viewer successfully streamed from the old build-74 Host before Host was updated.

The signed Host and actual Big Sur/Radeon iMac Viewer pass their complete self-tests, including all supported dimensions, partial bottom tiles, sparse/out-of-order IDs, retained/sliced buffers, legacy negotiation, adaptive/raw fallback, malformed metadata and existing GPU upload checks. ASan/UBSan pass every supported transform length with unaligned pointers and exact reconstruction. The isolated four-worker decoder benchmark on the iMac takes about 5.19 ms for LZ4 plus inverse transform versus 2.51 ms for LZ4 alone. The full live Host encode-and-pack cost remains about 11.3 ms in both conditions.

After explicit user approval, Apple accepted Viewer submission `59991c5f-f2b9-408a-8420-665bf0211169` and Host submission `429c0f41-dce8-44e3-8201-5eebde45dd7d`. Both tickets are stapled and Gatekeeper-verified. The Viewer installed through the authenticated update relay from a signed loopback feed; Host was replaced at its permanent path with a verified signed copy and a retained build-74 backup. Existing pairing and fullscreen streaming were retained. No public release was published as part of these build-75 tests. Normal Host startup is restored with compression enabled, automatic updates remain on, and temporary update infrastructure is removed.

Evidence: `work/compression-optimization/live-results.json`, `result.json`, signed self-test/sanitizer/fixture logs and `final-Host-ui.json`; the four valid `work/usb3-retest-20261021/compression75-{disabled,enabled,native-window,text-scroll}/` directories; signed/notarized artifacts in `work/release-0.8.8-build75/`. Exploratory prototype results are not production evidence; the evidence README identifies a discarded non-invertible prototype.

# USB throughput optimization trials — 21 October 2026

**No repeatable throughput or FPS improvement was established, so no production transport change was retained.** Twelve bounded Python socket trials and two compiled native C controls tested the same Studio-to-iMac USB path using synthetic data. Temporary listeners exited after each run; the iMac test executable was removed. No application, pairing, persistent network, account or power setting was modified. These are transport experiments, not a deployed optimization.

| Transport variant | Received Gbps |
| --- | ---: |
| Default TCP baseline A | 2.829 |
| App-like TCP_NODELAY baseline B | 2.869 |
| Four parallel streams, aggregate | 2.503 |
| Explicit 1-MiB / 4-MiB socket buffers | 2.854 / 2.868 |
| More frequent TCP acknowledgements | 2.841 |
| 64-KiB / 256-KiB application blocks | 2.746 / 2.746 |
| Scoped IPv6 | 2.835 |
| Interactive-video / responsive-data priority | 2.875 / 2.865 |
| TCP_NOPUSH | 2.849 |
| Compiled native C controls A / B | 2.829 / 2.833 |

The largest apparent gain over the comparable TCP_NODELAY baseline is 0.2%, smaller than variation between baseline runs; it is not evidence of a useful improvement. Native C controls exclude Python as the sole explanation for the measured throughput. Read-only `SIOCGIFDEVMTU` reports Studio USB current/minimum/maximum MTU 1500/46/16000, but iMac USB 1500/46/1500, so a matching larger MTU is unavailable. These trials do not prove that no future driver, OS or application change can improve throughput.

The exact 60-second native 5120 × 2880 full-screen gradient was repeated with the existing 0.8.7/74 apps: **25.85 delivered updates/s at 2.904 Gbps**, compared with **25.96 at 2.913 Gbps** earlier. The change is −0.11 updates/s (−0.44%), not an improvement. Capture averaged 59.89/s; the stream coalesced 34.04 captures/s. Both results count Viewer GPU-completion acknowledgements, not independently measured physical presentations. No socket-trial settings were applied to the display connection. At the end of those transport-only trials, the installed apps remained on their authenticated USB stream, with the same Host PID.

Correction to the earlier conversational estimate: 5-Gbps USB 3.0 is a signaling rate. Its 8b/10b encoding leaves 500 MB/s (4 Gbps) before further overhead; the specification describes 400 MB/s or more as realistic application throughput. Thus the hypothetical 45-fps estimate at 5 Gbps of application payload is not attainable on this link at the same frame size. See [USB 3.0 specification §4.4.11](https://people.computing.clemson.edu/~jmarty/projects/lowLatencyNetworking/papers/LowLatencyLinuxAndPerformance/USB3.0Standard.pdf#page=69). At that pre-optimization frame size, the full-screen workload needed approximately 6.7 Gbps of application payload at 60 updates/s.

Evidence: `work/usb-throughput-optimization/result.json`, all named trial JSON files, `transport_matrix.py`, `native_tcp.c`, and `work/usb3-retest-20261021/full-screen-confirmation/`. Original comparison evidence remains in the section below.

# USB 3 SuperSpeed performance retest — 21 October 2026

**The replacement cable negotiates USB SuperSpeed, and the iMac reports “Speed: Up to 5 Gb/s”. Native 5K window motion and scrolling now average approximately 60 delivered updates/s. Heavy full-screen animation does not reach 60.** The existing M2 Max Studio / Radeon R9 M290X iMac setup used Host and Viewer 0.8.7 build 74. Both applications remained running throughout; no application, pairing, account, network or power setting was changed.

Each workload ran for 60 seconds at 5120 × 2880. The table uses settled one-second Host diagnostics, excluding the first five seconds and final two seconds of the runner interval (54 samples for the first three trials, 53 for full-screen motion). “Delivered” counts acknowledgements sent after successful Viewer GPU completion, not source draw requests or physical panel presentations.

| Workload | Mean delivered updates/s | One-second range | Mean application traffic | Mean capture callbacks/s |
| --- | ---: | ---: | ---: | ---: |
| Native moving window | 59.54 | 55.0–61.0 | 383.2 Mbps | 59.54 |
| GPU scrolling | 59.75 | 58.8–60.9 | 128.0 Mbps | 59.75 |
| Core Animation bitmap-text scrolling | 59.89 | 58.0–61.1 | 484.4 Mbps | 59.87 |
| Full-screen animated gradient | 25.96 | 24.0–27.0 | 2,913.3 Mbps | 59.79 |

The first three trials have zero credit waits and zero capture coalescing in the measured samples. One-second accounting boundaries can produce values slightly above 60. The native-window result is substantially faster than the earlier USB 2 trial's median 32.1 rendered updates/s (28.9–39.0 range); that historical comparison also differs in app build and test duration and is not a controlled cable-only A/B experiment.

The heavier animated gradient averages 104.0 ms from frame submission to acknowledgement and coalesces 33.83 captured images/s. Its observed application bytes per delivered frame imply approximately **6.73 Gbps at 60 updates/s**, above the nominal 5-Gbps USB rate even before additional overhead. The observed 2.91-Gbps application traffic demonstrates throughput beyond the previous 1-Gbps Ethernet link, but does not separately measure the cable's maximum throughput or isolate all transport/Viewer processing costs.

A follow-up 12-second synthetic, single-stream TCP transfer bound to Studio `en9` and iMac `en7` received 4,406,116,352 bytes at **2.935 Gbps**, without screen encoding, TLS or Viewer rendering in the test connection. The temporary receiver exited afterward; no network settings or installed applications changed. This closely matches the heavy stream's 2.913 Gbps and points to the current USB networking/transport path as a significant throughput constraint. It does not establish the highest possible USB throughput or isolate USB-controller, driver, TCP or test-harness costs. The physical SuperSpeed link remains rated at 5 Gbps; the application traffic counter reports payload rate, not negotiated bus speed. Evidence: `work/usb3-retest-20261021/raw_transport.py` and `raw-transport.json`.

All per-second Host observations retain one authenticated USB connection on `en9`; independent counters on Studio `en9` and iMac `en7` confirm the bulk transfer. The full-screen trial transferred approximately 22.74 GB on those interfaces, while each endpoint's company Ethernet traffic remained below 2 MB. SuperSpeed was observed before and after every trial. No SSH polling or UI capture helper ran during motion; only local Host JSON metadata was sampled. The protected dedicated account's direct Viewer performance logs were unavailable, so these results use Host-received GPU-completion acknowledgements and do not claim independently measured physical display FPS, perfect frame pacing, or input-to-photon latency. Final state remains authenticated USB streaming, with the same Host and Viewer PIDs and Host-reported Viewer fullscreen confirmation.

Evidence and the reproducible runner: `work/usb3-retest-20261021/`, including `result.json`, each workload's `source.json`, `host-full.json`, `host-ui-observations.json`, before/after hardware and interface counters, executable hashes, and final connection state. SuperSpeed operation is now verified; **strictly stable physical 5K60 across workloads remains unestablished**.

# Physical-session reconnection repair — local 0.8.7 build 74, 21 October 2026

The owner's Viewer update to 0.8.6/73 installed and relaunched correctly but could not reconnect. Its connection guard compared its UID with the owner of `/dev/console`. On the actual Big Sur iMac, that file belonged to the separate remote administrator login (UID 501), while WindowServer's session list reported Dedicated Display (UID 502) on the physical console. The initial diagnosis that the owner needed to switch logins was incorrect.

Viewer now queries its own WindowServer session with `CGSessionCopyCurrentDictionary`, requiring matching UID, completed login and on-console status. Session notifications and a periodic reconciliation use the same check, so unrelated login activity cannot suspend the physical Viewer and a missed notification can recover automatically. Diagnostics include the actual GUI-session state and do not describe a trusted, not-yet-connected Viewer as requiring SSH.

**Live SSH recovery passed on the protected dedicated-account iMac.** The notarized 0.8.7/74 Viewer reconnected fullscreen without another approval while `/dev/console` still belonged to UID 501. A second Viewer startup returned fullscreen, and Host's deferred public updater completed 0.8.5/71 → 0.8.6/73. Final authenticated traffic uses scoped IPv6 link-local USB; Host reports native 5120 × 2880 capture. This is connection/startup validation, not a new stable-60-fps measurement. The installed Viewer is the local recovery candidate; **0.8.7 has not been published**.

Pairing-binding, startup agent, FileVault status, login, screen-lock, power and company-network preservation checks pass. UI capture helpers stayed off. Session fixtures and the real encrypted reconnect/listener-restart fixtures pass in the exact signed Viewer on both Studio and Big Sur. Host and universal Viewer build successfully and are accepted/stapled by Apple with the existing Developer ID, trust namespace and update keys. Evidence: `work/reconnect-after-update73/result.json`, `live-recovery.json`, signed test logs and Host update observations; accepted app state: `work/release-0.8.7-build74/release-state.json`.

Follow-up version alignment: the owner's installed Studio Host is now also the accepted **0.8.7/74** candidate at its existing application path. Both apps report build 74 and resume native 5K streaming, with Viewer reporting fullscreen. Host's installed executable matches the accepted build; pairing metadata, startup plist and FileVault checks remain identical. The first startup-agent reload failed and rolled back; the bounded retry with a short unload delay succeeded. The original startup agent is running again, and no additional Screen Recording approval was needed. Signed Host session/reconnection fixtures also pass. Evidence: `work/align-host74/`. This local alignment does not publish 0.8.7 or change the public feeds.

# Public brief-disconnect recovery update — 0.8.6 build 73, 21 October 2026

**[RetinaLink 0.8.6 build 73](https://github.com/apkdmg/RetinaLink/releases/tag/v0.8.6) is published for both apps.** The immutable tag pins clean source `9d5f688cecf8b9a3969161a559e41e80b1b42c02` with `source_dirty=false`. Viewer starts retrying after 0.25 seconds, then backs off through 0.75 and 1.5 seconds to the previous three-second rate. Orderly closes and local renderer cancellation do not punish healthy cables. TCP connection refusal during Host's listener restart also avoids a false 30-second cooldown; actual network/TLS failures, malformed packets and confirmed USB loss retain theirs. Fallback routes still rotate when a peer never delivers frames. Host ignores errors from a replaced capture session. These changes do not promise that an image returns within 0.25 seconds.

All **124 offline tests** pass against the final source. Both accepted signed apps pass the new recovery tests: bounded retries, route fairness, real TLS orderly close, wrong-key rejection, actual closed-port refusal and encrypted reconnection after reopening the same port. Final signed Host self-tests, scoped pairing/recovery/isolation guards, update-relay tests and the four account-recovery, three saved-display and two ordinary/Dedicated Display removal/re-add AppKit/TLS cases pass. The UI capture helper stayed off, test apps exited, and production pairing/login/network settings were not modified. Physical lock/Escape/unlock timing, the initial Viewer disconnect cause and a fresh Big Sur hardware run remain unverified; the previous SSH session expired. No installed update trial or physical 5K60 measurement was performed during publication.

Apple accepted/stapled Viewer (`a57c5b85-2da9-40aa-8313-d14df6fdd0a4`) and Host (`ae155d2e-9e49-4ffc-839c-5a5cc1ab8612`); Host embeds the exact accepted Viewer. The Host PKG (`cee34b96-5d42-4b37-b386-3c683a6c9a99`) and Viewer DMG (`af6b4572-e299-4711-b603-457716f623e4`) are separately accepted/stapled and Gatekeeper-verified. Packaging checks unchanged payloads, script-free Installer resources, mounted DMG layout and a disposable app copy. Actual WhatsApp delivery was not repeated. Both apps retain the previous public signing requirements, team, bundle identifiers, pairing namespace, minimum OS, update key and feed URLs.

All six public assets match their pinned hashes after anonymous HTTPS download. The deployed feeds advertise **0.8.6/73** and native Sparkle verification passes for the exact downloaded feeds and matching update archives. Initial feed requests preceded Pages deployment and observed the previous feed; later deployment checks verify the new signed bytes without changing any published asset or tag. The GPL-3.0-only source archive contains the exact committed project and pinned Sparkle dependency source, SHA-256 `48b6bc061f56261b2902d9fab8f47792093665e48dfdad195f559e2f4c87827d`. Unrelated untracked files and private publisher metadata were excluded. Only the explicit main branch, v0.8.6 tag and signed-feed gh-pages update were pushed.

The owner’s installed Host and Viewer were observed at **0.8.5/71**, connected with update relay enabled before publication. No installed app was manually replaced; the owner will try Host's Update Now action to acquire build 73 on both Macs. FileVault, lock/sleep, login, startup and company network settings stay unchanged. Only Host needs internet with this installed pair. The earlier build-72 candidate was superseded before publication and is not a public release asset.

Evidence: `work/github-publication-0.8.6-build73/` contains the plan, corresponding-source manifest, signed-app and recovery logs/results, offline results, public downloads/signature checks, identity comparisons and release notes. Final app state is `work/release-0.8.6-build73/release-state.json`; installer states are under `work/pkg-0.8.6-build73/` and `work/dmg-0.8.6-build73-viewer/`. Superseded records remain under `work/github-publication-0.8.6/` with `superseded.json`; they are not publication inputs.

---

# Listener-restart recovery — pre-release candidate 0.8.6 build 73, 21 October 2026

Final release review caught an additional edge case: a 0.25-second retry may reach Host before its listener restarts, and treating `ECONNREFUSED` as a broken cable would then impose the old 30-second penalty on an otherwise healthy single route. Build 73 classifies this specific response separately. It retains bounded retry timing and route rotation without adding a failure cooldown for a closed port. Other network/TLS failures, invalid packets and confirmed USB loss retain their cooldown. The new fixture stops a real TLS listener, observes refusal, reopens the same port and verifies encrypted recovery. Physical lock/unlock timing remains unverified.

The signed/notarized build-72 candidate was superseded before any source push, release tag, public assets or update-feed deployment. Its private artifacts are retained separately; they must not be published.

---

# Brief-disconnect recovery — unreleased development build 72, 21 October 2026

Investigation of the reported lock/Escape/wake behavior found two avoidable delays in Viewer 0.8.5: every reconnect starts with a fixed three-second wait, and every closed stream penalizes its route for 30 seconds, including orderly peer closes and local renderer cancellation. A recent Host diagnostic showed an ordinary reconnection taking 4.225 seconds (3.324 before authentication, 0.901 for capture creation). It was not independently identified as the reported lock cycle. The bounded macOS capture log shows stream teardown and recreation, but does not identify why the Viewer first closed. The prior SSH control session has expired; retry with the existing verified host-key file rejects saved authentication. No new host key, password, sharing setting or login policy was accepted or changed.

The development change retries at 0.25, 0.75 and 1.5 seconds, then retains the previous three-second rate for sustained failure. Only an actual rendered frame or a local wake/sign-in resets that burst; repeated TLS handshakes alone do not keep it fast. Link now reports typed close causes: orderly peer close and local cancellation do not mark a route as broken, while transport/TLS failure, confirmed USB loss and malformed packets keep their cooldown. An orderly close also prioritizes the previously working preferred route over an untried fallback, without erasing an independently recorded failure. Host ignores late capture errors from a session that has already been replaced.

The new `--wake-recovery-test` uses disposable loopback TLS streams and pure routing/timer state; it does not lock or sleep either Mac, use screen capture, access pairing/Keychain, or replace an installed app. It covers the bounded retry burst, graceful-close classification, a fresh encrypted connection, retained physical-failure cooldown and rejection of a different key. The initial test fixture stopped before any connection because its dummy key was not valid hexadecimal; the fixture was corrected without changing production authentication rules.

The final reviewed Host and universal Viewer compile successfully. Both pass the new recovery/TLS test, including route rotation for a peer that repeatedly closes before rendering. Host's full self-tests and scoped removal/capture guard pass; Viewer transport and encrypted-update relay tests pass. The AppKit/TLS integration passes both ordinary and Dedicated Display removal/re-add cases with exact original binding/credential retention. The UI capture helper remains off and temporary fixture apps exit. The tested compiler inputs match the current source manifest.

The actual cause on the iMac and physical lock/unlock timing remain unverified. This change does not add lock-screen capture, wake a locked session, change FileVault/sleep/login policy or replace the existing “Reconnecting” standby message. Published and installed 0.8.5 are unchanged. Private build, test and observation evidence is under `work/wake-recovery72/`: `observed-host-recovery.json`, `recent-system-capture.log`, `reviewed-source-manifest.json`, `reviewed-build.log`, `checks.json`, the per-check logs and `reviewed-integration/result.json`. Initial build/test attempts are retained separately; only the reviewed build is the final tested candidate.

---

# Public Host-only removal update — 0.8.5 build 71, 20 October 2026

**[RetinaLink 0.8.5](https://github.com/apkdmg/RetinaLink/releases/tag/v0.8.5) is public for both Host and Viewer.** The immutable tag points to clean source `34bc25324d56d6f8bd26e1991c673c44e6a4f062`, with `source_dirty=false`. Remove Display stops sharing while retaining approval; Add Display restores the exact binding from Host, including Dedicated Display Mode and offline Viewer recovery. Forget Display Approval is separate. The GPL-3.0-only corresponding-source archive includes pinned Sparkle 2.9.6 source, SHA-256 `91d839b7e1c6a26fa3eddd481aa270d12909b013da44dfe71c4da87002a129c4`. Unrelated untracked files and private publisher/test metadata were excluded.

Apple accepted/stapled Viewer (`3c97657d-db8e-4dc0-9cb9-bf935db390ed`) and Host (`4fe025b7-925d-4b63-a75f-8268ba1fa3e9`). Host embeds the exact accepted Viewer. The Host PKG and Viewer DMG are separately accepted/stapled and Gatekeeper-verified; packaging verifies unchanged app payloads, the script-free Installer and the mounted DMG layout/disposable copy. Actual WhatsApp delivery was not repeated. Both roles retain the previous public release's Developer ID requirement, identifiers, pairing namespace, update key, minimum OS and feed URLs.

All **124 offline tests** pass against the clean source. Disposable copies of the final signed apps pass self-tests, isolated removal/recovery guards, the encrypted Viewer-update fixture, four AppKit account-recovery cases, three saved-display TLS cases and both ordinary/Dedicated Display removal/re-add cases. The latter checks Host restart while removed, Viewer offline re-add and a fresh Viewer process reconnecting with the exact original binding/key. The exact final universal Viewer also passes signature/ticket/Gatekeeper, native approval and encrypted-relay checks over SSH on Big Sur 11.7.11. Its remote temporary directory was removed. The protected standard-login SSH feature tests and preservation checks are recorded below. The UI capture helper stayed off.

All six assets were downloaded anonymously over HTTPS and match the pinned publication hashes. Both public feeds advertise build 71 at the existing addresses; native Sparkle verification passes for each downloaded feed and its matching downloaded update archive. An initial feed check preceded Pages deployment and observed build 70; the new deployment and signatures were checked afterward without replacing assets or moving the tag. Only `main`, `v0.8.5` and the exact signed-feed `gh-pages` commit were pushed explicitly.

The installed Studio Host and iMac Viewer were observed at **0.8.3 build 67**, actively connected with update-relay support. They can discover build 71 from Host's Update Now action, with only Host needing internet. No installed app or production pairing was replaced by publication; an actual 67 → 71 installation was not performed during these release checks. FileVault, login, startup and company network configuration were not modified. These checks do not establish actual OS logout/reboot or stable physical 5K60 performance.

Evidence: `work/github-publication-0.8.5/` contains the pinned plan, source manifest, public download/signature records, signed-app and isolated removal/recovery results, Big Sur signed-Viewer results, identity comparison and release notes. Accepted app state is `work/release-0.8.5-build71/release-state.json`; installer states are under `work/pkg-0.8.5-build71/` and `work/dmg-0.8.5-build71-viewer/`. These local bookkeeping records are not release assets.

---

# Host-only remove and re-add — pre-release development build 71, 20 October 2026

**Remove Display…** is now available on the Host display card, including for Dedicated Display Mode. It stops sharing and removes the active display while retaining its existing secure approval in the login Keychain. **Add Display** restores the original binding, including management and automatic-login metadata, without requiring the Viewer to be online or approve again. **Forget Display Approval…** separately revokes approval and explains that adding afterward requires Viewer reset and approval on both Macs. Neither action alters FileVault or login settings. The updated Viewer shows an explicit removed-display standby; the Host also sends the existing paused command for older Viewers.

The Host's capture and permission-retry entry points refuse to capture while removed. Reopening Host cannot implicitly restore the display. A persistent removal marker also takes precedence over an interrupted binding write, so a crash during removal or re-adding leaves sharing disabled until Add Display completes. Restoration validates the original Keychain credential against its retained digest; corrupt or mismatched records fail closed. No credential is placed in preferences, shared across logins or replaced by removal/re-add.

The private build compiles for Apple silicon Host and universal Catalina/Big Sur-compatible Viewer. All **124 offline Python tests** pass, along with native removal/recovery/approval and encrypted-update tests, four existing account-recovery cases and three saved-display TLS-reconnection cases. New AppKit/TLS tests cover ordinary and Dedicated Display bindings: removal, Host restart while removed, Viewer exit, Host-only re-add while Viewer is offline, and a fresh Viewer process authenticating without another approval. Tests compare the complete original binding and credential, rather than merely the display name. Native tests also exercise the actual Host capture/retry guard without starting screen capture.

**SSH validation passed on the real Big Sur 11.7.11 iMac, in its existing non-administrator dedicated login (UID 502).** The signed test Viewer and isolated Host fixtures exercise both binding cases across the LAN with fresh authenticated TCP/TLS probes. Before/after records match for production pairing metadata, Viewer startup, authorized SSH keys, FileVault, login/automatic-login configuration, screensaver/lock preferences, power settings and company network configuration. The UI capture helper stayed off on both Macs. The bounded root worker exited and temporary apps, GUI jobs and remote staging files were removed. The first test copy stopped on a Launch Services error before functional testing; Developer ID signed, atomically staged copies launched successfully. A stale-PID/probe-generation race in the test driver was corrected before the successful complete run.

The final Host-only interrupted-write safeguard was compiled separately and passes the native removal and recovery checks plus the local AppKit/TLS removal/re-add suite. The iMac-tested Viewer code is unchanged by that safeguard. These tests use disposable pairing scopes, not destructive removal of the owner's installed pairing. They do not include an actual OS logout/reboot, an installed update trial or physical 5K60 presentation measurement. At this pre-release testing stage, installed apps and public release **0.8.4 build 70 remained unchanged**; publication is recorded above.

Evidence: `work/remove-display71/result.json` aggregates the results. `ssh-verified/{result,before,after}.json` records the protected-login run and preservation checks; `cleanup.json` records remote cleanup and the helper-off check. `final-local/`, `regression-recovery/`, `regression-saved/`, `native-results.json` and `offline/result.json` record the initial checks. `hardened-source-manifest.json`, `hardened-build.log`, `hardened-unit.log`, `hardened-recovery.log` and `hardened-integration/result.json` cover the final Host safeguard. Reproduce the scoped removal/re-add flow with `Tools/test_display_removal.py`; the native entry point is `--display-removal-test` with a UUID test scope. Private test apps and evidence are not public release assets.

---

# Public saved-display update — 0.8.4 build 70, 20 October 2026

**[Release v0.8.4](https://github.com/apkdmg/RetinaLink/releases/tag/v0.8.4) is published for both Host and Viewer.** The immutable tag points to `e12249a9163ba80ec8961a2bb87f522b7642fafb`, built from a clean checkout with `source_dirty=false`. Its GPL-3.0-only corresponding-source archive contains the committed project and pinned Sparkle 2.9.6 source, SHA-256 `92ce353c6aca09394e43269c49000a33345f26dc7c57a4d8b27025627ad3afc4`. Private publisher records and unrelated untracked files were excluded. Developer ID team, bundle identifiers, designated requirements, production Keychain namespace, Sparkle signing key and stable feed URLs are retained.

All six public assets were downloaded anonymously over HTTPS and match the pinned publication plan byte-for-byte. Both public appcasts serve build 70 at the existing addresses, with native Sparkle verification passing for the exact downloaded feeds and their matching update archives. The first feed check preceded GitHub Pages deployment; the deployed feeds were checked again without replacing release assets or moving the tag. Only `main`, the new `v0.8.4` tag and `gh-pages` were pushed explicitly.

Apple accepted and stapled Viewer (`61a0059a-fb78-4a5b-89d9-a45c493aa56e`) and Host (`a63d039b-0b15-402d-bd0c-13e8f2c5f7f8`). Host contains the exact accepted Viewer. The Host PKG (`d388eb90-de20-4e57-b722-7475a86a67fd`) and Viewer DMG (`645d1c52-8d37-42b0-8b5a-c2fed74ec364`) are separately Apple-accepted, stapled and Gatekeeper-verified. Packaging verifies unchanged payload identity and bytes, the script-free Host installer, and the Viewer's mounted layout and disposable-copy identity. Actual WhatsApp delivery was not repeated for this release.

All **124 offline tests** pass. Disposable copies of the final signed apps pass Host self-tests, native recovery/isolation guards, the encrypted Viewer-update fixture, four AppKit recovery cases and three saved-display encrypted reconnection cases. Over the existing SSH session, a disposable copy of the exact final universal Viewer also passes codesign, stapled-ticket and Gatekeeper checks plus native approval-protocol and encrypted-relay tests on the Big Sur 11.7.11 iMac. Its temporary remote directory was removed. No installed app was replaced by these release checks, and production pairing, FileVault, login and network settings were not accessed for mutation. The UI capture helper stayed off. These checks supplement the protected standard-login feature tests below; they do not constitute an actual OS logout/login switch, an installed 0.8.3 → 0.8.4 update trial, or stable physical 5K60 validation.

Evidence: `work/github-publication-0.8.4/` contains the pinned publication plan, source manifest, public verification/signature records, offline results, signed-app and saved-display results, Big Sur signed-Viewer results, identity-preservation check, release notes and build/packaging logs. Accepted app state is `work/release-0.8.4-build70/release-state.json`; installer states and payload checks are under `work/pkg-0.8.4-build70/` and `work/dmg-0.8.4-build70-viewer/`. These local evidence files are not public assets.

---

# One saved iMac across logins — unreleased development build 69, 20 October 2026

This supersedes the development-build-68 account-replacement UX below. Host presents one saved iMac with **Reconnect Display**. A fresh Viewer login needs matching-number approval on both Macs once; previously approved logins retain the same random TLS credential and reconnect without another approval. The saved Host display name and enrollment date remain stable. New Viewers derive a public discovery/setup identity from a domain-separated hash of the hardware UUID; this is a correlation hint, never authorization. The existing setup transcript remains compatible with published Viewer 0.8.3. Unpaired standby remains discoverable, with bounded/rate-limited handshakes. Production Viewer only initiates setup/streaming for the console login and releases its connection when that session resigns.

Each Viewer keeps its own binding/key in its login Keychain. No machine-readable shared secret file, root daemon, SSH permission, account creation, FileVault change or automatic-login change is introduced. In particular, reconnecting from another login preserves Dedicated Mode's original management and automatic-login target. Pending approval records only non-secret target metadata and requires the same committed Viewer identity and login on retry. A locally approved different known hardware identity is rejected rather than silently replacing the saved iMac. Local removal revokes Host's key for all offline copies without claiming to erase those copies' Keychains.

Local development builds compile for Apple silicon Host and universal Catalina/Big Sur-compatible Viewer. Tests use ad-hoc signed, UUID-isolated development apps with no production trust access or startup installation. The new login's private binding differs from Host's retained display record; integration testing caught and corrected the initial handoff mixing those records. The saved-display suite verifies a new login has no key before both approvals, both approved logins authenticate real fresh TCP/TLS echo connections, and the original login reopens without another approval. The four recovery scenarios also cover cancellation, interrupted persistence/retry and offline removal. Published Viewer 0.8.3 passes the compatible Host recovery protocol suite. Native Keychain/recovery and committed-X25519/two-approval tests pass for both roles. All **124 existing offline Python tests** pass.

**SSH validation passed on the real Big Sur iMac.** The Intel Viewer passes committed-X25519, matching-number, directional encryption, tamper/reflection/replay and real TCP two-approval tests on macOS 11.7.11 (20G1443). A bounded administrator bridge then runs the native AppKit Viewer under the actual non-administrator dedicated display login (UID 502), with two disposable preference/Keychain scopes and distinct test-only login names. Across the Studio–iMac LAN, fresh scope B has no credential before approval, receives the existing key only after both approvals, retains Host's saved display name/enrollment date, and authenticates a new encrypted connection. Reopening scope A authenticates again without another approval. Both scopes report the same real iMac hardware identity. The test apps use no capture helper or production screen capture.

This is an actual standard-login/Big Sur runtime check with simulated login scopes, **not an actual logout/login or Fast User Switching test**. The administrator account (UID 501) has no Aqua session; a separate SSH-only disposable-Keychain check returns `-25308`, so it is not reported as a successful second-user GUI test. No OS account is created, signed out or automatically logged in for this validation. Session-activation/resignation handling compiles, but actual console switching still needs a separate hardware exercise.

Preservation hashes match for the dedicated Viewer's real binding, startup agent, SSH authorized keys and system login configuration; FileVault remains off on iMac and on on Studio. The UI capture helper is off on both Macs. The owner had closed production Viewer before testing; the bounded bridge reopens its unchanged normal startup agent after cleanup, and installed Host/Viewer 0.8.3 build 67 resume streaming with their original pairing. Temporary iMac test apps, data and bridge files are removed. The first remote driver stopped on an incorrect macOS executable path; cleanup succeeded, the path was corrected and the complete run passed. SSH and sudo authorization were used only for these tests, not added to ordinary pairing or reconnection. No development app is installed as production or published; release configuration remains build 67.

Evidence: `work/display-identity69/` contains immutable build snapshots, build/native/offline logs, saved-display and recovery results, production metadata snapshots and the non-secret SSH failure logs. Reproduce the local flow with `Tools/test_saved_display.py` and `Tools/test_account_recovery.py`; the latter accepts separate `--port-base` values for concurrent compatibility runs. Final verification results are recorded in `result.json`. The final source snapshot is `complete-source`, with signatures/architecture checks on `complete-build`; local suites are `complete-native`, `complete-integration`, `complete-viewer67` and `complete-saved-display`. SSH evidence is `big-sur-native-pairing.log`, `big-sur-dedicated-preservation.json`, `ssh-live-after.json` and `live-dedicated-26294376/{result,before,after}.json`.

---

# Account-change recovery — unreleased development build 68, 20 October 2026

The reported failure has two causes: Viewer trust is stored in the signed-in account’s preferences/login Keychain, while Host’s existing-profile wizard disabled Continue and required the original Viewer to reconnect before removal. A standard account B therefore starts unpaired but could neither replace account A’s saved Host profile nor remove that offline profile.

The development fix adds **Set Up Another Account** on Host. The old profile/credential stay intact until both local approvals; Host then rotates the credential and binds to the approved account. Cancellation keeps the old pairing. Pending replacement resumes only for the same Viewer identity and reuses the new credential. Managed Dedicated Mode must be turned off before account changes, so ordinary pairing does not silently retarget automatic login. The reopened wizard refreshes its controls after a profile is forgotten.

**Forget on This Mac** works without the old Viewer, removes local trust only after successful Keychain deletion, and explains that the remote account/startup remain. A persistent reset marker blocks background Host startup from falling back to a saved legacy pairing code; approved setup clears that marker. Old listener callbacks are rejected after credential rotation. Viewer identifies its current account and adds a locally confirmed **Reset Pairing for This Account** action. These actions do not create accounts or change FileVault, login/power, network or startup settings. Connected two-peer removal still removes Viewer startup with authenticated acknowledgment.

Both the Apple silicon Host and universal Viewer compile with the existing deployment targets. Native tests pass for exact-profile replacement consent, a fresh credential for the new account, dedicated-mode protection, pending identity/credential reuse, failed key deletion preserving metadata, idempotent local reset, preserved stable identity/update preferences and the persisted reset guard. The existing real TCP committed-X25519/two-local-approval cryptographic tests pass too. Missing/malformed test-isolation flags are rejected before Keychain access in the earlier final compile; that entry-point guard is unchanged in the verified compile. All **124 existing offline Python tests** pass.

**Eight native AppKit/TCP integration cases pass on the Studio.** Four use both development apps and four pair the fixed Host with a disposable copy of the exact published **0.8.3 build-67 Viewer**. Each set covers one-sided approval/cancellation retaining the old trust, approved account replacement with matching new credentials, an injected persistence failure followed by recovery, and offline local forget restoring usable setup controls. The compatibility test demonstrates that a fresh unpaired account can use the fixed Host without first replacing its existing 0.8.3 Viewer. The new Viewer reset menu itself still requires the new Viewer build.

Separate random preference/Keychain namespaces model account A’s existing trust and account B’s empty state. These are not real macOS accounts: no actual logout/login, account creation, standard-account permission trial or new Big Sur runtime check is claimed. The renewed SSH helper reported **NOT CONNECTED**; its underlying error was not captured, and the Big Sur test was not run. No further credentials were requested. The UI capture helper stayed off for local tests. The installed Studio Host and dedicated-account iMac Viewer remain signed **0.8.3 build 67**, paired and streaming; no development build was installed or published, and the release configuration remains unchanged.

Evidence: `work/pairing-recovery68/verified/result.json`, `integration/result.json`, `viewer67-compatibility/result.json`, native recovery/protocol logs and compiled apps; isolation guard results under `final/isolation-guard-tests.json`, offline results under `final/offline/result.json`, production build/status snapshots, and `ssh-status.json`. `Tools/test_account_recovery.py` reproduces the isolated integration flow. Public 0.8.3 still has the original recovery limitation; the user guide documents its sign-back-into-A workaround.

---

# Public Host-delivered Viewer updates — 0.8.3 build 67, 19 October 2026

**[Release v0.8.3](https://github.com/apkdmg/RetinaLink/releases/tag/v0.8.3) is published.** All six public assets and both signed appcasts were downloaded anonymously over HTTPS and match the publication plan byte-for-byte. Native Sparkle verification passes for both downloaded feeds and their matching update archives. GitHub Pages serves build 67 at the existing Host/Viewer feed addresses; previous versioned assets and release tags were not replaced.

The immutable tag points to clean source commit `7bb332a164d9287f8ea098cd1ad7a6f92c1c9e0e`. The release records `source_dirty=false` for the clean build checkout. The GPL-3.0-only corresponding-source archive includes the exact tracked application source and pinned Sparkle 2.9.6 source with vendored dependencies; SHA-256 `eff45532be5482577e85012d038baaa830a96a62f52290a8d395d5387cb242d8`. Private publisher records, credentials and unrelated untracked files were excluded. Only `main`, the new `v0.8.3` tag and `gh-pages` were pushed explicitly.

Apple accepted and stapled Viewer (`8c21ff05-b3bc-4b75-99cf-5aa8c4c1d58a`) and Host (`800e476f-97c6-4725-a6e3-0e5036882f16`). The signed Host embeds the exact accepted Viewer. The outer Host PKG and Viewer DMG are also accepted, stapled and Gatekeeper-verified. Installer validation confirms the exact app payload, Developer ID, ticket and expected layout, without installing or launching the packaged apps. Bundled setup guidance explains the offline Viewer update and one-time upgrade from older Viewers. Build 67 preserves the tested update code; the final changes from private build 66 correct the installer guidance and build number.

The native signed Host self-tests and Viewer encrypted-relay fixture pass in build 67. All 124 offline tests passed on the feature commit, and all 25 installer policy tests passed again after the guide correction. The earlier private build 63 → 64 and 64 → 65 hardware tests below cover opt-out, modified-feed/archive rejection, interrupted-transfer retry, actual-version/fullscreen completion and no-update status.

**The installed Studio Host and dedicated-account Big Sur Viewer also updated from build 65 to the actual public build 67.** Host's normal update action used the production GitHub feed, delivered Viewer's update through the authenticated display connection and then updated itself. Both apps resumed streaming. This required no administrator authentication or SSH forwarding. Host pairing, startup, FileVault and company-network hashes match before/after, and its original startup agent was restored with no test arguments. The Viewer reused the existing authenticated pairing and protected installation. The UI capture helper remained off on both Macs. The cleanup verifier initially raced an exited Host PID; a separate read-only check matched current metadata to the live production agent PID and confirmed streaming. The harness now requires a fresh PID. Earlier root-observed private tests provide the independent protected-account settings/fullscreen evidence; no new root session or full protected-account snapshot was used for this public smoke test.

The iMac's company network was left connected. Private tests proved its update origin was unreachable directly and reachable only through Host; these checks do not claim a globally air-gapped iMac. No update test establishes stable physical 5K60 performance. Viewer 0.8.2 and earlier still need one initial signed upgrade before Host-delivered updates can work.

Apple's stapler could not write the ticket into the original test-launched build-67 bundle. An identical disposable copy stapled and verified successfully. Fresh staging copies of the unchanged signed apps were therefore used to resume the same accepted Viewer submission, then notarize Host normally. Final signatures, tickets, bundled Viewer and source metadata were all verified; no permissions, quarantine flags or security settings were reset.

Evidence: `work/github-publication-0.8.3/plan.json`, `publish.log`, `public-verification-final.json`, `public-feed-signatures.json`, `source-manifest-build67.json`; `work/update-relay67/live-public/` before/after policy, installed metadata and result; `host-self-tests.log`, `viewer-relay-tests.log`, Apple stapling diagnostics and accepted state in `work/release-0.8.3-build67-final/release-state.json`; outer installer states and contents validation in `work/pkg-0.8.3-build67/` and `work/dmg-0.8.3-build67-viewer/`. These local evidence files are not published assets.

---

# Host-delivered Viewer updates implemented — 0.8.3 candidate, 19 October 2026

The candidate negotiates relay capability over the authenticated display connection, downloads only the configured Viewer feed and allowlisted GitHub Viewer archives on Host, and transfers exact bytes in pull-based 64 KiB chunks. Viewer provides a token-protected loopback route for Sparkle while retaining mandatory signed-feed and archive verification. Disconnects discard partial files and preserve a manual retry request. Host keeps the expected Viewer build and waits for that version to confirm a rendered fullscreen display before reporting an installation complete. Explicit Update Now requests are queued when Sparkle is busy.

Both roles compile, including the universal Viewer's existing macOS 10.15 deployment target. Native relay tests pass for origin/redirect restrictions, packet bounds, legacy greeting compatibility, version/fullscreen confirmation and an exact 700,000-byte fixture through a real encrypted `Link` into the loopback HTTP endpoint. A request without the correct token is rejected without reaching the Host's source. Signed Host self-tests pass, and all **124 offline tests** pass when run in separate processes; aggregate unittest discovery encounters the existing `test_usb_link` module-name collision between `Tests` and `Tools`.

**Twenty live integration checks pass on the Studio and dedicated Big Sur iMac.** Host build 64 delivered a signed build-63 → build-64 Viewer update through authenticated Ethernet. The signed feed and archive were served only on Studio loopback; an independent SSH request confirmed that the iMac could not access that update origin directly, and no reverse forwarding was installed. This verifies the relay without disabling the company network or globally blocking iMac internet. Automatic opt-out reported availability without fetching an archive. Viewer rejected a modified feed with an EdDSA validation error and a modified ZIP with signature validation failure before unarchiving. A local test seam then disconnected the link after the first archive chunk; reconnection retried the manual update and installed the valid archive without re-pairing. The new Viewer rendered fullscreen and returned to its original startup agent.

Owner-approved Apple notarization accepted/stapled the build-63 baseline, build-64 Viewer and build-64 Host. Administrator authentication was used only to prepare/observe the protected dedicated-account baseline; Sparkle performed the actual update as Viewer. Before/after pairing, startup, login/power, FileVault, default-route/DNS and company-network checks match. Temporary overrides were removed, the original automatic preference was restored, Host returned to its ordinary startup agent and the bounded root worker exited. Staged remote baseline/scripts were removed. The first runner waiting window expired before owner authentication arrived; its evidence is retained under `waiting-window-expired/`, and the existing authorized worker was reused for the successful run without another password prompt.

That test also exposed an existing status issue: Sparkle reports the normal no-update outcome through error callbacks, briefly producing a false failure message. Build 65 classifies that outcome consistently while continuing to reject signature errors; native cases distinguish the no-update code/domain from signature failures and unrelated errors. **The final ordinary 64 → 65 update then passed on both apps without administrator authentication.** Viewer received its archive through the relay, Host installed its own update, both returned to streaming, and a subsequent check reported up to date normally on both ends. Fixture settings and the original automatic preference were restored, with Host returned to its production startup agent. A test-runner check initially raced stale startup metadata; it was repeated after verifying the actual new Host process was connected, and the harness now requires a fresh PID. Both installed apps are the Apple-accepted 0.8.3/build-65 candidate. No candidate has been published to GitHub. Neither these update tests nor the native byte fixture establishes physical 5K60 performance.

Evidence: `work/update-relay63/result.json`, `imac-result.json`, `imac-before.json`, `imac-after.json`, `imac-observations.jsonl`, `requests.json`, `bad-feed.json`, `bad-archive.json`, `host-confirmation.json`, `remote-cleanup.json`, native relay/self-test logs, `offline/result.json`, `live_test.py` and `watch_imac.py`; accepted release state in `work/release-0.8.3-build64-r2/release-state.json`. Build-65 records include `work/update-relay63/final65/result.json`, `final.json`, `no-update.json`, `requests.json`, signed native tests, and accepted release state under `work/release-0.8.3-build65-r2/`. Final checks confirm both apps report build 65, the Host's fresh PID belongs to its original production agent, test launch arguments/Host feed overrides are absent, and the UI capture helper remains off on both Macs. The public 0.8.2 release and the hardware results below remain separate.

---

# Public Viewer update verified on the dedicated iMac — 19 October 2026

**The installed Studio Host 0.8.2 successfully updated the running dedicated-account Viewer from 0.8.1/build 61 to 0.8.2/build 62 using Update Now and the public GitHub feed.** The iMac runs Big Sur 11.7.11. Its previous build-60 installation first received the signed, notarized build-61 Viewer at the same permanent path to acquire the public feed. That baseline replacement was test preparation; the subsequent 61 → 62 installation was performed by Sparkle, without a DMG installation, another pairing, a Viewer click or an update-specific password prompt.

The local Host test seam invoked the same `checkUpdatesBoth(installNow:true)` action as Update Now after the build-61 Viewer was connected and streaming. The remote watcher recorded checking, downloading, verification, installation, and a new build-62 process. It reconnected through authenticated direct TLS in one fullscreen window with the Dock/menu bar hidden; that state remained stable for the observation interval. The installed build-62 app passed strict Developer ID verification against RetinaLink's signing requirement and Gatekeeper assessment.

Before/after hashes match for the Viewer binding, startup agent, login preferences, power settings, network configuration, default route and DNS. FileVault remains off on the iMac and unchanged on the Studio. Host binding, startup-agent and network hashes also match. Host was restored to its ordinary startup agent and resumed streaming. The UI capture helper stayed off on both Macs. The bounded root worker exited; no root service, test feed or login-policy change was installed. Administrator authentication was required only for this test's preparation and observation of the other account's protected files, not for Sparkle's update.

**Scope:** this verifies an already-updated Host managing a build-61 Viewer, matching the reported version mismatch. It does not verify simultaneous Host-and-Viewer 61 → 62 installation, reproduce the other user's original failure, or establish physical 5K60 performance. Their submitted build-62 logs followed manual installation and do not explain the earlier failure. An initial test-harness signature-command error stopped before replacing Viewer; its evidence is retained separately, and the corrected command was independently verified on Big Sur before the successful retry.

Evidence: `work/viewer-update61-to62/result.json`, `imac-result.json`, `imac-before.json`, `imac-after.json`, `imac-observations.jsonl`, `update-now-requested.json`, `host-before.json`, `host-after.json` and `host-test.log`; the stopped harness attempt is under `attempt1/`. These private hardware-test records are not release assets. Earlier sections below retain their original testing context.

---

# Public 0.8.2 updates published — 19 October 2026

**[RetinaLink 0.8.2 build 62](https://github.com/apkdmg/RetinaLink/releases/tag/v0.8.2) is the latest public release.** It contains the [Host PKG](https://github.com/apkdmg/RetinaLink/releases/download/v0.8.2/RetinaLink-Host-0.8.2.pkg), [Viewer DMG](https://github.com/apkdmg/RetinaLink/releases/download/v0.8.2/RetinaLink-Viewer-0.8.2.dmg), separate signed update ZIPs, corresponding GPL source and checksums. The public [Host feed](https://apkdmg.github.io/RetinaLink/updates/host/appcast.xml) and [Viewer feed](https://apkdmg.github.io/RetinaLink/updates/viewer/appcast.xml) both advertise 0.8.2/build 62, using versioned v0.8.2 archive URLs. GitHub Pages reports the matching deployed feed commit `6d41d7405c872a1854a88cbaa94eaf55b29ae6bf` built successfully.

Anonymous HTTPS downloads of **all six assets and both feeds match the publication plan's full SHA-256 hashes and sizes**. Both downloaded feeds pass native Sparkle signature verification. The local update ZIPs also pass verification of the signatures in their appcast enclosures, and their bytes match the anonymously downloaded public assets. Both roles retain the update public key, feed URL, bundle identity, signing team and pairing namespace from 0.8.1. Initial checks briefly received the previous build-61 feeds before Pages completed deployment; that result is retained separately, and fresh build-62 checks pass. No unsigned or rewritten XML is served.

The immutable `v0.8.2` tag points to the exact clean application source `1bcb4c669c4e5815263ab5bd00dd9851f55c28e3`. Its corresponding-source archive includes Sparkle's source and notices; SHA-256 is `db858218fe8051de5cb3c13067f6c0eba90514c648d1941134f77c527464e820`. The accepted apps from the live-tested release were packaged without rebuilding or re-signing them. The outer Host package is Apple-accepted/stapled under submission `11af538c-b561-46a7-b6d3-ddd60d4ebb65`; SHA-256 `26b4948d41fa5fcc0c5c9626e58bb5bbb7e6b76e60751ad9a0715b901fefe952`. The Viewer image is accepted/stapled under `3ed8f220-f8da-4ef3-b682-9bd07eceff09`; SHA-256 `eac3e0bb891561c9175634b7dd6305188d2816efc1c2bb7067a8f91fa11eac69`. Package payloads, mounted DMG contents and copied app signatures/tickets pass the packaging verifiers. No installer was run during publication.

**Installed 0.8.1 apps can now discover build 62 with Update Now.** The public-update installation itself was not exercised on a fresh 0.8.1 pair during this publication; the signed direct-upgrade and lifecycle tests below provide the live 0.8.2 Host evidence. Publication leaves the already installed 0.8.2 Studio Host and the iMac Viewer unchanged. Releases through 0.8.0 still require one signed replacement on each Mac to acquire the public feeds, retaining their original paths and pairing. The previous public 0.8.1 assets and tag were not changed. No private publisher metadata, credentials or signing keys were uploaded, and the UI capture helper was not used.

Evidence: `work/github-publication-0.8.2/plan.json`, `publish.log`, `public-verification-initial.json`, `public-verification-final.json`, `local-signatures.json`, `public-feed-signatures.json`, `result.json` and `ReleaseNotes.md`; `work/pkg-0.8.2-build62/pkg-state.json` and `work/dmg-0.8.2-build62-viewer/dmg-state.json`. README download links now target 0.8.2. Earlier sections below retain their original testing context.

---

# Menu-bar Host lifecycle verified — 0.8.2 build 62, 19 October 2026

**The Studio's installed Host is now signed, Apple-accepted and stapled 0.8.2 build 62 at its existing permanent location.** Clicking the red close button closes its controls and switches the running app to menu-bar-only presentation without disconnecting the display. **Open RetinaLink** and reopening the installed app restore the controls and normal Dock navigation. Automatic startup remains hidden without taking focus. A nonmodal, eight-second native popover points out the menu-bar icon after the first close; reopening controls or choosing **Got it** dismisses it. The hint requires no notification permission. A user-pinned Dock shortcut is not removed.

The production presentation controller passes **13 native AppKit checks** using disposable windows and an isolated preference suite: quiet startup, foreground controls, actual red-button close, first-close hint persistence, menu-bar availability, reopening, no repeated hint, an auxiliary setup window, closing the final window, yellow minimize/restore, a new controller retaining the hint preference and observer cleanup. These are actual activation-policy/window checks, without a screen capture helper. The main Host window is constructed hidden and Host alone has `LSUIElement=true`, preventing its startup window/Dock flash. Viewer keeps its previous activation policy and default window behavior.

**Eight live checks pass on the real paired installation.** The accepted Host replaced build 60 with the same bundle identifier, Developer ID requirement and pairing namespace. It reconnected to the existing iMac Viewer without re-pairing or another Screen Recording approval. While a bounded native moving-window scene exercised the real extended desktop, closing, reopening via Launch Services and closing again retained the exact Host PID and authenticated connection ID. Positive delivered-frame samples were recorded strictly after closing with the controls hidden. This establishes streaming continuity for these actions, not a new frame-rate or physical-panel benchmark. The normal native Quit request exited Host; its untouched login agent then launched a fresh build-62 process, reconnected, and independently reported accessory activation policy, no visible main window and `active=false`.

Before/after Host binding, startup-agent hashes and Studio FileVault state match. The iMac Viewer was not replaced. FileVault, company network settings, pairing, automatic-login configuration and the startup-agent arguments were not changed. Temporary test arguments/control files and the motion scene were removed; Host is again running through its ordinary agent with only `--autostart`. The test restored the hint's original unset preference before that final launch, leaving the first-close hint available to the owner. The capture helper remained off. This startup check reloads the existing GUI-session agent; it is not a new physical login/reboot test.

The signed Host self-tests and **23 offline release/update-policy tests** pass. Clean source commit: `1bcb4c669c4e5815263ab5bd00dd9851f55c28e3`. Apple accepted/stapled Viewer submission `34c667ad-91d4-478e-ad05-0b4972cd81f5` and Host submission `3540eae2-4458-4521-b2f2-71bc5b84054c`; Host embeds the exact accepted Viewer. Local artifacts include `outputs/RetinaLink-0.8.2.zip` and matching corresponding source `outputs/RetinaLink-0.8.2-source.tar.gz` (SHA-256 `db858218fe8051de5cb3c13067f6c0eba90514c648d1941134f77c527464e820`). At this testing stage the public release was still 0.8.1; the subsequent 0.8.2 publication is recorded above. The active iMac remained on 0.8.0, so its earlier public-update bootstrap requirement remained.

Evidence: `work/host-window62/lifecycle-result.json`, `lifecycle-test.log`, `signed-host-self-test.log`, `release-tests.log`, `update-tests.log`, `live/result.json`, its before/after and window-stage records, `live/hidden-delivery.json`, `live/final-process.json`, `source-manifest.json` and `work/release-0.8.2-build62/release-state.json`. Earlier sections below are historical.

---

# Public GitHub releases and signed updates — 0.8.1 build 61, 19 October 2026

**[apkdmg/RetinaLink](https://github.com/apkdmg/RetinaLink) is public, and [release v0.8.1](https://github.com/apkdmg/RetinaLink/releases/tag/v0.8.1) is published with six verified assets.** GitHub Releases serves the Host PKG, Viewer DMG, two signed update ZIPs, corresponding source archive and SHA-256 checksums. GitHub Pages serves the exact signed [Host feed](https://apkdmg.github.io/RetinaLink/updates/host/appcast.xml) and [Viewer feed](https://apkdmg.github.io/RetinaLink/updates/viewer/appcast.xml). Anonymous HTTPS downloads of all eight files match the publication plan byte-for-byte; both downloaded feeds also pass Sparkle signature verification. The initial feed checks failed while Pages was deploying. The original failure record is retained, and both feeds passed fresh checks after Pages reported `built`.

The immutable release tag points to clean source commit `dd6bb6cd136e50009cc88ad8f2a5c32dba764893`. The apps were built from an isolated clean clone, with `source_dirty=false`. The repository declares **GNU GPLv3 (GPL-3.0-only)** and includes its full license, third-party notices and source-build instructions. The matching `RetinaLink-0.8.1-source.tar.gz` includes the exact application source plus hash-verified Sparkle 2.9.6 source and its vendored dependencies. Its SHA-256 is `f7d1e2049b44d7c0bbb3ea898d9acfbc758a71c97cb86c51d5ce2341f7912917`. The portable archive manifest contains no local absolute paths. Private publisher bookkeeping, signing keys, credentials and unrelated untracked files were not published. Git pushes named only `main`, `v0.8.1` and `gh-pages`; other local refs were not pushed. The previous local remote is retained as `local-archive`.

Apple accepted and stapled the universal Viewer (`4f3a386d-b9d4-45c7-86fb-0e01b123bbb8`) and Apple silicon Host (`0aa07468-2950-4cbb-8663-a221f787ee0b`); Host embeds the exact accepted Viewer. The outer Host PKG (`0e0be03c-7293-4cd6-8951-b1e54caf6288`) and Viewer DMG (`bef1b998-ed05-45d9-bb89-add6d58eda2f`) are also accepted, stapled and verified. The DMG's read-only contents and disposable drag-copy equivalent pass signature/ticket checks. Both apps contain the GPL license and third-party notices, retain Sparkle's license, pin the expected production feed and preserve their Developer ID team, bundle identifiers, update key and trust namespace.

**124 offline tests pass**, covering publisher recovery and immutable assets, Pages allowlisting and rollback protection, source archives, feed generation, release policy, installers and existing dedicated/USB tools. The signed build-61 Host self-tests also pass. There was no live build-61 installation or SSH upgrade on the iMac in this publication task; the earlier 0.8.0 runtime results below remain the hardware evidence. Version 0.8.1 does not change the streaming implementation or establish stable physical 5K60.

**Installed apps remain 0.8.0.** Releases through 0.8.0 contain no public feed address, so each Mac needs one compatible signed replacement with 0.8.1 before future public automatic updates can work. Preserve each app's existing permanent location and saved pairing; do not enroll again. The new Host PKG installs to `/Applications`, so it does not replace the Studio's current `~/Applications` copy automatically. Previous signed-update continuity tests remain valid, but no new production-feed installation is claimed here. No FileVault, network, login, startup, pairing or installed-app setting was changed; the UI capture helper stayed off.

Evidence: `work/github-publication-0.8.1/plan.json`, `public-verification-initial.json`, `public-verification-final.json`, `public-feed-signatures.json` and `result.json`; `work/github-setup/offline/result.json`, `host61-self-tests.log` and `bootstrap61-metadata.json`; `work/release-0.8.1-build61/release-state.json`, `work/pkg-0.8.1-build61/pkg-state.json` and `work/dmg-0.8.1-build61-viewer/dmg-state.json`. Local evidence files are not release assets. Earlier sections below are historical.

---

# Automatic direct USB verified — 0.8.0 build 60, 19 October 2026

The separate Viewer installer is now available as [`outputs/RetinaLink-Viewer-0.8.0.dmg`](outputs/RetinaLink-Viewer-0.8.0.dmg). Its outer DMG submission `2390d76a-48f3-4dcb-a1b6-9ab63e470975` is Apple-accepted, stapled and Gatekeeper-accepted. It contains the exact accepted universal Viewer below, an Applications shortcut and the updated offline setup guide. Verification mounted the image read-only, checked Finder layout and signed app/ticket, and verified a disposable drag-copy equivalent. Four packaging policy tests passed. The artwork preview was inspected as a generated layout, without capturing Finder or using the UI capture helper. No app was installed or launched for this packaging step; the already updated iMac remains unchanged. Packaging evidence: `work/dmg-0.8.0-build60-viewer/dmg-state.json` and `contents-validation.json`.

**The installed Studio Host and protected dedicated-account iMac Viewer are signed, notarized 0.8.0 build 60.** The Viewer updated from build 59 through its existing signed Sparkle updater, retained its saved binding and returned fullscreen without another approval or pairing code. Host kept its permanent application path and Developer ID. The exact Viewer executable matches the accepted release (`104231213fd3573f4f5afc672d7a5e8743e1ad7b6d561588fe5c61e34795eb43`). The shipped Host includes that accepted Viewer for setup. Installer: [`outputs/RetinaLink-Host-0.8.0.pkg`](outputs/RetinaLink-Host-0.8.0.pkg), Apple submission `2c3e3d9e-c5ab-4149-8da6-57f75ed986bd`, SHA-256 `9add5a378f07866347c97e43aef4e914c1379544c54bb06dfdf7b86441f7d05f`.

Live testing used a rear USB-C port on the M2 Max Studio and USB-A on the Late-2014 Radeon R9 M290X iMac running Big Sur 11.7.8. macOS exposed its existing public NCM interface; RetinaLink observed it read-only, discovered the saved Host on that interface, authenticated TLS and selected scoped IPv6 link-local endpoints. Neither an IP address nor an OS network configuration change was required. USB dongles and Apple's private/restricted NCM management interfaces do not qualify as the public Mac USB link.

The owner physically unplugged USB with both company Ethernet cables left connected. Fresh authenticated fullscreen streaming recovered on existing `en0` Ethernet. Reconnecting the working cable returned automatically to a new authenticated public USB stream, with the same Viewer and Host PIDs throughout this cycle. Public interface names changed from Studio `en8` / iMac `en6` to Studio `en9` / iMac `en7`; discovery and required-interface verification used the new names and indexes. OS samples first observed Ethernet fallback **4.27 seconds after the first absent-USB sample**, and USB streaming **6.40 seconds after the first returned-device sample**. Sampling intervals around those transitions were about 2.1 seconds; these are metadata observations, not exact physical unplug latency. Normal Host startup was restored afterward, and its preferred-route retry again selected USB automatically. A later `Connection unavailable` event also recovered through available routes to public USB; its exact cause was not isolated, so this bounded test does not establish uninterrupted long-duration USB stability.

**The working cable negotiated USB 2 high-speed, 480 Mbps. SuperSpeed and stable physical 5K60 are not validated.** A 20-second native moving-window smoke test produced real 5120 × 2880 Viewer render updates: 17 interior one-second samples ranged **28.9–39.0 rendered updates/s**, median **32.1**, receiving **297.9–317.3 Mbps**, median **308.3**. Source window-position callbacks requested approximately 60/s; they are not delivered or physically presented frames. These results do not meet stable 60 updates/s and are not a panel-latency benchmark. The virtual NCM driver's nominal 100 Mbps property is not the negotiated USB bus rate. A second possible USB-3 cable produced no macOS USB attachment; its speed capability was not established, and the working cable was restored.

Independent before/after comparisons preserve company network service configurations/order, IPv4/IPv6 default routes and DNS on both Macs. The protected account's saved binding and exact startup agent match; the Host binding and startup agent also match. FileVault remains **on at the Studio and off at the iMac**. The UI capture helper stayed off. The bounded root watcher only observed sanitized metadata and pairing hashes, then exited; no root service, driver, account, login/power policy or sharing change was installed. The temporary loopback feed/SSH forward/server and isolated remote test apps were removed. Both updater preferences are back to automatic with public hosting unconfigured. Normal Host `--autostart` and Viewer `--appliance` streaming remain active.

The final signed Host self-tests and signed Viewer self-tests passed, including actual AMD GPU upload checks at 5K. Nineteen USB policy/parser tests pass; the local recovery analyzer rejects stale state, wrong executable hashes, mismatched interfaces and unauthenticated paths. Test harness limitations are retained explicitly: the first protected-account watcher passed a bare requirement string to `codesign`, which treated it as a filename. Its failed signature boolean and gated optional wrong-key probes were **not** counted as successes. Separate completed Accepted/stapled release verification, exact installed executable hash, installed Team/identifier and Gatekeeper metadata, independent public USB CLI/hardware observations and fresh interface-scoped TLS UI established the real USB stream. The unprivileged company-policy tool keeps protected account fields unknown; the authorized watcher's final binding/startup hashes close those preservation checks separately.

Evidence: `work/usb-link60/result.json`, `usb-recovery-final-analysis.json`, `live-usb-observations.jsonl`, `dedicated-final/`, `final-normal-usb-policy.json`, `native-motion.json`, `final-host-self-test.log`, `final-imac-self-test.log`, `work/release-0.8.0-build60/release-state.json` and `work/pkg-0.8.0-build60/pkg-state.json`. Earlier sections below are historical.

---

# Native Host installer for document sharing — 0.7.0 build 59, 19 October 2026

**`outputs/RetinaLink-Host-0.7.0.pkg` is Developer ID Installer signed, accepted by Apple, stapled and Gatekeeper-accepted.** Its submission is `17e313b2-35ec-478a-987c-51fefb10b76c`; final SHA-256 is `6aefffd64d38c70732f01341a03e49524bdf585a1057196ff42f010fbec4db0b`. It packages the existing accepted build 59 without rebuilding or re-signing either app. Host executable SHA-256 remains `2671b51ceea1751e9b648a8864e2271bc20432910c0ef9a5edb37ad4e1eda72d`, and the exact bundled notarized Viewer is retained. The only payload is `/Applications/RetinaLink Host.app`. Welcome, preparation and completion screens use Apple's native Installer. Recipients open the received PKG, follow Continue/Install and open Host in Applications; Terminal and a replacement browser download are not part of that flow.

The reported `File created by an AppSandbox, exec/open not allowed` error was reproduced on a disposable signed Host by applying sandbox download quarantine `0087`. Strict signatures and notarization remained valid while execution was rejected. A native Archive Utility experiment confirmed that a ZIP of the app retained the blocking flag on both bundle and executable; an otherwise identical `0083` control passed. The original shipped DMG and its contents had no quarantine flag. These observations isolate the delivery marking rather than establishing a Tahoe API incompatibility. [Apple DTS describes this exact quarantine failure](https://developer.apple.com/forums/thread/767612).

The final production PKG was independently copied to disposable files and marked `0083`, `0087` and `0187`. **All three passed Apple's install policy as Notarized Developer ID.** The exact final `0087` package also opened in native Installer with title **Install RetinaLink Host** and its Continue button enabled. That check read only Installer accessibility text and closed its exclusive test session; it did not click Install or request an administrator password. No screen images or UI capture helper were used. `Tools/test_pkg_delivery.py` preserves these checks as a repeatable developer integration test.

A separate native Installer trial tested actual replacement safely: an installer variant restricted to the current user's home directory placed the **exact same Host payload** only under `work/tahoe-installer-audit/user-install`. That target was prepopulated with the identical version/build 59, recursively marked `0087`, and verified to fail with the friend's exact error. Native Installer completed successfully without a password in this user-only test. The replacement had no quarantine on its bundle or executable, its full path/byte/mode manifest and executable hash matched the accepted release, strict signature and Gatekeeper passed, and the built-in read-only `--list-displays` command exited successfully. This establishes that Installer can repair an already blocked copy at the same version. It is **not** a full system-domain installation trial of the production PKG; the disposable variant used `auth=none` and a workspace destination, while the production package correctly uses normal system-domain administrator authorization.

The production verifier expands and checks every app path, byte, mode and internal link, validates the exact signed app/Viewer/ticket, and rejects scripts, extra payloads, relocation, disabled version/identifier checks, altered resources and changed submitted/completed artifacts. The package contains no quarantine-removal or security-reset code, no postinstall launch, and no account, FileVault, pairing or network operations. It installs to `/Applications` only; it deliberately does not replace an existing copy in `~/Applications`. **21 new package policy tests, 11 existing release policy tests and 4 DMG policy tests pass.** The new tool's native check also passed with the UI capture helper off.

Test OS: **Mac Studio macOS 27.0.1**, with synthetic copies of the observed quarantine condition. Actual delivery of this PKG through WhatsApp, fresh-machine cache behavior and the friend's macOS Tahoe 26.5.2 installation have **not** been independently tested. Final confirmation on that Mac remains necessary; this report does not claim every WhatsApp or macOS version is validated. The disposable installed app was removed; ordinary Installer test receipt/history may remain. The running Host remained PID 33999 with its original executable hash, and the protected iMac Viewer was not replaced. No FileVault, saved pairing, company network or sharing settings were changed.

Evidence: `work/pkg-0.7.0-build59/pkg-state.json`, `contents-validation.json`, `work/tahoe-installer-audit/final-pkg-delivery.json`, `pkg-probe`, `zip-0087`, and `user-pkg-probe` (preblocked target, package verification, native installation and post-install checks). Existing DMG/ZIP artifacts are retained unchanged. The new PKG and its SHA-256 sidecar are available in `outputs`.

---

# Dedicated login, reboot and wake verified — 0.7.0 build 59, 19 October 2026

**The iMac now passes real automatic-login reboot, fullscreen startup, launchd recovery, automatic reconnection, display sleep/wake and full system sleep/wake checks.** At the start of this run it had already completed the dedicated account's first graphical sign-in: one-time enrollment was consumed, the account was trusted and Viewer was fullscreen. The test did not recreate the account or rerun enrollment. The subsequent controlled reboot independently returned to the standard `retinalinkdisplay` account (UID 502), with completed graphical login and `IOConsoleLocked=false`, without manual login, a pairing code or a Viewer click.

The actual kernel boot changed from epoch `1792371230` to `1792379875`. The existing Aqua-only startup agent launched installed Viewer 0.7.0 build 59, initially PID 484 after that reboot. Its single fullscreen window hid the Dock/menu bar and reconnected through authenticated direct TLS. Fresh 5120 × 2880 rendered updates were recorded **60.95 seconds after the reboot request**. The Host remained its original process throughout. Viewer restart was exercised both before and after reboot: launchd started a new installed Viewer process, each peer established a new connection, saved binding and startup-agent hashes matched, and fullscreen streaming resumed without input.

The measured display cycle was power state **4 → 1 → 4**, with fresh Host/Viewer status and nonzero native-5K render samples strictly after the observed display-on time. Full system sleep was separate: sanitized `pmset` events record Sleep at epoch `1792379818` and Wake at `1792379852`; the dedicated GUI remained unlocked and recovered fullscreen before the controlled reboot. A uniquely owned one-time wake was scheduled for the test and its removal was verified. Global power-policy hashes match. This tests recovery after an actual wake; it does not implement or claim a new Host-controlled wake feature.

All **22 final checks pass**. FileVault remains off on the iMac and on at the Studio. The account remains non-administrator, saved Host/Viewer binding and the exact startup agent are preserved, and the GUI-context lock policy remains disabled. The UI capture helper stayed off on both Macs. No FileVault setting, permanent login/power policy, network configuration or Remote Login setting was changed. The bounded root worker ended with the verified reboot; no root service or login helper was installed. After testing, only the temporary forced-command diagnostic key/script were removed, the key was independently rejected, the motion-test process was stopped, and normal RetinaLink streaming continued.

Live testing corrected the test tools rather than the installed apps: a missing legacy lock preference is now optional, effective lock reports distinguish `off`, `immediate`, numeric and unknown states, and actual console lock comes from Root's `IOConsoleLocked` boolean. The GUI-context query uses the dedicated bootstrap/audit session: ordinary sudo reported `immediate` even after its environment was cleaned, while `launchctl asuser 502` correctly reported `off`. A successful generic wake request had also failed to light the display within the earlier probe; the bounded test utility now uses public `IOPMAssertionDeclareUserActivity`, observes the power transition and releases its temporary assertion. Ten offline parser/console/wake tests pass, including unknown-state rejection, bounded retries and no false wake success. No runtime app rebuild was needed.

Evidence: `work/dedicated-first-login59/result.json` (22 checks), `final-metadata.json`, `post-reboot/result.json`, `final-reboot-recovery/result.json`, `corrected-recovery/result.json`, `effective-lock-contexts.json`, the bounded worker source and `cleanup.json`. Earlier failed or cancelled test-tool attempts are retained separately. These are startup/recovery checks, **not proof of stable physical 5K/60-fps scanout or panel latency**. Earlier sections below are historical; their deferred dedicated-session checks are superseded by this result.

---

# Dedicated-account Viewer updated — 0.7.0 build 59, 19 October 2026

**The protected `retinalinkdisplay` installation is now the accepted, notarized Viewer 0.7.0 build 59, upgraded from 0.6.0 build 53.** The owner authenticated SSH and sudo directly in Terminal. The maintenance operation replaced only `/Users/retinalinkdisplay/Applications/RetinaLink Viewer.app`; it did not activate that account, stop the original account's Viewer, log out or restart the iMac. Its executable SHA-256 matches the accepted release exactly. Strict Developer ID verification, Gatekeeper (`Notarized Developer ID`) and recursive dedicated-account ownership checks pass.

The installed binary passed its complete self-test suite as the non-administrator dedicated user through SSH on Big Sur, including AMD R9 M290X BC7 texture uploads at 5K, scoped automatic-Ethernet policy, receive teardown, native approval and encrypted transport. Separate native-pairing and transport tests also passed. These use disposable in-memory identities and loopback fixtures; they do not enroll the real account or access its saved Keychain credential. Ten controlled maintenance tests cover successful replacement, signature/ownership failure, running-app refusal, rollback and retention of a private backup when recovery fails.

All 22 before/after preservation checks pass. FileVault remains off on the iMac and on at the Studio. The dedicated account remains non-administrator; automatic-login selection, its exact startup agent, permitted sleep/lock/setup preferences and the original account's saved binding match. Pending first-login enrollment was inspected only with `lstat`; its contents were neither read nor hashed, and its metadata is unchanged. The UI capture helper stayed off on both Macs. Temporary remote update helpers were removed and noninteractive sudo authorization is unavailable afterward. Independent fresh application status still reports the original-account Viewer trusted, fullscreen and connected, with Host streaming through direct TLS.

**Still untested:** the dedicated account's first graphical sign-in, enrollment consumption, fullscreen streaming, automatic-login reboot and password-free wake. Its pending enrollment and existing `--appliance` startup agent are preserved for that first sign-in. Headless GPU and protocol tests do not establish dedicated-session presentation or stable physical 5K/60-fps output. No company network settings, FileVault setting or login policy were changed by this app update.

Evidence: `work/dedicated-viewer59-update/result.json`, `before.json`, `after.json`, `device-status.json`, `gatekeeper.txt`, `self-tests.txt`, `native-tests.txt`, `transport-tests.txt` and `final.json`. Runtime apps remain the existing accepted release; only the maintenance helper and its failure tests changed in the repository.

---

# Automatic Ethernet verified — 0.7.0 build 59, 18 October 2026

**The active Studio Host and Big Sur iMac Viewer are signed, notarized build 59, paired and streaming 5120 × 2880 over interface-scoped IPv6 Ethernet.** No IP addresses were entered. SSH was used for deployment and independent diagnostics; the UI capture helper remained off. This validates the existing company Ethernet LAN, not the unavailable CM888 direct cable.

The actual signed 58→59 update passed on both Macs without enrollment or another Screen Recording approval. Normal Host-agent restart and Viewer relaunch retained trust and fullscreen streaming. Native Host and AMD Radeon R9 M290X Viewer self-tests pass, including the new transport policy, scope, TLS and receive-credit teardown tests. Nineteen offline Python release-policy tests also passed.

The live runtime test authenticated a second, interface-bound TLS connection without sending a Viewer greeting or frame data. Both active connection IDs and process IDs remained unchanged through trusted and wrong-key probes, including fresh status publications afterward. The wrong key was rejected. Simulating an unavailable Ethernet route recovered to a verified Wi-Fi stream in **6.26 seconds**; automatic return to a new verified Ethernet stream took **55.96 seconds**, including failed-route cooldown and discovery/capture recovery. A second failure immediately after that return reused healthy Wi-Fi in **8.61 seconds**, with no app restart or Viewer crash. Switching is automatic, not instantaneous. The stored preferred-probe snapshot has no generation counter, so its freshness is not independently established; the new returned stream's TLS authentication, interface constraint and connection identity are independently checked.

Live testing found and fixed three defects before this release: Big Sur's `NWTXTRecord` subscript/getEntry returned nil while its dictionary contained a valid Host ID; temporary Bonjour withdrawal consumed the authenticated Ethernet preference during handover; and destroying a Viewer with outstanding frame credits triggered libdispatch's semaphore-disposal abort. Build 59 reads the compatibility dictionary, retains the verified preference for a bounded discovery grace period, and uses a bounded lock-protected receive counter whose teardown permits abandoned frames. The exact credit regression also passed as an isolated executable on the iMac. Candidate 56/57/58 failure evidence is retained privately and those installers were not delivered as the final release.

After testing, ordinary `--autostart` Host-agent and `--appliance` Viewer launches were restored, all local feed preferences and the temporary feed forward/server were removed, and both updater records report public hosting unconfigured. Final normal recovery took 6.31 seconds; the independent idle Host-agent recovery test took 43.16 seconds. A 27-check comparison against the pre-install baseline passed: persistent network configuration, service order, default routes, DNS, pairing and FileVault are unchanged on both Macs. Native update checks also retained public SSH keys and login/power/startup settings. No application SSH display tunnel is present. Scoped link-local sockets were independently observed on both Macs.

Runtime source commit: `643b2d0`. The release's overall dirty flag is true because an unrelated pre-existing untracked review file was left untouched; compiled source, release resources and tests match the commit. Host, universal Viewer, the exact bundled Viewer ZIP and both outer DMGs have validated Apple tickets and Gatekeeper acceptance. Installers: `outputs/RetinaLink-0.7.0.dmg` and `outputs/RetinaLink-Viewer-0.7.0.dmg`; artifact hashes and submission IDs are in `outputs/RetinaLink-0.7.0-Release.json`.

**Pending:** physical CM888/no-DHCP operation, real cable unplug/replug, physical panel FPS and reboot/wake testing. The active original-account Viewer is build 59. The protected dedicated-account copy was still build 53 during this October 18 test; its subsequent build-59 update is recorded above. Its first automatic sign-in and password-free wake remain untested. FileVault and company policy are never bypassed.

Evidence: `work/direct-ethernet/installed59/result.json`, `runtime59/result.json`, `runtime59/trusted-probe.json`, `runtime59/untrusted-probe.json`, `normal59.json`, `final59.json`, `host59-self-test.log`, `imac59-self-test.log`, `credits59-imac.txt` and the final release/DMG states. See [DIRECT_ETHERNET.md](DIRECT_ETHERNET.md) for setup and implementation boundaries. Earlier sections below are historical.

---

# Automatic updates verified — 0.4.0 build 48, 17 October 2026

**Both installed apps automatically updated through Sparkle from build 46 to build 48 and remain signed, notarized, paired and streaming fullscreen.** Host owns the automatic-update preference and explicit Update Now action. Viewer needs no updater interaction. The earlier signed 45→46 bootstrap also passes without pairing or capture reapproval.

The real SSH test disables automatic installation on both roles and confirms that availability alone does not download/install an archive. It then serves modified signed XML and corrupted ZIP bytes: both apps reject both cases, retain build 46, and keep streaming. Restoring the original signed feeds/archives automatically downloads, verifies, installs and relaunches both apps into build 48. Before/after Host and Viewer binding hashes and the complete public authorized_keys hash match; Host ID, signing team, namespace, startup preference, FileVault and login status also match. No enrollment or private-key export is used by this test.

Both updated apps hand control back to their existing startup agents. Simulated crashes on each Mac recover into fullscreen streaming with the retained pairing. After testing, loopback HTTP service, the temporary management-SSH feed forward and local test-feed preferences are removed. Normal agents retain only `--autostart` / `--appliance`; both updater status records explicitly report public hosting unconfigured. Public hosting was deferred by the owner; these builds do not pretend to have an online production feed. The UI capture helper stays off throughout. An internal Host view-hierarchy export, without screen capture, verifies the native update card layout.

Both clean signed releases are accepted and stapled. Final Viewer notarization ID: `45ddd38b-5a69-455e-9402-5976efa6e4e6`; final Host ID: `58438df7-5dd5-46fc-986e-820b60965896`. The final apps use source commit `9ea2427`, with Sparkle 2.9.6 and every nested helper re-signed for team ZPCS5VQL89. The private Ed25519 update key remains in Keychain; the owner authorized only the official publisher tools. Fifteen offline policy tests pass, along with actual signed Host and AMD iMac self-tests. Gatekeeper accepts the installed Viewer as Notarized Developer ID.

A final 30-second 5K native GPU scroll sanity check averages 58.65 delivered and 58.67 rendered updates/s; source drawing averages 58.81 fps. Host has zero backpressure skips; Viewer drawable wait averages 0.0 ms. This establishes moving-content streaming after the update, not stable 60 fps or physical scanout proof. No physical logout/reboot is performed.

Download: `outputs/RetinaLink-0.4.0.zip`, SHA-256 `5fbe9c70c1e250de4432d60d4a596f1ec5312364f07da3792ae18ae03747c44a`. Public release metadata is in `outputs/RetinaLink-0.4.0-Release.json`. Detailed evidence: `work/automatic-update-46-to-48/result.json`, its before/after/failure/request records, `work/signed-bootstrap-45-to-46/result.json`, `work/auto-update-48-imac-final-verification.txt`, `work/auto-update-policy-tests-final.txt`, final release states and `work/perf/automatic-update-040-live`. Earlier records below are historical.

---

# Apple notarization accepted — 17 October 2026

**Apple has accepted Host and Viewer in both signed builds 44 and 45.** Tickets are stapled and validated; Gatekeeper reports `source=Notarized Developer ID`. The final 0.3.1 build-45 distribution is `outputs/RetinaLink-0.3.1.zip`, SHA-256 `56d3defc11eb56ec0c37fe3067ed10f1eb61234c220ab88cfab9062cb2cc6aa8`. Its exact bundled Viewer ZIP was extracted and its signature, executable hash and stapled ticket verified before packaging. No passwords or private signing keys were copied into artifacts.

Accepted Viewer submission IDs: build 44 `236ba8d5-42d2-42e9-85b0-38db46fa216b`, build 45 `d98616db-3161-45ab-806e-038a5547f079`. Accepted Host submission IDs: build 44 `4f04da52-d969-4ef7-a553-2bff9727c05e`, build 45 `529fd163-660f-4c97-956b-afaaf17423a1`. Each release state retains the original uploaded archive hash and clean source commit. The notarization helper verifies its saved Keychain profile; eleven offline policy/credential-report tests pass.

The signed baseline build 44 is installed at the permanent Host and Viewer paths. Initial native setup encountered leftover signed-namespace test items whose ACLs still pinned an earlier ad-hoc `cdhash`. A read-only ACL/lock metadata diagnostic and the system's security log identified this; no secret item contents were read by diagnostics. The app's actual Forget Display action removed those stale test items. Fresh Host-led signed enrollment then completed automatically and the fullscreen iMac Viewer connected without manual Viewer input. FileVault and automatic-login settings were unchanged. The earlier development namespace remains separate.

**Installed signed update passes:** the owner replaced the old development Screen Recording entry once. The signed baseline then passed Host-led enrollment, fullscreen automatic streaming, pause/resume, closing the Host window, Viewer crash recovery, Forget/re-enrollment, native Host startup-agent recovery and tunnel repair. FileVault and automatic-login settings matched before/after; the UI capture helper stayed off. The test result now records the actual endpoint version/build instead of its old hardcoded 0.3.0 label.

`Tools/test_signed_update.py` then replaced the permanent Host with notarized build 45 and invoked the actual Host-side Update Display Software path to replace Viewer 44 with 45. This path did not run enrollment. Host and Viewer resumed 5120 × 2880 streaming fullscreen. Host/Viewer binding hashes and the complete public authorized_keys file hash remained unchanged, as did Host ID, signing team, namespace, startup preference and login settings. The final Host was restarted through its real startup agent with only `--autostart`; it captured successfully without another Screen Recording approval. Killing only the verified Viewer test process demonstrated launchd crash recovery and retained fullscreen pairing. Both installed apps remain 0.3.1 build 45 at their permanent Applications paths, with no test flags in startup agents.

A final 45-second native 5K GPU scroll scene (38 steady samples, first 5/final 2 seconds excluded) averaged 57.49 delivered/rendered updates/s and 121.88 Mbps on Viewer; source drawing averaged 57.68 fps. Host reported zero backpressure skips. Viewer drawable wait was 0.0 ms with mean queue 0.02 ms. This is a streaming sanity check, not proof of stable 60 fps or physical panel scanout; one-second Viewer rates ranged 41.8–60.8. Timing-only evidence is in `work/perf/signed-031-build45-live` and `work/signed-031-build45-live-summary.txt`.

These checks establish continuity for this actual update. First-run approval and periodic reauthorization remain macOS policy. A physical logout/reboot is not performed; FileVault and login settings remain unchanged. No hosted automatic Host-download feed is implemented; Host replacement and its bundled Viewer-update action are validated. The UI capture helper remains off.

Evidence: `work/notarization-accepted.json`, both `work/release-0.3.1*/release-state.json` files, `work/setup-030/enrollment.json`, `work/setup-030/host-ui.json`, `work/signed-baseline-final-setup.stdout`, `work/setup-030/result.json`, `work/signed-update-44-to-45/result.json`, its before/after metadata and the RetinaLink-only ACL/lock metadata reports. The following sections are historical preparation records, superseded by this result where they describe pending Apple acceptance.

---

# Developer ID signing validation — builds 44/45, 17 October 2026

**Real Developer ID signing now succeeds for both apps. Apple notarization and installed signed-upgrade validation are not yet complete.** The installed working apps remain 0.3.0 build 43; the final signed candidate is 0.3.1 build 45, with build 44 retained as the signed upgrade baseline.

The owner installed `Developer ID Application: Universiti Malaysia Sarawak (ZPCS5VQL89)`. Build 44 uses source commit `043f949`; build 45 uses `63af3b7`. Both preparations record clean source trees. Host and universal Viewer have Hardened Runtime, secure timestamps, the expected bundle identifiers, stable trust namespace and valid Apple Developer ID signatures. Both roles' designated requirements are identical between builds 44 and 45 while their executables differ. Certificate/build hashes are not pinned into the update identity.

Actual Developer ID Host and Radeon R9 M290X iMac Viewer self-tests pass for both builds. Build 45 additionally tests that the classic-Keychain dialog guard suppresses interaction and restores the previous process state after both success and an exception. These state tests do not access saved secrets. Simulated capture-denial recovery still passes. The UI capture helper stays off; isolated test copies on the iMac are removed after testing.

A native Launch Services probe uses two distinct hardened Developer ID binaries whose designated requirement is exactly the real Host's requirement. A creates a uniquely named temporary test item; B reads it successfully with authentication interaction explicitly suppressed. An ad-hoc clone fails immediately with status `-25293` under the same guard. The payload is a fixed non-secret test string, not a stream credential or private key. All test items are removed, and the installed Host's Launch Services registration is restored. This establishes native Keychain continuity and denial for that controlled test, not end-to-end production upgrade success.

The first probe relied only on `kSecUseAuthenticationUIFail`. That control could enter classic-Keychain authorization and is not used as evidence of silent access or unauthorized automatic access. Build 45 therefore adds a scoped `SecKeychainSetUserInteractionAllowed(false)` guard, restores the prior value on every exit and serializes the app's other vault operations against that process-local setting. This does not alter stored ACLs, grant another signer access, unlock Keychain or change any system security setting. The guarded native test confirms the intended behavior on the Studio, and the actual iMac passes the guard's state/restoration tests.

The notarization profile still needs successful credential entry through the dedicated Terminal helper. Its latest version verifies Apple's saved profile and records only profile/team/time readiness metadata, without reading the password into Python or logs. No application has been accepted by Apple's service yet, and no signed download is represented as notarized. The independent native Screen Recording startup and signed-to-signed Viewer replacement tests remain pending Apple's acceptance and the one-time transition from ad-hoc pairing.

Evidence: `work/release-0.3.1/release-state.json`, `work/release-0.3.1-build45/release-state.json`, `work/developer-id-upgrade-identities.json`, `work/developer-id-host-self-tests.txt`, `work/developer-id-imac-self-tests.txt`, `work/developer-id-45-host-self-tests.txt`, `work/developer-id-45-imac-self-tests.txt`, `work/developer-id-45-permission-test.txt`, `work/signing-keychain-native/result.json` and `work/signing-keychain-native-guarded.stdout`. The historical preparation notes follow.

---

# RetinaLink 0.3.1 build 44 — signing preparation, 17 October 2026

**The Developer ID/notarization pipeline is implemented but a signed, notarized release has not yet been produced.** The local Keychain exposes no valid Developer ID Application identity. It contains Apple Development certificates, which are not the required distribution identity. Apple's `notarytool history --keychain-profile RetinaLink-Notary` also reports that the dedicated credential profile does not exist. The owner has been asked to create/import the Developer ID identity in Xcode; the separate notarization setup uses Apple's secure Terminal password prompt. No passwords/private signing keys are requested in chat or exported.

The isolated 0.3.1 build 44 compiles for arm64 Host and universal Intel/Apple-silicon Viewer. Both app self-test suites pass, including on the actual Radeon R9 M290X iMac through SSH. New checks reject a different Host, team, development namespace or injected signing requirement. The existing isolated simulated capture-denial test passes. The iMac also correctly rejects the actual ad-hoc test app against the Apple Developer ID signature requirement. Nine offline release-policy tests pass for identity selection, accepted/rejected/pending submissions, changed upload rejection, Gatekeeper failures, resume without a duplicate upload, and Viewer ticket embedding before Host sealing/submission. These policy tests use explicit fixtures; they are not Apple notarization results.

Signed builds now require Developer ID Application, Hardened Runtime, secure timestamps, stable bundle identifiers and a stable Keychain namespace. The release tool separately notarizes/staples Viewer, embeds the exact stapled archive, re-signs/notarizes/staples Host, re-extracts Viewer for validation and only then creates a distribution ZIP. It records source identity and submitted archive hashes, retains rejection logs, and does not regenerate a completed published archive. No hardened-runtime exception or privacy/security bypass was added.

Host now has a separate **Update Display Software…** path. It verifies same-team signatures, checks that the existing Viewer is paired to this Host, validates the incoming replacement before stopping Viewer and preserves binding, Keychain items and startup configuration. It does not call enrollment or rotate pairing/tunnel keys. This real signed-to-signed replacement path remains unverified until the certificate and notarization profile are available. `RELEASING.md` specifies the two-successive-build validation required before claiming update continuity. A hosted automatic Host-download feed is not implemented.

The working installed Host and fullscreen iMac Viewer remain **0.3.0 build 43**, connected through the existing tunnel. The isolated test app was removed from the iMac after its tests. The UI capture helper remained off. FileVault, automatic login, the existing Screen Recording grant, system trust and the production pairing were not changed. No new notarized download is claimed or distributed. The first transition from ad-hoc to Developer ID will require one Host-led setup and may require one final macOS permission approval; later same-team updates are designed to preserve identity. macOS's own first-run and periodic authorization policy still applies.

Evidence: `work/build-signing-044.log`, `work/signing-host-self-tests.txt`, `work/signing-imac-self-tests.txt`, `work/signing-permission-test.txt`, `work/signing-imac-adhoc-rejected.txt`, `work/signing-release-tests.txt`, `work/signing-doctor.txt`, `work/signing-notary-profile-error.txt` and `work/signing-installed-state.json`.

---

# RetinaLink 0.3.0 build 43 — setup and appliance UX, 17 October 2026

## Implemented behavior

Setup and everyday controls now live on Host. Its native AppKit interface uses system typography, controls, SF Symbols and `NSVisualEffectView` materials. Host discovers SSH-enabled Macs, checks the selected iMac's macOS and FileVault status before installation, installs the bundled universal Viewer, and enrolls a saved device credential. A new installation still needs Remote Login enabled and an accessible signed-in account once; discovery is not authorization.

Viewer runs as a borderless native-panel window with automatically hidden Dock/menu bar. It has no routine address, pairing-code or Connect controls. It starts after graphical sign-in through its optional per-user login agent, shows fullscreen standby when disconnected, reconnects automatically and resumes without Viewer input when Host reconnects. Closing the paired Host window leaves streaming active in the menu bar. Host can identify, pause, reconnect or forget the display.

FileVault, automatic login, passwords, screen locking and system sharing policies are unchanged. The standard flow creates no volume, partition or additional macOS installation. FileVault-on and unknown states immediately explain the boot restriction; only a verified FileVault-off iMac receives the optional dedicated-display automatic-login guide. The guide explains physical access and account isolation and leaves password entry and automatic-login configuration to the owner in macOS. A user login agent cannot run before an Intel Mac's FileVault unlock or before its graphical sign-in.

## Build and correctness checks

- Final apps are **0.3.0, build 43**. Host is arm64; Viewer is universal x86_64/arm64. Built and installed executable hashes match on both Macs; strict deep signature verification passes. These are ad-hoc development signatures, not notarized distribution signatures.
- Host and actual iMac Viewer self-tests pass. They retain codec, packet validation, pairing, tile upload and capture-credit tests, plus enrollment input validation, FileVault on/off/unknown guidance and Aqua-only startup-agent checks.
- Host's isolated simulated permission-denial test passes: denial leaves the listener and authenticated connection alive, releases capture resources and permits explicit retry. It does not read screen content or grant an OS permission.
- A separate production-renderer probe on the actual AMD iMac renders native 5120 × 2880 full/sparse/full phases. Settled GPU-completion rates are **59.98 / 59.98 / 60.01 updates/s**; full-frame upload setup averages **5.15 / 4.87 ms**, with GPU work **3.75 / 3.63 ms**. This isolates the renderer and omits capture, compression and network work; it is not an end-to-end or physical-FPS result.

## Native setup and recovery validation

The **complete final build-43 suite passes** using native Launch Services for the initial Host and its real GUI login agent for Host recovery. It tests the standard setup selection, with dedicated display mode off:

| Actual SSH-controlled check | Result |
|---|---|
| Host installs/enrolls bundled Viewer without Viewer interaction | Pass |
| Native 5K stream, trusted connection, fullscreen, automatic Dock/menu-bar hiding | Pass |
| Host Disconnect → fullscreen standby; Connect → streaming | Pass |
| Closing the paired Host home leaves streaming active | Pass |
| Kill verified Viewer process → launchd restart and fullscreen reconnection | Pass |
| Forget → unpaired fullscreen readiness and startup removal | Pass |
| Host re-enrollment → streaming without Viewer input | Pass |
| Independent Host GUI login-agent startup restores trust and streaming | Pass |
| Exit app-owned tunnel → fullscreen reconnecting → passwordless automatic repair | Pass |
| FileVault and automatic-login before/after comparison unchanged | Pass |
| UI capture helper absent before/after | Pass |

The native-launch test initially exposed a stale Screen Recording approval for an older ad-hoc executable. The macOS permission log explicitly reported that its stored code requirement did not match build 43. Enabling the old switch and restarting did not resolve it. The owner removed that stale entry and added the permanently installed Host again through System Settings; the unchanged binary then passed native capture and the complete suite. No privacy database or system trust setting was modified. Earlier direct developer-tool launches that inherited the tool's capture authority are not used as evidence of independent Host permission.

## Final live native-5K regression

After the native recovery suite, the same production login-agent Host and fullscreen Viewer run an untraced 45-second GPU scrolling scene through ScreenCaptureKit, compression, SSH/TLS, unpacking and Metal. Both endpoints report 0.3.0 build 43. After excluding the first five and last two seconds:

| Measurement | Settled mean |
|---|---:|
| Source draw/GPU-completion counter | 59.53/s |
| Complete captures / Host delivered updates | 59.49/s |
| Viewer GPU-completed updates | 59.49/s |
| Host encode + pack | 7.24 ms |
| Host acknowledgement cycle | 24.71 ms |
| Viewer upload setup / GPU work | 2.22 / 4.01 ms |
| Viewer application queue / drawable wait | 0.01 / 0.00 ms |
| Traffic | About 126 Mbps |
| Capture credit-discard events | 0 |

Native dimensions remain 5120 × 2880. One-second Viewer rates range from 50.1 to 60.9/s; this is not a claim of a constant 60 new images each second. Source production also dips. The API unique-positive timestamp rate is 57.63/s; the prior AMD driver evidence below explains why this is not a physical-FPS calculation. No new driver trace or camera measurement was taken. Frame tracing and experimental pacing are off, and the UI capture helper stays off. One SSH read of startup-agent configuration overlaps this run; it is a realistic bounded regression, not an exclusive-idle benchmark. Evidence is `work/perf/setup-043-native-gpu-scroll` and `work/setup-043-performance-summary.txt`.

## Connection and trust boundaries

A separate earlier native control-plane recovery test passes with capture permission pending: exiting only the app-owned SSH master leaves Viewer fullscreen; Host recreates its loopback tunnel from its saved Keychain identity without a password and restores trusted TLS. A command attempt through the restricted tunnel key is rejected. Management SSH and Screen Sharing remain connected. This control-plane result is distinct from capture recovery.

Enrollment uses an authenticated owner SSH session. The stream credential is random 128-bit material; the tunnel has a separate Ed25519 key. Persistent secrets are in the login Keychains. The short-lived GUI enrollment helper consumes an owner-only temporary request over SSH and deletes it before saving trust. Unrelated SSH authorized keys are preserved; the app key cannot open a shell or PTY and is scoped to loopback forwarding. No password, private key, stream credential, SSH control socket or raw enrollment request is included in release artifacts.

Ad-hoc development builds use a build-specific Keychain namespace and require Host-side re-enrollment after upgrading; they do not automatically approve changed code. Missing or locked trusted credentials fail closed. macOS Screen Recording may also need its stale development entry replaced by the owner. Consistent Developer ID signing and notarization are required for the intended consumer update experience; no valid signing identity is installed in this development environment.

## Evidence and limits

App-only UI exports were reviewed on both machines without a screen capture bridge. Final setup and Host exports are `work/setup-030/control/setup-ui.png` and `host-ui.png`; the Host image records its preparing-desktop transition. The final Viewer standby export is `work/viewer-043-standby.png`. The complete native suite output is `work/setup-043-native-test.stdout`; its result is `work/setup-030/result.json`. Test evidence remains under `work/setup-030`, `work/self-test-043-host.txt`, `work/viewer-self-test-043.txt`, `work/permission-test-043.txt` and `work/render-probe-042-analysis.json`. The probe retains its build-42 label; build 43 changes the Host missing-credential guard and build/trust metadata, not the renderer.

The iMac's measured FileVault status is off and automatic login is not configured. Neither was changed. FileVault-on/unknown branches are checked with test inputs, not by toggling actual disk encryption. No reboot, logout or screen lock was triggered: loading/restarting a GUI login agent is not a cold-boot test. The agent UI capture helper remains off. Native 5K60 remains a target; stable physical 60 new displayed images/s and direct-monitor-equivalent latency are not established.

The previous rendering/capture investigation follows unchanged for its separate timing evidence.

---

# RetinaLink 0.2.10 build 38 — validation, 17 October 2026

## Outcome and corrected interpretation

**Strictly stable native 5120 × 2880 at 60 new updates/s has not been achieved. A driver trace now shows that the apparent post-GPU losses inferred from Metal presentation callbacks were not actual missing Viewer frames in that recorded interval.** This release retains the newest pending capture when frame credits are full, adds bounded diagnostics for API timestamp anomalies and hardens the diagnostic clock lifetime. The new pacing experiments do not establish a throughput gain. Normal operation retains native Metal presentation, three drawables and vsync; clock probes, frame traces, the single-presentation gate and pacing plans are off by default.

All runs in this investigation used SSH for installation, test control and evidence collection. The agent's UI capture helper remained off, and Screen Sharing remained connected. The machines are the same M2 Max Studio and Late-2014 Retina iMac / Radeon R9 M290X on Big Sur. Native dimensions, encryption and the existing connection route were retained. No thermal warning was observed. These conditions do not establish an otherwise idle or exclusive compositor environment. No camera-based physical frame-identity or input-to-photon measurement was made.

## Driver display evidence supersedes callback-based loss claims

A separate 15-second Metal System Trace on the actual iMac records 890 application command buffers and maps all 890 uniquely to Viewer GPU-commit sequences. The relationship is `Viewer sequence = Instruments application Frame + 11098`. The direct same-machine monotonic-clock mapping has residuals of approximately −39 to +4 microseconds. This joins actual application frame identities, rather than assuming the panel's roughly 60-Hz swap activity means 60 new application frames.

The completed display-surface intervals identify **887 consecutive application frames, Frame 1 through Frame 887, with no missing or repeated interior application frame ID**. Their rate over the labelled interval is **59.051 application display intervals/s**. The final three application command buffers lie at the recording boundary and do not have completed labelled intervals in that table. Within the 887 retained frames:

| Measurement for the same mapped frames | Count |
|---|---:|
| Driver-recorded distinct application display intervals | 887 |
| Positive Metal presentation callbacks | 868 |
| Zero-timestamp Metal presentation callbacks | 19 |
| Distinct positive Metal timestamps | 852 |
| Repeated-positive-timestamp pairs | 16 |

Every one of the 19 zero-timestamp callbacks maps to a distinct driver-recorded display interval. Every one of the 16 repeated-timestamp pairs maps to two different display-surface intervals, normally one refresh apart. For example, sequences 11338 and 11339 report the same positive timestamp, but the driver records their frames 240 and 241 at **4.401455917 s and 4.418138333 s**, on different output surfaces. Sequence 11345 reports zero, while its frame 247 has a recorded interval starting at **4.518157 s** and lasting about 16.70 ms.

Thus the corresponding **852 distinct API timestamps, 56.721/s, undercount the 887 recorded application display intervals**. Counting only positive callbacks also undercounts them. Deduplicating timestamps is useful for describing API behaviour, but is not a physical-FPS correction on this AMD/Big Sur path. The Viewer therefore labels this diagnostic **“Presentation timing (API): unique timestamps/s, positive callbacks/s”**, with zero, repeated, reordered, stale and invalid callback counts. GPU completion/acknowledgement remains a separate statistic. Counter tests verify bounded and orderly anomaly accounting, not physical display throughput.

The driver trace is stronger evidence of application frame retention than these callback timestamps. It still is not independent camera-based physical scanout or input-to-photon proof. It was collected during profiling and is kept separate from final untraced performance measurements.

## Genuine retained-frame intervals and capture gaps

The driver trace contains **14 intervals of approximately 33 ms** in which one application frame remains on the display for an extra refresh. These are genuine recorded holds even though no interior application frame ID is lost. Their stage-by-stage mapping is preserved in `metal-sequence-map-analysis.json`, separately from the 19 zero callbacks and 16 repeated-timestamp pairs.

Five holds have 33 ms gaps between transmitted source images with an intermediate idle callback containing no image. Another has a 67 ms transmitted-image gap, but ScreenCaptureKit produced the three intervening images: credit backpressure skipped them while waiting for earlier acknowledgements. Five additional holds already have 23–30 ms gaps at capture callback delivery. Two first show a larger delay downstream: Viewer body-arrival gaps of approximately **33.95 / 59.41 ms**, against Host packed-frame gaps of **18.11 / 11.62 ms**. One hold has otherwise ordinary approximately 17 ms stage spacing. These identify where delays first appear; they do not prove the internal compositor latch deadline or a single cause for every hold. GPU readiness before the next physical vsync does not prove that an earlier compositor deadline was met.

Source image production can vary independently of the receiver. Requested 60 Hz and source movement calls are not proof of 60 new composited images. Idle capture callbacks contain no missed image to recover. Exact attribution of the remaining source/capture gaps remains unresolved. No interpolated or forced duplicate frames are inserted to inflate output rates.

## Host credit retention and final-image correctness

The genuine hold at Instruments frame 736 exposed a recoverable loss in the old Host credit path: ScreenCaptureKit produced three complete images, but full frame credits caused the Host to consume and discard them. If the last changed image of a desktop update arrived in that state, the old path could discard the final image and have no later capture to trigger a correction.

Build 38 checks available credit **before consuming the capture mailbox**. When credits are full it parks the drain and retains one replaceable pending image. New captures replace that single pending image; the first acknowledgement that makes room schedules one asynchronous drain. This flushes the final pending image even if no new capture follows the acknowledgement. There is no polling, no unbounded queue and no increase in the normal three-frame credit limit. The old behaviour remains available only as the diagnostic `--drop-credit-frames` control.

Host build-38 tests pass for bounded retention/replacement, final-image flush without another capture, one ACK wake, no oversend, credit limits and stop/restart cleanup, including memory/ownership checks. These establish the state and lifetime rules; they are not a physical-FPS measurement.

Three 45-second controls deliberately force **one frame credit**, rather than the normal three, to exercise saturation:

| Forced one-credit policy | GPU completions/s |
|---|---:|
| Old discard path A | 29.97 |
| Retain newest pending image B | 35.37 |
| Old discard path C | 29.95 |

Retention improves this constrained workload by resuming when the ACK arrives instead of waiting for a later capture event. It still coalesces older captures into the newest pending image, at approximately 24 replaced captures/s in B. Zero credit-discard events does **not** mean zero capture coalescing or that every produced image is transmitted. This result does not establish stable 60 fps or a general throughput improvement with the default three credits.

B also contains an approximately two-second pause in complete-capture callbacks around test +16 s. During that pause the Host has zero frames in flight and no pending credit-held image; the source control timer remains alive. This rules out a parked credit wait, but does not isolate capture delivery from actual compositor image production or identify the internal OS cause. A second 45-second retention run produces **38.32 GPU completions/s** from **59.97 complete captures/s**, with a 19.89 ms mean ACK cycle. That pause does not recur. It records 1,455 credit waits and 1,455 ACK resumes, no credit-discard events, and 824 coalesced captures in the 38 settled samples. Both old-path controls produce approximately 30 completions/s. This confirms a useful improvement under deliberately restricted credit pressure, not a general 28% speed gain or an absence of all capture pauses.

## Controlled pacing experiments: API timing rates, not physical FPS

The following prototype comparisons use **distinct positive API timestamps/s**, not driver-recorded application display intervals or physical FPS. Their callback anomalies are now known to undercount actual retained application frames in the profiled interval above. The settled window excludes five seconds after each phase begins and its final two seconds, intersected with the source test's settled interval. Source/capture production also varies between phases.

Build 33 compares native presentation, a single outstanding presentation, and a native control:

| Policy | Distinct positive API timestamps/s | Zero callbacks | Repeated timestamps |
|---|---:|---:|---:|
| Native A | 55.83 | 61 | 55 |
| Single pending presentation B | 29.99 | 0 | 0 |
| Native C | 52.11 | 61 | 69 |

The single-presentation gate removes API anomalies at half rate. Waiting serially for a callback arriving about two refresh intervals after submission constrains throughput. Queue depth and rate change together, so this does not isolate which change removes the anomalies. The gate is not enabled in production.

Build 34 tests native/timed-refresh/native in one continuous stream, retaining normal in-flight GPU credits:

| Policy | Settled duration | GPU completions/s | Distinct positive API timestamps/s | API timestamp/GPU fraction |
|---|---:|---:|---:|---:|
| Native A | 22.55 s | 60.00 | 58.84 | 98.07% |
| Refresh-anchored timed B | 22.99 s | 54.51 | 52.98 | 97.19% |
| Native C | 28.69 s | 56.84 | 55.10 | 96.94% |

All timed frames finish GPU work before their requested target, with a minimum reported margin of 6.03 ms. Nevertheless, 93 of 1,241 positive timestamps appear approximately one refresh interval before the requested target, 866 in the predicted slot and 282 one slot afterward. The earliest reported timestamp is 14.04 ms before the target. Together with the driver frame mapping, this is evidence of API/driver timing limitations, not evidence that those frames physically appeared before the requested time. No useful throughput gain is established.

Build 35 paces CPU command submission against predicted refresh phases while retaining the native presentation helper. Submission deadlines are analysed separately from presentation targets:

| Policy | GPU completions/s | Distinct positive API timestamps/s | Mean Host ACK cycle |
|---|---:|---:|---:|
| Native A | 58.10 | 55.87 | 24.27 ms |
| Refresh-anchored submission B | 56.60 | 54.60 | 36.93 ms |
| Native C | 59.49 | 57.84 | 26.20 ms |

Submission pacing increases acknowledgement latency without establishing a throughput gain. All three experimental pacing policies are rejected as production defaults; native presentation is retained.

## Five-second timestamp correlation

The build-33 clock trace associates the API anomalies with a periodic CVDisplayLink output-prediction phase. Positive drawable timestamps exceed the nearest predicted output time by an offset that ramps from approximately zero to 0.82 ms over five seconds, then resets. Thirteen settled prediction corrections occur exactly **300 callbacks apart**, averaging **5.00138 seconds**. Raw CV host ticks show the same corrections, so translation to the Viewer clock does not introduce them.

All 61 zero-timestamp frames and all 110 frames belonging to repeated-timestamp pairs in that baseline occur near the tail of the sawtooth. GPU-end/command-commit phase distributions overlap normal frames. The source animation's four/eight-second cycle and a simple source/panel frequency beat do not explain the five-second pattern. Actual layer metadata confirms `presentsWithTransaction == false`, vsync enabled, three drawables, opacity enabled and the expected backing layer; redundant resize redraws do not explain the anomalies.

This identifies a timestamp/clock-prediction correlation, **not the cause of physical presentation drops**. The subsequent driver trace demonstrates that the zero/repeated callback inference was wrong for its mapped frames. The internal OS bookkeeping behind these timestamp anomalies remains unresolved.

## Profiling and final release checks

Earlier profiler attempts failed while saving with POSIX error 24 because the profiler child inherited a soft file-descriptor limit of 256. Raising only that child process's limit to 8192 allowed the authorized trace to save. No system permissions, security settings or persistent user limit were changed. Failed saves are not used as performance evidence.

The CVDisplayLink wrapper retains callback state independently of its owner, disables that state before stopping, and avoids an unretained callback context or owner/link retain cycle. The capture encoder also retains its Core Video texture wrapper until the GPU command finishes. These are ownership/lifetime corrections, not isolated performance-gain claims. Presentation-counter and scheduler tests cover ordering, bounds and deadline rules as diagnostic correctness checks.

The earlier build-37 untraced controls, with native presentation and the normal three credits, measured **59.98 complete captures/s and 59.93 GPU-delivered updates/s** for the GPU scrolling source, and **59.62 / 59.62 per second** for native-window motion. These are source/capture and GPU-completion rates, not physical presentation rates; they do not establish that every display refresh carried a new application frame.

Both final installed executables are **0.2.10 build 38**. The following untraced tests use normal three-frame credits, native presentation, three drawables and vsync. Clock/pacing probes, the legacy credit-discard control and frame tracing are off. Each aggregate excludes the first five and final two seconds; values are means of one-second snapshots. Host and Viewer sampling boundaries differ slightly, so small rate differences are not evidence of frame loss.

| Final build-38 workload | Duration | Complete captures/s | Host delivered/s | Viewer GPU completions/s | Mean ACK cycle | Mean Mbps |
|---|---:|---:|---:|---:|---:|---:|
| GPU scrolling source | 90 s | 60.00 | 59.97 | 59.97 | 34.52 ms | 127.04 |
| Native AppKit window motion | 45 s | 59.13 | 59.13 | 59.15 | 11.75 ms | 144.83 |
| Core Animation bitmap-text scroll | 45 s | 60.01 | 59.98 | 59.98 | 33.92 ms | 482.89 |

All three final workloads have **zero credit skips and zero mailbox coalescing** in the settled samples. GPU scrolling records 1,658 credit waits/resumes, and bitmap-text scrolling records 18; pending captures are recovered before a newer capture replaces them. Window motion records no credit waits. Viewer GPU execution averages 4.01 / 2.68 / 4.12 ms respectively. The GPU scrolling source issues 59.99 draws/s, but source physical presentation is not independently measured. Native-window capture falls to 49.1/s in one one-second sample, so its nearly-60 average does not establish stable cadence. These completion counters are not physical display FPS. A static desktop legitimately sends no unchanged images.

The earlier build-37 GPU-scroll ACK mean is lower than build 38's, while completion throughput is nearly identical. Those separate sessions do not isolate an ACK-latency regression or improvement. No end-to-end latency gain is claimed for credit retention; its final-image correctness fix and constrained-credit advantage are the supported results.

Host build-38 self-tests pass on the Studio, and Viewer build-38 self-tests pass on the actual AMD iMac over SSH. The final Host simulated permission-denial/retry test passes without accessing screen content or changing OS permissions. Both app signatures verify; Host is arm64 and Viewer is universal x86_64/arm64. The installed Viewer executable hash matches the supplied Viewer. The updated SSH launcher passes a smoke test using the existing connection, with both final apps remaining connected and no experimental flags. No test scene, profiler recorder or UI capture helper remains running.

The release includes the exact committed source, Git history bundle, selected timing-only evidence, self-test logs, executable hashes and checksums. Reproduce aggregate results with `python3 Tools/summarize_perf.py final-038-gpu-scroll final-038-native-window final-038-ca-scroll credit-retain-repeat-38` against the preserved `work/perf` directories (or the corresponding evidence folders in the release). The source/capture and occasional downstream timing gaps remain the diagnostic boundary. **Stable 60 new displayed frames/s across workloads and direct-monitor-equivalent latency have not been established.**

---

# Archive — RetinaLink 0.2.9 build 32 evidence

**Historical interpretation warning:** the archived text below preserves its original results. Its positive-callback “presentation fps” values are API observations, not physical FPS. The newer distinct-positive-timestamp rates also are not physical FPS: both measures undercount driver-recorded application display intervals in the mapped AMD/Big Sur trace above. Repeated API timestamps do not prove repeated displayed images, and zero callbacks do not prove missing displayed application frames on this receiver. The new driver evidence supersedes those implications in the archive. Stage-cost and byte-correctness results remain separate from throughput claims.

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

The earlier build-30 controls were tested with no experimental probe flags and frame tracing disabled. The automatic one-second snapshots still run. First five and final two seconds are excluded from the aggregate summaries. The scroll test polls over SSH every two seconds; native window motion collects afterward.

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

## Dedicated display setup (0.5.0, in validation)

Build 52 is signed, notarized and stapled. Its installed Host passes native self-tests and the final Viewer passes self-tests on the actual Big Sur AMD R9 M290X iMac through SSH. The helper also ran on that iMac and correctly refused unprivileged use. Native signed Host updates installed builds 50, 51 and 52 at the stable path without changing pairing. A simultaneous Host/Viewer 48→50 test stalled with Viewer still on 48 after Host updated; that run was stopped and its temporary feeds were removed, so it is not counted as a successful two-app upgrade. The 15 release/update policy tests pass. The owner authorized setup in Host. Provisioning succeeded: a new standard account `retinalinkdisplay` (UID 502), automatic login, its per-account idle policy and Viewer startup are configured. The helper’s real off/on recovery cycle passed. The original account’s idle preferences and global power settings compare byte-for-byte unchanged. FileVault remains off, unchanged. The temporary diagnostic key correctly rejects arbitrary commands and port forwarding. The UI capture helper remains off. On October 18, enabling ChatGPT’s Local Network access restored new SSH connections. The administrator’s temporary SSH session had expired overnight; a normal restart could not be requested through that session. The owner cannot restart the iMac now, so the waiting test process was stopped. Physical restart, first-login enrollment and display sleep/wake validation remain deferred and are not claimed as passed.

The temporary diagnostic SSH key cannot open a shell or forward ports. `Tools/test_dedicated_display.py` checks console account, standard-account membership, first-sign-in enrollment consumption, fullscreen pairing, idle policy, idle-sleep assertion, Viewer restart recovery, and a display-sleep/wake request. The helper’s explicit test path also exercises off/on recovery before first login. Never print or collect pending enrollment contents, `/etc/kcpassword`, the root recovery record, or account passwords.

The lock preference is configured, but this is not proof of password-free wake: `sysadminctl -screenLock status` still reports an immediate delay. Actual login/keybag and wake behavior need verification in the new account after its first automatic sign-in.


## Drag-to-Applications DMG (October 18, 2026)

`outputs/RetinaLink-0.5.0.dmg` packages the existing 0.5.0 build-52 Host, including its exact stapled Viewer archive. Neither app was rebuilt or installed by packaging. The outer DMG is Developer ID signed, accepted by Apple (submission `19ccc96d-dc35-4aa4-9724-331bd6e78578`), stapled and accepted by Gatekeeper as Notarized Developer ID. Its SHA-256 is recorded in the adjacent `.dmg.sha256` and `RetinaLink-0.5.0-DMG.json` files.

The exact final image passes filesystem checksum verification, strict/deep same-team Host signature checks, Host ticket/Gatekeeper checks, embedded Viewer digest/signature/ticket/Gatekeeper checks, and a disposable drag-copy equivalent of Host that preserves its executable, identity and ticket. Finder metadata has the expected three items, fixed icon positions, custom 1x/2x background, hidden toolbar/sidebar/status bar and `/Applications` symlink. The illustrative layout preview is rendered from our own artwork and icons, not captured from Finder; no human drag/drop or launch from a freshly downloaded/quarantined DMG was tested. Nineteen offline release/update/DMG policy tests pass, including rejection of changed submitted/final images and incomplete/rejected releases.

The DMG includes an offline Setup Guide that explicitly says Remote Login must remain enabled for the current SSH transport. Packaging does not implement the proposed app-owned connection without SSH, change the installed apps or pairing, grant permissions, enable a UI capture helper, or restart either Mac. The previously deferred dedicated-mode reboot/first-login/wake checks remain deferred.


## Native approval and direct connection (0.6.0 build 53, October 18)

Source application commit `2a9788d` builds both signed apps with the stable Developer ID team, designated requirements and `local.retinalink.device-trust` namespace. Apple accepted Viewer `904c5c78-3c71-45a3-99ae-5bdc41e43ffe` and Host `86685034-18cb-42f4-907b-a559d48fea20`; both tickets are stapled and Gatekeeper-verified, including the exact Viewer ZIP embedded in Host. The separate Host and Viewer DMGs are accepted/stapled under submissions `bca63dc5-28e8-41a9-8e51-2c9782cce067` and `e584c270-13df-48cd-a2a0-6e0f9faead29`. Artifact hashes and source provenance are in `outputs/RetinaLink-0.6.0-Release.json`.

Host self-tests and the actual AMD R9 M290X/Big Sur Viewer self-tests pass, including committed X25519 identity checks, matching authentication strings, directional authenticated encryption, tamper/reflection/replay rejection, bounded TCP setup, one-sided approval refusal and single commit. Nineteen offline release/update/DMG policy tests pass. These are implementation tests, not an independent cryptographic audit.

The actual native Host and Viewer approval controllers were run on their respective Macs in disposable UUID-isolated Keychain/preference domains. The same local button actions were invoked through explicit local-only test seams: approving Host alone left both unpaired, cancelling on Viewer created no trust, and approving both after matching the displayed numbers committed the same semantic binding and disposable credential on both Macs. Production Viewer binding, FileVault and public authorized keys remained identical. App-only interface exports show the matching numbers; no desktop capture or UI helper was used. The first attempt was denied by macOS Local Network (`Local network prohibited`); a later attempt connected without any privacy database change or bypass. An intermediate assertion incorrectly compared cross-version JSON encodings of a floating-point date; the passing test compares decoded fixture fields with a microsecond date tolerance. Neither failed attempt is counted as a passing run.

Native Sparkle updated the installed Host and original-account Viewer from 52→53. They resumed fullscreen streaming through direct authenticated TLS and the old app-owned display SSH master exited. Host/Viewer binding hashes, authorized-keys hash, FileVault, automatic-login selection, global power policy and the original account's Viewer-startup preference match the pre-update snapshot. The real Host startup agent (ordinary `--autostart` only) was restarted and reconnected; the original-account Viewer was relaunched and reconnected with its startup preference unchanged. That account's startup was deliberately disabled by the earlier dedicated-account setup, so this test does not claim Viewer launchd crash recovery there. The owner subsequently authenticated the separate protected-account app replacement. Its Viewer is now native-capable 0.6.0 build 53; the update result confirms pairing, FileVault and login settings unchanged. The root maintenance helper was removed and its sudo timestamp invalidated afterward. Physical first-login/reboot/wake checks are still deferred.

A bounded 15-second native 5K scrolling scene was measured before and after migration, with no SSH polling during motion and metadata collected afterward. In the explicitly reported 2–14-second interior window, Host/Viewer software rates averaged 59.92/59.93 updates/s with the old SSH tunnel and 58.66/58.00 with direct TLS. Complete collection windows, including startup/idle tails, are retained separately. This single short comparison does not establish stable physical 60 fps, input-to-photon latency or broad performance equivalence.

Independent SSH stayed enabled for test management and the temporary loopback update-feed forward, which was removed after updating. No system Remote Login toggle, FileVault change, logout or physical restart was performed. The UI capture helper stayed off. The previously deferred dedicated first-login/reboot/wake checks remain deferred. Standard product pairing, startup, streaming and reconnection use the app connection; optional privileged account administration still uses the legacy explicit SSH flow.


## Interrupted enrollment and idle reconnection (0.6.2 build 55, October 18)

Application source commit `6a385c3` includes the non-secret pending first-setup marker and retry logic from `9a32201`, plus TCP keepalives for idle half-open streams. Release provenance reports a dirty tree because the Python installed-update test was being improved during compilation; the runtime Swift and release resources match the recorded application commit. Apple accepted Viewer `cb313d50-d43c-41a5-a167-48f5e852e2a1` and Host `195d5b5f-ebca-4acc-b969-e1b6b58ebf3e`. Both apps and the exact embedded Viewer have validated tickets and Gatekeeper verdicts. Host self-tests, actual Big Sur/Radeon iMac Viewer self-tests and all nineteen offline release/update/DMG policy tests pass.

`work/native-link-test/pairing55-run1/result.json` passes real two-Mac cancellation, approval and interrupted-enrollment recovery with UUID-isolated Keychain/preferences. One-sided approval never creates a pair. Injecting Viewer persistence failure after Host approval leaves the Host's first binding resumable. Retry requires fresh matching numbers and local approval on both Macs, then commits the same original disposable credential and clears pending state. The authenticated Host address is cached. Production Viewer binding, authorized keys and FileVault compare unchanged. The same cases also passed on the intermediate notarized build 54. Interface exports contain only the apps' own rendered views; no desktop/UI helper capture was used.

The first installed build-54 attempt upgraded Host while Viewer stayed on 53. Its baseline check could accept stale Viewer streaming metadata, so this run was stopped and excluded. A corrected fresh-handshake check then timed out after 90 seconds: the idle old Viewer still reported streaming while the new Host had no authenticated greeting. Viewer TCP metadata showed an established connection to the terminated Host endpoint. This establishes stale liveness/recovery behavior, not an exact attribution of the missing close notification inside macOS or the company network. The old Viewer was explicitly relaunched to restore the baseline. Build 55 enables transport keepalive probes after ten idle seconds, at three-second intervals with three probes, without changing the application protocol or pairing.

`work/native-link-test/installed55/result.json` passes actual native Sparkle upgrades of Host 54→55 and original-account Viewer 53→55. One explicit baseline relaunch is recorded for the older Viewer; it is not counted as automatic recovery. After both apps updated, the normal Host startup agent was killed/restarted while idle, and Viewer reconnected without any restart/click/SSH forwarding for the display. The measured Host-recovery check took 27.68 seconds. That assertion requires new Host capture diagnostics, not only a stale Viewer phase. A separate Viewer relaunch reconnected fullscreen through direct TLS. Pairing hashes, public authorized keys, FileVault, automatic-login selection, global power policy and the original-account startup preference match before/after. Local feed preferences, server and the separate test SSH forward were removed, and Host returned to its unchanged ordinary startup agent. The original account's intentionally disabled Viewer startup remains disabled.

The protected `retinalinkdisplay` account remains on protocol-compatible native Viewer 0.6.0 build 53, installed through the owner's earlier sudo authorization. No further administrator prompt was requested. Its first graphical login, pending enrollment consumption, physical reboot and wake remain untested. Its app is not claimed to be build 55 or to have passed the new idle-recovery test. Once that account is running, signed Viewer updates can use the authenticated app connection. Public feed hosting remains unconfigured. SSH remains enabled only for independent test management; this validation did not toggle system Remote Login. FileVault remains unchanged and the UI capture helper stays off. No new stable physical 5K/60-fps or panel-latency claim follows from these setup and recovery tests.


The final Host and Viewer DMGs are signed, Apple-accepted and stapled under submissions `db4e11c5-4f5f-43ca-b67f-dfab11d08c96` and `00d2f981-9d24-4751-90e8-a61207c7cbd1`. Mounted contents, exact embedded Viewer, Finder metadata and disposable drag-copy equivalents pass the existing verifier. No human Finder drag/drop or fresh-download quarantine test is claimed. `outputs/RetinaLink-0.6.2-Release.json` records the exported digests and app provenance. A final normal-startup check after removing test feed preferences confirms both apps report update hosting unconfigured, direct fullscreen streaming resumes, no local feed server/forward or app display SSH master remains, and the UI capture helper is off (`work/native-link-test/final55-status.json`).

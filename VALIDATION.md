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

# RetinaLink

RetinaLink 0.7.0 adds automatic Ethernet discovery and selection without entering IP addresses. It uses macOS's existing automatic addresses and leaves company network settings unchanged. One-time Viewer installation, two-screen Host approval and encrypted reconnection remain: standard setup does not require Remote Login or an iMac account password. Existing pairs reuse their original Keychain credential and binding; FileVault and login settings remain unchanged. Host and Viewer have separate drag-to-Applications installers, and Host also includes an exportable signed Viewer archive.

Turn a Retina iMac into an unattended second display. Install Viewer on the iMac once, approve your main Mac, then use Host for everyday controls. Viewer stays fullscreen, shows a quiet standby screen when disconnected, and reconnects without a daily code or click. See [DIRECT_ETHERNET.md](DIRECT_ETHERNET.md) for cable connections and their validation boundaries, [NATIVE_CONNECTION.md](NATIVE_CONNECTION.md) for authentication and migration, and [AUTOMATIC_UPDATES.md](AUTOMATIC_UPDATES.md) for signed updates. Public update hosting remains unconfigured.

Host requires Apple silicon and macOS 13+. Viewer supports Intel macOS Catalina 10.15+ and Apple silicon macOS 11+. The current test receiver is a Late-2014 5K iMac on Big Sur 11.7.8 / AMD Radeon R9 M290X. One Viewer is supported at a time.

## Set up from Host

1. On the main Mac, open the Host DMG, drag **RetinaLink Host** to **Applications**, then open the installed app. Existing users should update their original permanent location to avoid duplicate copies.
2. On the iMac, drag **RetinaLink Viewer** from its DMG to **Applications** and open it once. Alternatively, use **Save Viewer Installer…** in Host and transfer that signed ZIP to the iMac.
3. Choose **Add Display** on Host and select the iMac. If discovery is unavailable, enter the iMac's local hostname or IP address. No account username, password or Remote Login is needed.
4. Compare the eight-digit verification number on **both** screens. Choose **Numbers Match — Pair** on Host and **Allow This Mac** on Viewer only if the numbers match and you initiated setup. Both approvals are required before saving trust. Existing pairings cannot be replaced through this flow.
5. Host shows FileVault's restart limitation before pairing. Choose startup after sign-in. FileVault, automatic login and screen-lock settings remain unchanged.
6. Allow Screen Recording for Host and Local Network access if macOS asks. Viewer does not need Screen Recording. Arrange the extended desktop from Host. After copying, eject both installer volumes.

An unpaired Viewer is discoverable for ten minutes. Its **Display → Make Discoverable for Setup** menu starts another setup window. Once paired, it no longer accepts network pairing requests. Neither app requires Remote Login for normal installation, pairing, streaming, startup or reconnection. Remote Login is not switched off automatically because other software or administrators may need it.

The one-time Viewer installation cannot be performed on an inaccessible Mac without an existing management service. It is the explicit local installation/approval that replaces enabling a general SSH service. Optional advanced Host-managed account creation/restoration retains its administrator-authorized SSH workflow; it is separate from standard setup. No disk creation or additional macOS installation is involved.

The existing test installs stay at `~/Applications/RetinaLink Host.app` on the Studio and `~/Applications/RetinaLink Viewer.app` on the iMac. New users can use `/Applications`. Preserve the existing path when updating.

## Everyday use

The Host display card contains **Arrange Displays**, **Identify** and **Disconnect/Connect**. Disconnect pauses the display while preserving trust. Connect resumes it without any Viewer input. Closing the paired Host’s window leaves it running in the menu bar. **Connection Details** contains diagnostics and **Forget Display**, which removes pairing on both reachable Macs and removes Viewer automatic startup. An unreachable iMac is never reported as definitely FileVault-locked: it may be asleep, offline, or waiting at a sign-in screen.

Viewer has a borderless native-resolution window. On connection loss, it replaces the previous image with a fullscreen standby screen rather than closing the window or reopening setup controls. It retries automatically. After a crash, its user login agent restarts it. Explicitly quitting normally is respected; a subsequent login starts it again if startup is enabled. Local maintenance and diagnostics are available from its application menu.

Viewer discovers its trusted Host and connects directly using the saved random TLS credential. Discovery cannot grant access: a peer must complete authenticated TLS before streaming. A verified Host address is retained as a fallback when discovery is unavailable. Updated existing pairs stop using the app-owned SSH display tunnel after the first authenticated direct connection. Their original pairing records and SSH keys are preserved, rather than silently regenerated or removed.

Host controls signed Viewer updates through the authenticated app connection. Sparkle validates the signed feed and archive, and compatible Developer ID replacements preserve pairing. Public hosting is not yet configured; supplied signed apps can be installed in the same permanent locations. The legacy management-SSH replacement path remains only for older installations and advanced maintenance.

## Automatic Ethernet

Connect a supported USB Ethernet hub to the Studio and run an ordinary Ethernet cable from the hub to the iMac's Ethernet port. Keep the Studio's existing company connection plugged in. With the usual automatic macOS network settings, RetinaLink discovers that route without a router, DHCP server or manual IP entry. It observes IPv6 link-local addresses and macOS's IPv4 link-local fallback; it does not assign addresses, enable protocols or change DNS, gateways, routes, network service order or Internet Sharing.

Viewer prefers Ethernet with only automatic addresses, then configured Ethernet, then Wi-Fi. Each discovered route retains its exact network interface. If a preferred Ethernet route appears while streaming, Viewer authenticates a separate TLS probe before reconnecting on it; an untrusted advertisement or failed probe cannot interrupt the working stream. If a route fails, retries rotate through available alternatives, with bounded attempt history and cooldowns. A handover can briefly interrupt the picture. Your saved pairing remains valid.

Connection diagnostics report **Ethernet**, **Ethernet · automatic addressing** or **Wi-Fi**. These describe the selected network path, not proof that a cable bypasses every switch. The iMac's Ethernet port is occupied by the display cable; preserving its company access may require an existing Wi-Fi connection or another Ethernet adapter. RetinaLink leaves those connections unchanged.

The physical UGREEN CM888 cable setup, operation without a DHCP server and real unplug/replug recovery remain untested until that hardware is connected. Existing Ethernet tests and software policy tests do not establish those results or stable physical 5K60. See [DIRECT_ETHERNET.md](DIRECT_ETHERNET.md) for requirements, managed-network limitations and the complete test boundary.

## FileVault and dedicated-display setup

FileVault is inspected, never changed. On older Intel iMacs, a FileVault-locked startup disk must be unlocked before Viewer or ordinary SSH can run. Login agents start **after a graphical sign-in**, not before FileVault. Selecting dedicated display mode does not bypass that requirement.

For a retired Intel iMac running Catalina or Big Sur with FileVault already off, **Dedicated Display Setup** creates a separate non-administrator `retinalinkdisplay` account from Host. After a one-time secure iMac administrator password prompt on Host, it installs the signed Viewer, enables automatic login, prepares pairing for first sign-in, disables that account’s screensaver/idle lock, and prevents idle system sleep while Viewer runs. Global power settings and other accounts’ lock settings stay unchanged. Anyone with physical access can use the display account; macOS stores a recoverable automatic-login credential. Keep personal files out of it. FileVault and company login policy are never changed; managed Macs and conflicts stop setup. Restart is offered after configuration, never forced. Manual locking or signing out still requires intervention. **Turn Off Dedicated Mode** disables automatic login and startup and enables that account’s idle lock while preserving its account and files. The generated account password is never displayed or saved by Host; an administrator can reset it for manual maintenance. Turning the mode off preserves a root-only recovery record so enabling it again does not reset the account password or its login Keychain. An administrator must authorize either change.

With FileVault on or its status unknown, the automatic-login instructions are replaced by an explanation of the boot limitation. No automatic-login, Keychain-lock or encryption settings are silently changed. A locked login Keychain is reported rather than triggering repeated background authorization dialogs.

## Pairing and installation security

New-device enrollment requires explicit local approval on both displays after comparing an eight-digit authentication string. Committed ephemeral X25519 identities are bound into the transcript; HKDF derives separate direction keys, and AES-GCM protects ordered, bounded setup messages. The credential is generated and transmitted only after both local approvals. Session expiry, attempt limits and single-use commit prevent background or replayed enrollment. Discovery alone cannot claim a device. See [NATIVE_CONNECTION.md](NATIVE_CONNECTION.md).

The random 128-bit stream credential is saved in the two login Keychains. Normal native pairing does not install an SSH key or change macOS sharing services. Existing enrolled pairs use that same credential directly: migration adds separate connection preferences without rewriting their binding or credential. The legacy restricted SSH key is kept for compatibility/advanced maintenance, and the app-owned SSH display master is closed after authenticated direct migration.

**Signing and migration:** Developer ID releases retain their bundle identifiers, signing team, designated requirements and Keychain namespace across versions. Ad-hoc development executables have hash-specific Keychain rules, so they use a separate build-specific namespace. Moving the existing development installation to Developer ID requires one final Host-led setup and may require Screen Recording approval again. Later compatible signed replacements are designed to retain trust. Signing does not bypass first-run permissions or reauthorization required by macOS policy. Apple has accepted both the Host and Viewer releases; stapled tickets and Gatekeeper acceptance are verified.

Screen Recording approval can also remain attached to an older ad-hoc executable even when System Settings shows its switch enabled. If macOS reports a code-requirement mismatch, remove the old RetinaLink Host entry and add the permanently installed app again through System Settings. The app does not reset or edit macOS's privacy database. Keep the approved executable unchanged during testing.

## Display quality and performance

The default remains native **5120 × 2880, target 60 updates/s**, bounded to three transfer credits, three drawables and normal vsynced Metal presentation. No interpolation, forced duplicates or silent downscaling is used. BC7 texture compression is lossy; native resolution does not make this a reference-colour pipeline. Audio, clipboard sync and remote input are not implemented.

The existing coalesced tile upload, write-combined staging and pending-capture retention improvements remain. The private CGVirtualDisplay API remains an OS-compatibility risk. Stable physical 5K60 across all workloads and direct-monitor-equivalent latency have not been established. See `VALIDATION.md` for the current release checks and preserved 0.2.10 timing evidence.

GPU-completed updates, capture production, API presentation timestamps and actual display intervals are different measurements. On this AMD/Big Sur receiver, zero/repeated Metal presentation timestamps can describe frames that the driver actually displayed. API timestamp rates are not physical FPS.

## Build and test

Run `bash build.sh` with full Xcode installed. Version/build defaults come from `Resources/Release.json`. `RETINALINK_BUILD_DIR` chooses the output directory; `RETINALINK_SDK` selects a compatible SDK; `RETINALINK_SIGN_IDENTITY` selects a **Developer ID Application** identity (default ad-hoc). Other certificate types are rejected for distribution. Signed builds enable Hardened Runtime and secure timestamps. `RETINALINK_BUILD_NUMBER` supports a distinct incremental build for upgrade testing. Host is arm64 and contains the universal Intel/Apple-silicon Viewer archive. The native icon is included as `Resources/AppIcon.icns`; `Tools/MakeIcon.swift` preserves its vector drawing source.

Both executables support `--self-test`. Host supports `--permission-test` for simulated permission-denial recovery. `Tools/test_display_setup.py` drives the actual Host setup controller and app-owned test controls, then reads state over SSH. It exercises enrollment, fullscreen standby, Host pause/resume, app crash recovery, login-agent startup, pairing removal/re-enrollment and tunnel repair. It does not reboot or change login/encryption policy. See `Tools/README.md` and `VALIDATION.md` for the tested boundaries.

Metadata diagnostics are bounded and saved in `~/Library/Logs/RetinaLink/Host.json` / `Viewer.json`; Viewer also writes its current appliance state to `Viewer-ui.json`. They contain no pairing secrets or captured pixels. Frame traces and UI test controls are opt-in. Interface images in validation are rendered from the app’s own view hierarchy; they do not use a UI capture bridge or capture other applications.

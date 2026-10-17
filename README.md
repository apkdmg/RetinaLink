# RetinaLink

RetinaLink 0.3.1 build 45 is Developer ID signed and notarized by Apple. Both apps have verified stapled tickets, including the Viewer bundled inside Host. The release adds pairing-preserving Viewer updates and a verified classic-Keychain dialog guard. The actual signed build-44 to build-45 installation update passes on the Mac Studio and iMac: pairing, startup settings and the existing capture grant are retained. See [RELEASING.md](RELEASING.md).

Turn a Retina iMac into an unattended second display, with setup and daily controls on the main Mac. Host installs Viewer over an authenticated SSH connection, establishes saved device trust, and manages its display connection automatically. Viewer stays fullscreen, shows a quiet standby screen when disconnected, and reconnects without a mouse, keyboard, pairing code or Connect button on the iMac.

Host requires Apple silicon and macOS 13+. Viewer supports Intel macOS Catalina 10.15+ and Apple silicon macOS 11+. The current test receiver is a Late-2014 5K iMac on Big Sur 11.7.8 / AMD Radeon R9 M290X. One Viewer is supported at a time.

## Set up from Host

1. Put **RetinaLink Host.app** in Applications and open it on the main Mac. The compatible Viewer installer is inside Host; there is no separate Viewer download to find.
2. Choose **Add Display**. Select a nearby Mac or enter the iMac’s local hostname/IP address and its account’s short username.
3. If this is a new iMac installation, enable **Remote Login** in its Sharing preferences once. RetinaLink cannot enable a remote-access service on an inaccessible Mac. All subsequent RetinaLink setup is driven from Host. Enter any requested SSH password or key passphrase in the native dialog on the main Mac; RetinaLink does not save it.
4. Setup checks macOS compatibility and FileVault before installing. Read the restart explanation and choose startup preferences. **Set Up Display** copies and verifies Viewer, saves device credentials in Keychain, installs the selected per-user login agents and starts Viewer fullscreen.
5. Allow Screen Recording for Host if macOS asks. Viewer does not need screen-capture permission. Arrange the extended desktop from **Arrange Displays** on Host.

Normal installation does not create disks, volumes, partitions or another macOS installation. It does not change FileVault, account passwords, automatic login, screen locking, SSH server settings, SIP, Gatekeeper or system trust settings. Apps are installed for the current user; no root daemon is installed.

The current stable app paths are `~/Applications/RetinaLink Host.app` on the Studio and `~/Applications/RetinaLink Viewer.app` on the iMac. Installing Host somewhere permanent avoids a login agent pointing into a temporary Downloads directory.

## Everyday use

The Host display card contains **Arrange Displays**, **Identify** and **Disconnect/Connect**. Disconnect pauses the display while preserving trust. Connect resumes it without any Viewer input. Closing the paired Host’s window leaves it running in the menu bar. **Connection Details** contains diagnostics and **Forget Display**, which removes pairing on both reachable Macs and removes Viewer automatic startup. An unreachable iMac is never reported as definitely FileVault-locked: it may be asleep, offline, or waiting at a sign-in screen.

Viewer has a borderless native-resolution window. On connection loss, it replaces the previous image with a fullscreen standby screen rather than closing the window or reopening setup controls. It retries automatically. After a crash, its user login agent restarts it. Explicitly quitting normally is respected; a subsequent login starts it again if startup is enabled. Local maintenance and diagnostics are available from its application menu.

Host owns the encrypted SSH tunnel and recreates it with a saved, restricted key when needed. There is no routine shell launcher, IP field or route selector on Viewer. The tunnel entrance is iMac loopback; the underlying image traffic still travels over the network. The legacy direct transport remains for compatibility/testing, but is not the new setup experience.

For consecutive Developer ID releases, replace Host in its permanent Applications location, then choose **Connection Details → Update Display Software…**. Host verifies the same developer team and Viewer identity, installs its bundled replacement and restarts Viewer without enrollment or new pairing keys. The owner may need to authenticate management SSH for installation; the saved restricted streaming key cannot open a shell or install software. A public automatic-download feed for Host is not configured by this release tooling.

## FileVault and dedicated-display setup

FileVault is inspected, never changed. On older Intel iMacs, a FileVault-locked startup disk must be unlocked before Viewer or ordinary SSH can run. Login agents start **after a graphical sign-in**, not before FileVault. Selecting dedicated display mode does not bypass that requirement.

For a retired iMac with FileVault already off, **Dedicated Display Guide** explains how its owner may configure automatic login for a non-administrator display account and review its sleep/lock policy. Anyone with physical access can use an automatically logged-in account, so it should hold no personal files. The guide can open the iMac’s Users & Groups preferences through SSH and open Screen Sharing on Host; the owner enters any account password into macOS itself. Company policy may prohibit this configuration.

With FileVault on or its status unknown, the automatic-login instructions are replaced by an explanation of the boot limitation. No automatic-login, Keychain-lock or encryption settings are silently changed. A locked login Keychain is reported rather than triggering repeated background authorization dialogs.

## Pairing and installation security

Enrollment uses an already authenticated SSH session. The native Host dialog asks the owner to verify a new SSH host fingerprint; changed host keys are rejected. The normal display tunnel pins the iMac’s public host key fetched through that authenticated connection. Discovery alone cannot claim a device or replace an existing owner.

Each enrollment generates a random 128-bit stream credential and a separate Ed25519 tunnel key. Persistent secrets are stored in the respective login Keychains. An owner-only temporary enrollment request is sent through SSH, consumed by a short-lived Viewer helper in the signed-in GUI session, and removed before saving trust. Pairing secrets are not placed in command arguments, diagnostics, preferences or package artifacts.

The iMac’s `authorized_keys` retains unrelated entries. RetinaLink’s marked key has a forced failing command, no PTY/agent/X11 access, and forwarding restricted to the loopback display endpoint. It cannot open a remote shell. Management operations such as installation and forgetting use the owner's separate authenticated SSH session. Replacing another Host’s binding requires an explicit replacement choice.

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

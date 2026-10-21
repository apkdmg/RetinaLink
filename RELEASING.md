# Developer ID releases

**[0.8.8 build 76](https://github.com/apkdmg/RetinaLink/releases/tag/v0.8.8) is public** with notarized Host PKG and Viewer DMG, signed updates on the existing feeds, and matching GPLv3 source. It adds adaptive reversible BC7 packing and fixes physical Viewer-session detection when a separate remote login owns `/dev/console`. Clean application source: `b2f00bd0f4bf8bde1bf6a9314e29ba03ba5f7147`. Final signed-app checks, the actual Big Sur/Radeon Viewer self-tests, all 124 offline policy tests, and public download/signature verification pass. The same application source in installed test build 75 improved full-screen 5K delivery from 25.51 to 35.27 updates/s with about 27.69% fewer bytes per frame; desktop scenes stayed near 60. These are GPU-completion acknowledgements, not physical panel FPS. Installed apps were not replaced for publication. See [VALIDATION.md](VALIDATION.md).

**[0.8.6 build 73](https://github.com/apkdmg/RetinaLink/releases/tag/v0.8.6) is public** with notarized Host PKG and Viewer DMG, signed updates on the existing feeds, and matching GPLv3 source. It adds bounded quick retry, healthy-route preservation, temporary closed-port recovery and stale-capture-error protection. Clean app source: `9d5f688cecf8b9a3969161a559e41e80b1b42c02`. Signed TLS listener-restart tests and pairing/update/removal regressions pass. Physical lock/unlock timing and a fresh Big Sur SSH run are not verified. No installed app was manually replaced; the owner is testing Update Now. See [VALIDATION.md](VALIDATION.md).

**[0.8.5 build 71](https://github.com/apkdmg/RetinaLink/releases/tag/v0.8.5) is public** with notarized Host PKG and Viewer DMG, signed updates on the existing feeds, and matching GPLv3 source. It supports Host-only display removal and re-adding, including Dedicated Display Mode, while preserving approval and login settings. Clean application source: `34bc25324d56d6f8bd26e1991c673c44e6a4f062`. Final signed-app regressions, Big Sur SSH compatibility checks and public signatures pass. The installed pair was left unchanged for the owner to update through Host; this publication did not repeat an installed upgrade or OS reboot. See [VALIDATION.md](VALIDATION.md).

The preceding public release, **0.8.4 build 70**, shipped with a notarized Host PKG and universal Viewer DMG, signed update archives and feeds, and matching GPLv3 source. It keeps one saved iMac across logins, with simple reconnect approval and retained trust for previously approved Viewers. It preserves FileVault and Dedicated Display configuration. The clean application source is `e12249a9163ba80ec8961a2bb87f522b7642fafb`. Validation includes signed native protocol and encrypted reconnection tests, protected standard-login SSH tests of the feature, and final signed Viewer tests on Big Sur. Actual macOS logout/login switching was not exercised. See [VALIDATION.md](VALIDATION.md) for publication evidence and limits.

The previous public release, **0.8.3 build 67**, added Host-delivered Viewer updates: after both apps support this feature, only Host needs internet. Viewer 0.8.2 and earlier need one initial upgrade using their own internet or a signed replacement at the existing path. Its clean application source is `7bb332a164d9287f8ea098cd1ad7a6f92c1c9e0e`. See [VALIDATION.md](VALIDATION.md) for its publication checks and live tests.

The **0.8.1 build 61** bootstrap configures public signed updates for `apkdmg/RetinaLink` and packages the GNU GPLv3 license and third-party notices. The feed base is `https://apkdmg.github.io/RetinaLink/updates`; update ZIPs use flat, versioned GitHub Release asset URLs. Existing 0.8.0 apps need one compatible signed replacement to acquire the public feed URL, retaining their existing pairing. Build, notarization and publication results are recorded in [VALIDATION.md](VALIDATION.md); changing source configuration alone does not activate hosting or old installations.

The preceding **0.8.0 build 60** apps and separate installers are Developer ID signed, Apple-accepted and stapled. Their USB cable negotiated USB 2.0 High Speed (480 Mbps); SuperSpeed and stable 5K60 remain unvalidated. Version 0.8.1 retains that display implementation. Dedicated-account automatic login, real reboot and sleep/wake recovery passed during earlier testing on the same iMac. See [DIRECT_ETHERNET.md](DIRECT_ETHERNET.md) and [NATIVE_CONNECTION.md](NATIVE_CONNECTION.md) for the unchanged connection and authentication boundaries.

## Build the native Host installer

Use the completed, accepted release without rebuilding or re-signing either app. The Keychain must contain a **Developer ID Installer** identity from the same team as Host; an Application certificate cannot sign a PKG.

```sh
python3 Tools/package_pkg.py prepare \
  --release work/release-0.8.0-build60 --directory work/pkg-0.8.0-build60
python3 Tools/package_pkg.py advance \
  --directory work/pkg-0.8.0-build60 --output outputs/RetinaLink-Host-0.8.0.pkg
```

Repeat `advance` after exit code 3 while Apple processes the saved submission. Once accepted, the tool staples the ticket, checks Gatekeeper's **install** policy, expands the package and verifies every app path, file, mode and internal symlink against the accepted release. It also verifies the bundled Viewer archive and app ticket. `verify` rechecks the immutable final digest before exporting. A SHA-256 sidecar accompanies the output. No app is installed, launched or published by these commands.

The accepted USB release comes from `work/release-0.8.0-build60`. Its finished, stapled Host package is `outputs/RetinaLink-Host-0.8.0.pkg`; Apple accepted package submission `2c3e3d9e-c5ab-4149-8da6-57f75ed986bd`. The package retains the accepted apps and their existing signing identities, bundle identifiers and pairing namespace. The native Installer's document-sharing policy checks and actual delivery/recipient-OS tests remain distinct from notarization acceptance.

The native Installer has welcome, preparation and completion screens. Its only payload is `/Applications/RetinaLink Host.app`; its component uses strict bundle identifiers, version checking and atomic upgrade, with relocation disabled. No preinstall/postinstall scripts, remote packages, automatic app launch, privacy resets or quarantine-removal commands are included. It does not find or replace an existing copy in `~/Applications`; existing users must retain their permanent installation path. Preferences and pairing remain outside the payload.

Use this PKG for WhatsApp sharing instead of the drag-copy Host DMG. Signing and notarization alone do not establish downloader compatibility: the distribution test must apply the reproduced sandbox quarantine flag to a disposable copy, confirm Gatekeeper's install decision and open that copy in native Installer. Keep a separate boundary for actual WhatsApp delivery and the recipient OS. A ZIP of the app preserves the blocking flag and is not a workaround. [Apple DTS describes this quarantine failure](https://developer.apple.com/forums/thread/767612), and [Apple's packaging guidance](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution) describes the normal Developer ID Installer workflow. Test evidence is recorded in [VALIDATION.md](VALIDATION.md).

## Build the consumer DMG

The standalone Viewer 0.8.0 build 60 DMG is exported to `outputs/RetinaLink-Viewer-0.8.0.dmg`. Apple accepted submission `2390d76a-48f3-4dcb-a1b6-9ab63e470975`; its outer ticket and the unchanged Viewer ticket are stapled and Gatekeeper-accepted. Mounted contents, Finder layout, Applications shortcut and a disposable drag-copy equivalent passed verification. No installed app or pairing was changed by packaging.

After `release.py advance` has completed both app tickets and embedded the stapled Viewer, package those exact binaries:

```sh
python3 -m venv work/dmg-tools
work/dmg-tools/bin/python -m pip install -r Tools/dmg-requirements.txt
work/dmg-tools/bin/python Tools/package_dmg.py prepare \
  --release work/release-0.6.2-build55 --directory work/dmg-0.6.2-build55
work/dmg-tools/bin/python Tools/package_dmg.py advance \
  --directory work/dmg-0.6.2-build55 --output outputs/RetinaLink-0.6.2.dmg
work/dmg-tools/bin/python Tools/package_dmg.py prepare --role Viewer \
  --release work/release-0.8.0-build60 --directory work/dmg-0.8.0-build60-viewer
work/dmg-tools/bin/python Tools/package_dmg.py advance \
  --directory work/dmg-0.8.0-build60-viewer --output outputs/RetinaLink-Viewer-0.8.0.dmg
```

`advance` submits once, then returns exit code 3 while Apple processes the DMG. Repeat that command later to check the saved submission; it never rebuilds a submitted image. Upon acceptance it staples and validates the DMG ticket, checks Gatekeeper, verifies the mounted Host and embedded Viewer, checks Finder layout and the Applications symlink, and verifies a disposable copy of Host. The source app signatures, identifiers, pairing namespace and embedded Viewer archive are unchanged. Nothing is installed or launched. Each image includes the offline no-SSH Setup Guide and the unchanged FileVault/restart limitations. The standard flow uses a one-time local Viewer installation; advanced dedicated-account administration remains separate.

`Tools/MakeInstallerArtwork.swift` renders the 1x/2x background and an illustrative layout preview from our own assets. `dmgbuild` writes Finder metadata without Finder automation or a UI capture helper. The preview is a layout rendering, not a screenshot of Finder. Use a fresh `--directory` for a changed design; never overwrite a signed/submitted release. `verify` checks the final digest, signature, staple and Gatekeeper verdict and can export the identical completed image. Artwork and copy-only changes do not require rebuilding or updating the installed apps. Public update feeds still use role-specific ZIP archives, not this DMG.

The previous update-validation release is **0.4.0 build 48**, signed by team ZPCS5VQL89 and notarized with all Sparkle installer/XPC helpers. The actual automatic build-46 to build-48 update passes on both Macs without re-pairing or another Screen Recording approval. Host owns the update toggle and Update Now action; Viewer stays unattended. Public update hosting was unconfigured during that historical test; it is configured from 0.8.1 onward. See [AUTOMATIC_UPDATES.md](AUTOMATIC_UPDATES.md) for signed-feed publication.

A valid **Developer ID Application** identity is installed for team ZPCS5VQL89. Real signed builds 44 and 45 pass Host and actual iMac self-tests. Build 45 adds the classic-Keychain silent-access guard. Apple has accepted both apps in both builds. Tickets are stapled and validated, Gatekeeper reports Notarized Developer ID, and the exact bundled Viewer ticket survives extraction. The actual build-44 to build-45 Host/Viewer update passes, including retained pairing, native startup and Viewer crash recovery without another Screen Recording approval.

## Developer setup, once

1. In **Xcode → Settings → Accounts → your team → Manage Certificates**, create or import **Developer ID Application**, including its private key. Creating a local Developer ID certificate requires the team's Account Holder; organizations may need their account administrator. This command-line pipeline requires a locally usable identity. Do not revoke existing certificates or change system trust settings.
2. In your own Terminal, run `python3 Tools/release.py credentials`, or run `bash 'Tools/Set Up Notarization.command'`. Enter your Developer Apple ID, then an **app-specific password** into Apple's hidden prompt. Apple's `notarytool` validates and stores it in Keychain under profile `RetinaLink-Notary`; Python never reads it. Do not put passwords in chat, command arguments, environment variables or repository files. Existing App Store Connect API-key users can configure that profile directly with `notarytool store-credentials` instead. The helper writes `work/notary-credentials-status.json` with the current step and exit code only, without Apple ID, password, command arguments or interactive output. On failure, Apple's actual error remains in your Terminal; the generic “SETUP FAILED” footer does not identify the cause. A ready marker is written only after the saved profile authenticates successfully.
3. Run `python3 Tools/release.py doctor`. If multiple identities exist, select one with `--identity 'Developer ID Application: YOUR NAME (TEAMID)'`. The private signing key stays in Keychain.

## Build and notarize

```sh
python3 Tools/release.py prepare --directory work/release-0.4.0-build48
python3 Tools/release.py advance --directory work/release-0.4.0-build48
```

`prepare` builds in isolation with Developer ID, Hardened Runtime and secure timestamps. It verifies both apps against Apple's Developer ID chain, the selected team and their expected bundle identifiers. Stable default designated requirements are retained; no build/certificate hash is pinned. Debugger access is rejected and no hardened-runtime exceptions are added. Other signing certificate types cannot create a distribution build.

`advance` submits Viewer first. Exit **3** means processing is pending or a submission has just been created; run it again after a reasonable wait. Submission IDs, archive hashes and progress persist in `release-state.json`. Resume that directory; do not rebuild an in-flight release. Authentication errors return 1. Apple rejections save their log and produce no final distribution.

After Viewer is accepted, the tool staples its ticket, validates it and checks Gatekeeper. It embeds the stapled Viewer ZIP into Host, re-signs Host, then submits Host. Once Host is accepted, its ticket is stapled and validated. The tool extracts the **exact bundled Viewer ZIP** and verifies its ticket, signature and executable hash again before creating a Host-only distribution ZIP. ZIP containers cannot themselves be stapled; their app tickets must be inside them. Re-running a completed release does not regenerate its archive.

Output: `work/release-0.4.0-build48/RetinaLink-0.4.0.zip`. Its SHA-256, accepted submission IDs, source commit and dirty-tree status are recorded in `release-state.json`. Commit source before a public release. These tools submit compiled software to Apple; they do not publish it or replace either installed app.

## Preserve trust across updates

Retain bundle identifiers `local.retinalink.Host` / `local.retinalink.Viewer`, the same Developer ID team, compatible designated requirements, Keychain namespace `local.retinalink.device-trust`, existing role-specific account names, preference keys and permanent installation paths. A renewed certificate within the same team need not change identity. Changing teams/channels requires a separate migration.

Replace Host in its permanent Applications location, then choose **Connection Details → Update Display Software…**. This path verifies Host's signature, checks that the existing Viewer is from the same developer and is bound to this Host, validates the incoming replacement before stopping the old one, installs it and restarts it with the existing startup preference. It never enrolls again, generates or exports credentials, edits `authorized_keys`, changes FileVault or enables automatic login. Management SSH can ask the owner to authenticate; the streaming key remains restricted to forwarding. Version 0.8.1 pins the public GitHub Pages feeds. The manual Viewer-update action remains available for bootstrap and recovery; older apps without a feed cannot discover the bootstrap simply because it was published.

The existing ad-hoc installation requires a **one-time transition**: complete Host-led Display Setup with the first signed release and approve its Screen Recording permission if macOS requires it. Signed code intentionally cannot silently read the old hash-specific Keychain item. Subsequent compatible signed releases are designed to retain pairing and identity-based approval. First-run prompts and periodic macOS reauthorization remain controlled by the OS; notarization is not a permission bypass.

## Validation status

Current USB release: **0.8.0 build 60**, accepted app release `work/release-0.8.0-build60` and stapled Host package `outputs/RetinaLink-Host-0.8.0.pkg`. The package acceptance ID is recorded above. USB topology detection is read-only and route changes retain the saved TLS pairing. See [VALIDATION.md](VALIDATION.md) for live USB results and preservation checks; the following paragraphs retain historical release evidence.

Previous Ethernet release: **0.7.0 build 59**, runtime commit `643b2d0`. Both installed active apps passed signed 58→59 update and SSH recovery testing with unchanged pairing, FileVault and company configuration. Host, universal Viewer, bundled Viewer archive and separate Host/Viewer DMGs are Apple-accepted, stapled and Gatekeeper-verified. Final artifacts and hashes are in `outputs/RetinaLink-0.7.0-Release.json`. The dirty-tree flag reflects an unrelated pre-existing untracked review file; runtime source and release resources match the recorded commit. Dedicated-account restart/wake testing subsequently passed; physical direct-Ethernet-cable testing was still pending for that release. See [VALIDATION.md](VALIDATION.md).

Actual Developer ID build-44/build-45 Host and AMD iMac Viewer self-tests, simulated capture-denial recovery and fifteen offline release-policy tests pass. A native Launch Services probe verifies two different signed binaries with the real Host designated requirement can share a temporary test item silently, while an ad-hoc clone is denied when the classic-Keychain interaction guard is applied. All temporary items were removed; production credentials were never accessed by that probe. The iMac correctly rejects the ad-hoc test app against the Developer ID requirement. The tests cover wrong-team/Host/namespace rejection, changed upload detection, resume without duplicate submission, rejection/Gatekeeper failure and Viewer-ticket-before-Host-signing order. Apple acceptance is separately recorded in the release states; these self-tests are not evidence of a signed-to-signed installation update.

The notarized updater bootstrap is `work/release-0.4.0-build46`, and the final notarized release is `work/release-0.4.0-build48` (clean application source commit `9ea2427`). The final distribution is copied unchanged to `outputs/RetinaLink-0.4.0.zip`, SHA-256 `5fbe9c70c1e250de4432d60d4a596f1ec5312364f07da3792ae18ae03747c44a`. Host and Viewer both have validated stapled tickets, including the exact Viewer archive embedded in Host. All Sparkle executables carry this developer's Hardened Runtime signatures and secure timestamps.

The signed 45→46 bootstrap and actual automatic 46→48 installation pass on the Studio and Radeon Big Sur iMac. Both roles respect opt-out and reject tampered feed and archive signatures while keeping their existing installation. The valid update installs and reconnects fullscreen without enrollment, changed binding/public authorized keys, or another capture approval. Both apps return to their actual startup agents and recover after simulated crashes. FileVault and login settings stay unchanged; the UI capture helper stays off. Local test preferences, server and forwarding are removed afterward. Fifteen offline policy tests and native Host/iMac self-tests pass. Physical logout/reboot is not tested.

Public hosting was deliberately deferred during the 0.4.0 tests. That historical configuration had no public URL and performed no production update checks; current releases pin the public feeds described above. See [AUTOMATIC_UPDATES.md](AUTOMATIC_UPDATES.md) for the production HTTPS feed configuration, publisher command and real integration test. The tools generate signed feeds and archives but never upload them automatically.

## Apple references

- [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), including custom installers and ticket stapling.
- [TN3127: Inside Code Signing — Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements), including privacy and Keychain identity across updates.

The Host also contains `RetinaLinkDedicatedSetup`, an Intel Catalina/Big Sur OpenDirectory helper signed with the same Developer ID and identifier `local.retinalink.DedicatedSetup`. It runs only over authenticated SSH after an explicit administrator password prompt, with request data on stdin. No root daemon or setuid installation is used. Its account password never travels to Host. On the iMac, the legacy automatic-login material and recovery record are root-only; automatic login inherently permits physical access. The optional diagnostic key is restricted to fixed non-secret test actions and must be removed after validation.

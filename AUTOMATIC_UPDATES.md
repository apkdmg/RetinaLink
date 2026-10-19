# Automatic Host and Viewer updates

Host owns the everyday controls: **Automatically keep both Macs up to date** and **Update Now…**. The preference is sent to the saved Viewer over the authenticated display connection and resynchronized after reconnection. Viewer never needs a mouse, keyboard or update dialog. An offline or rejected update keeps the existing installation and pairing; Host shows the Viewer status.

**Version 0.8.3 adds Host-delivered Viewer updates.** When both apps support the relay, only Host needs internet access: it downloads the signed Viewer feed and archive and sends the exact bytes through the existing authenticated display connection, including USB and Ethernet routes. Viewer still performs Sparkle's signed-feed and archive verification and installs into its existing application path. Releases through 0.8.2 use independent internet downloads; its Viewer needs one normal signed replacement with a relay-capable release before this feature can work. Older peers negotiate their existing update behavior, rather than receiving unknown relay messages. Hardware validation is recorded separately from publication evidence in [VALIDATION.md](VALIDATION.md).

Automatic checking and installation default to enabled, with a daily check interval. A verified update restarts the affected app, which reconnects using the existing pairing. Relaunched apps return to their existing startup agents so later crashes still recover. Update checks do not enroll, rotate the stream/tunnel keys, edit SSH authorization, change FileVault, enable automatic login, reset Screen Recording, or start the UI capture helper.

Earlier 0.3.x releases needed one normal signed software replacement to acquire the updater. That bootstrap used the existing **Update Display Software…** path and preserved pairing. Once an updater-enabled production release has a configured public feed, later compatible signed feed updates do not require another manual installation. macOS can still require first-run or periodic permission reauthorization.

## Signing and compatibility

Sparkle **2.9.6** is pinned to its official archive and SHA-256 in `Resources/Updates.json`. Its framework and installer/XPC tools support the older Viewer OS and are re-signed inside out with RetinaLink's Developer ID, Hardened Runtime and secure timestamps. The release verifier checks all those signatures. Sparkle 2.10 requires Monterey; it is unsuitable for the Big Sur iMac.

Both appcasts and update archives require Ed25519 signatures. Archives are verified before extraction. Signed-feed failures never expire into unsigned acceptance. The public key is embedded in each signed app; its private key stays in the developer's login Keychain under Sparkle account **RetinaLink-Updates**. No private update or pairing keys are included in builds, feeds, logs or Git. System profiling is disabled.

Keep the same bundle identifiers, signing team, designated requirements, Keychain namespace and installation paths. The app's updater does not weaken Keychain ACLs or privacy settings.

## Updates through the display connection

Viewer advertises relay version 1 in its optional greeting capability. Only a paired, authenticated connection can exchange relay packets. Host derives the Viewer feed from its own signed configuration and permits only Viewer ZIPs from the versioned `apkdmg/RetinaLink` GitHub releases. It refuses arbitrary URLs, Host archives, credentials in URLs and redirects to private or unrelated origins. Explicit developer loopback fixtures remain limited to the existing local test configuration.

Transfer uses pull-based 64 KiB chunks, a single active resource and exact offset/length checks. Feed and archive limits are 1 MiB and 64 MiB. Host enforces download limits while receiving, and both peers stage bytes in private temporary files. Disconnects cancel the transfer and remove partial files; installation begins only after Sparkle has received and verified the complete archive. A manual update request survives reconnection and can retry without re-pairing.

Viewer exposes only a token-protected HTTP server bound to `127.0.0.1` for Sparkle's local download route. Neither the signed feed nor its enclosure signatures are rewritten. The documented Sparkle feed/download delegates route these requests locally; release-note network downloads are disabled. This does not open a LAN update port, share internet, change the company network or require SSH. Pairing and FileVault settings remain outside the update protocol.

Host reports downloading, transfer, verification and installation separately. It retains the expected Viewer build across reconnection, and marks an installation complete only after that build (or a later one) confirms a rendered fullscreen display. A busy updater queues an explicit Update Now request instead of silently discarding it. For relay-capable Viewers, a manual update on Host itself waits for the Viewer result, avoiding an unnecessary interruption of the transfer.

## GitHub hosting

The public repository is configured as `apkdmg/RetinaLink`. Version 0.8.1 introduced these pinned public feeds. Release **0.8.3 build 66** uses the same addresses and signing key:

- Host: `https://apkdmg.github.io/RetinaLink/updates/host/appcast.xml`
- Viewer: `https://apkdmg.github.io/RetinaLink/updates/viewer/appcast.xml`

GitHub Pages serves only the signed XML and the `.nojekyll` marker. Versioned GitHub Releases serve the notarized role-specific ZIP archives, Host PKG, Viewer DMG and matching corresponding source archive. Release v0.8.2 is public: anonymous downloads of its six assets and both feeds match their planned hashes, and the signed feeds and update archives verify. Installed 0.8.1 apps can acquire build 62 using **Update Now…**; each app restarts and reuses saved pairing. That older update path needs outbound HTTPS from both Macs. With 0.8.3 on both ends, only Host needs outbound HTTPS; Viewer uses the authenticated display connection. The checks and installed-version boundary are recorded in [VALIDATION.md](VALIDATION.md).

The public Viewer 0.8.1/build 61 → 0.8.2/build 62 update was exercised on the dedicated Big Sur iMac with Studio Host 0.8.2. Host's Update Now action triggered the real signed download and installation; Viewer relaunched and reconnected fullscreen without re-pairing or local interaction. Pairing, startup, login/power settings, FileVault and network configuration were preserved. This test covers the Viewer update with Host already at 0.8.2, rather than simultaneous installation on both Macs. See [the hardware-test record](VALIDATION.md#public-viewer-update-verified-on-the-dedicated-imac--19-october-2026).

**Releases through 0.8.0 have no public feed address.** They require one normal signed replacement on both Macs to acquire this configuration. Publishing a feed cannot activate those old binaries remotely. Keep their existing application paths, bundle identifiers, Developer ID team and pairing; do not enroll them again. After the bootstrap, compatible signed updates use the public feeds.

Signing and notarization happen on the developer's Mac using the existing Keychain identities. GitHub does not receive Developer ID private keys, update-signing keys, notarization passwords or pairing credentials. Network peers cannot replace the pinned public feed address. The repository and corresponding source are GNU GPLv3; the release preserves Sparkle's own notices.

```sh
python3 Tools/release.py prepare --directory work/release-0.8.3-build66
python3 Tools/release.py advance --directory work/release-0.8.3-build66
# Repeat advance after Apple processing, until complete.
python3 Tools/release.py update-feed --directory work/release-0.8.3-build66 \
  --updates-directory outputs/github-updates-0.8.3 \
  --archive-base-url https://github.com/apkdmg/RetinaLink/releases/download/v0.8.3
```

The last command creates `host/appcast.xml`, `viewer/appcast.xml` and separate notarized ZIPs for each role, signed with the Keychain update key. `--archive-base-url` supplies the flat versioned release-asset prefix before the appcast is signed; XML must never be rewritten afterward. It does not upload or publish. The normal same-origin role-directory layout remains available when the override is absent, including local tests.

Publish and verify every release asset before updating the public feeds. Existing public versioned assets must not be overwritten. The publisher retains exact signed XML bytes, publishes only the feeds and `.nojekyll` marker on `gh-pages`, and excludes local `.release-records.json` bookkeeping. Feed and archive origins are pinned in staging records; changing either destination or an existing archive requires a fresh staging directory or a new build. Bump the build number for every release. Public Git pushes must name the intended branch or tag explicitly; never mirror local testing or Codex metadata refs.

## Publish a reviewed release

Commit the release configuration and build from a clean checkout of that exact source commit. Do not include local logs, credentials, testing refs or unrelated untracked files. The publisher requires the release's recorded clean commit to be on the public repository first; it will not move an existing tag or replace a published asset. Build and notarize the Host PKG and Viewer DMG from those completed apps using [RELEASING.md](RELEASING.md).

Generate the GPL corresponding-source archive from the same full commit SHA. It includes the committed project and the complete hash-verified Sparkle source, including its vendored dependencies; see [SOURCE_BUILD.md](SOURCE_BUILD.md). No working-tree files or Git history enter that archive.

```sh
python3 Tools/source_archive.py --commit FULL_SOURCE_COMMIT \
  --output outputs/RetinaLink-0.8.3-source.tar.gz \
  --manifest work/github-publication-0.8.3/source-manifest.json
python3 Tools/publish_github.py plan \
  --directory work/release-0.8.3-build66 \
  --feeds outputs/github-updates-0.8.3 \
  --source-archive outputs/RetinaLink-0.8.3-source.tar.gz \
  --source-manifest work/github-publication-0.8.3/source-manifest.json \
  --asset outputs/RetinaLink-Host-0.8.3.pkg \
  --asset outputs/RetinaLink-Viewer-0.8.3.dmg \
  --plan work/github-publication-0.8.3/plan.json
python3 Tools/publish_github.py publish \
  --plan work/github-publication-0.8.3/plan.json --gh /absolute/path/to/gh
python3 Tools/publish_github.py verify \
  --plan work/github-publication-0.8.3/plan.json
```

`plan` is local and records the exact source, signatures, URLs and SHA-256 digests. `publish` uses the authenticated GitHub CLI to resume or create a draft release, downloads every uploaded asset to verify its bytes, publishes the complete release, then deploys only the two signed feeds on `gh-pages`. It checks the existing Pages configuration and rejects older or conflicting feeds before publishing. Git pushes name only the intended tag or Pages branch and disable automatic following of other tags. The current source checkout and unrelated files are never checked out or rewritten for Pages.

The final verification downloads the public feeds and assets without account credentials and compares their complete bytes to the plan. Exit code 3 means GitHub Pages may still be deploying; wait briefly and run `verify` again. Do not report public updates as live until verification returns 0. Never upload the local plan, source-manifest sidecar or `.release-records.json`; they are private publisher bookkeeping. The source archive contains its own portable manifest without local paths.

## Native local integration test

`Tools/test_automatic_updates.py` exercises the real Sparkle updater on both Macs. It serves signed feeds only on Studio loopback, forwards the same loopback port over the existing authenticated management SSH session, and controls Host through its explicit local test command seam. It reads bounded metadata and public-key-file hashes, never pairing secrets or screen pixels.

The test covers opt-out, invalid feed signatures, invalid archive signatures, automatic installation of both roles, retained binding and public authorized-key hashes, native startup/crash recovery and unchanged login/FileVault settings. Temporary test-feed preferences, loopback forwarding and the server are removed at the end. The normal startup agents retain only `--autostart` / `--appliance`.

```sh
python3 Tools/release.py update-feed --directory work/release-0.4.0-build48 \
  --updates-directory work/auto-update-service \
  --update-base-url http://127.0.0.1:58475 --local-test
python3 Tools/test_automatic_updates.py \
  --feed-directory work/auto-update-service --output work/automatic-update-46-to-48 \
  --socket work/imac-ssh-session/control --address 10.28.114.22 --user opsounimas \
  --from-build 46 --to-build 48
```

The bootstrap must already be streaming and both builds must be notarized. The local test origin is restricted to a literal loopback IP with an explicit port, no credentials, path, query or fragment. It never relaxes the public HTTPS policy or signature requirements. Tests do not reboot, unlock FileVault, change login policy, or use a UI capture helper.

## Verified on the actual Macs

The signed 0.3.1 build-45 to 0.4.0 build-46 bootstrap passes without pairing or capture reapproval. The actual automatic build-46 to build-48 update then passes on Host and the Radeon Big Sur Viewer. Both roles reject modified signed XML and corrupted archive bytes, respect opt-out, install the valid update and reconnect fullscreen. Host/Viewer binding hashes and the public authorized_keys file hash stay unchanged. Both updated apps recover after simulated crashes through their startup agents. FileVault/login settings and the UI capture helper remain unchanged/off. All local test preferences, forwarding and the test server are removed afterward. No physical reboot is performed.

Evidence: `work/automatic-update-46-to-48/result.json`, its before/after metadata, failure status files and timing-only request log; `work/signed-bootstrap-45-to-46/result.json`; `work/auto-update-46-imac-self-tests.txt`; final notarization state in `work/release-0.4.0-build48/release-state.json`. All 15 offline policy tests pass. The developer approved the official `generate_appcast` and `sign_update` tools once in macOS Keychain; no private key was exported.

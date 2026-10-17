# Automatic Host and Viewer updates

Host owns the everyday controls: **Automatically keep both Macs up to date** and **Update Now…**. The preference is sent to the saved Viewer over the authenticated display connection and resynchronized after reconnection. Viewer never needs a mouse, keyboard or update dialog. Both apps download independently from their role's release feed. An offline or rejected update keeps the existing installation and pairing; Host shows the Viewer status.

Automatic checking and installation default to enabled, with a daily check interval. A verified update restarts the affected app, which reconnects using the existing pairing. Relaunched apps return to their existing startup agents so later crashes still recover. Update checks do not enroll, rotate the stream/tunnel keys, edit SSH authorization, change FileVault, enable automatic login, reset Screen Recording, or start the UI capture helper.

The installed 0.3.x releases need one normal signed software replacement to acquire the updater. This bootstrap uses the existing **Update Display Software…** path and preserves pairing. Once an updater-enabled production release is installed, later signed feed updates do not require another manual installation. macOS can still require first-run or periodic permission reauthorization.

## Signing and compatibility

Sparkle **2.9.6** is pinned to its official archive and SHA-256 in `Resources/Updates.json`. Its framework and installer/XPC tools support the older Viewer OS and are re-signed inside out with RetinaLink's Developer ID, Hardened Runtime and secure timestamps. The release verifier checks all those signatures. Sparkle 2.10 requires Monterey; it is unsuitable for the Big Sur iMac.

Both appcasts and update archives require Ed25519 signatures. Archives are verified before extraction. Signed-feed failures never expire into unsigned acceptance. The public key is embedded in each signed app; its private key stays in the developer's login Keychain under Sparkle account **RetinaLink-Updates**. No private update or pairing keys are included in builds, feeds, logs or Git. System profiling is disabled.

Keep the same bundle identifiers, signing team, designated requirements, Keychain namespace and installation paths. The app's updater does not weaken Keychain ACLs or privacy settings.

## Public hosting is deliberately unconfigured

The owner chose to test locally before selecting hosting. `Resources/Updates.json` therefore has `baseURL: null`. A normal launch reports that release hosting is not configured and starts no updater network checks. There is no invented public endpoint. Both Macs will need HTTPS access to the chosen update service.

When hosting is selected, set `baseURL` to a stable HTTPS prefix you control, for example `https://YOUR-DOMAIN/retinalink`. Build and notarize the first production release with that value before giving it to users. The signed app pins its role-specific feed URL; network peers cannot replace it with an arbitrary public URL.

```sh
python3 Tools/release.py prepare --directory work/NEW-RELEASE
python3 Tools/release.py advance --directory work/NEW-RELEASE
# Repeat advance after Apple processing, until complete.
python3 Tools/release.py update-feed --directory work/NEW-RELEASE \
  --updates-directory outputs/updates
```

The last command creates `host/appcast.xml`, `viewer/appcast.xml` and separate notarized ZIPs for each role, signed with the Keychain update key. It does not upload or publish. Upload each role's archives before its appcast, preserve the signed XML bytes, and retain immutable versioned archive URLs. Publish only appcasts and archives; local `.release-records.json` files are publisher bookkeeping. Reusing a staging directory with a different server URL or changed archive is rejected. Bump the build number for every release.

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

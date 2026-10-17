# Developer ID releases

A valid **Developer ID Application** identity is installed for team ZPCS5VQL89. Real signed builds 44 and 45 pass Host and actual iMac self-tests. Build 45 adds the classic-Keychain silent-access guard. The notarization login and Apple acceptance remain pending; the working installed apps remain 0.3.0 build 43.

## Developer setup, once

1. In **Xcode → Settings → Accounts → your team → Manage Certificates**, create or import **Developer ID Application**, including its private key. Creating a local Developer ID certificate requires the team's Account Holder; organizations may need their account administrator. This command-line pipeline requires a locally usable identity. Do not revoke existing certificates or change system trust settings.
2. In your own Terminal, run `python3 Tools/release.py credentials`, or run `bash 'Tools/Set Up Notarization.command'`. Enter your Developer Apple ID, then an **app-specific password** into Apple's hidden prompt. Apple's `notarytool` validates and stores it in Keychain under profile `RetinaLink-Notary`; Python never reads it. Do not put passwords in chat, command arguments, environment variables or repository files. Existing App Store Connect API-key users can configure that profile directly with `notarytool store-credentials` instead.
3. Run `python3 Tools/release.py doctor`. If multiple identities exist, select one with `--identity 'Developer ID Application: YOUR NAME (TEAMID)'`. The private signing key stays in Keychain.

## Build and notarize

```sh
python3 Tools/release.py prepare --directory work/release-0.3.1-build45
python3 Tools/release.py advance --directory work/release-0.3.1-build45
```

`prepare` builds in isolation with Developer ID, Hardened Runtime and secure timestamps. It verifies both apps against Apple's Developer ID chain, the selected team and their expected bundle identifiers. Stable default designated requirements are retained; no build/certificate hash is pinned. Debugger access is rejected and no hardened-runtime exceptions are added. Other signing certificate types cannot create a distribution build.

`advance` submits Viewer first. Exit **3** means processing is pending or a submission has just been created; run it again after a reasonable wait. Submission IDs, archive hashes and progress persist in `release-state.json`. Resume that directory; do not rebuild an in-flight release. Authentication errors return 1. Apple rejections save their log and produce no final distribution.

After Viewer is accepted, the tool staples its ticket, validates it and checks Gatekeeper. It embeds the stapled Viewer ZIP into Host, re-signs Host, then submits Host. Once Host is accepted, its ticket is stapled and validated. The tool extracts the **exact bundled Viewer ZIP** and verifies its ticket, signature and executable hash again before creating a Host-only distribution ZIP. ZIP containers cannot themselves be stapled; their app tickets must be inside them. Re-running a completed release does not regenerate its archive.

Output: `work/release-0.3.1-build45/RetinaLink-0.3.1.zip`. Its SHA-256, accepted submission IDs, source commit and dirty-tree status are recorded in `release-state.json`. Commit source before a public release. These tools submit compiled software to Apple; they do not publish it or replace either installed app.

## Preserve trust across updates

Retain bundle identifiers `local.retinalink.Host` / `local.retinalink.Viewer`, the same Developer ID team, compatible designated requirements, Keychain namespace `local.retinalink.device-trust`, existing role-specific account names, preference keys and permanent installation paths. A renewed certificate within the same team need not change identity. Changing teams/channels requires a separate migration.

Replace Host in its permanent Applications location, then choose **Connection Details → Update Display Software…**. This path verifies Host's signature, checks that the existing Viewer is from the same developer and is bound to this Host, validates the incoming replacement before stopping the old one, installs it and restarts it with the existing startup preference. It never enrolls again, generates or exports credentials, edits `authorized_keys`, changes FileVault or enables automatic login. Management SSH can ask the owner to authenticate; the streaming key remains restricted to forwarding. Host has no hosted automatic-download feed yet.

The existing ad-hoc installation requires a **one-time transition**: complete Host-led Display Setup with the first signed release and approve its Screen Recording permission if macOS requires it. Signed code intentionally cannot silently read the old hash-specific Keychain item. Subsequent compatible signed releases are designed to retain pairing and identity-based approval. First-run prompts and periodic macOS reauthorization remain controlled by the OS; notarization is not a permission bypass.

## Validation status

Actual Developer ID build-44 Host and AMD iMac Viewer self-tests, simulated capture-denial recovery and nine offline release-policy tests pass. A native Launch Services probe verifies two different signed binaries with the real Host designated requirement can share a temporary test item silently, while an ad-hoc clone is denied when the classic-Keychain interaction guard is applied. All temporary items were removed; production credentials were never accessed by that probe. The iMac correctly rejects the ad-hoc test app against the Developer ID requirement. The tests cover wrong-team/Host/namespace rejection, changed upload detection, resume without duplicate submission, rejection/Gatekeeper failure and Viewer-ticket-before-Host-signing order. They are not evidence of Apple's acceptance or a signed-to-signed update.

After the profile is available, finish notarizing the existing baseline in `work/release-0.3.1` (build 44), enroll once, then notarize the final build 45 in `work/release-0.3.1-build45`. Replace Host and test native login-agent capture, Host-side Viewer update, unchanged binding/public authorized key, resumed 5K streaming and tunnel/crash recovery through SSH. Never copy private keys or stream credentials into evidence. The UI capture helper stays off.

## Apple references

- [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), including custom installers and ticket stapling.
- [TN3127: Inside Code Signing — Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements), including privacy and Keychain identity across updates.

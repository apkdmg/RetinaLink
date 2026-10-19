# Build RetinaLink from source

RetinaLink is licensed under GPL-3.0-only; read `LICENSE` and `THIRD_PARTY_NOTICES.md`. Each published binary release is accompanied by a `RetinaLink-<version>-source.tar.gz` archive containing the matching committed application source, build and packaging scripts, resources, tests, and Sparkle's corresponding source. `SOURCE_MANIFEST.json` identifies that RetinaLink commit and the pinned dependency source. No Git history, local test logs, account credentials or signing keys are needed to build it.

Use a Mac with full Xcode selected by `xcode-select`, its command-line tools, Python 3.12 or later, and the macOS SDK. The project was developed with the macOS 27 SDK; a sufficiently recent SDK is required for its Swift and framework APIs. Host targets Apple silicon macOS 13+, while Viewer targets Intel macOS 10.15+ and Apple silicon macOS 11+. Building on the original target operating system is not required. Exact binary reproducibility across Apple toolchains, SDKs, signatures and notarization tickets is not claimed.

## Application build using the pinned official framework

From the extracted source directory:

```sh
bash build.sh
```

This downloads the SHA-256-pinned official Sparkle binary framework using HTTPS, builds both applications and signs them ad hoc. The apps appear in `build/apps`. It requires no developer certificate, Apple account, notarization credential or RetinaLink private update key. Ad-hoc builds use an isolated development pairing namespace and do not inherit the official release's Keychain access or trusted update identity. macOS can require local approval when opening your build, and Host needs Screen Recording permission. App-owned system or account setup still requires the affected Mac's administrator approval.

## Build Sparkle from its included source

The source release includes `VendorSources/Sparkle-2.9.6`, with its own Xcode project, configuration scripts, license and non-system vendored sources (`Vendor/bsdiff` and `Vendor/ed25519-sparkle`). The pinned upstream `.gitmodules` is empty, so no additional submodule downloads are required. Keep those upstream notices with your build.

Build the framework and its embedded helpers from that directory, then point RetinaLink at the result:

```sh
xcodebuild -project VendorSources/Sparkle-2.9.6/Sparkle.xcodeproj \
  -scheme Sparkle -configuration Release \
  -derivedDataPath "$PWD/build/sparkle-source" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY=- build
cp VendorSources/Sparkle-2.9.6/LICENSE build/sparkle-source/Build/Products/Release/LICENSE
RETINALINK_SPARKLE_DIR="$PWD/build/sparkle-source/Build/Products/Release" bash build.sh
```

`RETINALINK_SPARKLE_DIR` must contain `Sparkle.framework` and its `LICENSE`. It is an explicit local source-build override; the ordinary release build continues using the verified official framework. Upstream's `Configurations/ConfigCommon.xcconfig` contains its build options. Apple's system frameworks and SDK are supplied by Xcode rather than copied into the source release.

Run offline release-policy tests with `python3 -m unittest discover -s Tests -p 'test_*.py'`. The built executables also support `--self-test`; those tests use local networking and the actual GPU. SSH integration tools in `Tools` require separately authorized test Macs. See `VALIDATION.md` for the checks performed on official releases and their limits.

## Make a corresponding-source archive

The publisher first commits the complete release source, then builds and packages that exact commit. To create the matching source archive from a Git checkout:

```sh
python3 Tools/source_archive.py --commit FULL_40_CHARACTER_COMMIT \
  --output outputs/RetinaLink-VERSION-source.tar.gz \
  --manifest work/source-manifest.json
```

The tool reads committed Git blobs rather than the working tree, verifies the dependency archive's SHA-256, includes its full source tree, and rejects unknown submodules or mismatched binary/source dependency versions. It excludes Git history, `work`, `build`, `outputs` and `SECURITY_REVIEW.md`. Publish the matching source archive with every binary release and keep its download available. The public release publisher checks the archive digest and source commit before upload. Developer ID signing/notarization and Ed25519 update publication are separate distribution steps documented in `RELEASING.md`; they are not required to build or modify the application locally.

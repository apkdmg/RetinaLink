#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
RETINALINK_BUILD_DIR="${RETINALINK_BUILD_DIR:-build}"
RETINALINK_SIGN_IDENTITY="${RETINALINK_SIGN_IDENTITY:--}"
VERSION=$(python3 -c 'import json;print(json.load(open("Resources/Release.json"))["version"])')
BUILD_NUMBER="${RETINALINK_BUILD_NUMBER:-$(python3 -c 'import json;print(json.load(open("Resources/Release.json"))["build"])')}"
if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then echo 'Build number must be a positive integer.' >&2; exit 1; fi
TRUST_NAMESPACE="local.retinalink.development.$BUILD_NUMBER"
SIGNING_TEAM=''
SIGN_FLAGS=(--force --sign -)
if [ "$RETINALINK_SIGN_IDENTITY" != '-' ]; then
    IDENTITY_JSON=$(python3 Tools/signing.py identity --identity "$RETINALINK_SIGN_IDENTITY")
    RETINALINK_SIGN_IDENTITY=$(printf '%s' "$IDENTITY_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["identity"])')
    SIGNING_TEAM=$(printf '%s' "$IDENTITY_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["team"])')
    TRUST_NAMESPACE='local.retinalink.device-trust'
    SIGN_FLAGS=(--force --sign "$RETINALINK_SIGN_IDENTITY" --options runtime --timestamp)
fi
mkdir -p "$RETINALINK_BUILD_DIR/cache" "$RETINALINK_BUILD_DIR/apps"
RETINALINK_BUILD_DIR="$(cd "$RETINALINK_BUILD_DIR" && pwd)"
SDK="${RETINALINK_SDK:-$(xcode-select -p)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk}"
if [ ! -d "$SDK" ]; then SDK="$(xcrun --show-sdk-path)"; fi
SPARKLE_DIR=$(python3 Tools/sparkle.py fetch)
COMMON=(Sources/Protocol.swift Sources/Metrics.swift Sources/Diagnostics.swift Sources/DisplayClock.swift Sources/CaptureMailbox.swift Sources/Graphics.swift Sources/Enrollment.swift Sources/Signing.swift Sources/Updates.swift Sources/Design.swift Sources/UI.swift Sources/Viewer.swift Sources/HostProvisioning.swift Sources/HostSetup.swift Sources/main.swift Tests/SelfTests.swift)
FLAGS=(-O -whole-module-optimization -swift-version 5 -sdk "$SDK" -module-cache-path "$RETINALINK_BUILD_DIR/cache" -F "$SPARKLE_DIR" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks -framework AppKit -framework Network -framework Security -framework Metal -framework QuartzCore -framework CoreVideo -framework CoreMedia -lcompression)
xcrun clang -fobjc-arc -arch arm64 -mmacosx-version-min=13.0 -isysroot "$SDK" -c Sources/VirtualDisplay.m -o "$RETINALINK_BUILD_DIR/VirtualDisplay.o"
xcrun swiftc "${FLAGS[@]}" -target arm64-apple-macos13.0 -D HOST -import-objc-header Sources/VirtualDisplay.h "${COMMON[@]}" Sources/Host.swift Sources/CaptureProbe.swift "$RETINALINK_BUILD_DIR/VirtualDisplay.o" -framework ScreenCaptureKit -o "$RETINALINK_BUILD_DIR/Host"
for ARCH in arm64 x86_64; do
    MIN=10.15; if [ "$ARCH" = arm64 ]; then MIN=11.0; fi
    xcrun swiftc "${FLAGS[@]}" -target "$ARCH-apple-macos$MIN" "${COMMON[@]}" -o "$RETINALINK_BUILD_DIR/Viewer-$ARCH"
done
xcrun lipo -create "$RETINALINK_BUILD_DIR/Viewer-arm64" "$RETINALINK_BUILD_DIR/Viewer-x86_64" -output "$RETINALINK_BUILD_DIR/Viewer"
for ROLE in Host Viewer; do
    APP="$RETINALINK_BUILD_DIR/apps/RetinaLink $ROLE.app"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp "$RETINALINK_BUILD_DIR/$ROLE" "$APP/Contents/MacOS/RetinaLink"
    cp Resources/Shaders.metal "$APP/Contents/Resources/"
    cp Resources/AppIcon.icns "$APP/Contents/Resources/"
    MIN=10.15; if [ "$ROLE" = Host ]; then MIN=13.0; fi
    cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>RetinaLink</string>
<key>CFBundleIdentifier</key><string>local.retinalink.$ROLE</string>
<key>CFBundleName</key><string>RetinaLink $ROLE</string>
<key>CFBundleDisplayName</key><string>RetinaLink $ROLE</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>RetinaLinkTrustNamespace</key><string>$TRUST_NAMESPACE</string>
<key>RetinaLinkSigningTeam</key><string>$SIGNING_TEAM</string>
<key>LSMinimumSystemVersion</key><string>$MIN</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>Discover and connect to your other Mac to stream a display over your local network.</string>
<key>NSScreenCaptureUsageDescription</key><string>Send the RetinaLink extended desktop to your paired iMac.</string>
<key>NSBonjourServices</key><array><string>_retinalink._tcp</string><string>_ssh._tcp</string></array>
</dict></plist>
PLIST
    python3 Tools/sparkle.py configure --app "$APP" --role "$ROLE"
    mkdir -p "$APP/Contents/Frameworks"
    ditto "$SPARKLE_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
    cp "$SPARKLE_DIR/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
    FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
    for COMPONENT in Versions/B/Autoupdate Versions/B/Updater.app Versions/B/XPCServices/Downloader.xpc Versions/B/XPCServices/Installer.xpc; do
        codesign "${SIGN_FLAGS[@]}" "$FRAMEWORK/$COMPONENT"
    done
    codesign "${SIGN_FLAGS[@]}" "$FRAMEWORK"
    codesign "${SIGN_FLAGS[@]}" "$APP"
done
# The Host is the installer. Nontechnical users do not need a separate Viewer
# download or an external shell launcher to provision their iMac.
ditto -c -k --sequesterRsrc --keepParent "$RETINALINK_BUILD_DIR/apps/RetinaLink Viewer.app" "$RETINALINK_BUILD_DIR/apps/RetinaLink Host.app/Contents/Resources/RetinaLink Viewer.zip"
codesign "${SIGN_FLAGS[@]}" "$RETINALINK_BUILD_DIR/apps/RetinaLink Host.app"
printf 'Built apps in %s/apps\n' "$RETINALINK_BUILD_DIR"

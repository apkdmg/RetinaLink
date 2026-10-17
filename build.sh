#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
RETINALINK_BUILD_DIR="${RETINALINK_BUILD_DIR:-build}"
RETINALINK_SIGN_IDENTITY="${RETINALINK_SIGN_IDENTITY:--}"
mkdir -p "$RETINALINK_BUILD_DIR/cache" "$RETINALINK_BUILD_DIR/apps"
RETINALINK_BUILD_DIR="$(cd "$RETINALINK_BUILD_DIR" && pwd)"
SDK="${RETINALINK_SDK:-$(xcode-select -p)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk}"
if [ ! -d "$SDK" ]; then SDK="$(xcrun --show-sdk-path)"; fi
COMMON=(Sources/Protocol.swift Sources/Metrics.swift Sources/Diagnostics.swift Sources/DisplayClock.swift Sources/CaptureMailbox.swift Sources/Graphics.swift Sources/UI.swift Sources/main.swift Tests/SelfTests.swift)
FLAGS=(-O -whole-module-optimization -swift-version 5 -sdk "$SDK" -module-cache-path "$RETINALINK_BUILD_DIR/cache" -framework AppKit -framework Network -framework Security -framework Metal -framework QuartzCore -framework CoreVideo -framework CoreMedia -lcompression)
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
<key>CFBundleShortVersionString</key><string>0.2.10</string>
<key>CFBundleVersion</key><string>38</string>
<key>LSMinimumSystemVersion</key><string>$MIN</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>Discover and connect to your other Mac to stream a display over your local network.</string>
<key>NSScreenCaptureUsageDescription</key><string>Send the RetinaLink extended desktop to your paired iMac.</string>
<key>NSBonjourServices</key><array><string>_retinalink._tcp</string></array>
</dict></plist>
PLIST
    codesign --force --sign "$RETINALINK_SIGN_IDENTITY" "$APP"
done
printf 'Built apps in %s/apps\n' "$RETINALINK_BUILD_DIR"

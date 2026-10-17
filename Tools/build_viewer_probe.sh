#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$(pwd)"
build="${1:-25}"
[[ "$build" =~ ^[0-9]+$ ]] || { printf 'Invalid build number\n' >&2; exit 1; }
out="${RETINALINK_PROBE_BUILD_DIR:-$root/build/probe-$build}"
sdk="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
mkdir -p "$out/cache"
for arch in arm64 x86_64; do
  min=10.15; if [ "$arch" = arm64 ]; then min=11.0; fi
  xcrun swiftc -O -whole-module-optimization -swift-version 5 -sdk "$sdk" -module-cache-path "$out/cache" -target "$arch-apple-macos$min" -framework AppKit -framework Metal -framework Network -framework Security -framework QuartzCore -framework CoreVideo -framework CoreMedia -lcompression Sources/Protocol.swift Sources/Metrics.swift Sources/Diagnostics.swift Sources/DisplayClock.swift Sources/CaptureMailbox.swift Sources/Graphics.swift Sources/Enrollment.swift Sources/UI.swift Tests/SelfTests.swift Tools/ViewerProbe/main.swift -o "$out/Probe-$arch"
done
app="$out/RetinaLink Viewer.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
xcrun lipo -create "$out/Probe-arm64" "$out/Probe-x86_64" -output "$app/Contents/MacOS/RetinaLink"
cp Resources/Shaders.metal "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>RetinaLink</string>
<key>CFBundleIdentifier</key><string>local.retinalink.Viewer</string>
<key>CFBundleName</key><string>RetinaLink Viewer</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>$build</string>
<key>LSMinimumSystemVersion</key><string>10.15</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
printf 'Built local probe %s\n' "$app"

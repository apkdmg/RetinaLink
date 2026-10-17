#!/bin/bash
# One-time test-machine maintenance, run by the owner through sudo in Terminal.
# Replace only the already configured dedicated account's signed Viewer.
# No password, pairing, pending enrollment or login/encryption policy is read.
set -euo pipefail
if [ "$(/usr/bin/id -u)" != 0 ]; then
    echo 'Administrator authorization is required to update the other account’s app.' >&2
    exit 1
fi
if [ "$#" != 2 ] || [[ ! "$2" =~ ^[1-9][0-9]*$ ]]; then
    echo 'Usage: update_dedicated_viewer.sh /absolute/RetinaLink\ Viewer.app BUILD' >&2
    exit 1
fi
source_app="$1"
expected_build="$2"
case "$source_app" in /Users/*/Applications/'RetinaLink Viewer.app'|/Users/*/Library/Logs/RetinaLink/NativePairingTests/Apps/'RetinaLink Viewer.app') ;; *) echo 'Unexpected source application path.' >&2; exit 1;; esac
account=retinalinkdisplay
target_home="/Users/$account"
target_parent="$target_home/Applications"
target_app="$target_parent/RetinaLink Viewer.app"
for item in "$target_home" "$target_parent" "$target_app"; do
    if [ -L "$item" ] || [ ! -d "$item" ]; then echo 'Dedicated installation needs manual review.' >&2; exit 1; fi
done
display_uid=$(/usr/bin/id -u "$account")
if [ "$display_uid" -lt 501 ]; then echo 'Unexpected display account.' >&2; exit 1; fi
requirement='anchor apple generic and identifier "local.retinalink.Viewer" and certificate leaf[subject.OU] = "ZPCS5VQL89"'
/usr/bin/codesign --verify --deep --strict -R="$requirement" "$target_app"
previous_build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$target_app/Contents/Info.plist")
if [[ ! "$previous_build" =~ ^[1-9][0-9]*$ ]] || [ "$previous_build" -gt "$expected_build" ]; then echo 'Refusing an unknown build or downgrade.' >&2; exit 1; fi
staging=$(/usr/bin/mktemp -d /private/var/tmp/retinalink-viewer-update.XXXXXX)
/bin/chmod 700 "$staging"
rollback() {
    if [ -d "$staging/Previous Viewer.app" ] && [ ! -d "$target_app" ]; then
        /bin/mv "$staging/Previous Viewer.app" "$target_app"
    fi
    /bin/rm -rf "$staging"
}
trap rollback EXIT
# Validate the private clone, not a user-writable source that might change.
/usr/bin/ditto "$source_app" "$staging/New Viewer.app"
/usr/bin/codesign --verify --deep --strict -R="$requirement" "$staging/New Viewer.app"
/usr/sbin/spctl --assess --type execute "$staging/New Viewer.app"
actual_build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$staging/New Viewer.app/Contents/Info.plist")
if [ "$actual_build" != "$expected_build" ]; then echo 'Source build differs from the requested signed build.' >&2; exit 1; fi
/usr/sbin/chown -R "$display_uid":20 "$staging/New Viewer.app"
/bin/mv "$target_app" "$staging/Previous Viewer.app"
if ! /bin/mv "$staging/New Viewer.app" "$target_app"; then exit 1; fi
if ! /usr/bin/codesign --verify --deep --strict -R="$requirement" "$target_app"; then
    /bin/mv "$target_app" "$staging/Failed Viewer.app"
    exit 1
fi
/usr/bin/printf '{"success":true,"account":"retinalinkdisplay","build":"%s","previousBuild":"%s","pairingChanged":false,"fileVaultChanged":false,"loginSettingsChanged":false}\n' "$actual_build" "$previous_build"

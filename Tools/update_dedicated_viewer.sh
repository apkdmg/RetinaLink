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
requirement='anchor apple generic and identifier "local.retinalink.Viewer" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "ZPCS5VQL89"'
require_inactive() {
    local process_snapshot process_uid process_path
    process_snapshot=$(/bin/ps -axww -o uid=,comm=)
    while read -r process_uid process_path; do
        if [ "$process_path" = "$target_app/Contents/MacOS/RetinaLink" ]; then
            echo 'The dedicated Viewer is running. Quit that copy before updating it.' >&2
            exit 1
        fi
    done <<< "$process_snapshot"
}
require_inactive
/usr/bin/codesign --verify --deep --strict -R="$requirement" "$target_app"
previous_build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$target_app/Contents/Info.plist")
if [[ ! "$previous_build" =~ ^[1-9][0-9]*$ ]] || [ "$previous_build" -gt "$expected_build" ]; then echo 'Refusing an unknown build or downgrade.' >&2; exit 1; fi
staging=$(/usr/bin/mktemp -d /private/var/tmp/retinalink-viewer-update.XXXXXX)
/bin/chmod 700 "$staging"
backup_app="$staging/Previous Viewer.app"
committed=0
backup_created=0
retain_backup() {
    echo "Update recovery needs administrator review. The private backup was retained at: $staging" >&2
    exit 1
}
cleanup() {
    local status=$?
    trap - EXIT HUP INT TERM
    if [ "$committed" -ne 1 ]; then
        # Check the backup itself as well as the state flag: a signal may arrive
        # immediately after the rename, before backup_created is assigned.
        if [ -d "$backup_app" ]; then
            if [ -e "$target_app" ] || [ -L "$target_app" ]; then
                if ! /bin/mv "$target_app" "$staging/Failed Viewer.app"; then retain_backup; fi
            fi
            # Keep the original private backup until the restored copy passes
            # verification. A failed copy/verification must not erase it.
            if ! /usr/bin/ditto "$backup_app" "$target_app"; then retain_backup; fi
            if ! /usr/bin/codesign --verify --deep --strict -R="$requirement" "$target_app"; then retain_backup; fi
            local restored_build
            if ! restored_build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$target_app/Contents/Info.plist"); then retain_backup; fi
            if [ "$restored_build" != "$previous_build" ]; then retain_backup; fi
        elif [ "$backup_created" -eq 1 ]; then
            retain_backup
        fi
    fi
    if ! /bin/rm -rf "$staging"; then exit 1; fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
# Validate the private clone, not a user-writable source that might change.
/usr/bin/ditto "$source_app" "$staging/New Viewer.app"
/usr/bin/codesign --verify --deep --strict -R="$requirement" "$staging/New Viewer.app"
/usr/sbin/spctl --assess --type execute "$staging/New Viewer.app"
actual_build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$staging/New Viewer.app/Contents/Info.plist")
if [ "$actual_build" != "$expected_build" ]; then echo 'Source build differs from the requested signed build.' >&2; exit 1; fi
/usr/sbin/chown -R "$display_uid":20 "$staging/New Viewer.app"
# Recheck just before the swap; no process or login agent is stopped here.
require_inactive
/bin/mv "$target_app" "$backup_app"
backup_created=1
if ! /bin/mv "$staging/New Viewer.app" "$target_app"; then exit 1; fi
/usr/bin/codesign --verify --deep --strict -R="$requirement" "$target_app"
/usr/sbin/spctl --assess --type execute "$target_app"
installed_build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$target_app/Contents/Info.plist")
if [ "$installed_build" != "$expected_build" ]; then echo 'Installed Viewer build verification failed.' >&2; exit 1; fi
for item in "$target_app" "$target_app/Contents/MacOS/RetinaLink"; do
    if [ "$(/usr/bin/stat -f '%u:%g' "$item")" != "$display_uid:20" ]; then
        echo 'Installed Viewer ownership verification failed.' >&2
        exit 1
    fi
done
committed=1
/usr/bin/printf '{"success":true,"account":"retinalinkdisplay","build":"%s","previousBuild":"%s","pairingChanged":false,"fileVaultChanged":false,"loginSettingsChanged":false}\n' "$actual_build" "$previous_build"

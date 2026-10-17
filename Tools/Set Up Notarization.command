#!/bin/bash
# Developer setup only. Apple's tool owns the hidden password prompt.
set -euo pipefail
cd "$(dirname "$0")/.."
printf '\nRETINALINK — SAVE APPLE NOTARIZATION LOGIN\n\n'
printf 'Enter your Developer Apple ID email, then an app-specific password.\n'
printf 'The password is entered only at Apple’s hidden prompt.\n\n'
if python3 Tools/release.py credentials; then
    printf '\nSUCCESS — saved and verified the notarization login.\n'
    printf 'You can return to Codex. No logs or passwords need to be copied.\n'
else
    printf '\nSETUP FAILED — the login has not been verified.\n'
    printf 'Please share only the error text above, never a password.\n'
fi
printf '\nPress Return to close this window.\n'
read -r

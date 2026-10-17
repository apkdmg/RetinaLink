#!/bin/bash
# Developer setup only. Apple's tool owns the hidden password prompt.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 Tools/release.py credentials

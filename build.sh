#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if ! command -v lb >/dev/null 2>&1; then
  echo 'ERROR: live-build is missing. On Debian/Ubuntu run: sudo apt update && sudo apt install live-build debootstrap xorriso'
  exit 1
fi
sudo lb clean --purge || true
sudo lb config
sudo lb build

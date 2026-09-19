#!/bin/sh
# Project-owned CI checks for this governance-template repository.
set -eu

sh tests/acceptance.sh

if command -v pwsh >/dev/null 2>&1; then
  pwsh -NoLogo -NoProfile -File tests/acceptance.ps1
else
  echo "PowerShell is unavailable; skipping the PowerShell compatibility suite." >&2
fi

#!/usr/bin/env bash
# One-shot local setup for m365-configurator (POSIX-shell entry point).
#
# Verifies PowerShell 7+ is available, then runs the module installer. It makes
# no system-level changes itself and never authenticates to any tenant. If pwsh
# is missing it prints install guidance rather than silently installing software.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "m365-configurator — local bootstrap"

if ! command -v pwsh >/dev/null 2>&1; then
  cat >&2 <<'EOF'
ERROR: PowerShell 7+ (pwsh) was not found on PATH.

This project drives PowerShell modules, so pwsh is required. Install it:
  https://learn.microsoft.com/powershell/scripting/install/installing-powershell

Then re-run: ./scripts/bootstrap.sh
(Or open the folder in the dev container, which ships pwsh for you.)
EOF
  exit 1
fi

echo "Found: $(pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()')"
exec pwsh -NoProfile -File "${HERE}/install-modules.ps1" "$@"

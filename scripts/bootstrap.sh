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

PWSH_VERSION="$(pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()')"
echo "Found: ${PWSH_VERSION}"

# Full-version floor check (ADR-0015, amended): 7.6 LTS / .NET 10. The pinned
# ExchangeOnlineManagement 3.10.0 needs .NET 10, and the module manifest rejects
# import below 7.6 — fail here with guidance instead of later and confusingly.
FLOOR_MAJOR=7
FLOOR_MINOR=6
MAJOR="${PWSH_VERSION%%.*}"
REST="${PWSH_VERSION#*.}"
MINOR="${REST%%.*}"
if [ "${MAJOR}" -lt "${FLOOR_MAJOR}" ] || { [ "${MAJOR}" -eq "${FLOOR_MAJOR}" ] && [ "${MINOR}" -lt "${FLOOR_MINOR}" ]; }; then
  cat >&2 <<EOF
ERROR: PowerShell ${FLOOR_MAJOR}.${FLOOR_MINOR}+ is required; found ${PWSH_VERSION}.

The pinned ExchangeOnlineManagement module (3.10.0) requires PowerShell 7.6+
(.NET 10) — see docs/decisions/0015-runtime-version-pin-powershell-lts.md.
Install the current LTS:
  https://learn.microsoft.com/powershell/scripting/install/installing-powershell

Then re-run: ./scripts/bootstrap.sh
EOF
  exit 1
fi

exec pwsh -NoProfile -File "${HERE}/install-modules.ps1" "$@"

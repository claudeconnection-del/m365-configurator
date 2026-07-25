#requires -Version 7.0
# ^ Deliberately BELOW the 7.6 floor (ADR-0015): this script must still run on a
#   downlevel pwsh so the guard below can explain the floor and the fix
#   (ADR-0011) instead of dying on PowerShell's terse #requires error.
<#
.SYNOPSIS
    One-shot local setup for m365-configurator (PowerShell entry point).

.DESCRIPTION
    Convenience wrapper for developers not using the dev container. Verifies the
    PowerShell version and hands off to install-modules.ps1. Makes no system
    changes beyond installing modules into the CurrentUser scope, and never
    authenticates to any tenant.

.EXAMPLE
    pwsh -NoProfile -File scripts/bootstrap.ps1

.EXAMPLE
    pwsh -NoProfile -File scripts/bootstrap.ps1 -Full
#>
[CmdletBinding()]
param(
    [switch] $Full,
    [switch] $IncludeM365Dsc,
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "m365-configurator — local bootstrap" -ForegroundColor Cyan
Write-Host "PowerShell $($PSVersionTable.PSVersion) on $($PSVersionTable.Platform)"

# Full-version floor check (ADR-0015, amended): 7.6 LTS / .NET 10. The pinned
# ExchangeOnlineManagement 3.10.0 cannot load its .NET 10 assemblies on anything
# older, and the module manifest rejects import below 7.6.
$floor = [version] '7.6.0'
if ($PSVersionTable.PSVersion -lt $floor) {
    throw ("PowerShell {0}+ is required; you are on {1} (outside the ADR-0015 support window). Install the current LTS from https://aka.ms/powershell and re-run." -f $floor, $PSVersionTable.PSVersion)
}

$here = Split-Path -Parent $PSCommandPath
& (Join-Path $here 'install-modules.ps1') -Full:$Full -IncludeM365Dsc:$IncludeM365Dsc -Force:$Force

Write-Host ""
Write-Host "Ready. Install dev/test tooling with scripts/install-dev-tools.ps1, then run: Invoke-Pester -Path tests/" -ForegroundColor Green
Write-Host "See docs/ROADMAP.md for the phased plan and CONTRIBUTING.md for the workflow." -ForegroundColor DarkGray

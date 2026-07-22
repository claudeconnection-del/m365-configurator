#requires -Version 7.0
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

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7+ is required. Install it from https://aka.ms/powershell and re-run."
}

$here = Split-Path -Parent $PSCommandPath
& (Join-Path $here 'install-modules.ps1') -Full:$Full -IncludeM365Dsc:$IncludeM365Dsc -Force:$Force

Write-Host ""
Write-Host "Ready. Install dev/test tooling with scripts/install-dev-tools.ps1, then run: Invoke-Pester -Path tests/" -ForegroundColor Green
Write-Host "See docs/ROADMAP.md for the phased plan and CONTRIBUTING.md for the workflow." -ForegroundColor DarkGray

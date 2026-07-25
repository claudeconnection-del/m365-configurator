#requires -Version 7.0
<#
.SYNOPSIS
    Installs the developer / test tooling for m365-configurator.

.DESCRIPTION
    Deliberately separate from install-modules.ps1: Pester is a DEV/TEST
    dependency, not an app runtime dependency, so it stays out of the app's
    required-module set (Get-M365RequiredModule) and the minimal-runtime-deps
    tenet. Idempotent, CurrentUser scope, PowerShell Gallery only, no elevation,
    no tenant contact.

    Pinned for a reproducible dev environment (NFR-8). The test suite uses Pester
    5+ syntax; bumping the pin is a deliberate edit here.

.EXAMPLE
    pwsh -NoProfile -File scripts/install-dev-tools.ps1
#>
[CmdletBinding()]
param(
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# Floor check (ADR-0015, amended): the test suite imports the module manifest,
# which requires 7.6 — installing the tooling on an older host would only defer
# the failure to the first Invoke-Pester. The #requires header stays below the
# floor on purpose so this message can run (ADR-0011).
$floor = [version] '7.6.0'
if ($PSVersionTable.PSVersion -lt $floor) {
    throw ("PowerShell {0}+ is required; you are on {1} (outside the ADR-0015 support window). Install the current LTS from https://aka.ms/powershell and re-run." -f $floor, $PSVersionTable.PSVersion)
}

function Write-Step { param([string] $Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string] $Message) Write-Host "  ✓ $Message" -ForegroundColor Green }
function Write-Skip { param([string] $Message) Write-Host "  • $Message" -ForegroundColor DarkGray }

# Pinned dev/test tooling.
$pesterPin = [version] '6.0.1'

Write-Step "m365-configurator dev/test tooling"
Write-Host "    PowerShell : $($PSVersionTable.PSVersion) ($($PSVersionTable.Platform))"
Write-Host "    Scope      : CurrentUser (no elevation, no system changes)"
Write-Host ""

Write-Step "Pester  —  test runner for tests/*.Tests.ps1 (Pester 5+ syntax)"
$installed = Get-Module -ListAvailable -Name Pester |
    Where-Object { $_.Version -ge $pesterPin } |
    Sort-Object Version -Descending |
    Select-Object -First 1

if ($installed -and -not $Force) {
    Write-Skip "already satisfied: v$($installed.Version) meets pin v$pesterPin (use -Force to refresh)"
}
else {
    # -SkipPublisherCheck: Pester ships signed; older bundled Pester can otherwise
    # block the side-by-side install of a newer, differently-signed version.
    Install-Module -Name Pester -RequiredVersion $pesterPin -Scope CurrentUser `
        -Force -AllowClobber -SkipPublisherCheck -Repository PSGallery
    Write-Ok "installed Pester v$pesterPin (pinned)"
}
Write-Host ""

Write-Ok "Dev tooling ready. Run the tests with:  Invoke-Pester -Path tests/"

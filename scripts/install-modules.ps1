#requires -Version 7.0
<#
.SYNOPSIS
    Installs the PowerShell modules m365-configurator depends on.

.DESCRIPTION
    Idempotent, CurrentUser-scoped installer for the Microsoft 365 modules this
    project drives. It makes no system-level changes, requires no elevation, and
    never authenticates to any tenant — it only talks to the PowerShell Gallery.

    The required set and its PINNED versions come from the M365Configurator
    module itself (Get-M365RequiredModule) — a single source of truth shared with
    the app (FR-1, NFR-7). Idempotency uses the same satisfied rule the app uses
    (Get-M365ModuleStatus): an install is skipped when the pin is already met.

    Reflecting the project's design tenets:
      * Loud, fast failure  -> StrictMode + $ErrorActionPreference = 'Stop'
      * Verbose by default   -> every step is announced
      * Minimal footprint    -> installs into the CurrentUser scope only
      * Stability            -> required modules install at their pinned version

.PARAMETER Full
    Also install the complete Microsoft.Graph SDK meta-module (large; pulls ~40
    sub-modules). Unpinned exploration extra — not part of the required set.

.PARAMETER IncludeM365Dsc
    Also install Microsoft365DSC. Large; unpinned exploration extra.

.PARAMETER Force
    Reinstall/refresh modules even if a satisfying version is already present.

.EXAMPLE
    pwsh -NoProfile -File scripts/install-modules.ps1

.EXAMPLE
    pwsh -NoProfile -File scripts/install-modules.ps1 -Full -IncludeM365Dsc
#>
[CmdletBinding()]
param(
    [switch] $Full,
    [switch] $IncludeM365Dsc,
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'  # keeps CI/container logs clean

# Floor check BEFORE the module import below: the manifest requires 7.6, so on a
# downlevel host Import-Module would fail with PowerShell's terse version error —
# fail here with guidance instead (ADR-0015 amended; ADR-0011). The #requires
# header stays below the floor on purpose so this message can run.
$floor = [version] '7.6.0'
if ($PSVersionTable.PSVersion -lt $floor) {
    throw ("PowerShell {0}+ is required; you are on {1} (outside the ADR-0015 support window). Install the current LTS from https://aka.ms/powershell and re-run." -f $floor, $PSVersionTable.PSVersion)
}

function Write-Step { param([string] $Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string] $Message) Write-Host "  ✓ $Message" -ForegroundColor Green }
function Write-Skip { param([string] $Message) Write-Host "  • $Message" -ForegroundColor DarkGray }

# -----------------------------------------------------------------------------
# Single source of truth: import the app module and read its declared required
# set + pins. This is the same list the app detects/heals against at runtime, so
# a fresh bootstrap can never drift from what the app expects (fixes the old
# duplicated, unpinned list).
# -----------------------------------------------------------------------------
$modulePath = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
Import-Module $modulePath -Force

$targets = [System.Collections.Generic.List[hashtable]]::new()
foreach ($req in Get-M365RequiredModule) {
    $targets.Add(@{ Name = $req.Name; Version = $req.Version; Reason = $req.Reason })
}
# Opt-in exploration extras: not part of the pinned required set.
if ($Full)           { $targets.Add(@{ Name = 'Microsoft.Graph';  Version = $null; Reason = 'Full Microsoft Graph SDK (all sub-modules) — unpinned extra' }) }
if ($IncludeM365Dsc) { $targets.Add(@{ Name = 'Microsoft365DSC'; Version = $null; Reason = 'Desired State Configuration for M365 — unpinned extra' }) }

Write-Step "m365-configurator module bootstrap"
Write-Host "    PowerShell : $($PSVersionTable.PSVersion) ($($PSVersionTable.Platform))"
Write-Host "    Scope      : CurrentUser (no elevation, no system changes)"
Write-Host ""

# -----------------------------------------------------------------------------
# Ensure the PowerShell Gallery is available and trusted for this user only.
# -----------------------------------------------------------------------------
Write-Step "Verifying PowerShell Gallery availability"
$gallery = Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue
if (-not $gallery) {
    throw "PSGallery repository is not registered. Register it with Register-PSRepository -Default and re-run."
}
if ($gallery.InstallationPolicy -ne 'Trusted') {
    Write-Skip "PSGallery is 'Untrusted'; trusting it for this session's non-interactive installs."
    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
}
Write-Ok "PSGallery reachable and trusted"
Write-Host ""

# -----------------------------------------------------------------------------
# Install each target. Pinned (required) modules install at their exact version
# and are skipped when the pin is already satisfied; unpinned extras install the
# latest and are skipped when any version is present.
# -----------------------------------------------------------------------------
foreach ($target in $targets) {
    $name = $target.Name
    $pin  = $target.Version
    Write-Step "$name  —  $($target.Reason)"

    if ($pin) {
        $status = Get-M365ModuleStatus -Required @(
            [pscustomobject]@{ Name = $name; Version = $pin; Reason = $target.Reason }
        )
        if ($status.Satisfied -and -not $Force) {
            Write-Skip "already satisfied: v$($status.InstalledVersion) meets pin v$pin (use -Force to refresh)"
            continue
        }
        Install-Module -Name $name -RequiredVersion $pin -Scope CurrentUser -AllowClobber -Force -Repository PSGallery
        Write-Ok "installed v$pin (pinned)"
    }
    else {
        $installed = Get-Module -ListAvailable -Name $name |
            Sort-Object Version -Descending |
            Select-Object -First 1
        if ($installed -and -not $Force) {
            Write-Skip "already installed: v$($installed.Version) (unpinned extra; use -Force to refresh)"
            continue
        }
        Install-Module -Name $name -Scope CurrentUser -AllowClobber -Force -Repository PSGallery
        $now = Get-Module -ListAvailable -Name $name |
            Sort-Object Version -Descending |
            Select-Object -First 1
        Write-Ok "installed v$($now.Version) (latest)"
    }
}
Write-Host ""

# -----------------------------------------------------------------------------
# Report exactly what is present, against the (pinned where applicable) target.
# -----------------------------------------------------------------------------
Write-Step "Installed module summary"
$report = foreach ($target in $targets) {
    $m = Get-Module -ListAvailable -Name $target.Name |
        Sort-Object Version -Descending |
        Select-Object -First 1
    [pscustomobject]@{
        Module    = $target.Name
        Pinned    = if ($target.Version) { $target.Version } else { '(latest)' }
        Installed = if ($m) { $m.Version.ToString() } else { 'NOT FOUND' }
    }
}
$report | Format-Table -AutoSize | Out-String | Write-Host

if ($report.Installed -contains 'NOT FOUND') {
    throw "One or more modules failed to install. See the summary above."
}

Write-Ok "Bootstrap complete. No tenant was contacted; no credentials were stored."
Write-Host "    Next: connecting to M365 is an explicit, interactive step in the app." -ForegroundColor DarkGray

#requires -Version 7.0
<#
.SYNOPSIS
    Installs the PowerShell modules m365-configurator depends on.

.DESCRIPTION
    Idempotent, CurrentUser-scoped installer for the Microsoft 365 modules this
    project drives. It makes no system-level changes, requires no elevation, and
    never authenticates to any tenant — it only talks to the PowerShell Gallery.

    Reflecting the project's design tenets:
      * Loud, fast failure  -> StrictMode + $ErrorActionPreference = 'Stop'
      * Verbose by default   -> every step is announced
      * Minimal footprint    -> installs into the CurrentUser scope only

.PARAMETER Full
    Also install the complete Microsoft.Graph SDK meta-module (large; pulls ~40
    sub-modules). By default only Microsoft.Graph.Authentication is installed,
    which is enough to connect and to load specific Graph sub-modules on demand.

.PARAMETER IncludeM365Dsc
    Also install Microsoft365DSC (Desired State Configuration for M365). Large and
    pulls many dependencies; off by default. Included because DSC is an explicit
    area of interest for this project (see docs/OPEN-QUESTIONS.md).

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

function Write-Step { param([string] $Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string] $Message) Write-Host "  ✓ $Message" -ForegroundColor Green }
function Write-Skip { param([string] $Message) Write-Host "  • $Message" -ForegroundColor DarkGray }

# -----------------------------------------------------------------------------
# The dependency set. Keep this list small and deliberate (design tenet #2).
#
# NOTE ON VERSION PINNING (design tenet #6): stability is tied to the module
# syntax staying constant, so production deployments SHOULD pin exact versions.
# We do not hard-pin here yet — pinning strategy is an open design decision
# (see docs/OPEN-QUESTIONS.md). For now we install the latest available and
# report the exact versions so they can be recorded/pinned later.
# -----------------------------------------------------------------------------
$modules = [System.Collections.Generic.List[hashtable]]::new()
$modules.Add(@{ Name = 'Microsoft.Graph.Authentication'; Reason = 'Connect/disconnect + on-demand Graph sub-module loading' })
$modules.Add(@{ Name = 'ExchangeOnlineManagement';       Reason = 'Exchange Online configuration' })
if ($Full)          { $modules.Add(@{ Name = 'Microsoft.Graph'; Reason = 'Full Microsoft Graph SDK (all sub-modules)' }) }
if ($IncludeM365Dsc){ $modules.Add(@{ Name = 'Microsoft365DSC'; Reason = 'Desired State Configuration for M365' }) }

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
# Install each module if a satisfying version is not already present.
# -----------------------------------------------------------------------------
foreach ($module in $modules) {
    $name = $module.Name
    Write-Step "$name  —  $($module.Reason)"

    $installed = Get-Module -ListAvailable -Name $name |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if ($installed -and -not $Force) {
        Write-Skip "already installed: v$($installed.Version) (use -Force to refresh)"
        continue
    }

    Install-Module -Name $name -Scope CurrentUser -AllowClobber -Force -Repository PSGallery
    $now = Get-Module -ListAvailable -Name $name |
        Sort-Object Version -Descending |
        Select-Object -First 1
    Write-Ok "installed v$($now.Version)"
}
Write-Host ""

# -----------------------------------------------------------------------------
# Report exactly what is present, so versions can be recorded and pinned.
# -----------------------------------------------------------------------------
Write-Step "Installed module summary"
$report = foreach ($module in $modules) {
    $m = Get-Module -ListAvailable -Name $module.Name |
        Sort-Object Version -Descending |
        Select-Object -First 1
    [pscustomobject]@{
        Module  = $module.Name
        Version = if ($m) { $m.Version.ToString() } else { 'NOT FOUND' }
    }
}
$report | Format-Table -AutoSize | Out-String | Write-Host

if ($report.Version -contains 'NOT FOUND') {
    throw "One or more modules failed to install. See the summary above."
}

Write-Ok "Bootstrap complete. No tenant was contacted; no credentials were stored."
Write-Host "    Next: connecting to M365 is an explicit, interactive step in the app." -ForegroundColor DarkGray

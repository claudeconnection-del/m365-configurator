<#
.SYNOPSIS
    Build-time installer for the Microsoft365DSC container proof.

.DESCRIPTION
    Installs Microsoft365DSC (pinned or latest), imports it, and pins its
    dependency set via Update-M365DSCDependencies. Deliberately RESILIENT: it never
    throws and always exits 0, so the image always builds and the probe scripts
    become the single source of truth for the R1 verdict (import success/failure is
    itself a finding — see issue #3144). It records what happened to the console.

    Works under both PowerShell 7 (Linux image) and Windows PowerShell 5.1 (Windows
    image), so it avoids pwsh-7-only syntax.

.PARAMETER Version
    Exact Microsoft365DSC version to pin (recommended, R9), or 'latest'.

.PARAMETER Scope
    Install scope: 'CurrentUser' (Linux image) or 'AllUsers' (Windows image).
#>
[CmdletBinding()]
param(
    [string] $Version = 'latest',
    [ValidateSet('CurrentUser','AllUsers')] [string] $Scope = 'CurrentUser'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

function Say { param([string] $m) Write-Host "==> $m" }

try {
    Say "Preparing PSGallery (scope: $Scope)"
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -Force | Out-Null
    }
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

    if ($Version -eq 'latest') {
        Say "Installing Microsoft365DSC (latest available)"
        Install-Module Microsoft365DSC -Scope $Scope -Force -AllowClobber -Repository PSGallery
    } else {
        Say "Installing Microsoft365DSC v$Version (pinned)"
        Install-Module Microsoft365DSC -RequiredVersion $Version -Scope $Scope -Force -AllowClobber -Repository PSGallery
    }

    $m = Get-Module -ListAvailable Microsoft365DSC | Sort-Object Version -Descending | Select-Object -First 1
    if ($m) { Say "Installed Microsoft365DSC v$($m.Version)" } else { Say "WARNING: Microsoft365DSC not found after install" }

    Say "Importing Microsoft365DSC (this is the step issue #3144 reports may fail on Linux)"
    Import-Module Microsoft365DSC -ErrorAction Stop
    Say "Import succeeded"

    if (Get-Command Update-M365DSCDependencies -ErrorAction SilentlyContinue) {
        Say "Pinning dependency set via Update-M365DSCDependencies"
        Update-M365DSCDependencies -Force
    }
    Say "Install step complete"
}
catch {
    # A failure here is a RESULT, not a harness bug. Record it loudly and let the
    # probes report R1 = FAIL/BLOCKED at run time.
    Write-Host "==> INSTALL/IMPORT FAILED (recorded as an R1 finding): $($_.Exception.Message)"
}

exit 0

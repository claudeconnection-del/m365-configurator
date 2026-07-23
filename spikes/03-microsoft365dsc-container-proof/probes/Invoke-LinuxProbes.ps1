#requires -Version 7.0
<#
.SYNOPSIS
    Linux + PowerShell 7 probes for the Microsoft365DSC engine-viability proof.

.DESCRIPTION
    Empirically tests the claims in docs/research/03-microsoft365dsc.md that can be
    checked on our target runtime (Linux + pwsh 7). The high-value probes need NO
    tenant and NO credentials:

      R1  Does `Import-Module Microsoft365DSC` even succeed on Linux/pwsh7?
          (issue #3144 reported an import failure). Are the key cmdlets present?
      R3  On-disk footprint of Microsoft365DSC + its dependency set (NFR-3).
      R4  Does the Graph dependency stay at Microsoft.Graph.Authentication only,
          or are many Graph sub-modules present? (folklore vs the pinned manifest).
      R2  Is an *apply* path available at all on Linux — i.e. does
          `Invoke-DscResource` exist (DSC 2.0 keeps it; LCM cmdlets are gone)?
      R7  Offline delta report (`New-M365DSCDeltaReport`) — is the cross-platform
          diff engine usable, and does it report clean on two identical exports?
          (opt-in: needs two exported .ps1 files supplied via -ExportA/-ExportB).

    An OPTIONAL, opt-in export probe (-RunExport) attempts a single-component
    export; it requires operator-supplied auth and is documented in the README.
    By default this script contacts no tenant and stores no credentials.

.PARAMETER OutputDir
    Where to write results JSON/markdown. Default: ./results under the spike dir,
    or /proof-results inside the container.

.PARAMETER ExportA
.PARAMETER ExportB
    Two previously-exported Microsoft365DSC .ps1 files, for the R7 delta-report
    probe. If omitted, R7 is SKIPPED.

.PARAMETER RunExport
    Opt-in: attempt a live single-component export (requires auth env; see README).

.EXAMPLE
    pwsh -NoProfile -File probes/Invoke-LinuxProbes.ps1
#>
[CmdletBinding()]
param(
    [string] $OutputDir,
    [string] $ExportA,
    [string] $ExportB,
    [switch] $RunExport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

. (Join-Path $PSScriptRoot '_Common.ps1')

if (-not $OutputDir) {
    $OutputDir = if (Test-Path '/proof-results') { '/proof-results' }
                 else { Join-Path (Split-Path $PSScriptRoot -Parent) 'results' }
}

Write-Step "Microsoft365DSC container proof — Linux / pwsh 7 probes"
Write-Host "    PowerShell : $($PSVersionTable.PSVersion) ($($PSVersionTable.Platform))"
Write-Host "    Results dir: $OutputDir"
Write-Host "    No tenant is contacted and no credentials are stored unless -RunExport is set." -ForegroundColor DarkGray
Write-Host ""

$results = [System.Collections.Generic.List[object]]::new()

# --- R1: import + cmdlet availability -----------------------------------------
$results.Add((Invoke-Probe -Id 'R1' -Question 'Does Microsoft365DSC import on Linux/pwsh7?' -Body {
    $installed = Get-Module -ListAvailable -Name Microsoft365DSC |
        Sort-Object Version -Descending | Select-Object -First 1
    if (-not $installed) {
        return New-ProbeResult -Id 'R1' -Question 'import' -Status 'BLOCKED' `
            -Detail 'Microsoft365DSC is not installed in this image (install step failed or was skipped).' `
            -Evidence @{ installed = $false }
    }
    try {
        Import-Module Microsoft365DSC -ErrorAction Stop
    }
    catch {
        return New-ProbeResult -Id 'R1' -Question 'import' -Status 'FAIL' `
            -Detail "Import-Module failed (cf. issue #3144): $($_.Exception.Message)" `
            -Evidence @{ installed = $true; version = $installed.Version.ToString(); importError = $_.Exception.Message }
    }
    $keyCmds = 'Export-M365DSCConfiguration','New-M365DSCDeltaReport','Assert-M365DSCBlueprint'
    $present = @{}
    foreach ($c in $keyCmds) { $present[$c] = [bool](Get-Command $c -ErrorAction SilentlyContinue) }
    $allPresent = -not ($present.Values -contains $false)
    New-ProbeResult -Id 'R1' -Question 'import' -Status ($allPresent ? 'PASS' : 'FAIL') `
        -Detail ("Imported Microsoft365DSC v$($installed.Version); key cmdlets present: " +
                 (($present.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')) `
        -Evidence @{ version = $installed.Version.ToString(); cmdlets = $present }
}))

# --- R3: on-disk footprint ----------------------------------------------------
$results.Add((Invoke-Probe -Id 'R3' -Question 'What is the on-disk footprint (NFR-3)?' -Body {
    $userModulePath = ($env:PSModulePath -split [IO.Path]::PathSeparator) |
        Where-Object { $_ -like '*/.local/share/powershell/Modules' -or $_ -like '*CurrentUser*' } |
        Select-Object -First 1
    $sizes = [ordered]@{}
    $targets = 'Microsoft365DSC','Microsoft.Graph.Authentication','ExchangeOnlineManagement',
               'MicrosoftTeams','PnP.PowerShell','ReverseDSC','DSCParser','MSCloudLoginAssistant'
    $totalMB = 0.0
    foreach ($t in $targets) {
        $mod = Get-Module -ListAvailable -Name $t | Sort-Object Version -Descending | Select-Object -First 1
        if ($mod) {
            $dir = Split-Path $mod.Path -Parent
            $mb  = Get-DirectorySizeMB -Path $dir
            $sizes[$t] = $mb; $totalMB += $mb
        } else { $sizes[$t] = 'absent' }
    }
    # Also measure the whole CurrentUser module root, if we can find it.
    $rootMB = 0.0
    if ($userModulePath -and (Test-Path $userModulePath)) { $rootMB = Get-DirectorySizeMB -Path $userModulePath }
    New-ProbeResult -Id 'R3' -Question 'footprint' -Status 'INFO' `
        -Detail ("Named-module total ≈ ${totalMB} MB; CurrentUser module root ≈ ${rootMB} MB. Compare to the ~5-module custom slice.") `
        -Evidence @{ perModuleMB = $sizes; namedTotalMB = $totalMB; moduleRootMB = $rootMB }
}))

# --- R4: Graph dependency breadth ---------------------------------------------
$results.Add((Invoke-Probe -Id 'R4' -Question 'Graph dep = Authentication only, or many sub-modules?' -Body {
    $graphInstalled = Get-Module -ListAvailable -Name 'Microsoft.Graph*' |
        Select-Object -ExpandProperty Name -Unique | Sort-Object
    $graphLoaded = Get-Module -Name 'Microsoft.Graph*' |
        Select-Object -ExpandProperty Name -Unique | Sort-Object
    $onlyAuth = ($graphInstalled.Count -le 1) -and ($graphInstalled -contains 'Microsoft.Graph.Authentication' -or $graphInstalled.Count -eq 0)
    New-ProbeResult -Id 'R4' -Question 'graph breadth' -Status 'INFO' `
        -Detail ("Installed Graph modules: $($graphInstalled.Count) (" +
                 (($graphInstalled | Select-Object -First 6) -join ', ') +
                 ($graphInstalled.Count -gt 6 ? ', …' : '') + "). " +
                 ($onlyAuth ? 'Matches the "Authentication only" claim.' : 'Broader than Authentication-only — investigate.')) `
        -Evidence @{ installed = $graphInstalled; loadedAfterImport = $graphLoaded }
}))

# --- R2: is an apply path even present on Linux? ------------------------------
$results.Add((Invoke-Probe -Id 'R2' -Question 'Any apply path on Linux (Invoke-DscResource)?' -Body {
    $invoke = Get-Command Invoke-DscResource -ErrorAction SilentlyContinue
    $startCfg = Get-Command Start-DscConfiguration -ErrorAction SilentlyContinue   # expected ABSENT on pwsh7
    $psdsc = Get-Module -ListAvailable -Name PSDesiredStateConfiguration |
        Sort-Object Version -Descending | Select-Object -First 1
    $detail = "Invoke-DscResource: $([bool]$invoke); Start-DscConfiguration: $([bool]$startCfg) (expected absent on pwsh7); " +
              "PSDesiredStateConfiguration: $([bool]$psdsc)$($psdsc ? " v$($psdsc.Version)" : '')."
    # Status is INFO: presence of Invoke-DscResource does NOT prove an M365DSC
    # resource applies headless on Linux — that requires the deeper attempt below.
    New-ProbeResult -Id 'R2' -Question 'apply path' -Status 'INFO' `
        -Detail $detail `
        -Evidence @{
            invokeDscResource      = [bool]$invoke
            startDscConfiguration  = [bool]$startCfg
            psDesiredStateConfig   = $psdsc ? $psdsc.Version.ToString() : $null
            note = 'A real headless apply attempt via Invoke-DscResource -Method Set against one M365DSC resource requires auth; run with -RunExport and see README R2 for the guided manual step.'
        }
}))

# --- R7: offline delta report (cross-platform) --------------------------------
$results.Add((Invoke-Probe -Id 'R7' -Question 'Offline delta report clean on identical exports?' -Body {
    if (-not $ExportA -or -not $ExportB) {
        return New-ProbeResult -Id 'R7' -Question 'delta report' -Status 'SKIPPED' `
            -Detail 'No -ExportA/-ExportB supplied. Provide two exported .ps1 files to test New-M365DSCDeltaReport for false positives.' `
            -Evidence @{ reason = 'inputs not provided' }
    }
    if (-not (Get-Command New-M365DSCDeltaReport -ErrorAction SilentlyContinue)) {
        return New-ProbeResult -Id 'R7' -Question 'delta report' -Status 'BLOCKED' `
            -Detail 'New-M365DSCDeltaReport not available (module import failed?).'
    }
    $out = Join-Path $OutputDir 'delta-report.html'
    New-M365DSCDeltaReport -Source $ExportA -Destination $ExportB -OutputPath $out -DriftOnly -ErrorAction Stop | Out-Null
    New-ProbeResult -Id 'R7' -Question 'delta report' -Status 'INFO' `
        -Detail "Delta report generated at $out. Inspect it: identical inputs should show NO drift (watch for the known ResourceID / CA-exclusion false positives)." `
        -Evidence @{ outputPath = $out; inputA = $ExportA; inputB = $ExportB }
}))

# --- Optional live export (opt-in; needs auth) --------------------------------
if ($RunExport) {
    $results.Add((Invoke-Probe -Id 'R1x' -Question 'Does a single-component export run on Linux?' -Body {
        if (-not (Get-Command Export-M365DSCConfiguration -ErrorAction SilentlyContinue)) {
            return New-ProbeResult -Id 'R1x' -Question 'export' -Status 'BLOCKED' -Detail 'Export cmdlet unavailable.'
        }
        # Auth is operator-supplied via environment. We support app-only cert
        # (recommended for a non-interactive proof) OR device code. Secrets are
        # read from env and never echoed. See README for the variables.
        $exportPath = Join-Path $OutputDir 'export'
        New-Item -ItemType Directory -Force -Path $exportPath | Out-Null
        $common = @{ Components = @('AADAuthorizationPolicy'); Path = $exportPath }
        if ($env:M365_APPID -and $env:M365_TENANTID -and $env:M365_CERT_THUMBPRINT) {
            Export-M365DSCConfiguration @common -ApplicationId $env:M365_APPID `
                -TenantId $env:M365_TENANTID -CertificateThumbprint $env:M365_CERT_THUMBPRINT -ErrorAction Stop
        }
        elseif ($env:M365_TENANTID) {
            # Device-code / interactive path (M365DSC supports interactive for export).
            Export-M365DSCConfiguration @common -TenantId $env:M365_TENANTID -ErrorAction Stop
        }
        else {
            return New-ProbeResult -Id 'R1x' -Question 'export' -Status 'SKIPPED' `
                -Detail 'No auth env provided (M365_TENANTID [+ M365_APPID/M365_CERT_THUMBPRINT]). Export not attempted.'
        }
        $files = Get-ChildItem -Recurse -File $exportPath | Select-Object -ExpandProperty Name
        New-ProbeResult -Id 'R1x' -Question 'export' -Status 'PASS' `
            -Detail "Export of AADAuthorizationPolicy succeeded on this runtime; files: $($files -join ', ')" `
            -Evidence @{ files = $files; path = $exportPath }
    }))
}

# --- Persist + summarise ------------------------------------------------------
$env0 = Get-ProofEnvironment
$paths = Save-ProbeResults -Results $results -Environment $env0 -OutputDir $OutputDir

Write-Host ""
Write-Step "Summary"
$results | Select-Object Id, Status, Detail | Format-Table -AutoSize -Wrap | Out-String | Write-Host

# Loud, fast failure (NFR-6): a genuine FAIL exits non-zero so CI notices.
if ($results.Status -contains 'FAIL') {
    Write-Bad "One or more probes FAILED — see $($paths.Markdown)"
    exit 1
}
Write-Ok "Probes complete. No credentials were stored by this run."

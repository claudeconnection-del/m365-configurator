#requires -Version 7.0
<#
.SYNOPSIS
    Windows probes for the Microsoft365DSC engine-viability proof — the parts that
    the research (docs/research/03-microsoft365dsc.md) says only work on Windows.

.DESCRIPTION
    Runs inside a WINDOWS container (Windows PowerShell 5.1 present, or pwsh 7 with
    the Windows compatibility shim). It measures the "fallback" path ADR-0002
    anticipated, so the accept/reject call rests on data:

      R2  Full apply loop: compile a minimal M365DSC configuration to a MOF and
          hand it to the LCM (`Start-DscConfiguration -WhatIf`, then `Test-`).
          Confirms the LCM is present and the compile→MOF→apply path works.
      R6  MOF credential exposure: compile a config using ONLY app-only cert auth
          (no -Credential) and scan the resulting MOF for secrets/thumbprints —
          does a decryptable secret land on disk? (NFR-1 conflict check).
      R5  Cert re-check: whether the LCM's 15-min consistency check can run when
          the app cert lives only in an ephemeral store (guided; see README).
      R8  Windows image footprint (module tree + note on base-image size).

    SECURITY: this script never writes secrets to the results. The MOF scan reports
    only WHETHER secret-shaped content is present and its classification, not values.

.PARAMETER OutputDir
    Where to write results. Default: /proof-results (container) or ../results.

.PARAMETER ConfigPath
    Optional path to a minimal M365DSC .ps1 configuration to compile for R2/R6. If
    omitted, R2/R6 are BLOCKED with instructions (a real config needs an app
    registration + resource; see README) — the script does not fabricate one.
#>
[CmdletBinding()]
param(
    [string] $OutputDir,
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

. (Join-Path $PSScriptRoot '_Common.ps1')

if (-not $OutputDir) {
    $OutputDir = if (Test-Path '/proof-results') { '/proof-results' }
                 elseif (Test-Path 'C:\proof-results') { 'C:\proof-results' }
                 else { Join-Path (Split-Path $PSScriptRoot -Parent) 'results' }
}

$isWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::Windows)

Write-Step "Microsoft365DSC container proof — Windows probes"
Write-Host "    PowerShell : $($PSVersionTable.PSVersion) ($($PSVersionTable.Platform))"
Write-Host "    Windows OS : $isWindows"
Write-Host "    Results dir: $OutputDir"
Write-Host ""

if (-not $isWindows) {
    Write-Warn2 "These probes require a Windows container host. On a non-Windows OS the LCM and MOF apply do not exist (that is the whole point of the research); recording BLOCKED and exiting."
}

$results = [System.Collections.Generic.List[object]]::new()

# --- R2: LCM present + compile → apply ----------------------------------------
$results.Add((Invoke-Probe -Id 'R2' -Question 'Does the compile→MOF→LCM apply path work?' -Body {
    if (-not $isWindows) {
        return New-ProbeResult -Id 'R2' -Question 'apply loop' -Status 'BLOCKED' `
            -Detail 'Not on Windows — LCM/Start-DscConfiguration unavailable by design.'
    }
    $startCfg = Get-Command Start-DscConfiguration -ErrorAction SilentlyContinue
    $testCfg  = Get-Command Test-DscConfiguration  -ErrorAction SilentlyContinue
    if (-not $startCfg) {
        return New-ProbeResult -Id 'R2' -Question 'apply loop' -Status 'FAIL' `
            -Detail 'Start-DscConfiguration not found even on Windows — check Windows PowerShell 5.1 / compat availability.'
    }
    if (-not $ConfigPath) {
        return New-ProbeResult -Id 'R2' -Question 'apply loop' -Status 'BLOCKED' `
            -Detail 'LCM cmdlets present, but no -ConfigPath supplied to compile a MOF. Provide a minimal M365DSC config (see README R2) to exercise the full path.' `
            -Evidence @{ startDscConfiguration = $true; testDscConfiguration = [bool]$testCfg }
    }
    $mofDir = Join-Path $OutputDir 'mof'
    New-Item -ItemType Directory -Force -Path $mofDir | Out-Null
    . $ConfigPath                                   # dot-source defines the configuration
    # The configuration name must match; we call it and -WhatIf the apply.
    $cfgName = (Get-Command -CommandType Configuration | Select-Object -First 1).Name
    & $cfgName -OutputPath $mofDir | Out-Null
    Start-DscConfiguration -Path $mofDir -Wait -Force -WhatIf
    $testOut = $testCfg ? (Test-DscConfiguration -Path $mofDir -Detailed) : $null
    New-ProbeResult -Id 'R2' -Question 'apply loop' -Status 'PASS' `
        -Detail "Compiled '$cfgName' to MOF and validated the LCM apply path (WhatIf). Test-DscConfiguration ran: $([bool]$testOut)." `
        -Evidence @{ configuration = $cfgName; mofDir = $mofDir }
}))

# --- R6: MOF credential exposure ----------------------------------------------
$results.Add((Invoke-Probe -Id 'R6' -Question 'Does a compiled MOF embed secrets?' -Body {
    $mofDir = Join-Path $OutputDir 'mof'
    if (-not (Test-Path $mofDir)) {
        return New-ProbeResult -Id 'R6' -Question 'mof secrets' -Status 'BLOCKED' `
            -Detail 'No MOF compiled (R2 did not run). Compile a MOF with app-only cert auth first, then re-run.'
    }
    $mofs = Get-ChildItem -Path $mofDir -Filter '*.mof' -File -ErrorAction SilentlyContinue
    if (-not $mofs) {
        return New-ProbeResult -Id 'R6' -Question 'mof secrets' -Status 'BLOCKED' -Detail 'No .mof files found in the MOF dir.'
    }
    # Scan for secret-shaped markers WITHOUT recording any value.
    $patterns = @{
        PlainTextPassword = 'PasswordAllowPlainText|PSDscAllowPlainTextPassword'
        CredentialBlock   = 'MSFT_Credential|Password\s*='
        Thumbprint        = 'CertificateThumbprint\s*='
        EncryptedCred     = 'MSFT_KeyValuePair|-----BEGIN'
    }
    $hits = [ordered]@{}
    foreach ($mof in $mofs) {
        $text = Get-Content -LiteralPath $mof.FullName -Raw
        foreach ($k in $patterns.Keys) {
            if ($text -match $patterns[$k]) { $hits[$k] = ($hits.Contains($k) ? $hits[$k] : 0) + 1 }
        }
    }
    $anySecret = $hits.Keys.Count -gt 0
    New-ProbeResult -Id 'R6' -Question 'mof secrets' -Status ($anySecret ? 'FAIL' : 'PASS') `
        -Detail ($anySecret
            ? "MOF contains secret-shaped content: $(($hits.Keys) -join ', '). Confirms the NFR-1 conflict — a decryptable secret is at rest."
            : 'No secret-shaped markers found in the MOF under this auth mode (record the auth mode used).') `
        -Evidence @{ markerCounts = $hits; mofCount = $mofs.Count; note = 'Values are never recorded — only marker presence/counts.' }
}))

# --- R5: cert re-check under ephemeral store (guided) -------------------------
$results.Add((Invoke-Probe -Id 'R5' -Question 'Can the LCM re-check with an ephemeral cert only?' -Body {
    New-ProbeResult -Id 'R5' -Question 'cert re-check' -Status 'BLOCKED' `
        -Detail 'Manual/guided: register an app with a cert, place the cert only in a tmpfs-backed store, apply with ApplyAndMonitor, then remove the store and observe whether the 15-min consistency check still succeeds. Record the outcome here. (See README R5.)' `
        -Evidence @{ guided = $true }
}))

# --- R8: Windows footprint ----------------------------------------------------
$results.Add((Invoke-Probe -Id 'R8' -Question 'Windows module footprint / image cost?' -Body {
    $mod = Get-Module -ListAvailable -Name Microsoft365DSC | Sort-Object Version -Descending | Select-Object -First 1
    $mb = $mod ? (Get-DirectorySizeMB -Path (Split-Path $mod.Path -Parent)) : 0
    New-ProbeResult -Id 'R8' -Question 'windows footprint' -Status 'INFO' `
        -Detail ("Microsoft365DSC module ≈ ${mb} MB. NOTE: a Windows base image (servercore/nanoserver) is multi-GB and requires a Windows container host — record the built image size with `docker images`.") `
        -Evidence @{ moduleMB = $mb; version = $mod ? $mod.Version.ToString() : 'absent' }
}))

$env0 = Get-ProofEnvironment
$paths = Save-ProbeResults -Results $results -Environment $env0 -OutputDir $OutputDir

Write-Host ""
Write-Step "Summary"
$results | Select-Object Id, Status, Detail | Format-Table -AutoSize -Wrap | Out-String | Write-Host

if ($results.Status -contains 'FAIL') {
    Write-Bad "One or more probes reported FAIL (for R6 a FAIL is the *expected* NFR-1 finding, not a script error) — see $($paths.Markdown)"
    exit 1
}
Write-Ok "Windows probes complete."

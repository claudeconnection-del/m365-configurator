#requires -Version 7.0
<#
.SYNOPSIS
    Shared helpers for the Microsoft365DSC container-proof probes.

.DESCRIPTION
    Dot-sourced by Invoke-LinuxProbes.ps1 and Invoke-WindowsProbes.ps1. Provides
    consistent, colourised step output (matching scripts/install-modules.ps1), a
    structured probe-result object, a JSON/markdown result writer, and small
    utilities.

    Design tenets honoured here:
      * Loud, fast failure  -> callers use StrictMode + $ErrorActionPreference=Stop
      * Readability          -> one result object shape; stable ordering
      * Security is paramount-> never write secrets; result writer scrubs values
#>

Set-StrictMode -Version Latest

function Write-Step { param([string] $Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string] $Message) Write-Host "  ✓ $Message"  -ForegroundColor Green }
function Write-Skip { param([string] $Message) Write-Host "  • $Message"  -ForegroundColor DarkGray }
function Write-Warn2{ param([string] $Message) Write-Host "  ! $Message"  -ForegroundColor Yellow }
function Write-Bad  { param([string] $Message) Write-Host "  ✗ $Message"  -ForegroundColor Red }

# A single, stable result shape so the JSON and the printed table always align.
function New-ProbeResult {
    param(
        [Parameter(Mandatory)] [string] $Id,        # e.g. 'R1'
        [Parameter(Mandatory)] [string] $Question,  # short human question
        [Parameter(Mandatory)] [ValidateSet('PASS','FAIL','BLOCKED','SKIPPED','INFO')] [string] $Status,
        [string] $Detail = '',                      # one-line verdict
        [object] $Evidence = $null                  # structured, secret-free evidence
    )
    [pscustomobject]@{
        Id       = $Id
        Question = $Question
        Status   = $Status
        Detail   = $Detail
        Evidence = $Evidence
    }
}

# Run a probe body, turning any exception into a recorded FAIL/BLOCKED result
# instead of aborting the whole run. Distinguishes "not supported here" (BLOCKED)
# from a genuine failure (FAIL) by a caller-supplied classifier.
function Invoke-Probe {
    param(
        [Parameter(Mandatory)] [string]      $Id,
        [Parameter(Mandatory)] [string]      $Question,
        [Parameter(Mandatory)] [scriptblock] $Body
    )
    Write-Step "$Id — $Question"
    try {
        $result = & $Body
        if ($result -isnot [pscustomobject] -or -not ($result.PSObject.Properties.Name -contains 'Status')) {
            throw "Probe $Id body did not return a New-ProbeResult object."
        }
        switch ($result.Status) {
            'PASS'    { Write-Ok   $result.Detail }
            'FAIL'    { Write-Bad  $result.Detail }
            'BLOCKED' { Write-Warn2 $result.Detail }
            'SKIPPED' { Write-Skip $result.Detail }
            default   { Write-Host "    $($result.Detail)" -ForegroundColor Gray }
        }
        return $result
    }
    catch {
        Write-Bad "unhandled error: $($_.Exception.Message)"
        return New-ProbeResult -Id $Id -Question $Question -Status 'FAIL' `
            -Detail "unhandled error: $($_.Exception.Message)" `
            -Evidence @{ exceptionType = $_.Exception.GetType().FullName }
    }
}

# Recursively measure a directory's size in MB (0 if missing).
function Get-DirectorySizeMB {
    param([Parameter(Mandatory)] [string] $Path)
    if (-not (Test-Path $Path)) { return 0.0 }
    $bytes = (Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
              Measure-Object -Property Length -Sum).Sum
    if (-not $bytes) { return 0.0 }
    [math]::Round($bytes / 1MB, 1)
}

# Capture the host/runtime environment for the results header (no secrets).
function Get-ProofEnvironment {
    [pscustomobject]@{
        TimestampUtc     = (Get-Date).ToUniversalTime().ToString('o')
        PSVersion        = $PSVersionTable.PSVersion.ToString()
        PSEdition        = $PSVersionTable.PSEdition
        Platform         = $PSVersionTable.Platform
        OS               = $PSVersionTable.OS
        M365DscVersion   = (Get-Module -ListAvailable -Name Microsoft365DSC |
                            Sort-Object Version -Descending | Select-Object -First 1 |
                            ForEach-Object { $_.Version.ToString() }) ?? 'NOT INSTALLED'
    }
}

# Write results as JSON (canonical) and a readable markdown table. Never emits
# credential material: Evidence is expected to be pre-scrubbed by callers.
function Save-ProbeResults {
    param(
        [Parameter(Mandatory)] [object[]]     $Results,
        [Parameter(Mandatory)] [pscustomobject] $Environment,
        [Parameter(Mandatory)] [string]       $OutputDir
    )
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")

    $payload = [pscustomobject]@{ environment = $Environment; results = $Results }
    $jsonPath = Join-Path $OutputDir "results-$stamp.json"
    $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding utf8

    $mdPath = Join-Path $OutputDir "results-$stamp.md"
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("# Microsoft365DSC container-proof — results")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("- Timestamp (UTC): $($Environment.TimestampUtc)")
    [void]$sb.AppendLine("- PowerShell: $($Environment.PSVersion) ($($Environment.PSEdition), $($Environment.Platform))")
    [void]$sb.AppendLine("- OS: $($Environment.OS)")
    [void]$sb.AppendLine("- Microsoft365DSC: $($Environment.M365DscVersion)")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("| Probe | Question | Status | Detail |")
    [void]$sb.AppendLine("| --- | --- | --- | --- |")
    foreach ($r in $Results) {
        $detail = ($r.Detail -replace '\|', '\|')
        [void]$sb.AppendLine("| $($r.Id) | $($r.Question) | **$($r.Status)** | $detail |")
    }
    $sb.ToString() | Set-Content -LiteralPath $mdPath -Encoding utf8

    Write-Host ""
    Write-Step "Results written"
    Write-Ok "JSON: $jsonPath"
    Write-Ok "Markdown: $mdPath"
    [pscustomobject]@{ Json = $jsonPath; Markdown = $mdPath }
}

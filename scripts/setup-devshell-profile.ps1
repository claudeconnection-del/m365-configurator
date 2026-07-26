#requires -Version 7.0
<#
.SYNOPSIS
    Wires up the devcontainer's pwsh profile so every new shell auto-imports
    m365-configurator and prints a one-line "how to start" hint.

.DESCRIPTION
    Devcontainer-only convenience, not part of the app's runtime behavior:
    without this, a fresh shell requires three manual steps (import the
    module, connect, build a session) before you can do anything useful
    (owner feedback, 2026-07-26 — "let you kinda get in and work after
    authenticating"). This appends a small, idempotent snippet to
    $PROFILE.CurrentUserAllHosts — no elevation, CurrentUser scope only, the
    same posture as the module installers — so "Reopen in Container" -> open
    a terminal -> `$session = Connect-M365` is the whole onboarding path.

    Idempotent: re-running (e.g. on a container rebuild) does not duplicate
    the snippet.

.EXAMPLE
    pwsh -NoProfile -File scripts/setup-devshell-profile.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$marker    = '# >>> m365-configurator dev shell profile >>>'
$endMarker = '# <<< m365-configurator dev shell profile <<<'

$repoRoot     = (Split-Path -Parent $PSScriptRoot) -replace '\\', '/'
$manifestPath = "$repoRoot/src/M365Configurator/M365Configurator.psd1"

$snippet = @"
$marker
`$m365ConfiguratorManifest = '$manifestPath'
if (Test-Path -LiteralPath `$m365ConfiguratorManifest) {
    Import-Module `$m365ConfiguratorManifest -ErrorAction SilentlyContinue
    if (Get-Module -Name M365Configurator) {
        Write-Host 'm365-configurator loaded. Run `$session = Connect-M365 to authenticate, then:' -ForegroundColor Cyan
        Write-Host '  ./scripts/m365config.ps1 dryrun -ProfilePath ./profiles/security-baseline.yaml -Session `$session' -ForegroundColor DarkGray
    }
}
$endMarker
"@

$profilePath = $PROFILE.CurrentUserAllHosts
$profileDir  = Split-Path -Parent $profilePath
if (-not (Test-Path -LiteralPath $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

$existing = if (Test-Path -LiteralPath $profilePath) { Get-Content -LiteralPath $profilePath -Raw } else { '' }
if ($existing -match [regex]::Escape($marker)) {
    Write-Host "Dev shell profile already wired up: $profilePath"
}
else {
    Add-Content -LiteralPath $profilePath -Value "`n$snippet`n"
    Write-Host "Dev shell profile updated: $profilePath"
}

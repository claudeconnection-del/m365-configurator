#requires -Version 7.6
<#
.SYNOPSIS
    m365-configurator CLI — the primary interface for v1 (MCA-36; D11;
    ADR-0012 CLI-first).

.DESCRIPTION
    A thin dispatcher: it maps -Command plus its options onto the module's
    public functions through an injected -Invoker seam, and nothing else — no
    business logic lives here (that's the module's job). Save-M365Profile's
    -ControlReader is wired to Read-M365ControlState (the real tenant reader),
    which is why that function is public: this script runs outside the
    module and cannot resolve a private, unexported function by name.

.EXAMPLE
    Connect-M365Graph
    ./scripts/m365config.ps1 dryrun -ProfilePath ./profiles/security-baseline.yaml

.EXAMPLE
    ./scripts/m365config.ps1 apply -ProfilePath ./profiles/security-baseline.yaml -Approve

.EXAMPLE
    ./scripts/m365config.ps1 save -Name my-tenant-baseline -Session $session
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('save', 'dryrun', 'apply', 'drift')]
    [string] $Command,

    [string] $ProfilePath,
    [string] $Name,
    [string] $Framework = 'CISA-SCuBA',
    [string] $FrameworkVersion = '1.5.0',
    [string] $OutPath,
    [switch] $Approve,
    [hashtable] $NameOverride,

    # The connected session (New-M365Session). $null runs read-only commands
    # against whatever the module's own defaults resolve.
    $Session,

    # Seam: maps a function name + argument splat onto the real call. Tests
    # inject a capturing Invoker instead of touching the module or a tenant.
    [scriptblock] $Invoker = { param($FunctionName, $Splat) & (Get-Command $FunctionName) @Splat }
)

if (-not (Get-Module -Name M365Configurator)) {
    Import-Module (Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1') -Force
}

switch ($Command) {
    'save' {
        if (-not $Name) {
            throw "m365config save requires -Name."
        }
        $splat = @{
            Name             = $Name
            Framework        = $Framework
            FrameworkVersion = $FrameworkVersion
            ControlReader    = { Read-M365ControlState -Session $Session }
        }
        if ($OutPath) { $splat.Path = $OutPath }
        & $Invoker 'Save-M365Profile' $splat
    }
    'dryrun' {
        if (-not $ProfilePath) {
            throw "m365config dryrun requires -ProfilePath."
        }
        $splat = @{ ProfilePath = $ProfilePath; Session = $Session }
        if ($NameOverride) { $splat.NameOverride = $NameOverride }
        & $Invoker 'Invoke-M365DryRun' $splat
    }
    'apply' {
        if (-not $ProfilePath) {
            throw "m365config apply requires -ProfilePath."
        }
        $splat = @{ ProfilePath = $ProfilePath; Session = $Session }
        if ($Approve) { $splat.Approve = $true }
        if ($NameOverride) { $splat.NameOverride = $NameOverride }
        & $Invoker 'Invoke-M365Apply' $splat
    }
    'drift' {
        if (-not $ProfilePath) {
            throw "m365config drift requires -ProfilePath."
        }
        $splat = @{ ProfilePath = $ProfilePath; Session = $Session }
        if ($NameOverride) { $splat.NameOverride = $NameOverride }
        & $Invoker 'Get-M365Drift' $splat
    }
}

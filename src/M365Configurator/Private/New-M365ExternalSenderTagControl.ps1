#requires -Version 7.6

function New-M365ExternalSenderTagControl {
    <#
    .SYNOPSIS
        Builds the MDO-10 (external sender warning) control handler (MCA-32;
        SCuBA MS.EXO.7.1v1).

    .DESCRIPTION
        Turns on Outlook's native "External" tag, which warns recipients when
        a message originates outside the organization — a low-friction
        phishing-awareness signal that needs no mail-flow rule.

        Mechanism (verified against Microsoft Learn, exchangepowershell,
        2026-07-25): `Get-ExternalInOutlook` returns one config object per
        organization/region (`Identity`, `Enabled`, `AllowList` — senders on
        the allow list are exempted from the tag); `Set-ExternalInOutlook
        [-Identity <org>] [-Enabled <bool>] [-AllowList <addresses>]` writes
        it back (no `-Identity` needed to target the tenant default). v1
        manages the **first** returned object only — multi-geo tenants can
        return several, and picking the first is a deliberate v1
        simplification (recorded here per the RUNBOOK).

        `Set-ExternalInOutlook` has **no `-WhatIf` support** — unlike most
        Graph/EXO writes, a dry-run here cannot rely on the cmdlet's own
        preview; the engine's default Get/Compare diff (ADR-0013) is the
        entire dry-run safety net for this control, so `Get`'s projection
        must be complete and accurate.

        RequiredCapabilities: `exo` only. No DependsOn.

        Internal helper; assembled into the provider set by
        Get-M365ControlRegistry.

    .OUTPUTS
        pscustomobject (PSTypeName 'M365Configurator.Control').
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    New-M365Control -Id 'MDO-10' -Provider 'exo' -Shape 'singleton' `
        -Title 'External sender warning (Outlook native tag)' `
        -RequiredCapabilities @('exo') `
        -Get {
            param($Session)
            $config = @(Invoke-M365ExoCommand -Name 'Get-ExternalInOutlook') | Select-Object -First 1

            @{
                enabled   = [bool] (Get-M365MapValue $config 'Enabled')
                allowList = @(Get-M365MapValue $config 'AllowList' | Sort-Object)
            }
        } `
        -Set {
            param($Session, $Desired, $Current)
            $parameters = @{}
            if (Test-M365MapHasKey $Desired 'enabled') {
                $parameters['Enabled'] = [bool] (Get-M365MapValue $Desired 'enabled')
            }
            if (Test-M365MapHasKey $Desired 'allowList') {
                $parameters['AllowList'] = @(Get-M365MapValue $Desired 'allowList' | Sort-Object)
            }

            Invoke-M365ExoCommand -Name 'Set-ExternalInOutlook' -Parameters $parameters
        }
}

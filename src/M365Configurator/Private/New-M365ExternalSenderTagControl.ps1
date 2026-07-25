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
        simplification (recorded here per the RUNBOOK). Every tenant ships
        at least one config object, so a zero-object return is treated the
        same as MDO-4's absent-Default-policy case: a broken EXO session,
        not a legitimate "tag is off" state — `Get` throws rather than
        silently defaulting (NFR-6).

        `Set-ExternalInOutlook` has **no `-WhatIf` support**, which is
        irrelevant here: like every other control, dry-run never invokes
        `Set` at all (Get-M365Plan only ever calls `Get`), so the engine's
        default Get/Compare diff (ADR-0013) is already the entire dry-run
        safety net regardless of what the cmdlet supports.

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

            if (-not $config) {
                throw "external sender warning config not found — Get-ExternalInOutlook should always return at least one object; this indicates a broken EXO session."
            }

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

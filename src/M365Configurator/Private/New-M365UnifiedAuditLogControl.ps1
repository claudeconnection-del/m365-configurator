#requires -Version 7.6

function New-M365UnifiedAuditLogControl {
    <#
    .SYNOPSIS
        Builds the AUD-1 (unified audit log) control handler (MCA-33;
        SCuBA MS.DEFENDER.6.1v1).

    .DESCRIPTION
        Turns on tenant-wide unified audit log ingestion, the prerequisite
        for every other audit/investigation capability in the tenant.

        Mechanism (verified against Microsoft Learn, exchangepowershell,
        2026-07-25): `Get-AdminAuditLogConfig` returns a single tenant-wide
        config object including `UnifiedAuditLogIngestionEnabled`;
        `Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true`
        writes it back. The property is only meaningful when read/written
        from **Exchange Online** PowerShell — in Security & Compliance
        PowerShell it always reads `False` — so this control is exo-only,
        matching our EXO-only session. Most tenants have had this on by
        default since 2019, so the control usually plans NoChange; it
        exists to catch the turned-it-off case, and it is NOT on by default
        for Business Basic/Standard/Premium licenses, where it is
        genuinely actionable.

        **Propagation note (do not "fix"):** enabling can take up to 60
        minutes to apply tenant-wide (longer to become searchable). Apply
        reports the `Set` outcome and deliberately does NOT immediately
        re-read to verify — an instant re-read would false-fail.

        RequiredCapabilities: `exo` only. No DependsOn. No custom Compare —
        the engine's default canonical-JSON diff is the whole story for a
        one-key projection.

        Internal helper; assembled into the provider set by
        Get-M365ControlRegistry.

    .OUTPUTS
        pscustomobject (PSTypeName 'M365Configurator.Control').
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    New-M365Control -Id 'AUD-1' -Provider 'exo' -Shape 'singleton' `
        -Title 'Unified audit log ingestion' `
        -RequiredCapabilities @('exo') `
        -Get {
            param($Session)
            $config = Invoke-M365ExoCommand -Name 'Get-AdminAuditLogConfig'

            @{
                unifiedAuditLogIngestionEnabled = [bool] (Get-M365MapValue $config 'UnifiedAuditLogIngestionEnabled')
            }
        } `
        -Set {
            param($Session, $Desired, $Current)
            Invoke-M365ExoCommand -Name 'Set-AdminAuditLogConfig' -Parameters @{
                UnifiedAuditLogIngestionEnabled = [bool] (Get-M365MapValue $Desired 'unifiedAuditLogIngestionEnabled')
            }
        }
}

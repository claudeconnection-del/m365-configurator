#requires -Version 7.6

function New-M365MailboxAuditControl {
    <#
    .SYNOPSIS
        Builds the AUD-2 (mailbox auditing, organization default) control
        handler (MCA-34; SCuBA MS.EXO.13.1v1).

    .DESCRIPTION
        Ensures mailbox auditing is on by organization default.

        Mechanism (per research 02 §3.7 + SCuBA MS.EXO.13.1): `Get-OrganizationConfig`
        returns `AuditDisabled` (bool; `$false` = auditing ON);
        `Set-OrganizationConfig -AuditDisabled $false` turns it on. The
        projection uses the **positive** vocabulary (`auditEnabled`) so the
        profile and dry-run diff read naturally (NFR-9) — `Get` inverts
        `AuditDisabled` on the way in, `Set` inverts back on the way out.

        `Get-OrganizationConfig` returning nothing means a broken EXO
        session, not "auditing is off" — `Get` throws rather than silently
        defaulting (NFR-6; same convention as AUD-1/MDO-4/MDO-10).

        **Scope decision (recorded, do not "improve"):** per-mailbox audit
        actions (`Set-Mailbox -AuditOwner ...`) are OUT of v1 — org default
        only. Under audit-on-by-default, `Get-Mailbox` reports
        `AuditEnabled: True` for every mailbox regardless of reality, and
        setting it `$false` is silently ignored — the real exclusion
        mechanism is `Set-MailboxAuditBypassAssociation`, a different
        surface, deferred past v1.

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

    New-M365Control -Id 'AUD-2' -Provider 'exo' -Shape 'singleton' `
        -Title 'Mailbox auditing (organization default)' `
        -RequiredCapabilities @('exo') `
        -Get {
            param($Session)
            $config = Invoke-M365ExoCommand -Name 'Get-OrganizationConfig'

            if ($null -eq $config) {
                throw "organization config not found — Get-OrganizationConfig should always return the tenant config; this indicates a broken EXO session."
            }

            @{
                auditEnabled = -not [bool] (Get-M365MapValue $config 'AuditDisabled')
            }
        } `
        -Set {
            param($Session, $Desired, $Current)
            Invoke-M365ExoCommand -Name 'Set-OrganizationConfig' -Parameters @{
                AuditDisabled = -not [bool] (Get-M365MapValue $Desired 'auditEnabled')
            }
        }
}

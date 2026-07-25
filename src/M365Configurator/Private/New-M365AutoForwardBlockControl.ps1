#requires -Version 7.6

function New-M365AutoForwardBlockControl {
    <#
    .SYNOPSIS
        Builds the MDO-4 (block external auto-forwarding) control handler
        (MCA-31; SCuBA MS.EXO.1.1v2).

    .DESCRIPTION
        External auto-forwarding is a classic exfiltration vector (a mailbox
        rule or the outbound spam policy silently forwards mail to an
        attacker-controlled address). This control enforces the outbound
        spam filter policy's `AutoForwardingMode`, scoped to the well-known
        `Default` policy — the same fixed-name convention as ID-2/ID-3 (D2);
        MCA-16 will thread name-remap overrides through this and every other
        name-scoped control later.

        Mechanism (verified against Microsoft Learn, exchangepowershell,
        2026-07-25): `Get-HostedOutboundSpamFilterPolicy` lists every
        outbound spam policy (every tenant ships `Default`, and it cannot be
        disabled/removed); `Set-HostedOutboundSpamFilterPolicy -Identity
        <name> -AutoForwardingMode Off` sets it. `AutoForwardingMode` is one
        of `Automatic` | `On` | `Off`. Microsoft's docs note `Automatic` now
        BEHAVES as `Off` — the shipped profile still sets `Off` explicitly
        (the docs' own recommendation), so a dry-run showing `Automatic ->
        Off` is making existing behavior explicit, not changing it.

        v1 is **update-only**: the Default policy always exists, so there is
        no Create path — `Get` throws if it is somehow missing (a broken EXO
        session), rather than modeling a Create branch that can never
        legitimately fire.

        The custom policy + rule pairing that governs non-default policies
        (per Microsoft's model) is out of v1 scope: only the Default policy
        is managed here, and the Default policy needs no accompanying rule.

        RequiredCapabilities: `exo` only (no Defender license needed — this
        is an EOP-tier outbound spam setting). No DependsOn.

        Internal helper; assembled into the provider set by
        Get-M365ControlRegistry.

    .OUTPUTS
        pscustomobject (PSTypeName 'M365Configurator.Control').
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    New-M365Control -Id 'MDO-4' -Provider 'exo' -Shape 'policy-rule' `
        -Title 'Block external auto-forwarding' `
        -RequiredCapabilities @('exo') `
        -Get {
            param($Session)
            $policies = @(Invoke-M365ExoCommand -Name 'Get-HostedOutboundSpamFilterPolicy')
            $default  = $policies | Where-Object { (Get-M365MapValue $_ 'Name') -eq 'Default' } | Select-Object -First 1

            if (-not $default) {
                throw "outbound spam filter policy 'Default' not found — every tenant ships one; this indicates a broken EXO session."
            }

            @{
                name               = [string] (Get-M365MapValue $default 'Name')
                autoForwardingMode = [string] (Get-M365MapValue $default 'AutoForwardingMode')
            }
        } `
        -Set {
            param($Session, $Desired, $Current)
            Invoke-M365ExoCommand -Name 'Set-HostedOutboundSpamFilterPolicy' -Parameters @{
                Identity           = Get-M365MapValue $Desired 'name'
                AutoForwardingMode = Get-M365MapValue $Desired 'autoForwardingMode'
            }
        }
}

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
            # A per-client rename (MCA-16) rides in on the session, since the
            # ADR-0013 Get seam has no access to the profile's desired settings.
            $name = (Get-M365MapValue (Get-M365MapValue $Session 'NameOverride') 'MDO-4') ?? 'Default'
            $policies = @(Invoke-M365ExoCommand -Name 'Get-HostedOutboundSpamFilterPolicy')
            $match    = $policies | Where-Object { (Get-M365MapValue $_ 'Name') -eq $name } | Select-Object -First 1

            if (-not $match) {
                throw "outbound spam filter policy '$name' not found — every tenant ships 'Default', so this indicates a broken EXO session (or a -NameOverride pointing at a policy that does not exist)."
            }

            @{
                name               = [string] (Get-M365MapValue $match 'Name')
                autoForwardingMode = [string] (Get-M365MapValue $match 'AutoForwardingMode')
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

#requires -Version 7.6

function New-M365SecurityDefaultsControl {
    <#
    .SYNOPSIS
        Builds the ID-1 (Microsoft Entra security defaults) control handler — a
        Graph singleton on the ADR-0013 contract (MCA-22).

    .DESCRIPTION
        Security defaults is the tenant-wide on/off switch for Microsoft's baseline
        protections, and an ordering prerequisite: it must be OFF before Conditional
        Access enforces (they are mutually exclusive), so the CA controls (ID-2/ID-3)
        declare DependsOn 'ID-1', not the reverse — this control has no dependency.

        Mechanism (research 01 §4.5; verified against Microsoft Learn, graph-rest-1.0):
        the singleton `/policies/identitySecurityDefaultsEnforcementPolicy` — GET to
        read, PATCH `{ isEnabled }` to write — issued through the module Graph seam
        (ADR-0014). `Get` projects ONLY the config boolean, never the read-only
        id/displayName/description, so the canonical diff and any saved profile stay
        minimal and secret-free (NFR-1).

        Available on every tenant (no license gate) — RequiredCapabilities is
        just @('graph'), a connection-presence gate (MCA-21), not a license one.

        Internal helper; assembled into the provider set by Get-M365ControlRegistry.

    .OUTPUTS
        pscustomobject (PSTypeName 'M365Configurator.Control').
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    New-M365Control -Id 'ID-1' -Provider 'graph' -Shape 'singleton' `
        -Title 'Microsoft Entra security defaults' `
        -RequiredCapabilities @('graph') `
        -Get {
            param($Session)
            # Endpoint is inlined (not closed over): the engine invokes this seam
            # in its own scope, where an enclosing local would not be in scope.
            $current = Invoke-M365GraphRequest -Method GET -Uri 'v1.0/policies/identitySecurityDefaultsEnforcementPolicy'
            @{ isEnabled = [bool] (Get-M365MapValue $current 'isEnabled') }
        } `
        -Set {
            param($Session, $Desired, $Current)
            $target = [bool] (Get-M365MapValue $Desired 'isEnabled')
            Invoke-M365GraphRequest -Method PATCH `
                -Uri 'v1.0/policies/identitySecurityDefaultsEnforcementPolicy' `
                -Body @{ isEnabled = $target }
            @{ Id = 'ID-1'; Outcome = 'Applied'; isEnabled = $target }
        }
}

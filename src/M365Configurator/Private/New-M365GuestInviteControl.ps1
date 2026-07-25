#requires -Version 7.6

function New-M365GuestInviteControl {
    <#
    .SYNOPSIS
        Builds the SHR-1 (restrict who can invite guests) control handler —
        a Graph singleton on the ADR-0013 contract (MCA-28; SCuBA
        MS.AAD.8.2v1).

    .DESCRIPTION
        The simplest control in the v1 set: one flat field,
        `allowInvitesFrom`, on the same authorizationPolicy singleton CON-1
        (MCA-26) manages. The two controls declare disjoint keys — CON-1
        touches `defaultUserRolePermissions.*`, this touches
        `allowInvitesFrom` — so their diffs and PATCH bodies never overlap
        even though both target the same Graph resource.

        Enum values (verified against Microsoft Learn, graph-rest-1.0,
        2026-07-25): `none` | `adminsAndGuestInviters` |
        `adminsGuestInvitersAndAllMembers` | `everyone`.

        Available on every tenant; no DependsOn. RequiredCapabilities
        deliberately empty (MCA-21/S9 retrofits it).

        Internal helper; assembled into the provider set by
        Get-M365ControlRegistry.

    .OUTPUTS
        pscustomobject (PSTypeName 'M365Configurator.Control').
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    New-M365Control -Id 'SHR-1' -Provider 'graph' -Shape 'singleton' `
        -Title 'Restrict who can invite guests' `
        -RequiredCapabilities @('graph') `
        -Get {
            param($Session)
            $policy = Invoke-M365GraphRequest -Method GET -Uri 'v1.0/policies/authorizationPolicy'
            @{ allowInvitesFrom = [string] (Get-M365MapValue $policy 'allowInvitesFrom') }
        } `
        -Set {
            param($Session, $Desired, $Current)
            $target = [string] (Get-M365MapValue $Desired 'allowInvitesFrom')
            Invoke-M365GraphRequest -Method PATCH -Uri 'v1.0/policies/authorizationPolicy' `
                -Body @{ allowInvitesFrom = $target }
            @{ Id = 'SHR-1'; Outcome = 'Applied'; allowInvitesFrom = $target }
        }
}

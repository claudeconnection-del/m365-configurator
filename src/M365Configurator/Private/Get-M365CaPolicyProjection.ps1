#requires -Version 7.6

function Get-M365CaPolicyProjection {
    <#
    .SYNOPSIS
        Projects a raw Graph conditionalAccessPolicy object into the flat,
        control-owned allowlist vocabulary the CA controls compare and diff on
        (D2/D4; MCA-23/24).

    .DESCRIPTION
        Graph's conditionalAccessPolicy nests condition/grant fields several
        levels deep and carries read-only metadata (id, createdDateTime, …)
        alongside the config a profile actually declares. This flattens the
        config fields a CA control cares about into one map, and stashes the
        tenant-specific policy id for a later PATCH — that id is invisible to
        the default diff (extra keys in Current are ignored by
        Get-M365ControlChange), so it never leaks into a shareable profile.

        Every array is sorted so a profile's declared order never produces a
        false diff (D2). A part of the policy that is absent (e.g. no grant
        controls) projects to an empty array or $null, never throws.

        Internal helper, shared by every CA collection control; not exported.

    .OUTPUTS
        hashtable: id, displayName, state, clientAppTypes (sorted string[]),
        includeUsers (sorted), excludeUsers (sorted), includeApplications
        (sorted), grantOperator, grantControls (sorted).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] $Policy
    )

    $conditions = Get-M365MapValue $Policy 'conditions'
    $users      = Get-M365MapValue $conditions 'users'
    $apps       = Get-M365MapValue $conditions 'applications'
    $grant      = Get-M365MapValue $Policy 'grantControls'

    @{
        id                  = Get-M365MapValue $Policy 'id'
        displayName         = Get-M365MapValue $Policy 'displayName'
        state               = Get-M365MapValue $Policy 'state'
        clientAppTypes      = @(Get-M365MapValue $conditions 'clientAppTypes' | Sort-Object)
        includeUsers        = @(Get-M365MapValue $users 'includeUsers' | Sort-Object)
        excludeUsers        = @(Get-M365MapValue $users 'excludeUsers' | Sort-Object)
        includeApplications = @(Get-M365MapValue $apps 'includeApplications' | Sort-Object)
        grantOperator       = Get-M365MapValue $grant 'operator'
        grantControls       = @(Get-M365MapValue $grant 'builtInControls' | Sort-Object)
    }
}

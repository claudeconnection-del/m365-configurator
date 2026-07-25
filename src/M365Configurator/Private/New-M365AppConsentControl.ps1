#requires -Version 7.6

function New-M365AppConsentControl {
    <#
    .SYNOPSIS
        Builds the CON-1 (restrict user consent + app registration) control
        handler — a Graph singleton on the ADR-0013 contract (MCA-26; SCuBA
        MS.AAD.5.2v1 + 5.1v1).

    .DESCRIPTION
        Two fields on the authorizationPolicy singleton, both nested under
        `defaultUserRolePermissions` (verified against Microsoft Learn,
        graph-rest-1.0, 2026-07-25 — the v1.0 shape; beta uses a different,
        top-level, nonexistent-in-v1.0 property name, and the Entra "configure
        user consent" article's PowerShell tab has two documented bugs
        (wrong property name, doubled id prefix) — the Graph REST reference is
        the authority, not that article): `allowedToCreateApps` (bool) and
        `permissionGrantPoliciesAssigned` (string[]).

        Read-modify-write is MANDATORY for the consent-policy list.
        `permissionGrantPoliciesAssigned` also carries
        `managePermissionGrantsForOwnedResource.*` entries (e.g.
        `...DeveloperConsent`) that Microsoft's docs say must be preserved —
        a literal desired-state payload would silently strip developer-consent
        capability. So this control's vocabulary covers ONLY the
        `managePermissionGrantsForSelf.*` half (`userConsentPolicies`, D4):
        `Get` filters the live list down to just those entries (sorted); `Set`
        re-reads the live policy to recover whatever foreign entries the
        projection dropped, and rebuilds the full list as
        (foreign entries) + (desired self entries) — never a literal
        replacement of the whole array.

        `Set` only re-GETs when `userConsentPolicies` is actually declared in
        Desired; a profile touching only `allowedToCreateApps` costs one PATCH
        and no read.

        No custom Compare — the default map-diff (Get-M365ControlChange)
        already understands this control's flat, two-key vocabulary.

        Available on every tenant (no license gate); no DependsOn. Shares the
        authorizationPolicy endpoint with SHR-1 (S8) — the two controls
        declare disjoint keys, so their diffs and writes never collide.

        Internal helper; assembled into the provider set by
        Get-M365ControlRegistry.

    .OUTPUTS
        pscustomobject (PSTypeName 'M365Configurator.Control').
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    New-M365Control -Id 'CON-1' -Provider 'graph' -Shape 'singleton' `
        -Title 'Restrict user app consent and app registration' `
        -RequiredCapabilities @('graph') `
        -Get {
            param($Session)
            $policy = Invoke-M365GraphRequest -Method GET -Uri 'v1.0/policies/authorizationPolicy'
            $perms  = Get-M365MapValue $policy 'defaultUserRolePermissions'
            $assigned = @(Get-M365MapValue $perms 'permissionGrantPoliciesAssigned')

            @{
                allowedToCreateApps = [bool] (Get-M365MapValue $perms 'allowedToCreateApps')
                userConsentPolicies = @($assigned |
                    Where-Object { $_ -like 'managePermissionGrantsForSelf.*' } |
                    Sort-Object)
            }
        } `
        -Set {
            param($Session, $Desired, $Current)
            $updates = @{}

            if (Test-M365MapHasKey $Desired 'allowedToCreateApps') {
                $updates['allowedToCreateApps'] = [bool] (Get-M365MapValue $Desired 'allowedToCreateApps')
            }

            if (Test-M365MapHasKey $Desired 'userConsentPolicies') {
                # Read-modify-write: the projection lost the foreign
                # (managePermissionGrantsForOwnedResource.*) entries on
                # purpose, so recover them from a fresh read rather than
                # trusting $Current, which may be stale from plan time.
                $livePolicy = Invoke-M365GraphRequest -Method GET -Uri 'v1.0/policies/authorizationPolicy'
                $livePerms  = Get-M365MapValue $livePolicy 'defaultUserRolePermissions'
                $liveAssigned = @(Get-M365MapValue $livePerms 'permissionGrantPoliciesAssigned')
                $foreign = @($liveAssigned | Where-Object { $_ -notlike 'managePermissionGrantsForSelf.*' })

                $desiredSelf = @(Get-M365MapValue $Desired 'userConsentPolicies')
                $updates['permissionGrantPoliciesAssigned'] = @(@($foreign) + @($desiredSelf) | Sort-Object)
            }

            Invoke-M365GraphRequest -Method PATCH -Uri 'v1.0/policies/authorizationPolicy' `
                -Body @{ defaultUserRolePermissions = $updates }
            @{ Id = 'CON-1'; Outcome = 'Applied' }
        }
}

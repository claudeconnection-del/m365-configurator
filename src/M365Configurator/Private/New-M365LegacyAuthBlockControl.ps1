#requires -Version 7.6

function New-M365LegacyAuthBlockControl {
    <#
    .SYNOPSIS
        Builds the ID-2 (block legacy authentication) control handler — the
        first Conditional Access collection control on the ADR-0013 contract
        (MCA-23; SCuBA MS.AAD.1.1v1).

    .DESCRIPTION
        Legacy authentication protocols (Exchange ActiveSync, IMAP/POP/SMTP/
        Autodiscover) cannot perform MFA, so blocking them is the single
        highest-value Conditional Access policy (research 01 §4.1; Microsoft's
        own block-legacy-auth guidance). This control manages exactly ONE named
        CA policy (D2), matched by displayName since the ADR-0013 Get seam has
        no access to the profile's desired settings — the well-known name
        below is what the reference profile ships; per-client renames arrive
        with MCA-16 (S17), which threads the effective name through the session.

        Mechanism (verified against Microsoft Learn, graph-rest-1.0, 2026-07-25):
        `GET /identity/conditionalAccess/policies` to list, `POST` the same
        collection to create, `PATCH .../policies/{id}` to update — issued
        through the module Graph seam (ADR-0014). The projection
        (Get-M365CaPolicyProjection, shared with ID-3) flattens the nested
        conditions/grantControls into a control-owned vocabulary (D4) and
        stashes the tenant policy id for the PATCH; that id is invisible to the
        default diff.

        Compare is custom (D2): an absent policy is a Create (one Change per
        declared field, From $null) rather than the default engine's map-diff,
        which has no "absent" concept for a collection control. Otherwise it
        delegates to the canonical field-by-field diff (Get-M365ControlChange).

        DependsOn 'ID-1': security defaults must be off before Conditional
        Access enforces (they are mutually exclusive) — this control has no
        dependency of its own, so the ordering constraint lives on ID-2/ID-3.

        RequiredCapabilities is empty for now — MCA-21 (S9) retrofits
        @('graph') here once the session/capability model actually exists;
        adding it earlier would only make every plan involving this control
        silently Blocked in the interim (no session declares 'graph' yet).

        Internal helper; assembled into the provider set by
        Get-M365ControlRegistry.

    .OUTPUTS
        pscustomobject (PSTypeName 'M365Configurator.Control').
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    New-M365Control -Id 'ID-2' -Provider 'graph' -Shape 'collection' `
        -Title 'Block legacy authentication (Conditional Access)' `
        -DependsOn @('ID-1') `
        -RequiredCapabilities @('graph') `
        -Get {
            param($Session)
            # Endpoint and well-known name are inlined (not closed over): the
            # engine invokes this seam in its own scope, where an enclosing
            # local would not be in scope.
            $name = 'Block legacy authentication'
            $all = Invoke-M365GraphRequest -Method GET -Uri 'v1.0/identity/conditionalAccess/policies'
            $match = @(Get-M365MapValue $all 'value') |
                Where-Object { (Get-M365MapValue $_ 'displayName') -eq $name } |
                Select-Object -First 1
            if ($null -eq $match) { return $null }
            Get-M365CaPolicyProjection -Policy $match
        } `
        -Compare {
            param($Desired, $Current)
            if ($null -eq $Current) {
                # No existing policy: every declared field is a Create change,
                # From $null. Shape-agnostic key walk — profiles arrive as
                # dictionaries (YAML) or pscustomobjects (code-built), the same
                # duality Get-M365ControlChange handles.
                $keys =
                    if ($Desired -is [System.Collections.IDictionary]) { @($Desired.Keys) }
                    elseif ($Desired -is [System.Management.Automation.PSCustomObject]) { @($Desired.PSObject.Properties.Name) }
                    else { @() }
                $changes = @()
                foreach ($key in $keys) {
                    $changes += [pscustomobject]@{ Path = [string] $key; From = $null; To = (Get-M365MapValue $Desired ([string] $key)) }
                }
                return @{ Action = 'Create'; Changes = $changes }
            }
            $changes = @(Get-M365ControlChange -Desired $Desired -Current $Current)
            @{ Action = ($changes.Count -gt 0 ? 'Update' : 'NoChange'); Changes = $changes }
        } `
        -Set {
            param($Session, $Desired, $Current)
            $body = @{
                displayName = [string] (Get-M365MapValue $Desired 'displayName')
                state       = [string] (Get-M365MapValue $Desired 'state')
                conditions  = @{
                    clientAppTypes = @(Get-M365MapValue $Desired 'clientAppTypes' | Sort-Object)
                    users          = @{
                        includeUsers = @(Get-M365MapValue $Desired 'includeUsers' | Sort-Object)
                        excludeUsers = @(Get-M365MapValue $Desired 'excludeUsers' | Sort-Object)
                    }
                    applications   = @{ includeApplications = @(Get-M365MapValue $Desired 'includeApplications' | Sort-Object) }
                }
                grantControls = @{
                    operator        = [string] (Get-M365MapValue $Desired 'grantOperator')
                    builtInControls = @(Get-M365MapValue $Desired 'grantControls' | Sort-Object)
                }
            }
            if ($null -eq $Current) {
                Invoke-M365GraphRequest -Method POST -Uri 'v1.0/identity/conditionalAccess/policies' -Body $body
                @{ Id = 'ID-2'; Outcome = 'Applied'; Operation = 'Create'; displayName = $body.displayName }
            }
            else {
                $policyId = [string] (Get-M365MapValue $Current 'id')
                Invoke-M365GraphRequest -Method PATCH -Uri "v1.0/identity/conditionalAccess/policies/$policyId" -Body $body
                @{ Id = 'ID-2'; Outcome = 'Applied'; Operation = 'Update'; displayName = $body.displayName }
            }
        }
}

#requires -Version 7.6

function New-M365RequireMfaControl {
    <#
    .SYNOPSIS
        Builds the ID-3 (require MFA for all users) control handler — the
        second Conditional Access collection control on the ADR-0013 contract
        (MCA-24; SCuBA MS.AAD.3.2v2).

    .DESCRIPTION
        Requiring MFA for every user is the highest-value identity control
        after blocking legacy auth (research 01 §4.1; Microsoft's "MFA for all
        users" CA template). Structurally identical to ID-2
        (New-M365LegacyAuthBlockControl) — same mechanism, same projection
        (Get-M365CaPolicyProjection), same Compare shape — copied rather than
        further abstracted (D2): two similar ~60-line controls are easier to
        review independently than a premature shared control-builder.

        Matches exactly ONE named CA policy by displayName (the ADR-0013 Get
        seam has no access to the profile's desired settings); MCA-16 (S17)
        threads per-client renames through the session once it lands.

        Desired settings differ from ID-2 only in scope and grant: broad
        `clientAppTypes: [all]` (MFA applies to every client, not just legacy
        ones) and `grantControls: [mfa]`. A profile authoring MFA-for-all
        without first registering admins for MFA can lock people out — that is
        the profile's stated posture, previewed by dry-run; not this control's
        problem to prevent.

        DependsOn 'ID-1': security defaults must be off before Conditional
        Access enforces (mutually exclusive).

        RequiredCapabilities is @('graph') (MCA-21) — same connection-presence
        gate as ID-2.

        Internal helper; assembled into the provider set by
        Get-M365ControlRegistry.

    .OUTPUTS
        pscustomobject (PSTypeName 'M365Configurator.Control').
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    New-M365Control -Id 'ID-3' -Provider 'graph' -Shape 'collection' `
        -Title 'Require MFA for all users (Conditional Access)' `
        -DependsOn @('ID-1') `
        -RequiredCapabilities @('graph') `
        -Get {
            param($Session)
            # Endpoint and well-known name are inlined (not closed over): the
            # engine invokes this seam in its own scope, where an enclosing
            # local would not be in scope.
            $name = 'Require MFA for all users'
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
                # dictionaries (YAML) or pscustomobjects (code-built).
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
                @{ Id = 'ID-3'; Outcome = 'Applied'; Operation = 'Create'; displayName = $body.displayName }
            }
            else {
                $policyId = [string] (Get-M365MapValue $Current 'id')
                Invoke-M365GraphRequest -Method PATCH -Uri "v1.0/identity/conditionalAccess/policies/$policyId" -Body $body
                @{ Id = 'ID-3'; Outcome = 'Applied'; Operation = 'Update'; displayName = $body.displayName }
            }
        }
}

#requires -Version 7.6

function New-M365WeakMfaMethodsControl {
    <#
    .SYNOPSIS
        Builds the AM-2 (disable weak MFA methods) control handler — a Graph
        singleton on the ADR-0013 contract (MCA-25; SCuBA MS.AAD.3.5v2).

    .DESCRIPTION
        SMS, voice call, and email one-time-passcode are the weakest supported
        MFA methods (phishable, SIM-swap/PSTN-fraud exposed); disabling them
        pushes users toward the Authenticator app or a phishing-resistant
        method (research 01 §4.2).

        Mechanism (verified against Microsoft Learn, graph-rest-1.0,
        2026-07-25): the auth-methods policy singleton
        `/policies/authenticationMethodsPolicy` lists every method's
        configuration (`authenticationMethodConfigurations[]`, each
        `{ id, state }`) in one GET; each method is written independently via
        `PATCH .../authenticationMethodConfigurations/{method}`. Two casing
        traps documented by Microsoft: the method id in the GET/body is
        PascalCase (`Sms`, `Voice`, `Email`), but the documented PATCH URL
        segment is lowercase (`/sms`, `/voice`, `/email`) — this control uses
        fixed lowercase URL constants, never the id read back from Get, so it
        can't be broken by that mismatch. The PATCH body's `@odata.type` is
        mandatory (Microsoft's own examples fail without it).

        Get projects only the three weak methods to a flat, lowercase-keyed
        map (D3/D4) — Fido2, MicrosoftAuthenticator, and any other configured
        method are invisible to this control's diff. A method absent from the
        tenant's response (Get-M365MapValue) projects to $null rather than
        assuming enabled/disabled, so the default diff reports an honest
        "$null -> disabled" rather than silently passing.

        Set patches only the methods whose desired state actually differs
        from current, one PATCH per differing method — never rewrites a
        method that already matches.

        Available on every tenant (no license gate), so RequiredCapabilities
        is empty; no DependsOn (a singleton unrelated to ID-1/CA ordering).

        Internal helper; assembled into the provider set by
        Get-M365ControlRegistry.

    .OUTPUTS
        pscustomobject (PSTypeName 'M365Configurator.Control').
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    New-M365Control -Id 'AM-2' -Provider 'graph' -Shape 'singleton' `
        -Title 'Disable weak MFA methods (SMS / Voice / Email OTP)' `
        -RequiredCapabilities @('graph') `
        -Get {
            param($Session)
            $policy = Invoke-M365GraphRequest -Method GET -Uri 'v1.0/policies/authenticationMethodsPolicy'
            $configs = @(Get-M365MapValue $policy 'authenticationMethodConfigurations')

            $byId = @{}
            foreach ($config in $configs) {
                $byId[[string] (Get-M365MapValue $config 'id')] = Get-M365MapValue $config 'state'
            }

            @{
                sms   = if ($byId.ContainsKey('Sms'))   { $byId['Sms'] }   else { $null }
                voice = if ($byId.ContainsKey('Voice')) { $byId['Voice'] } else { $null }
                email = if ($byId.ContainsKey('Email')) { $byId['Email'] } else { $null }
            }
        } `
        -Set {
            param($Session, $Desired, $Current)
            # Keyed by the control's own flat vocabulary: [lowercase URL segment, @odata.type].
            # The URL segment is a fixed constant, deliberately NOT the PascalCase id Get reads
            # back (Microsoft documents the PATCH path as lowercase while id/body use PascalCase).
            $methods = [ordered]@{
                sms   = @('sms',   '#microsoft.graph.smsAuthenticationMethodConfiguration')
                voice = @('voice', '#microsoft.graph.voiceAuthenticationMethodConfiguration')
                email = @('email', '#microsoft.graph.emailAuthenticationMethodConfiguration')
            }

            $patched = [System.Collections.Generic.List[string]]::new()
            foreach ($key in $methods.Keys) {
                if (-not (Test-M365MapHasKey $Desired $key)) { continue }
                $want = Get-M365MapValue $Desired $key
                $have = Get-M365MapValue $Current $key
                if ($want -eq $have) { continue }

                $segment, $odataType = $methods[$key]
                Invoke-M365GraphRequest -Method PATCH `
                    -Uri "v1.0/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/$segment" `
                    -Body @{ '@odata.type' = $odataType; state = $want }
                $patched.Add($key)
            }

            @{ Id = 'AM-2'; Outcome = 'Applied'; Patched = @($patched.ToArray()) }
        }
}

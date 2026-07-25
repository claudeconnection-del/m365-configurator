#requires -Version 7.6
<#
    Tests for the AM-2 disable-weak-MFA-methods control (MCA-25; SCuBA
    MS.AAD.3.5v2) — a Graph singleton on the ADR-0013 contract (D3). Exercised
    via the registry, mirroring the ID-1 convention. The Graph seam
    (Invoke-M365GraphRequest) is mocked module-scoped, so these are
    tenant-free.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force
}

Describe 'Get-M365ControlRegistry — AM-2' {

    It 'registers AM-2 as a graph singleton with no DependsOn' {
        $am2 = Get-M365ControlRegistry | Where-Object { $_.Id -eq 'AM-2' }

        $am2            | Should -Not -BeNullOrEmpty
        $am2.Provider   | Should -Be 'graph'
        $am2.Shape      | Should -Be 'singleton'
        @($am2.DependsOn).Count | Should -Be 0
        $am2.RequiredCapabilities | Should -Be @('graph')
    }
}

Describe 'AM-2 disable-weak-MFA-methods control (wired via the registry)' {

    BeforeAll {
        $script:am2 = @(Get-M365ControlRegistry | Where-Object { $_.Id -eq 'AM-2' })[0]
    }

    It 'Get reads the auth methods policy once and projects exactly sms/voice/email states (extra methods excluded)' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator {
            @{
                authenticationMethodConfigurations = @(
                    @{ id = 'Sms'; state = 'enabled' }
                    @{ id = 'Voice'; state = 'disabled' }
                    @{ id = 'Email'; state = 'enabled' }
                    @{ id = 'Fido2'; state = 'enabled' }
                    @{ id = 'MicrosoftAuthenticator'; state = 'enabled' }
                )
            }
        }

        $current = & $script:am2.Get $null

        Should -Invoke Invoke-M365GraphRequest -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Uri -eq 'v1.0/policies/authenticationMethodsPolicy'
        }
        @($current.Keys | Sort-Object) | Should -Be @('email', 'sms', 'voice')
        $current['sms']   | Should -Be 'enabled'
        $current['voice'] | Should -Be 'disabled'
        $current['email'] | Should -Be 'enabled'
    }

    It 'Get projects $null for a method id absent from the fixture' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator {
            @{ authenticationMethodConfigurations = @(@{ id = 'Sms'; state = 'enabled' }) }
        }

        $current = & $script:am2.Get $null

        $current['sms']   | Should -Be 'enabled'
        $current['voice']  | Should -BeNullOrEmpty
        $current['email']  | Should -BeNullOrEmpty
    }

    It 'Set PATCHes all three methods when all three differ, each to the right lowercase URI with the right @odata.type' {
        $script:patchedUris = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator {
            param($Method, $Uri, $Body)
            $script:patchedUris.Add($Uri)
        }
        $desired = @{ sms = 'disabled'; voice = 'disabled'; email = 'disabled' }
        $current = @{ sms = 'enabled'; voice = 'enabled'; email = 'enabled' }

        & $script:am2.Set $null $desired $current

        Should -Invoke Invoke-M365GraphRequest -ModuleName M365Configurator -Times 3 -Exactly
        Should -Invoke Invoke-M365GraphRequest -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -eq 'v1.0/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/sms' -and
            $Body['@odata.type'] -eq '#microsoft.graph.smsAuthenticationMethodConfiguration' -and $Body['state'] -eq 'disabled'
        }
        Should -Invoke Invoke-M365GraphRequest -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -eq 'v1.0/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/voice' -and
            $Body['@odata.type'] -eq '#microsoft.graph.voiceAuthenticationMethodConfiguration' -and $Body['state'] -eq 'disabled'
        }
        Should -Invoke Invoke-M365GraphRequest -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -eq 'v1.0/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/email' -and
            $Body['@odata.type'] -eq '#microsoft.graph.emailAuthenticationMethodConfiguration' -and $Body['state'] -eq 'disabled'
        }
        # Lowercase URL segments are fixed constants, never the PascalCase id read
        # back — -cmatch because PowerShell's plain -match is case-insensitive and
        # would silently accept a PascalCase regression here.
        foreach ($uri in $script:patchedUris) { ($uri -cmatch '/(Sms|Voice|Email)$') | Should -BeFalse }
    }

    It 'Set PATCHes only sms when only sms differs (voice/email untouched)' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator { }
        $desired = @{ sms = 'disabled'; voice = 'disabled'; email = 'disabled' }
        $current = @{ sms = 'enabled'; voice = 'disabled'; email = 'disabled' }

        & $script:am2.Set $null $desired $current

        Should -Invoke Invoke-M365GraphRequest -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'v1.0/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/sms'
        }
    }
}

Describe 'AM-2 end-to-end through Get-M365Plan' {

    It 'plans Update with the one Change when sms is enabled but desired disabled' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator {
            @{
                authenticationMethodConfigurations = @(
                    @{ id = 'Sms'; state = 'enabled' }
                    @{ id = 'Voice'; state = 'disabled' }
                    @{ id = 'Email'; state = 'disabled' }
                )
            }
        }

        $profile = [ordered]@{
            schemaVersion = '1.0'; name = 'x'; framework = 'X'; frameworkVersion = '1.0'
            controls = @(
                [ordered]@{ id = 'AM-2'; framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'
                    settings = @{ sms = 'disabled'; voice = 'disabled'; email = 'disabled' } }
            )
        }

        $plan = Get-M365Plan -Profile $profile -Session @{ Capabilities = @('graph') }
        $am2  = $plan.Items | Where-Object { $_.Id -eq 'AM-2' }

        $am2.Action | Should -Be 'Update'
        @($am2.Changes).Count | Should -Be 1
        $am2.Changes[0].Path | Should -Be 'sms'
        $am2.Changes[0].To   | Should -Be 'disabled'
    }
}

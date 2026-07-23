#requires -Version 7.0
<#
    Tests for Test-M365Profile — validation of a profile against schema v1
    (MCA-13; FR-5, NFR-1). The schema is config-only: each control is tagged with
    its framework control ID and the pinned framework version, and NO credential-
    shaped field may appear anywhere (that is the guard MCA-15's import relies on
    to reject credential-bearing files loudly).

    Test-M365Profile is a pure validator: it returns { Valid; Errors } rather than
    throwing, so callers (import/apply) decide how loud to be. It never mutates.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force

    $script:validProfile = [ordered]@{
        schemaVersion    = '1.0'
        name             = 'security-baseline'
        framework        = 'SCuBA'
        frameworkVersion = '1.5.0'
        controls         = @(
            [ordered]@{ id = 'MS.AAD.1.1'; framework = 'SCuBA'; frameworkVersion = '1.5.0'; provider = 'graph'; name = 'Block legacy auth'; settings = [ordered]@{ state = 'enabled' } }
            [ordered]@{ id = 'MS.EXO.4.1'; framework = 'SCuBA'; frameworkVersion = '1.5.0'; provider = 'exo';   settings = [ordered]@{ enabled = $true } }
        )
    }
}

Describe 'Test-M365Profile' {

    It 'accepts a well-formed v1 profile' {
        $result = Test-M365Profile -Profile $script:validProfile

        $result.Valid  | Should -BeTrue
        $result.Errors | Should -BeNullOrEmpty
    }

    It 'rejects a profile missing required top-level fields' {
        $bad = [ordered]@{ name = 'x'; controls = @() }   # no schemaVersion/framework/frameworkVersion

        $result = Test-M365Profile -Profile $bad

        $result.Valid  | Should -BeFalse
        ($result.Errors -join '; ') | Should -Match 'schemaVersion'
        ($result.Errors -join '; ') | Should -Match 'frameworkVersion'
    }

    It 'rejects a control missing its framework ID or pinned framework version' {
        $bad = [ordered]@{
            schemaVersion = '1.0'; name = 'x'; framework = 'SCuBA'; frameworkVersion = '1.5.0'
            controls = @( [ordered]@{ provider = 'graph'; settings = [ordered]@{ a = 1 } } )   # no id / frameworkVersion
        }

        $result = Test-M365Profile -Profile $bad

        $result.Valid | Should -BeFalse
        ($result.Errors -join '; ') | Should -Match 'id'
    }

    It 'rejects a control whose required field is present but empty/null' {
        $bad = [ordered]@{
            schemaVersion = '1.0'; name = 'x'; framework = 'SCuBA'; frameworkVersion = '1.5.0'
            controls = @( [ordered]@{ id = 'MS.AAD.1.1'; framework = 'SCuBA'; frameworkVersion = '1.5.0'; provider = $null; settings = [ordered]@{ a = 1 } } )
        }

        $result = Test-M365Profile -Profile $bad

        $result.Valid | Should -BeFalse
        ($result.Errors -join '; ') | Should -Match 'provider'
    }

    It 'rejects an unknown provider on a control' {
        $bad = [ordered]@{
            schemaVersion = '1.0'; name = 'x'; framework = 'SCuBA'; frameworkVersion = '1.5.0'
            controls = @( [ordered]@{ id = 'MS.AAD.1.1'; framework = 'SCuBA'; frameworkVersion = '1.5.0'; provider = 'sharepoint'; settings = [ordered]@{ a = 1 } } )
        }

        $result = Test-M365Profile -Profile $bad

        $result.Valid | Should -BeFalse
        ($result.Errors -join '; ') | Should -Match 'provider'
    }

    It 'rejects a profile carrying a credential-shaped field anywhere (config-only; NFR-1)' {
        $leaky = [ordered]@{
            schemaVersion = '1.0'; name = 'x'; framework = 'SCuBA'; frameworkVersion = '1.5.0'
            controls = @(
                [ordered]@{ id = 'MS.AAD.1.1'; framework = 'SCuBA'; frameworkVersion = '1.5.0'; provider = 'graph'; settings = [ordered]@{ clientSecret = 'oops' } }
            )
        }

        $result = Test-M365Profile -Profile $leaky

        $result.Valid | Should -BeFalse
        ($result.Errors -join '; ') | Should -Match '(?i)credential|secret'
    }

    It 'flags several credential-shaped key names (password, token, thumbprint, apiKey)' {
        foreach ($key in 'password', 'accessToken', 'certificateThumbprint', 'apiKey') {
            $leaky = [ordered]@{
                schemaVersion = '1.0'; name = 'x'; framework = 'SCuBA'; frameworkVersion = '1.5.0'
                controls = @( [ordered]@{ id = 'MS.AAD.1.1'; framework = 'SCuBA'; frameworkVersion = '1.5.0'; provider = 'graph'; settings = [ordered]@{ $key = 'v' } } )
            }
            (Test-M365Profile -Profile $leaky).Valid | Should -BeFalse -Because "$key should be rejected"
        }
    }

    It 'does not mutate the profile it validates' {
        $before = ConvertTo-M365CanonicalJson $script:validProfile
        $null   = Test-M365Profile -Profile $script:validProfile
        $after  = ConvertTo-M365CanonicalJson $script:validProfile

        $after | Should -Be $before
    }
}

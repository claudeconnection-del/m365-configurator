#requires -Version 7.6
<#
    Tests for Set-M365ProfileNameOverride (MCA-16; FR-7 name remapping, D9)
    — per-client renames of name-scoped controls (ID-2/ID-3's displayName,
    MDO-4's name) applied to a copy of the profile, without mutating the
    caller's original profile object. A private helper, so exercised via
    InModuleScope. The companion mechanism — threading the effective name
    through $Session.NameOverride so a name-scoped control's Get seam can
    still find the (renamed) tenant object — is exercised end-to-end in
    tests/Invoke-M365DryRun.Tests.ps1 and the three name-scoped control test
    files.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force
}

Describe 'Set-M365ProfileNameOverride' {

    It 'rewrites ID-2''s displayName without mutating the source profile object' {
        InModuleScope M365Configurator {
            $profile = [ordered]@{
                schemaVersion = '1.0'; name = 'baseline'; framework = 'X'; frameworkVersion = '1.0'
                controls = @(
                    [ordered]@{ id = 'ID-2'; framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'
                        settings = [ordered]@{ displayName = 'Block legacy authentication'; state = 'enabled' } }
                )
            }

            $result = Set-M365ProfileNameOverride -InputObject $profile -NameOverride @{ 'ID-2' = 'Contoso - Block legacy auth' }

            # Original untouched.
            $profile.controls[0].settings.displayName | Should -Be 'Block legacy authentication'

            $rewrittenControl = $result.Profile.controls | Where-Object { $_.id -eq 'ID-2' }
            $rewrittenControl.settings.displayName | Should -Be 'Contoso - Block legacy auth'
            $rewrittenControl.settings.state       | Should -Be 'enabled'   # untouched sibling field
        }
    }

    It 'rewrites MDO-4''s settings.name AND the control''s top-level name field' {
        InModuleScope M365Configurator {
            $profile = [ordered]@{
                schemaVersion = '1.0'; name = 'baseline'; framework = 'X'; frameworkVersion = '1.0'
                controls = @(
                    [ordered]@{ id = 'MDO-4'; name = 'Block external auto-forwarding'; framework = 'X'; frameworkVersion = '1.0'; provider = 'exo'
                        settings = [ordered]@{ name = 'Default'; autoForwardingMode = 'Off' } }
                )
            }

            $result = Set-M365ProfileNameOverride -InputObject $profile -NameOverride @{ 'MDO-4' = 'Contoso Outbound Spam' }
            $rewritten = $result.Profile.controls | Where-Object { $_.id -eq 'MDO-4' }

            $rewritten.settings.name           | Should -Be 'Contoso Outbound Spam'
            $rewritten.name                    | Should -Be 'Contoso Outbound Spam'
            $rewritten.settings.autoForwardingMode | Should -Be 'Off'   # untouched sibling field
        }
    }

    It 'leaves controls not named in the override map untouched (same values, still present)' {
        InModuleScope M365Configurator {
            $profile = [ordered]@{
                schemaVersion = '1.0'; name = 'baseline'; framework = 'X'; frameworkVersion = '1.0'
                controls = @(
                    [ordered]@{ id = 'ID-1'; framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'; settings = [ordered]@{ isEnabled = $false } }
                    [ordered]@{ id = 'ID-2'; framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'; settings = [ordered]@{ displayName = 'Block legacy authentication' } }
                )
            }

            $result = Set-M365ProfileNameOverride -InputObject $profile -NameOverride @{ 'ID-2' = 'Renamed' }

            $id1 = $result.Profile.controls | Where-Object { $_.id -eq 'ID-1' }
            $id1.settings.isEnabled | Should -BeFalse
        }
    }

    It 'throws on a control id with no name-bearing key registered (NFR-6)' {
        InModuleScope M365Configurator {
            $profile = [ordered]@{
                schemaVersion = '1.0'; name = 'baseline'; framework = 'X'; frameworkVersion = '1.0'
                controls = @( [ordered]@{ id = 'ID-1'; framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'; settings = @{ isEnabled = $false } } )
            }

            { Set-M365ProfileNameOverride -InputObject $profile -NameOverride @{ 'ID-1' = 'Nope' } } | Should -Throw '*ID-1*'
        }
    }

    It 'throws when a name-scoped override id is not present among the profile''s controls (NFR-6: no silent no-op)' {
        InModuleScope M365Configurator {
            $profile = [ordered]@{
                schemaVersion = '1.0'; name = 'baseline'; framework = 'X'; frameworkVersion = '1.0'
                controls = @( [ordered]@{ id = 'ID-1'; framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'; settings = @{ isEnabled = $false } } )
            }

            # MDO-4 is a known name-scoped id, but this profile never declares it.
            { Set-M365ProfileNameOverride -InputObject $profile -NameOverride @{ 'MDO-4' = 'Contoso Outbound Spam' } } | Should -Throw '*MDO-4*'
        }
    }

    It 'returns the effective-name map alongside the rewritten profile' {
        InModuleScope M365Configurator {
            $profile = [ordered]@{
                schemaVersion = '1.0'; name = 'baseline'; framework = 'X'; frameworkVersion = '1.0'
                controls = @( [ordered]@{ id = 'ID-3'; framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'; settings = @{ displayName = 'Require MFA for all users' } } )
            }
            $map = @{ 'ID-3' = 'Contoso - Require MFA' }

            $result = Set-M365ProfileNameOverride -InputObject $profile -NameOverride $map

            $result.NameOverride['ID-3'] | Should -Be 'Contoso - Require MFA'
        }
    }
}

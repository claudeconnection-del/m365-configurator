#requires -Version 7.6
<#
    Tests for Save-M365Profile — persist the current in-scope tenant configuration
    as a named, versioned, config-only profile (MCA-14; FR-5; ADR-0008/0009).

    The tenant read is an injected seam (-ControlReader): the real Graph/EXO
    providers (MCA-4/5) are not built yet, and injecting keeps this unit-testable
    without a tenant. The file write is an injected seam too (-Writer), so tests
    assert content and path without touching disk.

    Load-bearing guarantees: the assembled profile is validated (config-only —
    a credential read back from a tenant must never be written; NFR-1), and a
    re-save of unchanged state is byte-identical (clean diffs; NFR-9).
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force

    # A reader standing in for "current in-scope tenant state": returns control
    # descriptors (id/provider/settings, optional name). Framework + pinned
    # version are stamped by Save from its parameters.
    $script:tenantReader = {
        @(
            [ordered]@{ id = 'MS.AAD.1.1'; provider = 'graph'; name = 'Block legacy auth'; settings = [ordered]@{ state = 'enabled' } }
            [ordered]@{ id = 'MS.EXO.4.1'; provider = 'exo';   settings = [ordered]@{ enabled = $true } }
        )
    }
}

Describe 'Save-M365Profile' {

    BeforeEach { $script:written = $null }

    It 'assembles a valid v1 profile from the tenant reader and writes YAML' {
        $result = Save-M365Profile -Name 'baseline' -Framework 'SCuBA' -FrameworkVersion '1.5.0' `
            -ControlReader $script:tenantReader `
            -Writer { param($FilePath, $Content) $script:written = [pscustomobject]@{ Path = $FilePath; Content = $Content } }

        $script:written | Should -Not -BeNullOrEmpty
        $reparsed = ConvertFrom-M365ProfileYaml $script:written.Content
        (Test-M365Profile -Profile $reparsed).Valid | Should -BeTrue
        @($reparsed.controls).Count | Should -Be 2
        $result.Path | Should -Match 'baseline\.ya?ml$'
    }

    It 'stamps the framework and pinned framework version on every control' {
        $result = Save-M365Profile -Name 'baseline' -Framework 'SCuBA' -FrameworkVersion '1.5.0' `
            -ControlReader $script:tenantReader `
            -Writer { param($FilePath, $Content) $script:written = $Content }

        foreach ($control in $result.Profile.controls) {
            $control.framework        | Should -Be 'SCuBA'
            $control.frameworkVersion | Should -Be '1.5.0'
        }
    }

    It 'is byte-stable: re-saving unchanged tenant state produces identical content (NFR-9)' {
        $first = $null; $second = $null
        Save-M365Profile -Name 'baseline' -Framework 'SCuBA' -FrameworkVersion '1.5.0' `
            -ControlReader $script:tenantReader -Writer { param($p, $c) $script:first = $c } | Out-Null
        Save-M365Profile -Name 'baseline' -Framework 'SCuBA' -FrameworkVersion '1.5.0' `
            -ControlReader $script:tenantReader -Writer { param($p, $c) $script:second = $c } | Out-Null

        $script:first | Should -Be $script:second
    }

    It 'refuses to write a profile carrying a credential read back from the tenant (NFR-1)' {
        $leakyReader = {
            @( [ordered]@{ id = 'MS.AAD.1.1'; provider = 'graph'; settings = [ordered]@{ clientSecret = 'leaked-from-tenant' } } )
        }

        { Save-M365Profile -Name 'baseline' -Framework 'SCuBA' -FrameworkVersion '1.5.0' `
            -ControlReader $leakyReader -Writer { param($p, $c) $script:written = $c } } |
            Should -Throw -ExpectedMessage '*credential*'

        $script:written | Should -BeNullOrEmpty   # nothing written on failure
    }

    It 'fails loud if the tenant reader yields a control missing required fields (NFR-6)' {
        $badReader = { @( [ordered]@{ id = 'MS.AAD.1.1'; settings = [ordered]@{ a = 1 } } ) }   # no provider

        { Save-M365Profile -Name 'baseline' -Framework 'SCuBA' -FrameworkVersion '1.5.0' `
            -ControlReader $badReader -Writer { param($p, $c) $script:written = $c } } |
            Should -Throw
        $script:written | Should -BeNullOrEmpty
    }

    It 'derives the default profile path from the name and profile directory' {
        $result = Save-M365Profile -Name 'security-baseline' -Framework 'SCuBA' -FrameworkVersion '1.5.0' `
            -ControlReader $script:tenantReader -ProfileDirectory '/tmp/profiles' `
            -Writer { param($FilePath, $Content) $script:written = $FilePath }

        $script:written | Should -Be (Join-Path '/tmp/profiles' 'security-baseline.yaml')
    }

    It 'returns a secret-free result naming the profile and path' {
        $result = Save-M365Profile -Name 'baseline' -Framework 'SCuBA' -FrameworkVersion '1.5.0' `
            -ControlReader $script:tenantReader -Writer { param($p, $c) }

        $result.Name | Should -Be 'baseline'
        $result.PSObject.Properties.Name | Should -Contain 'Path'
        $result.PSObject.Properties.Name | Should -Contain 'Profile'
        ($result | Out-String) | Should -Not -Match 'clientSecret|password'
    }
}

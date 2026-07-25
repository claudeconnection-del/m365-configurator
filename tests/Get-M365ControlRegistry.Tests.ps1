#requires -Version 7.6
<#
    Tests for Get-M365ControlRegistry (the ADR-0013 registry seam) and, through the
    control it returns, the ID-1 security-defaults Graph control (MCA-22). The Graph
    seam (Invoke-M365GraphRequest) is mocked, so these are tenant-free.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force
}

Describe 'Get-M365ControlRegistry' {

    It 'returns control handlers, each tagged with the control type name' {
        $controls = @(Get-M365ControlRegistry)

        $controls.Count | Should -BeGreaterThan 0
        foreach ($control in $controls) {
            $control.PSObject.TypeNames | Should -Contain 'M365Configurator.Control'
        }
    }

    It 'exposes unique control ids (no silent shadowing)' {
        $ids = @(Get-M365ControlRegistry).Id
        ($ids | Sort-Object -Unique).Count | Should -Be $ids.Count
    }

    It 'includes the ID-1 security-defaults graph singleton' {
        $id1 = Get-M365ControlRegistry | Where-Object { $_.Id -eq 'ID-1' }

        $id1          | Should -Not -BeNullOrEmpty
        $id1.Provider | Should -Be 'graph'
        $id1.Shape    | Should -Be 'singleton'
    }
}

Describe 'ID-1 security-defaults control (wired via the registry)' {

    BeforeAll {
        $script:id1 = @(Get-M365ControlRegistry | Where-Object { $_.Id -eq 'ID-1' })[0]
    }

    It 'Get reads the security-defaults singleton and projects only isEnabled (bool, secret-free)' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator {
            @{ isEnabled = $true; id = 'x'; displayName = 'Security Defaults'; description = 'd'; '@odata.context' = 'c' }
        }

        $current = & $script:id1.Get $null

        Should -Invoke Invoke-M365GraphRequest -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Uri -match 'identitySecurityDefaultsEnforcementPolicy'
        }
        @($current.Keys)      | Should -Be @('isEnabled')   # only the config field, no read-only metadata
        $current['isEnabled'] | Should -BeOfType [bool]
        $current['isEnabled'] | Should -BeTrue
    }

    It 'Get coerces an absent enablement flag to [bool] $false' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator { @{ id = 'x' } }

        $current = & $script:id1.Get $null

        $current['isEnabled'] | Should -BeOfType [bool]
        $current['isEnabled'] | Should -BeFalse
    }

    It 'Set PATCHes the desired boolean to the singleton endpoint' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator { }

        & $script:id1.Set $null @{ isEnabled = $false } @{ isEnabled = $true }

        Should -Invoke Invoke-M365GraphRequest -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PATCH' -and
            $Uri -match 'identitySecurityDefaultsEnforcementPolicy' -and
            $Body['isEnabled'] -eq $false
        }
    }
}

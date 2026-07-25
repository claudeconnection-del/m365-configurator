#requires -Version 7.6
<#
    Tests for Get-M365RequiredModule — the single source of truth for the
    PowerShell modules m365-configurator depends on and their pinned versions
    (FR-1, NFR-7). See Jira MCA-2.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force
}

Describe 'Get-M365RequiredModule' {

    It 'returns the required modules, each with a pinned, parseable version' {
        $modules = Get-M365RequiredModule

        $modules | Should -Not -BeNullOrEmpty
        $modules.Name | Should -Contain 'Microsoft.Graph.Authentication'
        $modules.Name | Should -Contain 'ExchangeOnlineManagement'

        foreach ($m in $modules) {
            $m.Name    | Should -Not -BeNullOrEmpty
            $m.Version | Should -Not -BeNullOrEmpty
            { [version] $m.Version } | Should -Not -Throw
        }
    }

    It 'declares each pinned version exactly once (no duplicate module names)' {
        $names = (Get-M365RequiredModule).Name
        ($names | Sort-Object -Unique).Count | Should -Be $names.Count
    }

    It 'pins each version to a precise 3-part release (not a floating major.minor)' {
        # A deliberate pin is e.g. 2.38.1 (Build >= 0); a floating '2.38' has
        # Build = -1. This keeps "upgrades are deliberate" (NFR-7) honest.
        foreach ($m in Get-M365RequiredModule) {
            ([version] $m.Version).Build | Should -BeGreaterOrEqual 0
        }
    }
}

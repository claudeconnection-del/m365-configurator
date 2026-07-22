#requires -Version 7.0
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
}

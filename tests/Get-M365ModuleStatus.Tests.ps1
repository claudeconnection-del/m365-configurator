#requires -Version 7.0
<#
    Tests for Get-M365ModuleStatus — the pure decision logic that decides, for
    each required module, whether an installed version satisfies the pin. This
    is the detection + idempotency core of MCA-2 (FR-1, NFR-7).

    The "installed modules" lookup is injected so this logic is testable without
    touching the machine's real module state or the PowerShell Gallery.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force

    # A required set fixed for the tests, independent of the real pinned list.
    $script:required = @(
        [pscustomobject]@{ Name = 'Foo.Bar'; Version = '1.2.3'; Reason = 'test fixture' }
    )
}

Describe 'Get-M365ModuleStatus' {

    It 'reports a required module that is not installed as not satisfied' {
        $lookup = { param($Name) @() }   # nothing installed

        $status = Get-M365ModuleStatus -Required $script:required -InstalledLookup $lookup

        $status | Should -HaveCount 1
        $status[0].Name             | Should -Be 'Foo.Bar'
        $status[0].RequiredVersion  | Should -Be '1.2.3'
        $status[0].Installed        | Should -BeFalse
        $status[0].Satisfied        | Should -BeFalse
        $status[0].InstalledVersion | Should -BeNullOrEmpty
    }

    It 'reports satisfied when an installed version meets the pin exactly' {
        $lookup = { param($Name) @([pscustomobject]@{ Name = $Name; Version = [version] '1.2.3' }) }

        $status = Get-M365ModuleStatus -Required $script:required -InstalledLookup $lookup

        $status[0].Installed        | Should -BeTrue
        $status[0].Satisfied        | Should -BeTrue
        $status[0].InstalledVersion | Should -Be '1.2.3'
    }

    It 'reports installed-but-not-satisfied when only an older version is present' {
        $lookup = { param($Name) @([pscustomobject]@{ Name = $Name; Version = [version] '1.0.0' }) }

        $status = Get-M365ModuleStatus -Required $script:required -InstalledLookup $lookup

        $status[0].Installed        | Should -BeTrue
        $status[0].Satisfied        | Should -BeFalse
        $status[0].InstalledVersion | Should -Be '1.0.0'
    }

    It 'uses the highest installed version when several are present' {
        $lookup = { param($Name) @(
            [pscustomobject]@{ Name = $Name; Version = [version] '1.0.0' }
            [pscustomobject]@{ Name = $Name; Version = [version] '2.5.0' }
        ) }

        $status = Get-M365ModuleStatus -Required $script:required -InstalledLookup $lookup

        $status[0].InstalledVersion | Should -Be '2.5.0'
        $status[0].Satisfied        | Should -BeTrue   # 2.5.0 >= pinned 1.2.3
    }
}

#requires -Version 7.6
<#
    Tests for Get-M365ModuleRemediation — the "self-healing" offer. Instead of
    just reporting a missing/outdated module, the app turns each unsatisfied
    status into an actionable, consent-ready remediation: what's missing, where
    it lives, and the exact (non-elevating) command to fix it. This mirrors the
    app's dry-run -> gated-apply philosophy for its own dependencies. See MCA-2.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force
}

Describe 'Get-M365ModuleRemediation' {

    It 'offers to install a missing module from the PowerShell Gallery at user scope' {
        $status = @(
            [pscustomobject]@{ Name = 'Foo.Bar'; RequiredVersion = '1.2.3'; Installed = $false; InstalledVersion = $null; Satisfied = $false }
        )

        $plan = Get-M365ModuleRemediation -Status $status

        $plan | Should -HaveCount 1
        $plan[0].Name           | Should -Be 'Foo.Bar'
        $plan[0].Action         | Should -Be 'Install'
        $plan[0].Source         | Should -Be 'PSGallery'
        $plan[0].SourceLocation | Should -Match 'powershellgallery\.com'
        $plan[0].Command        | Should -Match 'RequiredVersion 1\.2\.3'
        $plan[0].Command        | Should -Match 'CurrentUser'
        $plan[0].Command        | Should -Not -Match 'AllUsers'   # never elevate (NFR)
        $plan[0].Offer          | Should -Match 'Gallery'
    }

    It 'offers to upgrade a module that is installed but older than the pin' {
        $status = @(
            [pscustomobject]@{ Name = 'Foo.Bar'; RequiredVersion = '1.2.3'; Installed = $true; InstalledVersion = '1.0.0'; Satisfied = $false }
        )

        $plan = Get-M365ModuleRemediation -Status $status

        $plan | Should -HaveCount 1
        $plan[0].Action | Should -Be 'Upgrade'
        $plan[0].Offer  | Should -Match '1\.0\.0'   # names the current version
        $plan[0].Offer  | Should -Match '1\.2\.3'   # ...and the required one
    }

    It 'offers nothing when every module is already satisfied (nothing to heal)' {
        $status = @(
            [pscustomobject]@{ Name = 'Foo.Bar'; RequiredVersion = '1.2.3'; Installed = $true; InstalledVersion = '1.2.3'; Satisfied = $true }
            [pscustomobject]@{ Name = 'Baz.Qux'; RequiredVersion = '2.0.0'; Installed = $true; InstalledVersion = '2.1.0'; Satisfied = $true }
        )

        $plan = @(Get-M365ModuleRemediation -Status $status)

        $plan | Should -HaveCount 0
    }
}

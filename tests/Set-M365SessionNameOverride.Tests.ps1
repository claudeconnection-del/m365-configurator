#requires -Version 7.6
<#
    Tests for Set-M365SessionNameOverride (MCA-16; FR-7, D9) — the shared
    session-shallow-copy helper the three -NameOverride entry points
    (Invoke-M365DryRun/Apply, Get-M365Drift) all use, factored out to avoid
    tripling the hashtable/pscustomobject-shape-handling logic (review
    finding on commit 3242e7c). A private helper, so exercised via
    InModuleScope.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force
}

Describe 'Set-M365SessionNameOverride' {

    It 'augments a hashtable session without mutating the original' {
        InModuleScope M365Configurator {
            $original = @{ Capabilities = @('graph', 'exo') }

            $copy = Set-M365SessionNameOverride -Session $original -NameOverride @{ 'ID-2' = 'Renamed' }

            $copy['NameOverride']['ID-2'] | Should -Be 'Renamed'
            @($copy['Capabilities'])      | Should -Be @('graph', 'exo')   # survives the copy
            $original.ContainsKey('NameOverride') | Should -BeFalse       # original untouched
        }
    }

    It 'augments a pscustomobject session (e.g. New-M365Session output) without mutating the original' {
        InModuleScope M365Configurator {
            $original = [pscustomobject]@{ PSTypeName = 'M365Configurator.Session'; Graph = $null; Exo = $null; Capabilities = @('exo') }

            $copy = Set-M365SessionNameOverride -Session $original -NameOverride @{ 'MDO-4' = 'Renamed' }

            $copy.NameOverride['MDO-4'] | Should -Be 'Renamed'
            @($copy.Capabilities)       | Should -Be @('exo')   # survives the copy
            $original.PSObject.Properties.Name | Should -Not -Contain 'NameOverride'   # original untouched
        }
    }

    It 'builds a fresh hashtable when the session is $null' {
        InModuleScope M365Configurator {
            $copy = Set-M365SessionNameOverride -Session $null -NameOverride @{ 'ID-3' = 'Renamed' }

            $copy['NameOverride']['ID-3'] | Should -Be 'Renamed'
        }
    }
}

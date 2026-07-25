#requires -Version 7.6
<#
    Tests for the MDO-10 external-sender-warning control (MCA-32; SCuBA
    MS.EXO.7.1v1) — the native Outlook "External" tag, driven by
    Get/Set-ExternalInOutlook. Set-ExternalInOutlook has no -WhatIf, so the
    engine's own diff (research 05 §2.3) is the entire dry-run safety net;
    Get is never allowed to silently misreport current state. The EXO seam
    (Invoke-M365ExoCommand) is mocked module-scoped, so these are
    tenant-free.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force
}

Describe 'Get-M365ControlRegistry — MDO-10' {

    It 'registers MDO-10 as an exo singleton requiring exo' {
        $mdo10 = Get-M365ControlRegistry | Where-Object { $_.Id -eq 'MDO-10' }

        $mdo10                  | Should -Not -BeNullOrEmpty
        $mdo10.Provider         | Should -Be 'exo'
        $mdo10.Shape            | Should -Be 'singleton'
        @($mdo10.RequiredCapabilities) | Should -Be @('exo')
    }
}

Describe 'MDO-10 external-sender-tag control (wired via the registry)' {

    BeforeAll {
        $script:mdo10 = @(Get-M365ControlRegistry | Where-Object { $_.Id -eq 'MDO-10' })[0]
    }

    It 'Get projects enabled and a sorted allowList from the first returned object (multi-geo tenants return several)' {
        Mock Invoke-M365ExoCommand -ModuleName M365Configurator {
            param($Name, $Parameters)
            if ($Name -eq 'Get-ExternalInOutlook') {
                return @(
                    [pscustomobject]@{ Identity = 'Primary'; Enabled = $true; AllowList = @('zeta.com', 'alpha.com') }
                    [pscustomobject]@{ Identity = 'Secondary'; Enabled = $false; AllowList = @() }
                )
            }
        }

        $current = & $script:mdo10.Get $null

        Should -Invoke Invoke-M365ExoCommand -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'Get-ExternalInOutlook'
        }
        $current['enabled']             | Should -BeTrue
        @($current['allowList'])        | Should -Be @('alpha.com', 'zeta.com')
    }

    It 'Get throws when Get-ExternalInOutlook returns zero objects (broken EXO session)' {
        Mock Invoke-M365ExoCommand -ModuleName M365Configurator {
            param($Name, $Parameters)
            if ($Name -eq 'Get-ExternalInOutlook') { return @() }
        }

        { & $script:mdo10.Get $null } | Should -Throw '*Get-ExternalInOutlook*'
    }

    It 'Set with only enabled declared: passes only -Enabled, no -AllowList' {
        Mock Invoke-M365ExoCommand -ModuleName M365Configurator { }
        $desired = @{ enabled = $true }
        $current = @{ enabled = $false; allowList = @() }

        & $script:mdo10.Set $null $desired $current

        Should -Invoke Invoke-M365ExoCommand -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'Set-ExternalInOutlook' -and
            $Parameters.ContainsKey('Enabled') -and $Parameters.Enabled -eq $true -and
            -not $Parameters.ContainsKey('AllowList')
        }
    }

    It 'Set with both keys declared: passes -Enabled and the sorted -AllowList' {
        Mock Invoke-M365ExoCommand -ModuleName M365Configurator { }
        $desired = @{ enabled = $true; allowList = @('zeta.com', 'alpha.com') }
        $current = @{ enabled = $false; allowList = @() }

        & $script:mdo10.Set $null $desired $current

        Should -Invoke Invoke-M365ExoCommand -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'Set-ExternalInOutlook' -and
            $Parameters.Enabled -eq $true -and
            @($Parameters.AllowList) -join ',' -eq 'alpha.com,zeta.com'
        }
    }
}

Describe 'MDO-10 end-to-end through Get-M365Plan' {

    It 'plans Update with enabled false -> true when the tenant has not yet turned the tag on' {
        Mock Invoke-M365ExoCommand -ModuleName M365Configurator {
            param($Name, $Parameters)
            if ($Name -eq 'Get-ExternalInOutlook') {
                return @([pscustomobject]@{ Identity = 'Primary'; Enabled = $false; AllowList = @() })
            }
        }

        $profile = [ordered]@{
            schemaVersion = '1.0'; name = 'x'; framework = 'X'; frameworkVersion = '1.0'
            controls = @(
                [ordered]@{ id = 'MDO-10'; framework = 'X'; frameworkVersion = '1.0'; provider = 'exo'
                    settings = @{ enabled = $true; allowList = @() } }
            )
        }
        $session = @{ Capabilities = @('exo') }

        $plan  = Get-M365Plan -Profile $profile -Session $session
        $mdo10 = $plan.Items | Where-Object { $_.Id -eq 'MDO-10' }

        $mdo10.Action          | Should -Be 'Update'
        $mdo10.Changes[0].Path | Should -Be 'enabled'
        $mdo10.Changes[0].From | Should -BeFalse
        $mdo10.Changes[0].To   | Should -BeTrue
    }
}

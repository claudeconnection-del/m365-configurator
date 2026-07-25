#requires -Version 7.6
<#
    Tests for the AUD-1 unified-audit-log control (MCA-33; SCuBA
    MS.DEFENDER.6.1v1) — turns on the tenant-wide unified audit log via
    Get/Set-AdminAuditLogConfig. Only meaningful read/write from Exchange
    Online PowerShell (our EXO-only session is the right one). The EXO seam
    (Invoke-M365ExoCommand) is mocked module-scoped, so these are
    tenant-free.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force
}

Describe 'Get-M365ControlRegistry — AUD-1' {

    It 'registers AUD-1 as an exo singleton requiring exo' {
        $aud1 = Get-M365ControlRegistry | Where-Object { $_.Id -eq 'AUD-1' }

        $aud1                   | Should -Not -BeNullOrEmpty
        $aud1.Provider          | Should -Be 'exo'
        $aud1.Shape             | Should -Be 'singleton'
        @($aud1.RequiredCapabilities) | Should -Be @('exo')
    }
}

Describe 'AUD-1 unified-audit-log control (wired via the registry)' {

    BeforeAll {
        $script:aud1 = @(Get-M365ControlRegistry | Where-Object { $_.Id -eq 'AUD-1' })[0]
    }

    It 'Get projects the one bool from a noisy fixture' {
        Mock Invoke-M365ExoCommand -ModuleName M365Configurator {
            param($Name, $Parameters)
            if ($Name -eq 'Get-AdminAuditLogConfig') {
                return [pscustomobject]@{
                    UnifiedAuditLogIngestionEnabled = $true
                    AdminAuditLogEnabled            = $true
                    LogLevel                        = 'None'
                    AdminAuditLogAgeLimit           = '90.00:00:00'
                }
            }
        }

        $current = & $script:aud1.Get $null

        Should -Invoke Invoke-M365ExoCommand -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'Get-AdminAuditLogConfig'
        }
        $current.Keys.Count                             | Should -Be 1
        $current['unifiedAuditLogIngestionEnabled']      | Should -BeTrue
    }

    It 'Set calls Set-AdminAuditLogConfig with the desired flag' {
        Mock Invoke-M365ExoCommand -ModuleName M365Configurator { }
        $desired = @{ unifiedAuditLogIngestionEnabled = $true }
        $current = @{ unifiedAuditLogIngestionEnabled = $false }

        & $script:aud1.Set $null $desired $current

        Should -Invoke Invoke-M365ExoCommand -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'Set-AdminAuditLogConfig' -and
            $Parameters.ContainsKey('UnifiedAuditLogIngestionEnabled') -and
            $Parameters.UnifiedAuditLogIngestionEnabled -eq $true
        }
    }
}

Describe 'AUD-1 end-to-end through Get-M365Plan' {

    It 'plans Update with false -> true when the tenant has not enabled ingestion' {
        Mock Invoke-M365ExoCommand -ModuleName M365Configurator {
            param($Name, $Parameters)
            if ($Name -eq 'Get-AdminAuditLogConfig') {
                return [pscustomobject]@{ UnifiedAuditLogIngestionEnabled = $false }
            }
        }

        $profile = [ordered]@{
            schemaVersion = '1.0'; name = 'x'; framework = 'X'; frameworkVersion = '1.0'
            controls = @(
                [ordered]@{ id = 'AUD-1'; framework = 'X'; frameworkVersion = '1.0'; provider = 'exo'
                    settings = @{ unifiedAuditLogIngestionEnabled = $true } }
            )
        }
        $session = @{ Capabilities = @('exo') }

        $plan = Get-M365Plan -Profile $profile -Session $session
        $aud1 = $plan.Items | Where-Object { $_.Id -eq 'AUD-1' }

        $aud1.Action          | Should -Be 'Update'
        $aud1.Changes[0].Path | Should -Be 'unifiedAuditLogIngestionEnabled'
        $aud1.Changes[0].From | Should -BeFalse
        $aud1.Changes[0].To   | Should -BeTrue
    }
}

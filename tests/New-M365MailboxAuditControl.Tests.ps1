#requires -Version 7.6
<#
    Tests for the AUD-2 mailbox-auditing (org default) control (MCA-34;
    SCuBA MS.EXO.13.1v1) — org-wide `AuditDisabled` via
    Get/Set-OrganizationConfig, projected to the positive vocabulary
    `auditEnabled` (NFR-9: readable profiles, not double negatives).
    Per-mailbox audit actions are OUT of v1 (docs/RUNBOOK.md S14) — this
    control is org-default only. The EXO seam (Invoke-M365ExoCommand) is
    mocked module-scoped, so these are tenant-free.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force
}

Describe 'Get-M365ControlRegistry — AUD-2' {

    It 'registers AUD-2 as an exo singleton requiring exo' {
        $aud2 = Get-M365ControlRegistry | Where-Object { $_.Id -eq 'AUD-2' }

        $aud2                   | Should -Not -BeNullOrEmpty
        $aud2.Provider          | Should -Be 'exo'
        $aud2.Shape             | Should -Be 'singleton'
        @($aud2.RequiredCapabilities) | Should -Be @('exo')
    }
}

Describe 'AUD-2 mailbox-audit control (wired via the registry)' {

    BeforeAll {
        $script:aud2 = @(Get-M365ControlRegistry | Where-Object { $_.Id -eq 'AUD-2' })[0]
    }

    It 'Get inverts AuditDisabled=$false to auditEnabled=$true from a noisy fixture' {
        Mock Invoke-M365ExoCommand -ModuleName M365Configurator {
            param($Name, $Parameters)
            if ($Name -eq 'Get-OrganizationConfig') {
                return [pscustomobject]@{
                    AuditDisabled = $false
                    Name          = 'contoso.onmicrosoft.com'
                    DisplayName   = 'contoso'
                }
            }
        }

        $current = & $script:aud2.Get $null

        Should -Invoke Invoke-M365ExoCommand -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'Get-OrganizationConfig'
        }
        $current.Keys.Count               | Should -Be 1
        $current['auditEnabled']          | Should -BeTrue
    }

    It 'Get inverts AuditDisabled=$true to auditEnabled=$false' {
        Mock Invoke-M365ExoCommand -ModuleName M365Configurator {
            param($Name, $Parameters)
            if ($Name -eq 'Get-OrganizationConfig') { return [pscustomobject]@{ AuditDisabled = $true } }
        }

        $current = & $script:aud2.Get $null

        $current['auditEnabled'] | Should -BeFalse
    }

    It 'Get throws when Get-OrganizationConfig returns nothing (broken EXO session)' {
        Mock Invoke-M365ExoCommand -ModuleName M365Configurator {
            param($Name, $Parameters)
            if ($Name -eq 'Get-OrganizationConfig') { return $null }
        }

        { & $script:aud2.Get $null } | Should -Throw '*Get-OrganizationConfig*'
    }

    It 'Set inverts auditEnabled=$true back to -AuditDisabled:$false' {
        Mock Invoke-M365ExoCommand -ModuleName M365Configurator { }
        $desired = @{ auditEnabled = $true }
        $current = @{ auditEnabled = $false }

        & $script:aud2.Set $null $desired $current

        Should -Invoke Invoke-M365ExoCommand -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'Set-OrganizationConfig' -and
            $Parameters.ContainsKey('AuditDisabled') -and
            $Parameters.AuditDisabled -eq $false
        }
    }

    It 'Set inverts auditEnabled=$false to -AuditDisabled:$true' {
        Mock Invoke-M365ExoCommand -ModuleName M365Configurator { }
        $desired = @{ auditEnabled = $false }
        $current = @{ auditEnabled = $true }

        & $script:aud2.Set $null $desired $current

        Should -Invoke Invoke-M365ExoCommand -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'Set-OrganizationConfig' -and
            $Parameters.AuditDisabled -eq $true
        }
    }
}

Describe 'AUD-2 end-to-end through Get-M365Plan' {

    It 'plans Update when the org currently has auditing disabled' {
        Mock Invoke-M365ExoCommand -ModuleName M365Configurator {
            param($Name, $Parameters)
            if ($Name -eq 'Get-OrganizationConfig') { return [pscustomobject]@{ AuditDisabled = $true } }
        }

        $profile = [ordered]@{
            schemaVersion = '1.0'; name = 'x'; framework = 'X'; frameworkVersion = '1.0'
            controls = @(
                [ordered]@{ id = 'AUD-2'; framework = 'X'; frameworkVersion = '1.0'; provider = 'exo'
                    settings = @{ auditEnabled = $true } }
            )
        }
        $session = @{ Capabilities = @('exo') }

        $plan = Get-M365Plan -Profile $profile -Session $session
        $aud2 = $plan.Items | Where-Object { $_.Id -eq 'AUD-2' }

        $aud2.Action          | Should -Be 'Update'
        $aud2.Changes[0].Path | Should -Be 'auditEnabled'
        $aud2.Changes[0].From | Should -BeFalse
        $aud2.Changes[0].To   | Should -BeTrue
    }
}

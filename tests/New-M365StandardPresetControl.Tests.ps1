#requires -Version 7.6
<#
    Tests for the MDO-1 Standard-preset-security-policy control (MCA-30;
    SCuBA MS.DEFENDER.1.*) — the flagship EXO control, modeled as a
    rule-state + coverage check (D2/research 05 R6), not a field-by-field
    settings diff, since preset settings are Microsoft-owned. The EXO seam
    (Invoke-M365ExoCommand) is mocked module-scoped, so these are
    tenant-free.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force
}

Describe 'Get-M365ControlRegistry — MDO-1' {

    It 'registers MDO-1 as an exo preset requiring exo and defender-office365' {
        $mdo1 = Get-M365ControlRegistry | Where-Object { $_.Id -eq 'MDO-1' }

        $mdo1          | Should -Not -BeNullOrEmpty
        $mdo1.Provider | Should -Be 'exo'
        $mdo1.Shape    | Should -Be 'preset'
        @($mdo1.RequiredCapabilities | Sort-Object) | Should -Be @('defender-office365', 'exo')
    }
}

Describe 'MDO-1 Standard preset control (wired via the registry)' {

    BeforeAll {
        $script:mdo1 = @(Get-M365ControlRegistry | Where-Object { $_.Id -eq 'MDO-1' })[0]
    }

    It 'Get maps two present rule fixtures to their states' {
        Mock Invoke-M365ExoCommand -ModuleName M365Configurator {
            param($Name, $Parameters)
            if ($Name -eq 'Get-EOPProtectionPolicyRule') { return [pscustomobject]@{ Identity = $Parameters.Identity; State = 'Enabled' } }
            if ($Name -eq 'Get-ATPProtectionPolicyRule') { return [pscustomobject]@{ Identity = $Parameters.Identity; State = 'Disabled' } }
        }

        $current = & $script:mdo1.Get $null

        Should -Invoke Invoke-M365ExoCommand -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'Get-EOPProtectionPolicyRule' -and $Parameters.Identity -eq 'Standard Preset Security Policy'
        }
        Should -Invoke Invoke-M365ExoCommand -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'Get-ATPProtectionPolicyRule' -and $Parameters.Identity -eq 'Standard Preset Security Policy'
        }
        $current['eopRuleState'] | Should -Be 'Enabled'
        $current['atpRuleState'] | Should -Be 'Disabled'
    }

    It 'Get maps a rule-not-found failure to NotPresent, but rethrows an unrelated error' {
        Mock Invoke-M365ExoCommand -ModuleName M365Configurator {
            param($Name, $Parameters)
            if ($Name -eq 'Get-EOPProtectionPolicyRule') {
                throw "The operation couldn't be performed because object 'Standard Preset Security Policy' couldn't be found on 'contoso.onmicrosoft.com'."
            }
            if ($Name -eq 'Get-ATPProtectionPolicyRule') { return [pscustomobject]@{ State = 'Enabled' } }
        }

        $current = & $script:mdo1.Get $null

        $current['eopRuleState'] | Should -Be 'NotPresent'
        $current['atpRuleState'] | Should -Be 'Enabled'
    }

    It 'Get rethrows an unrelated (non-not-found) error rather than swallowing it' {
        Mock Invoke-M365ExoCommand -ModuleName M365Configurator {
            param($Name, $Parameters)
            if ($Name -eq 'Get-EOPProtectionPolicyRule') { throw 'Access is denied.' }
            if ($Name -eq 'Get-ATPProtectionPolicyRule') { return [pscustomobject]@{ State = 'Enabled' } }
        }

        { & $script:mdo1.Get $null } | Should -Throw '*Access is denied*'
    }

    It 'Set enables only the differing rule (ATP disabled, EOP already enabled)' {
        Mock Invoke-M365ExoCommand -ModuleName M365Configurator { }
        $desired = @{ eopRuleState = 'Enabled'; atpRuleState = 'Enabled' }
        $current = @{ eopRuleState = 'Enabled'; atpRuleState = 'Disabled' }

        & $script:mdo1.Set $null $desired $current

        Should -Invoke Invoke-M365ExoCommand -ModuleName M365Configurator -Times 1 -Exactly
        Should -Invoke Invoke-M365ExoCommand -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'Enable-ATPProtectionPolicyRule' -and $Parameters.Identity -eq 'Standard Preset Security Policy'
        }
    }

    It 'Set disables a rule when desired is Disabled' {
        Mock Invoke-M365ExoCommand -ModuleName M365Configurator { }
        $desired = @{ eopRuleState = 'Disabled'; atpRuleState = 'Enabled' }
        $current = @{ eopRuleState = 'Enabled'; atpRuleState = 'Enabled' }

        & $script:mdo1.Set $null $desired $current

        Should -Invoke Invoke-M365ExoCommand -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'Disable-EOPProtectionPolicyRule' -and $Parameters.Identity -eq 'Standard Preset Security Policy'
        }
    }

    It 'Set throws the initialisation message when desired Enabled meets current NotPresent (not self-healing, ADR-0011)' {
        Mock Invoke-M365ExoCommand -ModuleName M365Configurator { }
        $desired = @{ eopRuleState = 'Enabled'; atpRuleState = 'Enabled' }
        $current = @{ eopRuleState = 'NotPresent'; atpRuleState = 'Enabled' }

        { & $script:mdo1.Set $null $desired $current } | Should -Throw '*Defender portal*'
        Should -Invoke Invoke-M365ExoCommand -ModuleName M365Configurator -Times 0 -Exactly
    }
}

Describe 'MDO-1 end-to-end through Get-M365Plan' {

    It 'plans Update when the ATP rule is Disabled' {
        Mock Invoke-M365ExoCommand -ModuleName M365Configurator {
            param($Name, $Parameters)
            if ($Name -eq 'Get-EOPProtectionPolicyRule') { return [pscustomobject]@{ State = 'Enabled' } }
            if ($Name -eq 'Get-ATPProtectionPolicyRule') { return [pscustomobject]@{ State = 'Disabled' } }
        }

        $profile = [ordered]@{
            schemaVersion = '1.0'; name = 'x'; framework = 'X'; frameworkVersion = '1.0'
            controls = @(
                [ordered]@{ id = 'MDO-1'; framework = 'X'; frameworkVersion = '1.0'; provider = 'exo'
                    settings = @{ eopRuleState = 'Enabled'; atpRuleState = 'Enabled' } }
            )
        }
        $session = @{ Capabilities = @('exo', 'defender-office365') }

        $plan = Get-M365Plan -Profile $profile -Session $session
        $mdo1 = $plan.Items | Where-Object { $_.Id -eq 'MDO-1' }

        $mdo1.Action | Should -Be 'Update'
        $mdo1.Changes[0].Path | Should -Be 'atpRuleState'
        $mdo1.Changes[0].From | Should -Be 'Disabled'
        $mdo1.Changes[0].To   | Should -Be 'Enabled'
    }
}

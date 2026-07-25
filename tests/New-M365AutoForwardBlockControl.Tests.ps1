#requires -Version 7.6
<#
    Tests for the MDO-4 block-external-auto-forwarding control (MCA-31; SCuBA
    MS.EXO.1.1v2) — the outbound spam filter policy's AutoForwardingMode,
    scoped to the well-known Default policy (same fixed-name convention as
    ID-2/ID-3, D2). v1 is update-only: every tenant ships the Default policy,
    so there is no Create path. The EXO seam (Invoke-M365ExoCommand) is
    mocked module-scoped, so these are tenant-free.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force
}

Describe 'Get-M365ControlRegistry — MDO-4' {

    It 'registers MDO-4 as an exo policy-rule control requiring exo' {
        $mdo4 = Get-M365ControlRegistry | Where-Object { $_.Id -eq 'MDO-4' }

        $mdo4                  | Should -Not -BeNullOrEmpty
        $mdo4.Provider         | Should -Be 'exo'
        $mdo4.Shape            | Should -Be 'policy-rule'
        @($mdo4.RequiredCapabilities) | Should -Be @('exo')
    }
}

Describe 'MDO-4 block-external-auto-forwarding control (wired via the registry)' {

    BeforeAll {
        $script:mdo4 = @(Get-M365ControlRegistry | Where-Object { $_.Id -eq 'MDO-4' })[0]
    }

    It 'Get lists outbound spam filter policies once and projects name+mode from the Default policy' {
        Mock Invoke-M365ExoCommand -ModuleName M365Configurator {
            param($Name, $Parameters)
            if ($Name -eq 'Get-HostedOutboundSpamFilterPolicy') {
                return @(
                    [pscustomobject]@{ Name = 'Custom-Policy'; AutoForwardingMode = 'On' }
                    [pscustomobject]@{ Name = 'Default'; AutoForwardingMode = 'Automatic' }
                )
            }
        }

        $current = & $script:mdo4.Get $null

        Should -Invoke Invoke-M365ExoCommand -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'Get-HostedOutboundSpamFilterPolicy'
        }
        $current['name']               | Should -Be 'Default'
        $current['autoForwardingMode'] | Should -Be 'Automatic'
    }

    It 'Get throws when the Default policy is absent (broken EXO session)' {
        Mock Invoke-M365ExoCommand -ModuleName M365Configurator {
            param($Name, $Parameters)
            if ($Name -eq 'Get-HostedOutboundSpamFilterPolicy') {
                return @([pscustomobject]@{ Name = 'Custom-Policy'; AutoForwardingMode = 'On' })
            }
        }

        { & $script:mdo4.Get $null } | Should -Throw "*outbound spam filter policy 'Default' not found*"
    }

    It 'Set calls Set-HostedOutboundSpamFilterPolicy with the right Identity and AutoForwardingMode' {
        Mock Invoke-M365ExoCommand -ModuleName M365Configurator { }
        $desired = @{ name = 'Default'; autoForwardingMode = 'Off' }
        $current = @{ name = 'Default'; autoForwardingMode = 'Automatic' }

        & $script:mdo4.Set $null $desired $current

        Should -Invoke Invoke-M365ExoCommand -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'Set-HostedOutboundSpamFilterPolicy' -and
            $Parameters.Identity -eq 'Default' -and
            $Parameters.AutoForwardingMode -eq 'Off'
        }
    }
}

Describe 'MDO-4 end-to-end through Get-M365Plan' {

    It 'plans Update with Automatic -> Off when the tenant has not yet made the mode explicit' {
        Mock Invoke-M365ExoCommand -ModuleName M365Configurator {
            param($Name, $Parameters)
            if ($Name -eq 'Get-HostedOutboundSpamFilterPolicy') {
                return @([pscustomobject]@{ Name = 'Default'; AutoForwardingMode = 'Automatic' })
            }
        }

        $profile = [ordered]@{
            schemaVersion = '1.0'; name = 'x'; framework = 'X'; frameworkVersion = '1.0'
            controls = @(
                [ordered]@{ id = 'MDO-4'; framework = 'X'; frameworkVersion = '1.0'; provider = 'exo'
                    settings = @{ name = 'Default'; autoForwardingMode = 'Off' } }
            )
        }
        $session = @{ Capabilities = @('exo') }

        $plan = Get-M365Plan -Profile $profile -Session $session
        $mdo4 = $plan.Items | Where-Object { $_.Id -eq 'MDO-4' }

        $mdo4.Action          | Should -Be 'Update'
        $mdo4.Changes[0].Path | Should -Be 'autoForwardingMode'
        $mdo4.Changes[0].From | Should -Be 'Automatic'
        $mdo4.Changes[0].To   | Should -Be 'Off'
    }
}

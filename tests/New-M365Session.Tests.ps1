#requires -Version 7.6
<#
    Tests for New-M365Session (MCA-21; D8) — the connection-presence and
    license-derived capability aggregator that makes Session.Capabilities
    real. Tenant-free: the license probe is an injected seam.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force
}

Describe 'New-M365Session' {

    It 'yields empty Capabilities when neither Graph nor Exo is connected (license seam never invoked)' {
        $script:licenseSeamCalled = $false
        $reader = { $script:licenseSeamCalled = $true; @{ value = @() } }

        $session = New-M365Session -LicenseReader $reader

        @($session.Capabilities).Count | Should -Be 0
        $script:licenseSeamCalled | Should -BeFalse
    }

    It 'adds graph when Graph is connected, and invokes the license seam' {
        $script:licenseSeamCalled = $false
        $reader = { $script:licenseSeamCalled = $true; @{ value = @() } }

        $session = New-M365Session -Graph @{ Connected = $true } -LicenseReader $reader

        @($session.Capabilities) | Should -Contain 'graph'
        $script:licenseSeamCalled | Should -BeTrue
    }

    It 'adds exo when Exo is connected, and does NOT invoke the license seam (no Graph connection to probe with)' {
        $script:licenseSeamCalled = $false
        $reader = { $script:licenseSeamCalled = $true; @{ value = @() } }

        $session = New-M365Session -Exo @{ Connected = $true } -LicenseReader $reader

        @($session.Capabilities) | Should -Be @('exo')
        $script:licenseSeamCalled | Should -BeFalse
    }

    It 'does not add graph/exo when the connect-state object says Connected = $false' {
        $session = New-M365Session -Graph @{ Connected = $false } -Exo @{ Connected = $false } -LicenseReader { @{ value = @() } }

        @($session.Capabilities).Count | Should -Be 0
    }

    It 'derives entra-id-p1, entra-id-p2, and defender-office365 from a SKU fixture, sorted and unique' {
        $reader = {
            @{
                value = @(
                    @{ servicePlans = @(@{ servicePlanName = 'AAD_PREMIUM' }, @{ servicePlanName = 'EXCHANGE_S_ENTERPRISE' }) }
                    @{ servicePlans = @(@{ servicePlanName = 'AAD_PREMIUM_P2' }) }
                    @{ servicePlans = @(@{ servicePlanName = 'ATP_ENTERPRISE' }) }
                )
            }
        }

        $session = New-M365Session -Graph @{ Connected = $true } -LicenseReader $reader

        @($session.Capabilities) | Should -Be @('defender-office365', 'entra-id-p1', 'entra-id-p2', 'graph')
    }

    It 'has the correct shape: PSTypeName and Graph/Exo passthrough' {
        $graphState = @{ Connected = $true; Account = 'admin@contoso.com' }
        $exoState   = @{ Connected = $true; UserPrincipalName = 'admin@contoso.com' }

        $session = New-M365Session -Graph $graphState -Exo $exoState -LicenseReader { @{ value = @() } }

        $session.PSObject.TypeNames | Should -Contain 'M365Configurator.Session'
        $session.Graph | Should -Be $graphState
        $session.Exo   | Should -Be $exoState
    }
}

Describe 'Session capability gating end-to-end through Get-M365Plan' {

    It 'Blocks a graph control with the exact gate text when the session lacks the graph capability' {
        $registry = @(
            New-M365Control -Id 'A' -Provider 'graph' -Shape 'singleton' -Title 'A' `
                -RequiredCapabilities @('graph') `
                -Get { param($Session) throw 'Get must not run for a blocked control' } -Set { param($Session, $Desired, $Current) }
        )
        $profile = [ordered]@{
            schemaVersion = '1.0'; name = 'x'; framework = 'X'; frameworkVersion = '1.0'
            controls = @([ordered]@{ id = 'A'; framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'; settings = @{ v = 1 } })
        }
        $session = New-M365Session -LicenseReader { @{ value = @() } }   # nothing connected

        $plan = Get-M365Plan -Profile $profile -Session $session -Registry $registry
        $item = $plan.Items[0]

        $item.Action | Should -Be 'Blocked'
        $item.Gate   | Should -Be 'requires capability: graph'
    }
}

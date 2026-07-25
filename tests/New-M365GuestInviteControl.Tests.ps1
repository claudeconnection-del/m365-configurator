#requires -Version 7.6
<#
    Tests for the SHR-1 restrict-guest-inviters control (MCA-28; SCuBA
    MS.AAD.8.2v1) — the simplest control in the set: a single flat field on
    the authorizationPolicy singleton it shares with CON-1 (MCA-26). The
    Graph seam (Invoke-M365GraphRequest) is mocked module-scoped, so these
    are tenant-free.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force

    function New-TestProfile {
        param([object[]] $Controls, [string] $Name = 'baseline')
        [ordered]@{
            schemaVersion = '1.0'; name = $Name; framework = 'X'; frameworkVersion = '1.0'
            controls      = @($Controls)
        }
    }
}

Describe 'Get-M365ControlRegistry — SHR-1' {

    It 'registers SHR-1 as a graph singleton' {
        $shr1 = Get-M365ControlRegistry | Where-Object { $_.Id -eq 'SHR-1' }

        $shr1          | Should -Not -BeNullOrEmpty
        $shr1.Provider | Should -Be 'graph'
        $shr1.Shape    | Should -Be 'singleton'
    }
}

Describe 'SHR-1 restrict-guest-inviters control (wired via the registry)' {

    BeforeAll {
        $script:shr1 = @(Get-M365ControlRegistry | Where-Object { $_.Id -eq 'SHR-1' })[0]
    }

    It 'Get projects only allowInvitesFrom from a noisy authorizationPolicy fixture' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator {
            @{
                allowInvitesFrom = 'everyone'
                allowEmailVerifiedUsersToJoinOrganization = $true
                defaultUserRolePermissions = @{
                    allowedToCreateApps = $false
                    permissionGrantPoliciesAssigned = @('managePermissionGrantsForSelf.microsoft-user-default-low')
                }
            }
        }

        $current = & $script:shr1.Get $null

        Should -Invoke Invoke-M365GraphRequest -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Uri -eq 'v1.0/policies/authorizationPolicy'
        }
        @($current.Keys) | Should -Be @('allowInvitesFrom')
        $current['allowInvitesFrom'] | Should -Be 'everyone'
    }

    It 'Set PATCHes exactly the allowInvitesFrom body' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator { }
        $desired = @{ allowInvitesFrom = 'adminsAndGuestInviters' }

        & $script:shr1.Set $null $desired $null

        Should -Invoke Invoke-M365GraphRequest -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -eq 'v1.0/policies/authorizationPolicy' -and
            @($Body.Keys).Count -eq 1 -and $Body.ContainsKey('allowInvitesFrom') -and
            $Body['allowInvitesFrom'] -eq 'adminsAndGuestInviters'
        }
    }
}

Describe 'SHR-1 end-to-end through Get-M365Plan' {

    It 'plans Update when allowInvitesFrom differs (everyone -> adminsAndGuestInviters)' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator {
            @{ allowInvitesFrom = 'everyone' }
        }

        $profile = New-TestProfile @(
            [ordered]@{ id = 'SHR-1'; framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'
                settings = @{ allowInvitesFrom = 'adminsAndGuestInviters' } }
        )

        $plan = Get-M365Plan -Profile $profile
        $shr1 = $plan.Items | Where-Object { $_.Id -eq 'SHR-1' }

        $shr1.Action | Should -Be 'Update'
        $shr1.Changes[0].Path | Should -Be 'allowInvitesFrom'
        $shr1.Changes[0].From | Should -Be 'everyone'
        $shr1.Changes[0].To   | Should -Be 'adminsAndGuestInviters'
    }

    It 'coexists with CON-1 on the shared authorizationPolicy endpoint: two independent plan items, no cross-talk' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator {
            @{
                allowInvitesFrom = 'everyone'
                defaultUserRolePermissions = @{
                    allowedToCreateApps = $true
                    permissionGrantPoliciesAssigned = @('managePermissionGrantsForSelf.microsoft-user-default-legacy')
                }
            }
        }

        $profile = New-TestProfile @(
            [ordered]@{ id = 'SHR-1'; framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'
                settings = @{ allowInvitesFrom = 'adminsAndGuestInviters' } }
            [ordered]@{ id = 'CON-1'; framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'
                settings = @{ allowedToCreateApps = $false } }
        )

        $plan = Get-M365Plan -Profile $profile
        $shr1 = $plan.Items | Where-Object { $_.Id -eq 'SHR-1' }
        $con1 = $plan.Items | Where-Object { $_.Id -eq 'CON-1' }

        $shr1.Action | Should -Be 'Update'
        @($shr1.Changes).Count | Should -Be 1
        $shr1.Changes[0].Path | Should -Be 'allowInvitesFrom'

        $con1.Action | Should -Be 'Update'
        @($con1.Changes).Count | Should -Be 1
        $con1.Changes[0].Path | Should -Be 'allowedToCreateApps'
    }
}

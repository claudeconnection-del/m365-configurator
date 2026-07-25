#requires -Version 7.6
<#
    Tests for the CON-1 restrict-user-consent-and-app-registration control
    (MCA-26; SCuBA MS.AAD.5.2v1 + 5.1v1) — a Graph singleton on the ADR-0013
    contract (D4) sharing the authorizationPolicy endpoint with SHR-1 (S8).

    The load-bearing behavior here is the MANDATORY read-modify-write:
    permissionGrantPoliciesAssigned also carries
    managePermissionGrantsForOwnedResource.* entries that must survive a
    write untouched — a literal desired-state payload would silently strip
    developer-consent capability. This control's vocabulary covers only the
    managePermissionGrantsForSelf.* half.

    The Graph seam (Invoke-M365GraphRequest) is mocked module-scoped, so
    these are tenant-free.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force
}

Describe 'Get-M365ControlRegistry — CON-1' {

    It 'registers CON-1 as a graph singleton' {
        $con1 = Get-M365ControlRegistry | Where-Object { $_.Id -eq 'CON-1' }

        $con1          | Should -Not -BeNullOrEmpty
        $con1.Provider | Should -Be 'graph'
        $con1.Shape    | Should -Be 'singleton'
        $con1.RequiredCapabilities | Should -Be @('graph')
    }
}

Describe 'CON-1 restrict-consent control (wired via the registry)' {

    BeforeAll {
        $script:con1 = @(Get-M365ControlRegistry | Where-Object { $_.Id -eq 'CON-1' })[0]
    }

    It 'Get projects allowedToCreateApps and userConsentPolicies (self-entries only, sorted); other authorizationPolicy fields excluded' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator {
            @{
                allowInvitesFrom = 'everyone'
                defaultUserRolePermissions = @{
                    allowedToCreateApps = $false
                    permissionGrantPoliciesAssigned = @(
                        'managePermissionGrantsForOwnedResource.DeveloperConsent'
                        'managePermissionGrantsForSelf.microsoft-user-default-low'
                        'managePermissionGrantsForSelf.microsoft-user-default-legacy'
                    )
                }
            }
        }

        $current = & $script:con1.Get $null

        Should -Invoke Invoke-M365GraphRequest -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Uri -eq 'v1.0/policies/authorizationPolicy'
        }
        @($current.Keys | Sort-Object) | Should -Be @('allowedToCreateApps', 'userConsentPolicies')
        $current['allowedToCreateApps'] | Should -BeFalse
        @($current['userConsentPolicies']) | Should -Be @(
            'managePermissionGrantsForSelf.microsoft-user-default-legacy',
            'managePermissionGrantsForSelf.microsoft-user-default-low'
        )
    }

    It 'Set with both keys declared: re-GETs the live policy and PATCHes, preserving the foreign owned-resource entry' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator {
            param($Method, $Uri, $Body)
            if ($Method -eq 'GET') {
                return @{
                    defaultUserRolePermissions = @{
                        allowedToCreateApps = $true
                        permissionGrantPoliciesAssigned = @(
                            'managePermissionGrantsForSelf.microsoft-user-default-legacy'
                            'managePermissionGrantsForOwnedResource.DeveloperConsent'
                        )
                    }
                }
            }
        }
        $desired = @{ allowedToCreateApps = $false; userConsentPolicies = @('managePermissionGrantsForSelf.microsoft-user-default-low') }

        & $script:con1.Set $null $desired $null

        Should -Invoke Invoke-M365GraphRequest -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Uri -eq 'v1.0/policies/authorizationPolicy'
        }
        Should -Invoke Invoke-M365GraphRequest -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -eq 'v1.0/policies/authorizationPolicy' -and
            $Body['defaultUserRolePermissions']['allowedToCreateApps'] -eq $false -and
            (@($Body['defaultUserRolePermissions']['permissionGrantPoliciesAssigned']) -contains 'managePermissionGrantsForOwnedResource.DeveloperConsent') -and
            (@($Body['defaultUserRolePermissions']['permissionGrantPoliciesAssigned']) -contains 'managePermissionGrantsForSelf.microsoft-user-default-low') -and
            (@($Body['defaultUserRolePermissions']['permissionGrantPoliciesAssigned']) -notcontains 'managePermissionGrantsForSelf.microsoft-user-default-legacy')
        }
    }

    It 'Set with only allowedToCreateApps declared: no re-GET, and the PATCH body carries only that key' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator { }
        $desired = @{ allowedToCreateApps = $false }

        & $script:con1.Set $null $desired $null

        # Exactly one call total: the PATCH. No GET was needed since the
        # foreign-entry-preserving read-modify-write only applies when
        # userConsentPolicies is actually being written.
        Should -Invoke Invoke-M365GraphRequest -ModuleName M365Configurator -Times 1 -Exactly
        Should -Invoke Invoke-M365GraphRequest -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PATCH' -and
            @($Body['defaultUserRolePermissions'].Keys).Count -eq 1 -and
            $Body['defaultUserRolePermissions'].ContainsKey('allowedToCreateApps')
        }
    }
}

Describe 'CON-1 end-to-end through Get-M365Plan' {

    It 'plans Update with exactly one Change on userConsentPolicies (legacy current vs low-risk desired)' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator {
            @{
                defaultUserRolePermissions = @{
                    allowedToCreateApps = $false
                    permissionGrantPoliciesAssigned = @('managePermissionGrantsForSelf.microsoft-user-default-legacy')
                }
            }
        }

        $profile = [ordered]@{
            schemaVersion = '1.0'; name = 'x'; framework = 'X'; frameworkVersion = '1.0'
            controls = @(
                [ordered]@{ id = 'CON-1'; framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'
                    settings = @{ allowedToCreateApps = $false; userConsentPolicies = @('managePermissionGrantsForSelf.microsoft-user-default-low') } }
            )
        }

        $plan = Get-M365Plan -Profile $profile -Session @{ Capabilities = @('graph') }
        $con1 = $plan.Items | Where-Object { $_.Id -eq 'CON-1' }

        $con1.Action | Should -Be 'Update'
        @($con1.Changes).Count | Should -Be 1
        $con1.Changes[0].Path | Should -Be 'userConsentPolicies'
    }
}

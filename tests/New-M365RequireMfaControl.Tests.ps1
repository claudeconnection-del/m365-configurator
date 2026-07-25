#requires -Version 7.6
<#
    Tests for the ID-3 require-MFA-for-all-users control (MCA-24; SCuBA
    MS.AAD.3.2v2) — the second Conditional Access collection control on the
    ADR-0013 contract (D2), mirroring ID-2's structure exactly. Exercised via
    the registry; the Graph seam (Invoke-M365GraphRequest) is mocked
    module-scoped, so these are tenant-free.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force

    # A fixture CA policy shaped like a raw Graph response: unsorted arrays and
    # read-only metadata (createdDateTime etc.) that must NOT survive the
    # projection.
    $script:rawPolicyFixture = @{
        id              = 'policy-guid-456'
        displayName     = 'Require MFA for all users'
        state           = 'enabled'
        createdDateTime = '2026-01-01T00:00:00Z'
        modifiedDateTime = '2026-01-02T00:00:00Z'
        conditions      = @{
            clientAppTypes = @('all')
            users          = @{ includeUsers = @('All'); excludeUsers = @('user-2', 'user-1') }
            applications   = @{ includeApplications = @('All') }
        }
        grantControls   = @{ operator = 'OR'; builtInControls = @('mfa') }
    }

    function New-TestProfile {
        param([object[]] $Controls, [string] $Name = 'baseline')
        [ordered]@{
            schemaVersion = '1.0'; name = $Name; framework = 'X'; frameworkVersion = '1.0'
            controls      = @($Controls)
        }
    }
    function New-TestControl {
        param([string] $Id, [hashtable] $Settings)
        [ordered]@{ id = $Id; framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'; settings = $Settings }
    }
}

Describe 'Get-M365ControlRegistry — ID-3' {

    It 'registers ID-3 as a graph collection depending on ID-1' {
        $id3 = Get-M365ControlRegistry | Where-Object { $_.Id -eq 'ID-3' }

        $id3             | Should -Not -BeNullOrEmpty
        $id3.Provider    | Should -Be 'graph'
        $id3.Shape       | Should -Be 'collection'
        $id3.DependsOn   | Should -Contain 'ID-1'
        $id3.RequiredCapabilities | Should -Be @('graph')
    }
}

Describe 'ID-3 require-MFA control (wired via the registry)' {

    BeforeAll {
        $script:id3 = @(Get-M365ControlRegistry | Where-Object { $_.Id -eq 'ID-3' })[0]
    }

    It 'Get lists CA policies once and returns $null when no policy matches the well-known name' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator {
            @{ value = @(@{ id = 'other'; displayName = 'Some other policy' }) }
        }

        $current = & $script:id3.Get $null

        Should -Invoke Invoke-M365GraphRequest -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Uri -match 'identity/conditionalAccess/policies'
        }
        $current | Should -BeNullOrEmpty
    }

    It 'Get projects a matching policy to exactly the nine keys, arrays sorted, metadata stripped' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator {
            @{ value = @($script:rawPolicyFixture) }
        }

        $current = & $script:id3.Get $null

        @($current.Keys | Sort-Object) | Should -Be @(
            'clientAppTypes', 'displayName', 'excludeUsers', 'grantControls',
            'grantOperator', 'id', 'includeApplications', 'includeUsers', 'state'
        )
        $current['id']                  | Should -Be 'policy-guid-456'
        $current['displayName']         | Should -Be 'Require MFA for all users'
        $current['state']               | Should -Be 'enabled'
        @($current['clientAppTypes'])   | Should -Be @('all')
        @($current['includeUsers'])     | Should -Be @('All')
        @($current['excludeUsers'])     | Should -Be @('user-1', 'user-2')                  # sorted
        @($current['includeApplications']) | Should -Be @('All')
        $current['grantOperator']       | Should -Be 'OR'
        @($current['grantControls'])    | Should -Be @('mfa')
    }

    It 'Set POSTs a new policy (nested body from flat desired) when no current policy exists' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator { }
        $desired = @{
            displayName = 'Require MFA for all users'; state = 'enabled'
            clientAppTypes = @('all'); includeUsers = @('All'); excludeUsers = @()
            includeApplications = @('All'); grantOperator = 'OR'; grantControls = @('mfa')
        }

        & $script:id3.Set $null $desired $null

        Should -Invoke Invoke-M365GraphRequest -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Uri -eq 'v1.0/identity/conditionalAccess/policies' -and
            $Body['displayName'] -eq 'Require MFA for all users' -and
            $Body['state'] -eq 'enabled' -and
            @($Body['conditions']['clientAppTypes']) -join ',' -eq 'all' -and
            @($Body['conditions']['users']['includeUsers']) -join ',' -eq 'All' -and
            @($Body['conditions']['applications']['includeApplications']) -join ',' -eq 'All' -and
            $Body['grantControls']['operator'] -eq 'OR' -and
            @($Body['grantControls']['builtInControls']) -join ',' -eq 'mfa'
        }
    }

    It 'Set PATCHes the existing policy by its stashed id when a current policy exists' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator { }
        $desired = @{
            displayName = 'Require MFA for all users'; state = 'enabled'
            clientAppTypes = @('all'); includeUsers = @('All'); excludeUsers = @()
            includeApplications = @('All'); grantOperator = 'OR'; grantControls = @('mfa')
        }
        $current = @{ id = 'policy-guid-456'; displayName = 'Require MFA for all users' }

        & $script:id3.Set $null $desired $current

        Should -Invoke Invoke-M365GraphRequest -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -eq 'v1.0/identity/conditionalAccess/policies/policy-guid-456'
        }
    }

    It 'Compare treats an absent policy as Create, one Change per desired key, From $null' {
        $desired = @{ displayName = 'Require MFA for all users'; state = 'enabled' }

        $result = & $script:id3.Compare $desired $null

        $result.Action | Should -Be 'Create'
        @($result.Changes).Count | Should -Be 2
        ($result.Changes | Where-Object Path -eq 'state').From | Should -BeNullOrEmpty
        ($result.Changes | Where-Object Path -eq 'state').To   | Should -Be 'enabled'
    }

    It 'Compare treats an identical projection as NoChange with empty Changes' {
        $desired = @{ state = 'enabled' }
        $current = @{ state = 'enabled'; id = 'policy-guid-456' }

        $result = & $script:id3.Compare $desired $current

        $result.Action  | Should -Be 'NoChange'
        @($result.Changes).Count | Should -Be 0
    }

    It 'Compare reports Update with exactly the differing field when state differs' {
        $desired = @{ state = 'enabled' }
        $current = @{ state = 'disabled'; id = 'policy-guid-456' }

        $result = & $script:id3.Compare $desired $current

        $result.Action | Should -Be 'Update'
        @($result.Changes).Count | Should -Be 1
        $result.Changes[0].Path | Should -Be 'state'
        $result.Changes[0].From | Should -Be 'disabled'
        $result.Changes[0].To   | Should -Be 'enabled'
    }
}

Describe 'ID-3 end-to-end through Get-M365Plan' {

    It 'orders ID-1 before ID-3 (DependsOn) and shows Create when the policy is absent' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator {
            param($Method, $Uri, $Body)
            if ($Uri -match 'identitySecurityDefaultsEnforcementPolicy') { return @{ isEnabled = $true } }
            if ($Uri -match 'identity/conditionalAccess/policies') { return @{ value = @() } }
        }

        $profile = New-TestProfile @(
            New-TestControl -Id 'ID-3' -Settings @{
                displayName = 'Require MFA for all users'; state = 'enabled'
                clientAppTypes = @('all'); includeUsers = @('All'); excludeUsers = @()
                includeApplications = @('All'); grantOperator = 'OR'; grantControls = @('mfa')
            }
            New-TestControl -Id 'ID-1' -Settings @{ isEnabled = $false }
        )

        $plan = Get-M365Plan -Profile $profile -Session @{ Capabilities = @('graph') }

        $plan.Items[0].Id | Should -Be 'ID-1'
        $plan.Items[1].Id | Should -Be 'ID-3'
        $plan.Items[1].Action | Should -Be 'Create'
    }
}

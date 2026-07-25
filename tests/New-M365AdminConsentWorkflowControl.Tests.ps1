#requires -Version 7.6
<#
    Tests for the CON-2 admin-consent-workflow control (MCA-27; SCuBA
    MS.AAD.5.3v1) — a Graph singleton on the ADR-0013 contract. The Graph
    update here is a full-replace PUT (not PATCH), so Set requires the
    complete five-key settings map and refuses an enabled-with-no-reviewers
    desired state (a consent workflow with no reviewers silently blackholes
    every request). The Graph seam (Invoke-M365GraphRequest) is mocked
    module-scoped, so these are tenant-free.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force
}

Describe 'Get-M365ControlRegistry — CON-2' {

    It 'registers CON-2 as a graph singleton' {
        $con2 = Get-M365ControlRegistry | Where-Object { $_.Id -eq 'CON-2' }

        $con2          | Should -Not -BeNullOrEmpty
        $con2.Provider | Should -Be 'graph'
        $con2.Shape    | Should -Be 'singleton'
        $con2.RequiredCapabilities | Should -Be @('graph')
    }
}

Describe 'CON-2 admin-consent-workflow control (wired via the registry)' {

    BeforeAll {
        $script:con2 = @(Get-M365ControlRegistry | Where-Object { $_.Id -eq 'CON-2' })[0]
    }

    It 'Get projects the five keys, reviewers flattened to sorted queries (unsorted + queryType noise in the fixture)' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator {
            @{
                isEnabled             = $true
                notifyReviewers       = $true
                remindersEnabled      = $false
                requestDurationInDays = 14
                reviewers             = @(
                    @{ query = '/users/bbb'; queryType = 'MicrosoftGraph' }
                    @{ query = '/users/aaa'; queryType = 'MicrosoftGraph' }
                )
            }
        }

        $current = & $script:con2.Get $null

        Should -Invoke Invoke-M365GraphRequest -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Uri -eq 'v1.0/policies/adminConsentRequestPolicy'
        }
        @($current.Keys | Sort-Object) | Should -Be @(
            'isEnabled', 'notifyReviewers', 'remindersEnabled', 'requestDurationInDays', 'reviewerQueries'
        )
        $current['isEnabled']             | Should -BeTrue
        $current['notifyReviewers']       | Should -BeTrue
        $current['remindersEnabled']      | Should -BeFalse
        $current['requestDurationInDays'] | Should -Be 14
        @($current['reviewerQueries'])    | Should -Be @('/users/aaa', '/users/bbb')
    }

    It 'Set PUTs (not PATCHes) the full body with reviewers rebuilt from sorted queries' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator { }
        $desired = @{
            isEnabled = $true; notifyReviewers = $true; remindersEnabled = $true
            requestDurationInDays = 30
            reviewerQueries = @('/users/zzz', '/users/aaa')
        }

        & $script:con2.Set $null $desired $null

        Should -Invoke Invoke-M365GraphRequest -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and $Uri -eq 'v1.0/policies/adminConsentRequestPolicy' -and
            $Body['isEnabled'] -eq $true -and $Body['notifyReviewers'] -eq $true -and
            $Body['remindersEnabled'] -eq $true -and $Body['requestDurationInDays'] -eq 30 -and
            @($Body['reviewers']).Count -eq 2 -and
            $Body['reviewers'][0]['query'] -eq '/users/aaa' -and $Body['reviewers'][0]['queryType'] -eq 'MicrosoftGraph' -and
            $Body['reviewers'][1]['query'] -eq '/users/zzz' -and $Body['reviewers'][1]['queryType'] -eq 'MicrosoftGraph'
        }
    }

    It 'Set throws the full-map message when a required key is missing from Desired' {
        $desired = @{ isEnabled = $true; notifyReviewers = $true; remindersEnabled = $true; requestDurationInDays = 30 }  # reviewerQueries missing

        { & $script:con2.Set $null $desired $null } | Should -Throw '*full settings map*'
    }

    It 'Set throws when isEnabled is true and reviewerQueries is empty (would silently blackhole requests)' {
        $desired = @{
            isEnabled = $true; notifyReviewers = $true; remindersEnabled = $true
            requestDurationInDays = 30; reviewerQueries = @()
        }

        { & $script:con2.Set $null $desired $null } | Should -Throw '*reviewer*'
    }

    It 'Set does not throw when isEnabled is false even with zero reviewers' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator { }
        $desired = @{
            isEnabled = $false; notifyReviewers = $true; remindersEnabled = $true
            requestDurationInDays = 30; reviewerQueries = @()
        }

        { & $script:con2.Set $null $desired $null } | Should -Not -Throw
    }
}

Describe 'CON-2 end-to-end through Get-M365Plan' {

    It 'plans Update when isEnabled differs (false -> true)' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator {
            @{
                isEnabled = $false; notifyReviewers = $true; remindersEnabled = $true
                requestDurationInDays = 30; reviewers = @()
            }
        }

        $profile = [ordered]@{
            schemaVersion = '1.0'; name = 'x'; framework = 'X'; frameworkVersion = '1.0'
            controls = @(
                [ordered]@{ id = 'CON-2'; framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'
                    settings = @{
                        isEnabled = $true; notifyReviewers = $true; remindersEnabled = $true
                        requestDurationInDays = 30; reviewerQueries = @('/users/aaa')
                    } }
            )
        }

        $plan = Get-M365Plan -Profile $profile -Session @{ Capabilities = @('graph') }
        $con2 = $plan.Items | Where-Object { $_.Id -eq 'CON-2' }

        $con2.Action | Should -Be 'Update'
        ($con2.Changes | Where-Object Path -eq 'isEnabled').From | Should -BeFalse
        ($con2.Changes | Where-Object Path -eq 'isEnabled').To   | Should -BeTrue
    }
}

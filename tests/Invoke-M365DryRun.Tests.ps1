#requires -Version 7.0
<#
    Tests for Invoke-M365DryRun — the owner-facing dry-run entry point (MCA-17) —
    and Format-M365Plan, its readable renderer (NFR-9). Fake controls + an injected
    importer keep it tenant-free and file-free. A dry-run must change nothing.
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
    function New-TestControl {
        param([string] $Id, [hashtable] $Settings)
        [ordered]@{ id = $Id; framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'; settings = $Settings }
    }
}

Describe 'Invoke-M365DryRun' {

    It 'returns a typed plan for a supplied profile object, using the injected registry' {
        $registry = @(
            New-M365Control -Id 'A' -Provider 'graph' -Shape 'singleton' -Title 'Ctl A' `
                -Get { param($Session) @{ enabled = $true } } -Set { param($Session, $Desired, $Current) }
        )
        $profile = New-TestProfile @( New-TestControl -Id 'A' -Settings @{ enabled = $false } )

        $plan = Invoke-M365DryRun -Profile $profile -Registry $registry -InformationAction Ignore

        $plan.PSObject.TypeNames | Should -Contain 'M365Configurator.Plan'
        $plan.Signal             | Should -Be 'NeedsAttention'
        $plan.Items[0].Action    | Should -Be 'Update'
    }

    It 'loads from a path through the injected importer seam (no real file)' {
        $registry = @(
            New-M365Control -Id 'A' -Provider 'graph' -Shape 'singleton' -Title 'Ctl A' `
                -Get { param($Session) @{ enabled = $true } } -Set { param($Session, $Desired, $Current) }
        )
        $fakeProfile = New-TestProfile @( New-TestControl -Id 'A' -Settings @{ enabled = $true } )
        $importer = { param($Path) $fakeProfile }

        $plan = Invoke-M365DryRun -ProfilePath 'anywhere.yaml' -Registry $registry -Importer $importer -InformationAction Ignore

        $plan.Signal          | Should -Be 'Pass'
        $plan.Items[0].Action | Should -Be 'NoChange'
    }

    It 'never applies changes: no handler Set is invoked during a dry-run (FR-8)' {
        $script:setCalled = $false
        $registry = @(
            New-M365Control -Id 'A' -Provider 'graph' -Shape 'singleton' -Title 'Ctl A' `
                -Get { param($Session) @{ enabled = $true } } `
                -Set { param($Session, $Desired, $Current) $script:setCalled = $true }
        )
        $profile = New-TestProfile @( New-TestControl -Id 'A' -Settings @{ enabled = $false } )

        $null = Invoke-M365DryRun -Profile $profile -Registry $registry -InformationAction Ignore

        $script:setCalled | Should -BeFalse
    }
}

Describe 'Invoke-M365DryRun end-to-end (shipped profile + real registry, Graph mocked)' {

    BeforeAll {
        $script:profilePath = Join-Path $PSScriptRoot '..' 'profiles' 'security-baseline.yaml'
    }

    It 'plans ID-1 as Update when the tenant currently has security defaults ON' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator { @{ isEnabled = $true } }

        $plan = Invoke-M365DryRun -ProfilePath $script:profilePath -InformationAction Ignore
        $id1  = $plan.Items | Where-Object { $_.Id -eq 'ID-1' }

        $plan.Signal         | Should -Be 'NeedsAttention'
        $id1.Action          | Should -Be 'Update'
        $id1.Changes[0].Path | Should -Be 'isEnabled'
        $id1.Changes[0].To   | Should -BeFalse
    }

    It 'plans ID-1 as NoChange (Pass) when the tenant already has security defaults OFF' {
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator { @{ isEnabled = $false } }

        $plan = Invoke-M365DryRun -ProfilePath $script:profilePath -InformationAction Ignore

        $plan.Signal | Should -Be 'Pass'
        ($plan.Items | Where-Object { $_.Id -eq 'ID-1' }).Action | Should -Be 'NoChange'
    }
}

Describe 'Format-M365Plan (readable rendering, NFR-9)' {

    It 'renders header, glyphs, a from -> to change line, and a verdict footer' {
        InModuleScope M365Configurator {
            $registry = @(
                New-M365Control -Id 'ID-1' -Provider 'graph' -Shape 'singleton' -Title 'Security defaults' `
                    -Get { param($Session) @{ isEnabled = $true } } -Set { param($Session, $Desired, $Current) }
                New-M365Control -Id 'AM-2' -Provider 'graph' -Shape 'singleton' -Title 'Weak MFA methods' `
                    -Get { param($Session) @{ sms = $false } } -Set { param($Session, $Desired, $Current) }
            )
            $profile = [ordered]@{
                schemaVersion = '1.0'; name = 'baseline'; framework = 'X'; frameworkVersion = '1.0'
                controls = @(
                    [ordered]@{ id = 'ID-1'; framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'; settings = @{ isEnabled = $false } }
                    [ordered]@{ id = 'AM-2'; framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'; settings = @{ sms = $false } }
                )
            }

            $plan   = Get-M365Plan -Profile $profile -Registry $registry
            $lines  = Format-M365Plan -Plan $plan
            $joined = $lines -join "`n"

            $lines[0] | Should -Match 'Dry-run plan: baseline'
            $joined   | Should -Match 'Result: NEEDS ATTENTION'
            $joined   | Should -Match 'isEnabled: True -> False'
            $joined   | Should -Match '\[~\] ID-1'
            $joined   | Should -Match '\[=\] AM-2'
        }
    }
}

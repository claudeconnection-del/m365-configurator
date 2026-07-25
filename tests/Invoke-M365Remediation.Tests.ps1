#requires -Version 7.6
<#
    Tests for Invoke-M365Remediation (MCA-20; FR-11 deterministic remediation,
    NFR-6) — D7: remediation is apply-the-drifted-subset. No new diff/apply
    logic: computes the full plan, refuses on any Blocked/Unsupported item,
    builds a sub-plan of only the Create/Update items (preserving plan
    order), previews it, and — gated on -Approve — hands it to the existing
    Invoke-M365PlanApplication (MCA-18). Driven entirely with in-memory fake
    control handlers, so it is tenant-free.
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

Describe 'Invoke-M365Remediation' {

    It 'reports NothingToDo and invokes no Set when there is no drift' {
        $script:setCalled = $false
        $registry = @(
            New-M365Control -Id 'A' -Provider 'graph' -Shape 'singleton' -Title 'Ctl A' `
                -Get { param($Session) @{ v = 1 } } `
                -Set { param($Session, $Desired, $Current) $script:setCalled = $true }
        )
        $profile = New-TestProfile @( New-TestControl -Id 'A' -Settings @{ v = 1 } )

        $result = Invoke-M365Remediation -Profile $profile -Registry $registry -Approve -InformationAction Ignore

        $result.PSObject.TypeNames | Should -Contain 'M365Configurator.ApplyResult'
        $result.Outcome            | Should -Be 'NothingToDo'
        $script:setCalled          | Should -BeFalse
    }

    It 'with -Approve: applies only the drifted item of three, leaving the other two Set calls uninvoked' {
        $script:setCalls = [System.Collections.Generic.List[string]]::new()
        $registry = @(
            New-M365Control -Id 'A' -Provider 'graph' -Shape 'singleton' -Title 'A' `
                -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) $script:setCalls.Add('A') }
            New-M365Control -Id 'B' -Provider 'graph' -Shape 'singleton' -Title 'B' `
                -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) $script:setCalls.Add('B'); @{ done = $true } }
            New-M365Control -Id 'C' -Provider 'graph' -Shape 'singleton' -Title 'C' `
                -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) $script:setCalls.Add('C') }
        )
        $profile = New-TestProfile @(
            New-TestControl -Id 'A' -Settings @{ v = 1 }   # NoChange
            New-TestControl -Id 'B' -Settings @{ v = 2 }   # drifted
            New-TestControl -Id 'C' -Settings @{ v = 1 }   # NoChange
        )

        $result = Invoke-M365Remediation -Profile $profile -Registry $registry -Approve -InformationAction Ignore

        $result.Outcome     | Should -Be 'Applied'
        $result.Items.Count | Should -Be 1
        $result.Items[0].Id | Should -Be 'B'
        $result.Items[0].Detail.done | Should -BeTrue
        @($script:setCalls)  | Should -Be @('B')
    }

    It 'without -Approve: previews only (returns a Plan-typed object of the drifted subset), no Set invoked' {
        $script:setCalled = $false
        $registry = @(
            New-M365Control -Id 'A' -Provider 'graph' -Shape 'singleton' -Title 'A' `
                -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) $script:setCalled = $true }
            New-M365Control -Id 'B' -Provider 'graph' -Shape 'singleton' -Title 'B' `
                -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) $script:setCalled = $true }
        )
        $profile = New-TestProfile @(
            New-TestControl -Id 'A' -Settings @{ v = 1 }   # NoChange
            New-TestControl -Id 'B' -Settings @{ v = 2 }   # drifted
        )

        $preview = Invoke-M365Remediation -Profile $profile -Registry $registry -WarningAction SilentlyContinue -InformationAction Ignore

        $preview.PSObject.TypeNames | Should -Contain 'M365Configurator.Plan'
        $preview.Items.Count        | Should -Be 1
        $preview.Items[0].Id        | Should -Be 'B'
        $script:setCalled           | Should -BeFalse
    }

    It 'warns when -Approve is omitted' {
        $registry = @(
            New-M365Control -Id 'A' -Provider 'graph' -Shape 'singleton' -Title 'A' `
                -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) }
        )
        $profile = New-TestProfile @( New-TestControl -Id 'A' -Settings @{ v = 2 } )

        $warnings = @()
        $null = Invoke-M365Remediation -Profile $profile -Registry $registry -InformationAction Ignore -WarningVariable warnings -WarningAction SilentlyContinue

        $warnings.Count   | Should -BeGreaterThan 0
        "$($warnings[0])" | Should -Match 'Approve'
    }

    It 'throws and applies nothing when the plan has a Blocked item anywhere' {
        $script:setCalled = $false
        $registry = @(
            New-M365Control -Id 'A' -Provider 'graph' -Shape 'singleton' -Title 'A' `
                -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) $script:setCalled = $true }
            New-M365Control -Id 'GATED' -Provider 'graph' -Shape 'collection' -Title 'Gated' `
                -RequiredCapabilities @('entra-id-p2') `
                -Get { param($Session) throw 'Get must not run for a blocked control' } `
                -Set { param($Session, $Desired, $Current) $script:setCalled = $true }
        )
        $profile = New-TestProfile @(
            New-TestControl -Id 'A'     -Settings @{ v = 2 }
            New-TestControl -Id 'GATED' -Settings @{ x = 1 }
        )

        { Invoke-M365Remediation -Profile $profile -Registry $registry -Approve -InformationAction Ignore } |
            Should -Throw '*GATED*'
        $script:setCalled | Should -BeFalse
    }

    It 'preserves the relative order of drifted items from the full plan (DependsOn chain)' {
        $script:setCalls = [System.Collections.Generic.List[string]]::new()
        $registry = @(
            New-M365Control -Id 'FIRST' -Provider 'graph' -Shape 'singleton' -Title 'First' `
                -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) $script:setCalls.Add('FIRST') }
            New-M365Control -Id 'SECOND' -Provider 'graph' -Shape 'singleton' -Title 'Second' `
                -DependsOn @('FIRST') `
                -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) $script:setCalls.Add('SECOND') }
        )
        # Authored out of order on purpose; both are drifted so both must apply, FIRST before SECOND.
        $profile = New-TestProfile @(
            New-TestControl -Id 'SECOND' -Settings @{ v = 2 }
            New-TestControl -Id 'FIRST'  -Settings @{ v = 2 }
        )

        $result = Invoke-M365Remediation -Profile $profile -Registry $registry -Approve -InformationAction Ignore

        $result.Items.Count | Should -Be 2
        $result.Items[0].Id | Should -Be 'FIRST'
        $result.Items[1].Id | Should -Be 'SECOND'
        @($script:setCalls) | Should -Be @('FIRST', 'SECOND')
    }

    It 'loads from a path through the injected importer seam (no real file)' {
        $registry = @(
            New-M365Control -Id 'A' -Provider 'graph' -Shape 'singleton' -Title 'Ctl A' `
                -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) @{ ok = $true } }
        )
        $fakeProfile = New-TestProfile @( New-TestControl -Id 'A' -Settings @{ v = 2 } )
        $importer = { param($Path) $fakeProfile }

        $result = Invoke-M365Remediation -ProfilePath 'anywhere.yaml' -Registry $registry -Importer $importer -Approve -InformationAction Ignore

        $result.Outcome | Should -Be 'Applied'
    }
}

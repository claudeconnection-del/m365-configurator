#requires -Version 7.0
<#
    Tests for Get-M365Plan — the provider-agnostic dry-run engine (MCA-17; FR-8,
    NFR-6, NFR-9; ADR-0013). Driven entirely with in-memory fake control handlers
    (via New-M365Control) injected through -Registry, so it is tenant-free and the
    engine's own logic — gating, compare, ordering, aggregation — is what's tested.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force

    # A profile is just a map with a controls array; the engine reads id + settings.
    function New-TestProfile {
        param([object[]] $Controls, [string] $Name = 'test-profile')
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

Describe 'Get-M365Plan' {

    It 'reports NoChange (Pass) when desired matches current' {
        $registry = @(
            New-M365Control -Id 'A' -Provider 'graph' -Shape 'singleton' -Title 'Ctl A' `
                -Get { param($Session) @{ enabled = $true } } -Set { param($Session, $Desired, $Current) }
        )
        $profile = New-TestProfile @( New-TestControl -Id 'A' -Settings @{ enabled = $true } )

        $plan = Get-M365Plan -Profile $profile -Registry $registry

        $plan.Signal            | Should -Be 'Pass'
        $plan.Items.Count       | Should -Be 1
        $plan.Items[0].Action   | Should -Be 'NoChange'
        $plan.Items[0].Changes  | Should -BeNullOrEmpty
        $plan.ProfileName       | Should -Be 'test-profile'
    }

    It 'reports Update (NeedsAttention) with a From/To change when desired differs' {
        $registry = @(
            New-M365Control -Id 'A' -Provider 'graph' -Shape 'singleton' -Title 'Ctl A' `
                -Get { param($Session) @{ enabled = $true } } -Set { param($Session, $Desired, $Current) }
        )
        $profile = New-TestProfile @( New-TestControl -Id 'A' -Settings @{ enabled = $false } )

        $plan = Get-M365Plan -Profile $profile -Registry $registry

        $plan.Signal          | Should -Be 'NeedsAttention'
        $plan.Items[0].Action | Should -Be 'Update'
        $plan.Items[0].Changes.Count | Should -Be 1
        $plan.Items[0].Changes[0].Path | Should -Be 'enabled'
        $plan.Items[0].Changes[0].From | Should -BeTrue
        $plan.Items[0].Changes[0].To   | Should -BeFalse
    }

    It 'compares only the fields the profile declares (extra current state is not a change)' {
        $registry = @(
            New-M365Control -Id 'A' -Provider 'graph' -Shape 'singleton' -Title 'Ctl A' `
                -Get { param($Session) @{ enabled = $true; extra = 'ignored' } } -Set { param($Session, $Desired, $Current) }
        )
        $profile = New-TestProfile @( New-TestControl -Id 'A' -Settings @{ enabled = $true } )

        (Get-M365Plan -Profile $profile -Registry $registry).Items[0].Action | Should -Be 'NoChange'
    }

    It 'marks a control with no registered handler as Unsupported, with a reason' {
        $profile = New-TestProfile @( New-TestControl -Id 'GHOST' -Settings @{ x = 1 } )

        $plan = Get-M365Plan -Profile $profile -Registry @()

        $plan.Items[0].Action | Should -Be 'Unsupported'
        $plan.Items[0].Gate   | Should -Match 'GHOST'
        $plan.Signal          | Should -Be 'NeedsAttention'
    }

    It 'Blocks a control whose RequiredCapabilities the session does not provide (never calls Get)' {
        $registry = @(
            New-M365Control -Id 'P2' -Provider 'graph' -Shape 'collection' -Title 'Risk CA' `
                -RequiredCapabilities @('EntraIdP2') `
                -Get { param($Session) throw 'Get must not run for a blocked control' } -Set { param($Session, $Desired, $Current) }
        )
        $profile = New-TestProfile @( New-TestControl -Id 'P2' -Settings @{ enabled = $true } )
        $session = @{ Capabilities = @('EntraIdP1') }

        $plan = Get-M365Plan -Profile $profile -Session $session -Registry $registry

        $plan.Items[0].Action | Should -Be 'Blocked'
        $plan.Items[0].Gate   | Should -Match 'EntraIdP2'
    }

    It 'does not Block when the session provides the required capability' {
        $registry = @(
            New-M365Control -Id 'P2' -Provider 'graph' -Shape 'collection' -Title 'Risk CA' `
                -RequiredCapabilities @('EntraIdP2') `
                -Get { param($Session) @{ enabled = $true } } -Set { param($Session, $Desired, $Current) }
        )
        $profile = New-TestProfile @( New-TestControl -Id 'P2' -Settings @{ enabled = $true } )
        $session = @{ Capabilities = @('EntraIdP2') }

        (Get-M365Plan -Profile $profile -Session $session -Registry $registry).Items[0].Action | Should -Be 'NoChange'
    }

    It 'honours a custom Compare and validates its Action against the plan enum' {
        $registry = @(
            New-M365Control -Id 'PRESET' -Provider 'exo' -Shape 'preset' -Title 'Standard preset' `
                -Get { param($Session) @{ state = 'on' } } -Set { param($Session, $Desired, $Current) } `
                -Compare { param($Desired, $Current) @{ Action = 'Update'; Changes = @([pscustomobject]@{ Path = 'coverage'; From = 'partial'; To = 'all' }) } }
        )
        $profile = New-TestProfile @( New-TestControl -Id 'PRESET' -Settings @{ state = 'on' } )

        $plan = Get-M365Plan -Profile $profile -Registry $registry
        $plan.Items[0].Action | Should -Be 'Update'
        $plan.Items[0].Changes[0].Path | Should -Be 'coverage'
    }

    It 'throws when a custom Compare returns an Action outside the plan enum (NFR-6)' {
        $registry = @(
            New-M365Control -Id 'BAD' -Provider 'exo' -Shape 'preset' -Title 'Bad' `
                -Get { param($Session) @{} } -Set { param($Session, $Desired, $Current) } `
                -Compare { param($Desired, $Current) @{ Action = 'Delete'; Changes = @() } }
        )
        $profile = New-TestProfile @( New-TestControl -Id 'BAD' -Settings @{} )

        { Get-M365Plan -Profile $profile -Registry $registry } | Should -Throw '*Delete*'
    }

    It 'orders items so a dependency is planned before its dependent' {
        $registry = @(
            New-M365Control -Id 'FIRST'  -Provider 'graph' -Shape 'singleton' -Title 'First' `
                -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) }
            New-M365Control -Id 'SECOND' -Provider 'graph' -Shape 'collection' -Title 'Second' `
                -DependsOn @('FIRST') -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) }
        )
        # Author the profile in the WRONG order on purpose.
        $profile = New-TestProfile @(
            New-TestControl -Id 'SECOND' -Settings @{ v = 1 }
            New-TestControl -Id 'FIRST'  -Settings @{ v = 1 }
        )

        $plan = Get-M365Plan -Profile $profile -Registry $registry
        $plan.Items[0].Id | Should -Be 'FIRST'
        $plan.Items[1].Id | Should -Be 'SECOND'
    }

    It 'throws loudly on a dependency cycle (NFR-6)' {
        $registry = @(
            New-M365Control -Id 'A' -Provider 'graph' -Shape 'singleton' -Title 'A' `
                -DependsOn @('B') -Get { param($Session) @{} } -Set { param($Session, $Desired, $Current) }
            New-M365Control -Id 'B' -Provider 'graph' -Shape 'singleton' -Title 'B' `
                -DependsOn @('A') -Get { param($Session) @{} } -Set { param($Session, $Desired, $Current) }
        )
        $profile = New-TestProfile @(
            New-TestControl -Id 'A' -Settings @{}
            New-TestControl -Id 'B' -Settings @{}
        )

        { Get-M365Plan -Profile $profile -Registry $registry } | Should -Throw '*cycle*'
    }

    It 'throws when a handler DependsOn an unregistered control (NFR-6)' {
        $registry = @(
            New-M365Control -Id 'A' -Provider 'graph' -Shape 'singleton' -Title 'A' `
                -DependsOn @('NOPE') -Get { param($Session) @{} } -Set { param($Session, $Desired, $Current) }
        )
        $profile = New-TestProfile @( New-TestControl -Id 'A' -Settings @{} )

        { Get-M365Plan -Profile $profile -Registry $registry } | Should -Throw '*NOPE*'
    }

    It 'summarises per-Action counts across a mixed plan' {
        $registry = @(
            New-M365Control -Id 'SAME' -Provider 'graph' -Shape 'singleton' -Title 'Same' `
                -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) }
            New-M365Control -Id 'DIFF' -Provider 'graph' -Shape 'singleton' -Title 'Diff' `
                -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) }
        )
        $profile = New-TestProfile @(
            New-TestControl -Id 'SAME'  -Settings @{ v = 1 }
            New-TestControl -Id 'DIFF'  -Settings @{ v = 2 }
            New-TestControl -Id 'GHOST' -Settings @{ v = 3 }
        )

        $plan = Get-M365Plan -Profile $profile -Registry $registry
        $plan.Summary.NoChange    | Should -Be 1
        $plan.Summary.Update      | Should -Be 1
        $plan.Summary.Unsupported | Should -Be 1
        $plan.Signal              | Should -Be 'NeedsAttention'
    }
}

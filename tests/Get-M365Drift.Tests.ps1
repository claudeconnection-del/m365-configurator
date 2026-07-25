#requires -Version 7.6
<#
    Tests for Get-M365Drift — FR-10 drift detection (MCA-19) — and its
    renderer Format-M365DriftReport (NFR-9). Per D6, drift is the plan
    re-labelled: zero new diff logic, just a Get-M365Plan wrapper that
    projects Action -> Status. Fake controls + an injected importer keep it
    tenant-free and file-free. Drift is read-only: no handler Set is ever
    invoked (Get-M365Plan already guarantees this; asserted here as a spy
    check against regression).
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

Describe 'Get-M365Drift' {

    It 'reports InSync when every control matches (all-NoChange plan), statuses mapped' {
        $script:setCalled = $false
        $registry = @(
            New-M365Control -Id 'A' -Provider 'graph' -Shape 'singleton' -Title 'Ctl A' `
                -Get { param($Session) @{ enabled = $true } } `
                -Set { param($Session, $Desired, $Current) $script:setCalled = $true }
        )
        $profile = New-TestProfile @( New-TestControl -Id 'A' -Settings @{ enabled = $true } )

        $report = Get-M365Drift -Profile $profile -Registry $registry -InformationAction Ignore

        $report.PSObject.TypeNames | Should -Contain 'M365Configurator.DriftReport'
        $report.Signal             | Should -Be 'InSync'
        $report.Items[0].Status    | Should -Be 'InSync'
        $script:setCalled          | Should -BeFalse
    }

    It 'reports Drifted with Changes carried through when a control differs' {
        $registry = @(
            New-M365Control -Id 'A' -Provider 'graph' -Shape 'singleton' -Title 'Ctl A' `
                -Get { param($Session) @{ enabled = $true } } -Set { param($Session, $Desired, $Current) }
        )
        $profile = New-TestProfile @( New-TestControl -Id 'A' -Settings @{ enabled = $false } )

        $report = Get-M365Drift -Profile $profile -Registry $registry -InformationAction Ignore
        $item   = $report.Items[0]

        $report.Signal      | Should -Be 'NeedsAttention'
        $item.Status         | Should -Be 'Drifted'
        $item.Changes[0].Path | Should -Be 'enabled'
        $item.Changes[0].From | Should -BeTrue
        $item.Changes[0].To   | Should -BeFalse
    }

    It 'maps Blocked and Unsupported through with their Gate text' {
        $registry = @(
            New-M365Control -Id 'GATED' -Provider 'graph' -Shape 'singleton' -Title 'Gated Ctl' `
                -RequiredCapabilities @('graph') `
                -Get { param($Session) @{} } -Set { param($Session, $Desired, $Current) }
        )
        $profile = New-TestProfile @(
            New-TestControl -Id 'GATED' -Settings @{ x = 1 }
            New-TestControl -Id 'GHOST' -Settings @{ y = 2 }
        )

        $report = Get-M365Drift -Profile $profile -Registry $registry -Session @{ Capabilities = @() } -InformationAction Ignore

        $gated = $report.Items | Where-Object { $_.Id -eq 'GATED' }
        $ghost = $report.Items | Where-Object { $_.Id -eq 'GHOST' }

        $gated.Status | Should -Be 'Blocked'
        $gated.Gate   | Should -Match 'requires capability'
        $ghost.Status | Should -Be 'Unsupported'
        $ghost.Gate   | Should -Match 'no control handler is registered'
        $report.Signal | Should -Be 'NeedsAttention'
    }

    It 'loads from a path through the injected importer seam (no real file)' {
        $registry = @(
            New-M365Control -Id 'A' -Provider 'graph' -Shape 'singleton' -Title 'Ctl A' `
                -Get { param($Session) @{ enabled = $true } } -Set { param($Session, $Desired, $Current) }
        )
        $fakeProfile = New-TestProfile @( New-TestControl -Id 'A' -Settings @{ enabled = $true } )
        $importer = { param($Path) $fakeProfile }

        $report = Get-M365Drift -ProfilePath 'anywhere.yaml' -Registry $registry -Importer $importer -InformationAction Ignore

        $report.Signal        | Should -Be 'InSync'
        $report.Items[0].Status | Should -Be 'InSync'
    }

    It 'threads -NameOverride to both the desired settings and the session (MCA-16)' {
        InModuleScope M365Configurator {
            $registry = @(
                New-M365Control -Id 'ID-2' -Provider 'graph' -Shape 'collection' -Title 'Fake ID-2' `
                    -Get {
                        param($Session)
                        @{ displayName = (Get-M365MapValue (Get-M365MapValue $Session 'NameOverride') 'ID-2') }
                    } `
                    -Set { param($Session, $Desired, $Current) }
            )
            $profile = [ordered]@{
                schemaVersion = '1.0'; name = 'baseline'; framework = 'X'; frameworkVersion = '1.0'
                controls = @( [ordered]@{ id = 'ID-2'; framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'; settings = @{ displayName = 'Block legacy authentication' } } )
            }

            $report = Get-M365Drift -Profile $profile -Registry $registry -NameOverride @{ 'ID-2' = 'Contoso - Block legacy auth' } -InformationAction Ignore

            # Get's session-threaded name matched the rewritten desired name -> InSync.
            $report.Items[0].Status | Should -Be 'InSync'
        }
    }
}

Describe 'Format-M365DriftReport (readable rendering, NFR-9)' {

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
            $statusMap = @{ NoChange = 'InSync'; Create = 'Drifted'; Update = 'Drifted'; Blocked = 'Blocked'; Unsupported = 'Unsupported' }
            $items = @($plan.Items | ForEach-Object {
                [pscustomobject]@{ Id = $_.Id; Title = $_.Title; Provider = $_.Provider; Status = $statusMap[$_.Action]; Changes = $_.Changes; Gate = $_.Gate }
            })
            $summary = [ordered]@{ InSync = 0; Drifted = 0; Blocked = 0; Unsupported = 0 }
            foreach ($i in $items) { $summary[$i.Status]++ }
            $report = [pscustomobject]@{
                PSTypeName = 'M365Configurator.DriftReport'; ProfileName = 'baseline'
                Signal = 'NeedsAttention'; Summary = [pscustomobject] $summary; Items = $items
            }

            $lines  = Format-M365DriftReport -Report $report
            $joined = $lines -join "`n"

            $lines[0] | Should -Match 'Drift report: baseline'
            $joined   | Should -Match 'Result: NEEDS ATTENTION'
            $joined   | Should -Match 'isEnabled: True -> False'
            $joined   | Should -Match '\[~\] ID-1'
            $joined   | Should -Match '\[=\] AM-2'
        }
    }

    It 'renders the empty-report line, and blocked/unsupported glyphs with their gate reason' {
        InModuleScope M365Configurator {
            $emptyReport = [pscustomobject]@{
                PSTypeName = 'M365Configurator.DriftReport'; ProfileName = 'empty'; Signal = 'InSync'
                Summary = [pscustomobject]@{ InSync = 0; Drifted = 0; Blocked = 0; Unsupported = 0 }; Items = @()
            }
            $emptyLines = Format-M365DriftReport -Report $emptyReport
            ($emptyLines -join "`n") | Should -Match 'profile declares no controls'

            $gatedReport = [pscustomobject]@{
                PSTypeName = 'M365Configurator.DriftReport'; ProfileName = 'gated'; Signal = 'NeedsAttention'
                Summary = [pscustomobject]@{ InSync = 0; Drifted = 0; Blocked = 1; Unsupported = 1 }
                Items = @(
                    [pscustomobject]@{ Id = 'P2'; Title = 'Risk CA'; Provider = 'graph'; Status = 'Blocked'; Changes = @(); Gate = 'requires capability: EntraIdP2' }
                    [pscustomobject]@{ Id = 'GHOST'; Title = 'GHOST'; Provider = $null; Status = 'Unsupported'; Changes = @(); Gate = "no control handler is registered for id 'GHOST'" }
                )
            }
            $joined = (Format-M365DriftReport -Report $gatedReport) -join "`n"

            $joined | Should -Match '\[!\] P2'
            $joined | Should -Match 'requires capability'
            $joined | Should -Match '\[\?\] GHOST'
        }
    }
}

#requires -Version 7.6
<#
    Tests for the apply engine (MCA-18; FR-9, NFR-6): the private per-item
    application loop (Invoke-M365PlanApplication), its renderer
    (Format-M365ApplyResult), and the owner-facing entry point
    (Invoke-M365Apply). Driven entirely with in-memory fake control handlers
    (via New-M365Control), so it is tenant-free.
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

    # Every -Approve call in this file that doesn't inject its own -AuditWriter
    # falls through to Invoke-M365PlanApplication's real default (D10/MCA-35),
    # which writes JSONL via Write-M365AuditRecord. Redirect that default to a
    # throwaway scratch directory for the whole file so these engine tests
    # never touch the real './logs' (or the repo working directory).
    $script:m365AuditTestLogDir  = Join-Path ([System.IO.Path]::GetTempPath()) "m365-audit-test-$([guid]::NewGuid())"
    $script:m365AuditPreviousDir = $env:M365_CONFIGURATOR_LOG_DIR
    $env:M365_CONFIGURATOR_LOG_DIR = $script:m365AuditTestLogDir
}

AfterAll {
    $env:M365_CONFIGURATOR_LOG_DIR = $script:m365AuditPreviousDir
    if (Test-Path -LiteralPath $script:m365AuditTestLogDir) {
        Remove-Item -LiteralPath $script:m365AuditTestLogDir -Recurse -Force
    }
}

Describe 'Invoke-M365Apply' {

    It 'without -Approve: renders the plan, returns the plan object, and applies nothing' {
        $script:setCalled = $false
        $registry = @(
            New-M365Control -Id 'A' -Provider 'graph' -Shape 'singleton' -Title 'Ctl A' `
                -Get { param($Session) @{ enabled = $true } } `
                -Set { param($Session, $Desired, $Current) $script:setCalled = $true }
        )
        $profile = New-TestProfile @( New-TestControl -Id 'A' -Settings @{ enabled = $false } )

        $result = Invoke-M365Apply -Profile $profile -Registry $registry -WarningAction SilentlyContinue -InformationAction Ignore

        $result.PSObject.TypeNames | Should -Contain 'M365Configurator.Plan'
        $result.Signal             | Should -Be 'NeedsAttention'
        $script:setCalled          | Should -BeFalse
    }

    It 'warns when -Approve is omitted' {
        $registry = @(
            New-M365Control -Id 'A' -Provider 'graph' -Shape 'singleton' -Title 'Ctl A' `
                -Get { param($Session) @{ enabled = $true } } -Set { param($Session, $Desired, $Current) }
        )
        $profile = New-TestProfile @( New-TestControl -Id 'A' -Settings @{ enabled = $false } )

        $warnings = @()
        $null = Invoke-M365Apply -Profile $profile -Registry $registry -InformationAction Ignore -WarningVariable warnings -WarningAction SilentlyContinue

        $warnings.Count | Should -BeGreaterThan 0
        "$($warnings[0])" | Should -Match 'Approve'
    }

    It 'with -Approve, clean plan: applies Create/Update items via Set in dependency order and reports Applied/Skipped per item' {
        $script:setCalls = [System.Collections.Generic.List[string]]::new()
        $registry = @(
            New-M365Control -Id 'FIRST' -Provider 'graph' -Shape 'singleton' -Title 'First' `
                -Get { param($Session) @{ v = 1 } } `
                -Set { param($Session, $Desired, $Current) $script:setCalls.Add('FIRST') }
            New-M365Control -Id 'SECOND' -Provider 'graph' -Shape 'singleton' -Title 'Second' `
                -DependsOn @('FIRST') `
                -Get { param($Session) @{ v = 1 } } `
                -Set { param($Session, $Desired, $Current) $script:setCalls.Add('SECOND'); @{ done = $true } }
        )
        # Authored out of order on purpose — the engine's dependency sort must still put FIRST first.
        $profile = New-TestProfile @(
            New-TestControl -Id 'SECOND' -Settings @{ v = 2 }
            New-TestControl -Id 'FIRST'  -Settings @{ v = 1 }
        )

        $result = Invoke-M365Apply -Profile $profile -Registry $registry -Approve -InformationAction Ignore

        $result.PSObject.TypeNames | Should -Contain 'M365Configurator.ApplyResult'
        $result.Outcome            | Should -Be 'Applied'
        $result.Items[0].Id        | Should -Be 'FIRST'
        $result.Items[0].Outcome   | Should -Be 'Skipped'
        $result.Items[1].Id        | Should -Be 'SECOND'
        $result.Items[1].Outcome   | Should -Be 'Applied'
        $result.Items[1].Detail.done | Should -BeTrue
        @($script:setCalls)        | Should -Be @('SECOND')
    }

    It 'with -Approve, throws and applies nothing when the plan has a Blocked item' {
        $script:setCalled = $false
        $registry = @(
            New-M365Control -Id 'GATED' -Provider 'graph' -Shape 'collection' -Title 'Gated' `
                -RequiredCapabilities @('entra-id-p2') `
                -Get { param($Session) throw 'Get must not run for a blocked control' } `
                -Set { param($Session, $Desired, $Current) $script:setCalled = $true }
        )
        $profile = New-TestProfile @( New-TestControl -Id 'GATED' -Settings @{ x = 1 } )

        { Invoke-M365Apply -Profile $profile -Registry $registry -Approve -InformationAction Ignore } |
            Should -Throw '*GATED*'
        $script:setCalled | Should -BeFalse
    }

    It 'with -Approve, throws and applies nothing when the plan has an Unsupported item' {
        $script:setCalled = $false
        $registry = @(
            New-M365Control -Id 'KNOWN' -Provider 'graph' -Shape 'singleton' -Title 'Known' `
                -Get { param($Session) @{ v = 1 } } `
                -Set { param($Session, $Desired, $Current) $script:setCalled = $true }
        )
        $profile = New-TestProfile @(
            New-TestControl -Id 'GHOST' -Settings @{ x = 1 }
            New-TestControl -Id 'KNOWN' -Settings @{ v = 2 }
        )

        { Invoke-M365Apply -Profile $profile -Registry $registry -Approve -InformationAction Ignore } |
            Should -Throw '*GHOST*'
        $script:setCalled | Should -BeFalse
    }

    It 'stops at the first Set failure: earlier items stay Applied, the failing item is Failed, later items are NotAttempted (FR-9, NFR-6)' {
        $registry = @(
            New-M365Control -Id 'ONE' -Provider 'graph' -Shape 'singleton' -Title 'One' `
                -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) @{ ok = $true } }
            New-M365Control -Id 'TWO' -Provider 'graph' -Shape 'singleton' -Title 'Two' `
                -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) throw 'tenant rejected the change' }
            New-M365Control -Id 'THREE' -Provider 'graph' -Shape 'singleton' -Title 'Three' `
                -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) @{ ok = $true } }
        )
        $profile = New-TestProfile @(
            New-TestControl -Id 'ONE'   -Settings @{ v = 2 }
            New-TestControl -Id 'TWO'   -Settings @{ v = 2 }
            New-TestControl -Id 'THREE' -Settings @{ v = 2 }
        )

        $result = Invoke-M365Apply -Profile $profile -Registry $registry -Approve -InformationAction Ignore

        # The per-item throw must be captured and reported, never escape the call (FR-9).
        $result.Outcome          | Should -Be 'Failed'
        $result.Items[0].Outcome | Should -Be 'Applied'
        $result.Items[1].Outcome | Should -Be 'Failed'
        $result.Items[1].Error   | Should -Match 'tenant rejected the change'
        $result.Items[2].Outcome | Should -Be 'NotAttempted'
    }

    It 'reports NothingToDo and invokes no Set when every item is NoChange' {
        $script:setCalled = $false
        $registry = @(
            New-M365Control -Id 'A' -Provider 'graph' -Shape 'singleton' -Title 'A' `
                -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) $script:setCalled = $true }
        )
        $profile = New-TestProfile @( New-TestControl -Id 'A' -Settings @{ v = 1 } )

        $result = Invoke-M365Apply -Profile $profile -Registry $registry -Approve -InformationAction Ignore

        $result.Outcome   | Should -Be 'NothingToDo'
        $script:setCalled | Should -BeFalse
    }

    It 'loads from a path through the injected importer seam (no real file)' {
        $registry = @(
            New-M365Control -Id 'A' -Provider 'graph' -Shape 'singleton' -Title 'Ctl A' `
                -Get { param($Session) @{ enabled = $true } } -Set { param($Session, $Desired, $Current) @{ ok = $true } }
        )
        $fakeProfile = New-TestProfile @( New-TestControl -Id 'A' -Settings @{ enabled = $false } )
        $importer = { param($Path) $fakeProfile }

        $result = Invoke-M365Apply -ProfilePath 'anywhere.yaml' -Registry $registry -Importer $importer -Approve -InformationAction Ignore

        $result.Outcome | Should -Be 'Applied'
    }

    It 'threads -NameOverride to both the desired settings and the session (MCA-16)' {
        InModuleScope M365Configurator {
            $registry = @(
                New-M365Control -Id 'ID-2' -Provider 'graph' -Shape 'collection' -Title 'Fake ID-2' `
                    -Get {
                        param($Session)
                        @{ displayName = (Get-M365MapValue (Get-M365MapValue $Session 'NameOverride') 'ID-2') }
                    } `
                    -Set { param($Session, $Desired, $Current) @{ ok = $true } }
            )
            $profile = [ordered]@{
                schemaVersion = '1.0'; name = 'baseline'; framework = 'X'; frameworkVersion = '1.0'
                controls = @( [ordered]@{ id = 'ID-2'; framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'; settings = @{ displayName = 'Block legacy authentication' } } )
            }

            $result = Invoke-M365Apply -Profile $profile -Registry $registry -NameOverride @{ 'ID-2' = 'Contoso - Block legacy auth' } -Approve -InformationAction Ignore

            # Get's session-threaded name matched the rewritten desired name -> NoChange -> nothing to apply.
            $result.Outcome | Should -Be 'NothingToDo'
        }
    }
}

Describe 'Invoke-M365PlanApplication (private per-item application loop)' {

    It 'resolves the handler from the supplied Registry by id and fails loud when it is missing' {
        InModuleScope M365Configurator {
            $plan = [pscustomobject]@{
                PSTypeName = 'M365Configurator.Plan'; ProfileName = 'x'; Signal = 'NeedsAttention'
                Summary = [pscustomobject]@{}
                Items = @([pscustomobject]@{ PSTypeName = 'M365Configurator.PlanItem'; Id = 'NOPE'; Title = 'Nope'; Provider = 'graph'; Action = 'Update'; Changes = @(); Gate = $null; Desired = @{}; Current = @{} })
            }

            { Invoke-M365PlanApplication -Plan $plan -Registry @() } | Should -Throw '*NOPE*'
        }
    }

    It 'fails loud on a plan item whose Action is Blocked or Unsupported — callers must gate first (NFR-6)' {
        InModuleScope M365Configurator {
            $plan = [pscustomobject]@{
                PSTypeName = 'M365Configurator.Plan'; ProfileName = 'x'; Signal = 'NeedsAttention'
                Summary = [pscustomobject]@{}
                Items = @([pscustomobject]@{ PSTypeName = 'M365Configurator.PlanItem'; Id = 'B'; Title = 'B'; Provider = 'graph'; Action = 'Blocked'; Changes = @(); Gate = 'x'; Desired = @{}; Current = $null })
            }

            { Invoke-M365PlanApplication -Plan $plan -Registry @() } | Should -Throw '*Blocked*'
        }
    }

    It 'emits run-started / apply-item / run-finished records via the injected AuditWriter, in order, with the right shape and stable field order (MCA-35, D10)' {
        InModuleScope M365Configurator {
            $registry = @(
                New-M365Control -Id 'ONE' -Provider 'graph' -Shape 'singleton' -Title 'One' `
                    -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) @{ ok = $true } }
            )
            $session = [pscustomobject]@{ Graph = [pscustomobject]@{ Account = 'admin@contoso.com' } }
            $profile = [ordered]@{
                schemaVersion = '1.0'; name = 'baseline'; framework = 'X'; frameworkVersion = '1.0'
                controls = @(
                    [ordered]@{ id = 'ONE'; framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'; settings = @{ v = 2 } }
                )
            }
            $plan = Get-M365Plan -Profile $profile -Registry $registry -Session $session

            # List[object], not List[hashtable]: a strongly-typed hashtable list
            # would coerce the engine's [ordered] records to unordered
            # Hashtables on .Add(), hiding the very ordering this test verifies.
            $captured = [System.Collections.Generic.List[object]]::new()
            $auditWriter = { param($Record) $captured.Add($Record) }.GetNewClosure()

            $result = Invoke-M365PlanApplication -Plan $plan -Session $session -Registry $registry -AuditWriter $auditWriter

            $captured.Count | Should -Be 3
            $captured[0].action | Should -Be 'run-started'
            $captured[0].actor | Should -Be 'admin@contoso.com'
            $captured[0].runId | Should -Not -BeNullOrEmpty
            $captured[0].profileName | Should -Be 'baseline'
            $captured[0].itemCount | Should -Be 1
            # Documented D10 schema order (plus the run-started extras) — proves
            # the engine builds [ordered] records, not plain (hash-order) ones.
            @($captured[0].Keys) | Should -Be @('timestamp', 'actor', 'runId', 'action', 'controlId', 'outcome', 'changes', 'error', 'profileName', 'itemCount')

            $captured[1].action    | Should -Be 'apply-item'
            $captured[1].controlId | Should -Be 'ONE'
            $captured[1].outcome   | Should -Be 'Applied'
            $captured[1].runId     | Should -Be $captured[0].runId
            # The item's Changes (Path/From/To) must survive onto its audit record.
            @($captured[1].changes).Count | Should -Be 1
            $captured[1].changes[0].Path  | Should -Be 'v'
            $captured[1].changes[0].From  | Should -Be 1
            $captured[1].changes[0].To    | Should -Be 2

            $captured[2].action  | Should -Be 'run-finished'
            $captured[2].outcome | Should -Be 'Applied'
            $captured[2].runId   | Should -Be $captured[0].runId
            $captured[2].counts.Applied | Should -Be 1

            $result.Outcome | Should -Be 'Applied'
        }
    }

    It 'logs the error and NotAttempted follow-on items on their own apply-item records, and reports run-finished Outcome Failed (MCA-35, D10)' {
        InModuleScope M365Configurator {
            $registry = @(
                New-M365Control -Id 'ONE' -Provider 'graph' -Shape 'singleton' -Title 'One' `
                    -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) @{ ok = $true } }
                New-M365Control -Id 'TWO' -Provider 'graph' -Shape 'singleton' -Title 'Two' `
                    -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) throw 'tenant rejected the change' }
                New-M365Control -Id 'THREE' -Provider 'graph' -Shape 'singleton' -Title 'Three' `
                    -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) @{ ok = $true } }
            )
            $profile = [ordered]@{
                schemaVersion = '1.0'; name = 'baseline'; framework = 'X'; frameworkVersion = '1.0'
                controls = @(
                    [ordered]@{ id = 'ONE';   framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'; settings = @{ v = 2 } }
                    [ordered]@{ id = 'TWO';   framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'; settings = @{ v = 2 } }
                    [ordered]@{ id = 'THREE'; framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'; settings = @{ v = 2 } }
                )
            }
            $plan = Get-M365Plan -Profile $profile -Registry $registry

            $captured = [System.Collections.Generic.List[object]]::new()
            $auditWriter = { param($Record) $captured.Add($Record) }.GetNewClosure()

            $null = Invoke-M365PlanApplication -Plan $plan -Registry $registry -AuditWriter $auditWriter

            $itemRecords = @($captured | Where-Object { $_.action -eq 'apply-item' })
            $itemRecords.Count | Should -Be 3

            ($itemRecords | Where-Object controlId -eq 'ONE').outcome   | Should -Be 'Applied'
            ($itemRecords | Where-Object controlId -eq 'ONE').error     | Should -BeNullOrEmpty

            $failedRecord = $itemRecords | Where-Object controlId -eq 'TWO'
            $failedRecord.outcome | Should -Be 'Failed'
            $failedRecord.error   | Should -Match 'tenant rejected the change'

            $notAttemptedRecord = $itemRecords | Where-Object controlId -eq 'THREE'
            $notAttemptedRecord.outcome | Should -Be 'NotAttempted'
            $notAttemptedRecord.error   | Should -BeNullOrEmpty

            $finished = $captured | Where-Object { $_.action -eq 'run-finished' }
            $finished.outcome        | Should -Be 'Failed'
            $finished.counts.Applied | Should -Be 1
            $finished.counts.Failed  | Should -Be 1
            $finished.counts.NotAttempted | Should -Be 1
        }
    }

    It 'defaults the AuditWriter to Write-M365AuditRecord' {
        InModuleScope M365Configurator {
            Mock Write-M365AuditRecord {}

            $registry = @(
                New-M365Control -Id 'ONE' -Provider 'graph' -Shape 'singleton' -Title 'One' `
                    -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) @{ ok = $true } }
            )
            $profile = [ordered]@{
                schemaVersion = '1.0'; name = 'baseline'; framework = 'X'; frameworkVersion = '1.0'
                controls = @( [ordered]@{ id = 'ONE'; framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'; settings = @{ v = 2 } } )
            }
            $plan = Get-M365Plan -Profile $profile -Registry $registry

            $null = Invoke-M365PlanApplication -Plan $plan -Registry $registry

            Should -Invoke Write-M365AuditRecord -Times 3
        }
    }
}

Describe 'Format-M365ApplyResult (readable rendering, NFR-9)' {

    It 'renders header, glyphs, an error line for a failure, and a verdict footer' {
        InModuleScope M365Configurator {
            $registry = @(
                New-M365Control -Id 'ONE' -Provider 'graph' -Shape 'singleton' -Title 'One' `
                    -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) @{ ok = $true } }
                New-M365Control -Id 'TWO' -Provider 'graph' -Shape 'singleton' -Title 'Two' `
                    -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) throw 'boom' }
                New-M365Control -Id 'THREE' -Provider 'graph' -Shape 'singleton' -Title 'Three' `
                    -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) @{ ok = $true } }
            )
            $profile = [ordered]@{
                schemaVersion = '1.0'; name = 'baseline'; framework = 'X'; frameworkVersion = '1.0'
                controls = @(
                    [ordered]@{ id = 'ONE';   framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'; settings = @{ v = 2 } }
                    [ordered]@{ id = 'TWO';   framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'; settings = @{ v = 2 } }
                    [ordered]@{ id = 'THREE'; framework = 'X'; frameworkVersion = '1.0'; provider = 'graph'; settings = @{ v = 2 } }
                )
            }

            $plan   = Get-M365Plan -Profile $profile -Registry $registry
            $result = Invoke-M365PlanApplication -Plan $plan -Registry $registry
            $lines  = Format-M365ApplyResult -Result $result
            $joined = $lines -join "`n"

            $lines[0] | Should -Match 'Apply: baseline'
            $joined   | Should -Match 'Result: FAILED'
            $joined   | Should -Match '\[\+\] ONE'
            $joined   | Should -Match '\[x\] TWO.*\(boom\)'
            $joined   | Should -Match '\[\.\] THREE'
        }
    }

    It 'renders the nothing-to-apply line' {
        InModuleScope M365Configurator {
            $emptyPlan = [pscustomobject]@{ PSTypeName = 'M365Configurator.Plan'; ProfileName = 'empty'; Signal = 'Pass'; Summary = [pscustomobject]@{}; Items = @() }
            $result = Invoke-M365PlanApplication -Plan $emptyPlan -Registry @()
            $lines  = Format-M365ApplyResult -Result $result

            ($lines -join "`n") | Should -Match 'nothing to apply'
            $result.Outcome     | Should -Be 'NothingToDo'
        }
    }
}

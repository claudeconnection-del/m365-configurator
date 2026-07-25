#requires -Version 7.6
<#
    Tests for Read-M365ControlState (MCA-36; D11): the real -ControlReader
    Save-M365Profile was built to receive. It's Public (not Private) despite
    reading like an engine-internal piece -- see the file header's note and
    the S19 correction in docs/RUNBOOK.md: it must be directly callable from
    scripts/m365config.ps1, which runs outside the module and cannot resolve
    a private, unexported function by name. Driven entirely with in-memory
    fake control handlers, so it is tenant-free.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force
}

Describe 'Read-M365ControlState' {

    It 'emits a descriptor (id, provider, settings) per readable, in-scope control' {
        $registry = @(
            New-M365Control -Id 'A' -Provider 'graph' -Shape 'singleton' -Title 'A' -RequiredCapabilities @('graph') `
                -Get { param($Session) @{ enabled = $true } } -Set { param($Session, $Desired, $Current) }
            New-M365Control -Id 'B' -Provider 'exo' -Shape 'singleton' -Title 'B' -RequiredCapabilities @('exo') `
                -Get { param($Session) @{ mode = 'Off' } } -Set { param($Session, $Desired, $Current) }
        )
        $session = [pscustomobject]@{ Capabilities = @('graph', 'exo') }

        $result = @(Read-M365ControlState -Session $session -Registry $registry)

        $result.Count | Should -Be 2
        ($result | Where-Object id -eq 'A').provider        | Should -Be 'graph'
        ($result | Where-Object id -eq 'A').settings.enabled | Should -BeTrue
        ($result | Where-Object id -eq 'B').provider         | Should -Be 'exo'
        ($result | Where-Object id -eq 'B').settings.mode    | Should -Be 'Off'
    }

    It 'skips a control whose Get returns $null (nothing to save)' {
        $registry = @(
            New-M365Control -Id 'ABSENT' -Provider 'graph' -Shape 'collection' -Title 'Absent' -RequiredCapabilities @('graph') `
                -Get { param($Session) $null } -Set { param($Session, $Desired, $Current) }
            New-M365Control -Id 'PRESENT' -Provider 'graph' -Shape 'singleton' -Title 'Present' -RequiredCapabilities @('graph') `
                -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) }
        )
        $session = [pscustomobject]@{ Capabilities = @('graph') }

        $result = @(Read-M365ControlState -Session $session -Registry $registry -Verbose 4>$null)

        $result.Count | Should -Be 1
        $result[0].id  | Should -Be 'PRESENT'
    }

    It 'skips a control gated by a missing required capability' {
        $registry = @(
            New-M365Control -Id 'GATED' -Provider 'graph' -Shape 'singleton' -Title 'Gated' -RequiredCapabilities @('entra-id-p2') `
                -Get { param($Session) throw 'Get must not run for a capability-gated control' } -Set { param($Session, $Desired, $Current) }
        )
        $session = [pscustomobject]@{ Capabilities = @('graph') }

        $result = @(Read-M365ControlState -Session $session -Registry $registry -Verbose 4>$null)

        $result | Should -BeNullOrEmpty
    }

    It 'strips the stashed id key from a COPY of the settings, leaving the Get result untouched' {
        $original = [ordered]@{ displayName = 'X'; state = 'enabled'; id = 'tenant-guid-123' }
        $registry = @(
            New-M365Control -Id 'ID-2' -Provider 'graph' -Shape 'collection' -Title 'ID-2' -RequiredCapabilities @('graph') `
                -Get { param($Session) $original } -Set { param($Session, $Desired, $Current) }
        )
        $session = [pscustomobject]@{ Capabilities = @('graph') }

        $result = @(Read-M365ControlState -Session $session -Registry $registry)

        $result[0].settings.Keys        | Should -Not -Contain 'id'
        $result[0].settings.displayName | Should -Be 'X'
        # The object Get actually returned must be untouched.
        $original.Contains('id') | Should -BeTrue
        $original['id']          | Should -Be 'tenant-guid-123'
    }

    It 'defaults -Registry to the real Get-M365ControlRegistry' {
        Mock Get-M365ControlRegistry -ModuleName M365Configurator {
            @(New-M365Control -Id 'X' -Provider 'graph' -Shape 'singleton' -Title 'X' -RequiredCapabilities @('graph') `
                    -Get { param($Session) @{ v = 1 } } -Set { param($Session, $Desired, $Current) })
        }
        $session = [pscustomobject]@{ Capabilities = @('graph') }

        $result = @(Read-M365ControlState -Session $session)

        $result.Count | Should -Be 1
        $result[0].id | Should -Be 'X'
        Should -Invoke Get-M365ControlRegistry -ModuleName M365Configurator -Times 1
    }
}

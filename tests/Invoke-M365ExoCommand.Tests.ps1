#requires -Version 7.6
<#
    Tests for Invoke-M365ExoCommand (D5) — the module's single Exchange Online
    call seam, mirroring Invoke-M365GraphRequest (ADR-0014). Resolves the
    named cmdlet at call time so the EXO module is a runtime prerequisite
    (ADR-0011 preflight), not a parse-time dependency.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force
}

Describe 'Invoke-M365ExoCommand' {

    It 'invokes the named command with the splatted parameters and returns its output' {
        # global: scope — InModuleScope switches session state, and Get-Command
        # (inside Invoke-M365ExoCommand) only reliably finds a fake registered
        # in the truly global function table from there.
        function global:Get-FakeExoThing {
            param($Identity, $State)
            [pscustomobject]@{ Identity = $Identity; State = $State }
        }
        try {
            $result = InModuleScope M365Configurator {
                Invoke-M365ExoCommand -Name 'Get-FakeExoThing' -Parameters @{ Identity = 'Default'; State = 'Enabled' }
            }

            $result.Identity | Should -Be 'Default'
            $result.State    | Should -Be 'Enabled'
        }
        finally {
            Remove-Item -LiteralPath function:Get-FakeExoThing -ErrorAction SilentlyContinue
        }
    }

    It 'invokes with no parameters when -Parameters is omitted' {
        function global:Get-FakeExoNoArgs { 'called' }
        try {
            $result = InModuleScope M365Configurator {
                Invoke-M365ExoCommand -Name 'Get-FakeExoNoArgs'
            }

            $result | Should -Be 'called'
        }
        finally {
            Remove-Item -LiteralPath function:Get-FakeExoNoArgs -ErrorAction SilentlyContinue
        }
    }

    It 'fails loud when the named command does not exist' {
        InModuleScope M365Configurator {
            { Invoke-M365ExoCommand -Name 'Get-ThisCommandDoesNotExist12345' } | Should -Throw
        }
    }
}

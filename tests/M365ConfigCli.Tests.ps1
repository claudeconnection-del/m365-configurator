#requires -Version 7.6
<#
    Tests for the CLI dispatcher (MCA-36; D11; ADR-0012 CLI-first):
    scripts/m365config.ps1. A thin dispatcher — every test injects a
    capturing -Invoker so no module function is ever really invoked against a
    tenant; the real module is imported so the script's "unless already
    loaded" import guard has nothing to do.
#>

BeforeAll {
    $manifest  = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force
    $script:cli = Join-Path $PSScriptRoot '..' 'scripts' 'm365config.ps1'

    function New-CapturingInvoker {
        $captured = [System.Collections.Generic.List[object]]::new()
        $invoker = { param($FunctionName, $Splat) $captured.Add([pscustomobject]@{ FunctionName = $FunctionName; Splat = $Splat }) }.GetNewClosure()
        [pscustomobject]@{ Invoker = $invoker; Captured = $captured }
    }
}

Describe 'scripts/m365config.ps1 (CLI dispatcher)' {

    It 'save: maps to Save-M365Profile with Name/Framework/FrameworkVersion and a working ControlReader' {
        $rig = New-CapturingInvoker

        & $script:cli save -Name 'my-tenant-baseline' -Invoker $rig.Invoker

        $rig.Captured.Count | Should -Be 1
        $rig.Captured[0].FunctionName | Should -Be 'Save-M365Profile'
        $rig.Captured[0].Splat.Name             | Should -Be 'my-tenant-baseline'
        $rig.Captured[0].Splat.Framework        | Should -Be 'CISA-SCuBA'
        $rig.Captured[0].Splat.FrameworkVersion | Should -Be '1.5.0'
        $rig.Captured[0].Splat.ControlReader | Should -BeOfType [scriptblock]

        # "Working": a real, invokable seam correctly threading -Session through
        # to Read-M365ControlState — not a stub. Capabilities-less session ->
        # every real control is capability-gated -> empty result, no throw, no
        # tenant/network call.
        $result = @(& $rig.Captured[0].Splat.ControlReader)
        $result | Should -BeNullOrEmpty
    }

    It 'save: -OutPath forwards as -Path' {
        $rig = New-CapturingInvoker

        & $script:cli save -Name 'x' -OutPath 'profiles/x.yaml' -Invoker $rig.Invoker

        $rig.Captured[0].Splat.Path | Should -Be 'profiles/x.yaml'
    }

    It 'save: throws when -Name is missing' {
        $rig = New-CapturingInvoker

        { & $script:cli save -Invoker $rig.Invoker } | Should -Throw '*-Name*'
        $rig.Captured.Count | Should -Be 0
    }

    It 'dryrun: maps to Invoke-M365DryRun with -ProfilePath and -Session' {
        $rig = New-CapturingInvoker
        $session = [pscustomobject]@{ Capabilities = @('graph') }

        & $script:cli dryrun -ProfilePath './profiles/security-baseline.yaml' -Session $session -Invoker $rig.Invoker

        $rig.Captured[0].FunctionName          | Should -Be 'Invoke-M365DryRun'
        $rig.Captured[0].Splat.ProfilePath     | Should -Be './profiles/security-baseline.yaml'
        $rig.Captured[0].Splat.Session         | Should -Be $session
        $rig.Captured[0].Splat.ContainsKey('NameOverride') | Should -BeFalse
    }

    It 'dryrun: throws when -ProfilePath is missing' {
        $rig = New-CapturingInvoker

        { & $script:cli dryrun -Invoker $rig.Invoker } | Should -Throw '*-ProfilePath*'
        $rig.Captured.Count | Should -Be 0
    }

    It 'apply: maps to Invoke-M365Apply and forwards -Approve and -NameOverride' {
        $rig = New-CapturingInvoker
        $override = @{ 'ID-2' = 'Contoso - Block legacy auth' }

        & $script:cli apply -ProfilePath './profiles/security-baseline.yaml' -Approve -NameOverride $override -Invoker $rig.Invoker

        $rig.Captured[0].FunctionName      | Should -Be 'Invoke-M365Apply'
        $rig.Captured[0].Splat.ProfilePath | Should -Be './profiles/security-baseline.yaml'
        $rig.Captured[0].Splat.Approve     | Should -BeTrue
        $rig.Captured[0].Splat.NameOverride | Should -Be $override
    }

    It 'apply: omits -Approve and -NameOverride from the splat when not supplied' {
        $rig = New-CapturingInvoker

        & $script:cli apply -ProfilePath './profiles/security-baseline.yaml' -Invoker $rig.Invoker

        $rig.Captured[0].Splat.ContainsKey('Approve')      | Should -BeFalse
        $rig.Captured[0].Splat.ContainsKey('NameOverride') | Should -BeFalse
    }

    It 'apply: throws when -ProfilePath is missing' {
        $rig = New-CapturingInvoker

        { & $script:cli apply -Approve -Invoker $rig.Invoker } | Should -Throw '*-ProfilePath*'
        $rig.Captured.Count | Should -Be 0
    }

    It 'drift: maps to Get-M365Drift with -ProfilePath and -Session' {
        $rig = New-CapturingInvoker
        $session = [pscustomobject]@{ Capabilities = @('exo') }

        & $script:cli drift -ProfilePath './profiles/security-baseline.yaml' -Session $session -Invoker $rig.Invoker

        $rig.Captured[0].FunctionName      | Should -Be 'Get-M365Drift'
        $rig.Captured[0].Splat.ProfilePath | Should -Be './profiles/security-baseline.yaml'
        $rig.Captured[0].Splat.Session     | Should -Be $session
    }

    It 'drift: throws when -ProfilePath is missing' {
        $rig = New-CapturingInvoker

        { & $script:cli drift -Invoker $rig.Invoker } | Should -Throw '*-ProfilePath*'
        $rig.Captured.Count | Should -Be 0
    }

    It 'rejects an unknown command via ValidateSet' {
        { & $script:cli bogus-command } | Should -Throw '*ValidateSet*'
    }
}

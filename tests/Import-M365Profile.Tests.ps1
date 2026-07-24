#requires -Version 7.0
<#
    Tests for Get-M365Profile (list/select) and Import-M365Profile (load/import a
    file) — MCA-15; FR-6; ADR-0009.

    A profile is loaded by path or imported from an exported single file; it is
    parsed and validated against schema v1, and a malformed, schema-invalid, or
    credential-bearing file is rejected loudly (NFR-6/NFR-1). These tests use real
    temp files so the default filesystem list/read paths are exercised.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force

    $script:validYaml = @'
schemaVersion: "1.0"
name: security-baseline
framework: SCuBA
frameworkVersion: 1.5.0
controls:
  - id: MS.AAD.1.1
    framework: SCuBA
    frameworkVersion: 1.5.0
    provider: graph
    settings:
      state: enabled
'@

    $script:workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("m365prof-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $script:workDir | Out-Null
}

AfterAll {
    if ($script:workDir -and (Test-Path $script:workDir)) {
        Remove-Item $script:workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Get-M365Profile' {

    It 'lists the profiles found under the profile directory' {
        $dir = Join-Path $script:workDir 'list'
        New-Item -ItemType Directory -Path $dir | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'baseline.yaml') -Value $script:validYaml
        Set-Content -LiteralPath (Join-Path $dir 'strict.yaml')   -Value $script:validYaml

        $list = @(Get-M365Profile -ProfileDirectory $dir)

        $list.Count | Should -Be 2
        ($list.Name | Sort-Object) | Should -Be @('baseline', 'strict')
        $list[0].PSObject.Properties.Name | Should -Contain 'Path'
    }

    It 'returns nothing (no throw) for a missing or empty directory' {
        $empty = Join-Path $script:workDir 'nope'
        { Get-M365Profile -ProfileDirectory $empty } | Should -Not -Throw
        @(Get-M365Profile -ProfileDirectory $empty).Count | Should -Be 0
    }
}

Describe 'Import-M365Profile' {

    It 'imports a valid profile file and returns an object that validates against schema v1' {
        $file = Join-Path $script:workDir 'valid.yaml'
        Set-Content -LiteralPath $file -Value $script:validYaml

        $profile = Import-M365Profile -Path $file

        (Test-M365Profile -Profile $profile).Valid | Should -BeTrue
        $profile.name | Should -Be 'security-baseline'
        @($profile.controls).Count | Should -Be 1
    }

    It 'rejects malformed YAML loudly (NFR-6)' {
        $file = Join-Path $script:workDir 'malformed.yaml'
        Set-Content -LiteralPath $file -Value "name: security`ncontrols: [unclosed"

        { Import-M365Profile -Path $file } | Should -Throw
    }

    It 'rejects a credential-bearing file loudly (config-only; NFR-1)' {
        $file = Join-Path $script:workDir 'leaky.yaml'
        Set-Content -LiteralPath $file -Value @'
schemaVersion: "1.0"
name: leaky
framework: SCuBA
frameworkVersion: 1.5.0
controls:
  - id: MS.AAD.1.1
    framework: SCuBA
    frameworkVersion: 1.5.0
    provider: graph
    settings:
      clientSecret: super-secret-value
'@

        { Import-M365Profile -Path $file } | Should -Throw -ExpectedMessage '*credential*'
    }

    It 'rejects a schema-invalid file loudly (missing required field)' {
        $file = Join-Path $script:workDir 'invalid.yaml'
        Set-Content -LiteralPath $file -Value @'
name: no-framework
controls: []
'@

        { Import-M365Profile -Path $file } | Should -Throw
    }

    It 'throws a clear error when the file does not exist' {
        { Import-M365Profile -Path (Join-Path $script:workDir 'ghost.yaml') } | Should -Throw
    }

    It 'round-trips a profile written by Save-M365Profile' {
        $file = Join-Path $script:workDir 'roundtrip.yaml'
        Save-M365Profile -Name 'roundtrip' -Framework 'SCuBA' -FrameworkVersion '1.5.0' -Path $file `
            -ControlReader { @( [ordered]@{ id = 'MS.AAD.1.1'; provider = 'graph'; settings = [ordered]@{ state = 'enabled' } } ) } | Out-Null

        $profile = Import-M365Profile -Path $file

        (Test-M365Profile -Profile $profile).Valid | Should -BeTrue
        $profile.name | Should -Be 'roundtrip'
    }
}

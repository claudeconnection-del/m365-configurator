#requires -Version 7.6
<#
    Guards the ADR-0015 runtime pin (as amended 2026-07-25): the manifest floor,
    the per-file #requires floors, and the module-pin <-> runtime coupling the
    MCA-39 review caught (ExchangeOnlineManagement 3.10.0+ requires PowerShell
    7.6+ / .NET 10). These tests are what stop the floor drifting again.
#>

BeforeAll {
    $script:repoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:manifestPath = Join-Path $repoRoot 'src' 'M365Configurator' 'M365Configurator.psd1'
    $script:manifestData = Import-PowerShellDataFile -Path $manifestPath

    # The one place the ADR-0015 floor is restated in tests. Bumping the floor is
    # a deliberate edit here AND in the manifest AND in ADR-0015.
    $script:floor = [version] '7.6'

    Import-Module $manifestPath -Force
}

Describe 'ADR-0015 runtime pin' {

    It 'declares the ADR-0015 floor in the module manifest' {
        [version] $manifestData.PowerShellVersion | Should -Be $floor
    }

    It 'is a valid module manifest' {
        { Test-ModuleManifest -Path $manifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'declares no per-file #requires floor below ADR-0015 in src/ or tests/' {
        # scripts/ is exempt by design: the bootstrap/install scripts keep a low
        # #requires so their friendly floor guard can run on downlevel hosts
        # (ADR-0011); each carries its own runtime check instead.
        $files = @(Get-ChildItem (Join-Path $repoRoot 'src')   -Recurse -Include '*.ps1', '*.psm1' -File) +
                 @(Get-ChildItem (Join-Path $repoRoot 'tests') -Filter '*.ps1' -File)

        $files.Count | Should -BeGreaterThan 40   # the sweep covers the whole module + suite

        $below = foreach ($file in $files) {
            $first = Get-Content -LiteralPath $file.FullName -TotalCount 1
            if ($first -match '^#requires -Version (?<v>[0-9.]+)') {
                if ([version] $Matches.v -lt $floor) { $file.FullName }
            }
            else {
                # No #requires at all would silently inherit the host: also a fault.
                $file.FullName
            }
        }
        $below | Should -BeNullOrEmpty
    }

    It 'keeps the manifest floor consistent with the ExchangeOnlineManagement pin (3.10.0+ needs pwsh 7.6+)' {
        $exo = Get-M365RequiredModule | Where-Object { $_.Name -eq 'ExchangeOnlineManagement' }
        $exo | Should -Not -BeNullOrEmpty

        if ([version] $exo.Version -ge [version] '3.10.0') {
            # Microsoft: EXO module 3.10.0+ requires PowerShell 7.6+ (.NET 10).
            [version] $manifestData.PowerShellVersion | Should -BeGreaterOrEqual ([version] '7.6')
        }
    }
}

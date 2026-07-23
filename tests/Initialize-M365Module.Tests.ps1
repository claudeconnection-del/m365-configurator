#requires -Version 7.0
<#
    Tests for Initialize-M365Module — the orchestration that ties the module
    lifecycle together (MCA-2): detect status -> for each unsatisfied module
    present the self-healing remediation offer -> on consent install (CurrentUser,
    pinned via -RequiredVersion) -> import -> report the resolved versions.

    It must be idempotent (a no-op install when the pin is already met) and
    audit-logged (every step announced, pinned versions surfaced). The side
    effects — the installed-module lookup, the consent prompt, the installer, and
    the importer — are all injected as seams so the orchestration logic is
    unit-testable without touching the machine, prompting a human, or reaching
    the PowerShell Gallery. See ADR-0011 (self-healing) and CONTRIBUTING §4.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force

    # A required set fixed for the tests, independent of the real pinned list.
    $script:required = @(
        [pscustomobject]@{ Name = 'Foo.Bar'; Version = '1.2.3'; Reason = 'test fixture' }
    )

    # A consent seam that must never fire in the satisfied/idempotent paths.
    $script:denyAll  = { param($Offer) throw "consent should not have been requested for '$($Offer.Name)'" }
    $script:grantAll = { param($Offer) $true }

    # An importer that echoes back a resolved version, standing in for the real
    # Import-Module. It records what it was asked to import.
    $script:makeImporter = {
        param([version] $Resolves)
        {
            param($Name, $MinimumVersion)
            $script:imported += [pscustomobject]@{ Name = $Name; MinimumVersion = $MinimumVersion }
            [pscustomobject]@{ Name = $Name; Version = $Resolves }
        }.GetNewClosure()
    }
}

Describe 'Initialize-M365Module' {

    BeforeEach {
        $script:installed = @()   # offers passed to the installer seam
        $script:imported  = @()   # (Name, MinimumVersion) pairs passed to the importer seam
    }

    Context 'when the pinned module is already satisfied (idempotent path)' {

        It 'installs nothing, never asks for consent, and reports the resolved version' {
            $lookup   = { param($Name) @([pscustomobject]@{ Name = $Name; Version = [version] '1.2.3' }) }
            $importer = & $script:makeImporter ([version] '1.2.3')

            $report = Initialize-M365Module -Required $script:required `
                -InstalledLookup $lookup -Consent $script:denyAll `
                -Installer { param($Offer) $script:installed += $Offer } -Importer $importer

            $script:installed | Should -HaveCount 0        # idempotent: no install
            $report | Should -HaveCount 1
            $report[0].Name            | Should -Be 'Foo.Bar'
            $report[0].Action          | Should -Be 'AlreadySatisfied'
            $report[0].Imported        | Should -BeTrue
            $report[0].ResolvedVersion | Should -Be '1.2.3'
            $report[0].Satisfied       | Should -BeTrue
        }
    }

    Context 'when the pinned module is missing and consent is granted' {

        It 'installs it once at CurrentUser scope pinned to the required version, then imports and reports' {
            $lookup   = { param($Name) @() }                       # nothing installed
            $importer = & $script:makeImporter ([version] '1.2.3') # resolves after install

            $report = Initialize-M365Module -Required $script:required `
                -InstalledLookup $lookup -Consent $script:grantAll `
                -Installer { param($Offer) $script:installed += $Offer } -Importer $importer

            $script:installed | Should -HaveCount 1
            $script:installed[0].Name            | Should -Be 'Foo.Bar'
            $script:installed[0].RequiredVersion | Should -Be '1.2.3'   # pinned exactly
            $script:installed[0].Command         | Should -Match 'CurrentUser'
            $script:installed[0].Command         | Should -Not -Match 'AllUsers'

            $report[0].Action          | Should -Be 'Installed'
            $report[0].Imported        | Should -BeTrue
            $report[0].ResolvedVersion | Should -Be '1.2.3'
            $report[0].Satisfied       | Should -BeTrue
        }
    }

    Context 'when the pinned module is installed but older and consent is granted' {

        It 'reports the action as an Upgrade' {
            $lookup   = { param($Name) @([pscustomobject]@{ Name = $Name; Version = [version] '1.0.0' }) }
            $importer = & $script:makeImporter ([version] '1.2.3')

            $report = Initialize-M365Module -Required $script:required `
                -InstalledLookup $lookup -Consent $script:grantAll `
                -Installer { param($Offer) $script:installed += $Offer } -Importer $importer

            $script:installed | Should -HaveCount 1
            $report[0].Action          | Should -Be 'Upgraded'
            $report[0].ResolvedVersion | Should -Be '1.2.3'
            $report[0].Satisfied       | Should -BeTrue
        }
    }

    Context 'when remediation is offered but consent is declined' {

        It 'does not install or import, and reports the module as Declined and unsatisfied' {
            $lookup   = { param($Name) @() }                       # missing
            $importer = & $script:makeImporter ([version] '1.2.3')
            $decline  = { param($Offer) $false }

            $report = Initialize-M365Module -Required $script:required `
                -InstalledLookup $lookup -Consent $decline `
                -Installer { param($Offer) $script:installed += $Offer } -Importer $importer

            $script:installed | Should -HaveCount 0   # gated apply: no consent, no change
            $script:imported  | Should -HaveCount 0   # nothing to import
            $report[0].Action    | Should -Be 'Declined'
            $report[0].Imported  | Should -BeFalse
            $report[0].Satisfied | Should -BeFalse
        }
    }

    Context 'when the installer fails' {

        It 'reports the module as Failed with the error, without dead-ending the run' {
            $lookup   = { param($Name) @() }
            $importer = & $script:makeImporter ([version] '1.2.3')
            $boom     = { param($Offer) throw 'gallery unreachable' }

            $report = Initialize-M365Module -Required $script:required `
                -InstalledLookup $lookup -Consent $script:grantAll `
                -Installer $boom -Importer $importer

            $report[0].Action    | Should -Be 'Failed'
            $report[0].Imported  | Should -BeFalse
            $report[0].Satisfied | Should -BeFalse
            $report[0].Detail    | Should -Match 'gallery unreachable'
        }
    }

    Context 'when the install succeeds but the import fails' {

        It 'reports Failed when the importer returns no module' {
            $lookup      = { param($Name) @() }
            $nilImporter = { param($Name, $MinimumVersion) $null }

            $report = Initialize-M365Module -Required $script:required `
                -InstalledLookup $lookup -Consent $script:grantAll `
                -Installer { param($Offer) $script:installed += $Offer } -Importer $nilImporter

            $script:installed | Should -HaveCount 1        # install happened
            $report[0].Action    | Should -Be 'Failed'
            $report[0].Imported  | Should -BeFalse
            $report[0].Satisfied | Should -BeFalse
            $report[0].Detail    | Should -Match 'no module'
        }

        It 'reports Failed with the error when the importer throws' {
            $lookup        = { param($Name) @() }
            $throwImporter = { param($Name, $MinimumVersion) throw 'assembly load conflict' }

            $report = Initialize-M365Module -Required $script:required `
                -InstalledLookup $lookup -Consent $script:grantAll `
                -Installer { param($Offer) $script:installed += $Offer } -Importer $throwImporter

            $report[0].Action    | Should -Be 'Failed'
            $report[0].Imported  | Should -BeFalse
            $report[0].Satisfied | Should -BeFalse
            $report[0].Detail    | Should -Match 'assembly load conflict'
        }
    }

    Context 'the real default installer (security tenets on the actual install path)' {

        It 'invokes Install-Module at CurrentUser scope pinned to the required version, never AllUsers' {
            # Exercise the built-in -Installer default (not a fake) to prove the real
            # install command never elevates and pins exactly. Install-Module is
            # mocked inside the module scope so nothing reaches the Gallery.
            $lookup   = { param($Name) @() }                       # missing -> triggers install
            $importer = & $script:makeImporter ([version] '1.2.3') # keep import off the machine

            Mock -ModuleName M365Configurator Install-Module { }

            $null = Initialize-M365Module -Required $script:required `
                -InstalledLookup $lookup -Consent $script:grantAll -Importer $importer

            Should -Invoke -ModuleName M365Configurator Install-Module -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'Foo.Bar' -and
                $RequiredVersion -eq '1.2.3' -and
                $Scope -eq 'CurrentUser'
            }
        }
    }

    Context 'audit logging (NFR-6 loud, NFR-7 pins surfaced)' {

        It 'announces each pinned module and its required version on the verbose stream' {
            $lookup   = { param($Name) @([pscustomobject]@{ Name = $Name; Version = [version] '1.2.3' }) }
            $importer = & $script:makeImporter ([version] '1.2.3')

            $verbose = Initialize-M365Module -Required $script:required `
                -InstalledLookup $lookup -Consent $script:denyAll `
                -Installer { param($Offer) $script:installed += $Offer } -Importer $importer `
                -Verbose 4>&1

            ($verbose -join "`n") | Should -Match 'Foo\.Bar'
            ($verbose -join "`n") | Should -Match '1\.2\.3'
        }
    }

    Context 'across several modules in one run' {

        It 'handles satisfied, installable, and declined modules independently in one report' {
            $required = @(
                [pscustomobject]@{ Name = 'Already.Ok'; Version = '2.0.0'; Reason = 'present' }
                [pscustomobject]@{ Name = 'Needs.Install'; Version = '1.2.3'; Reason = 'missing' }
                [pscustomobject]@{ Name = 'User.Says.No'; Version = '3.1.0'; Reason = 'declined' }
            )
            $lookup = {
                param($Name)
                switch ($Name) {
                    'Already.Ok' { @([pscustomobject]@{ Name = $Name; Version = [version] '2.0.0' }) }
                    default      { @() }
                }
            }
            # Consent yes for the installable one, no for the other.
            $consent = { param($Offer) $Offer.Name -eq 'Needs.Install' }
            $importer = {
                param($Name, $MinimumVersion)
                $script:imported += [pscustomobject]@{ Name = $Name; MinimumVersion = $MinimumVersion }
                [pscustomobject]@{ Name = $Name; Version = $MinimumVersion }
            }

            $report = Initialize-M365Module -Required $required `
                -InstalledLookup $lookup -Consent $consent `
                -Installer { param($Offer) $script:installed += $Offer } -Importer $importer

            $report | Should -HaveCount 3
            ($report | Where-Object Name -eq 'Already.Ok').Action    | Should -Be 'AlreadySatisfied'
            ($report | Where-Object Name -eq 'Needs.Install').Action | Should -Be 'Installed'
            ($report | Where-Object Name -eq 'User.Says.No').Action  | Should -Be 'Declined'

            $script:installed | Should -HaveCount 1                  # only the consented one
            $script:installed[0].Name | Should -Be 'Needs.Install'
        }
    }
}

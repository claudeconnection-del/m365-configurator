#requires -Version 7.6

function Get-M365RequiredModule {
    <#
    .SYNOPSIS
        The single source of truth for the PowerShell modules m365-configurator
        depends on, and their pinned versions.

    .DESCRIPTION
        Returns one record per required module: its name, the pinned version, and
        the reason the dependency exists. This is the one place versions are
        declared (FR-1, NFR-7) — every install / detect / import / report step
        reads from here, and an upgrade is a deliberate edit to this list,
        verified against the pinned module's cmdlet surface.

        The set is kept intentionally small (NFR-3). Pinned versions are the
        current PSGallery releases as of the last deliberate bump.

    .OUTPUTS
        pscustomobject with properties: Name, Version, Reason.

    .EXAMPLE
        Get-M365RequiredModule | Format-Table Name, Version
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    [pscustomobject]@{
        Name    = 'Microsoft.Graph.Authentication'
        Version = '2.38.1'
        Reason  = 'Connect/disconnect Microsoft Graph + on-demand Graph sub-module loading'
    }
    [pscustomobject]@{
        # RUNTIME COUPLING: 3.10.0+ requires PowerShell 7.6+ (.NET 10 assembly
        # dependencies — Microsoft EXO module docs; research 02 §7). The module
        # manifest's PowerShellVersion floor must stay >= 7.6 while this pin is
        # >= 3.10.0 (ADR-0015, amended 2026-07-25; guarded by the manifest tests).
        Name    = 'ExchangeOnlineManagement'
        Version = '3.10.0'
        Reason  = 'Exchange Online / Defender for Office 365 configuration'
    }
    [pscustomobject]@{
        Name    = 'powershell-yaml'
        Version = '0.4.12'
        Reason  = 'Profile authoring/parsing (YAML authored, JSON canonical) — ADR-0008'
    }
}

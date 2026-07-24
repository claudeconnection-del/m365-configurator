#requires -Version 7.0

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

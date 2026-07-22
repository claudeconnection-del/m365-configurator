#requires -Version 7.0

function Get-M365ModuleRemediation {
    <#
    .SYNOPSIS
        Turns unsatisfied module status into a consent-ready "self-healing" offer.

    .DESCRIPTION
        The app is self-healing about its own dependencies: rather than failing
        with "won't work, you need X", it produces, for each unsatisfied module,
        an actionable offer — what's missing, where it lives (the PowerShell
        Gallery), and the exact, non-elevating command that would fix it — so the
        interface layer can ask "I'm missing this, want me to get it for you?".

        This is pure data (no installs, no prompts, no network): it mirrors the
        app's dry-run -> gated-apply model for its own prerequisites. Satisfied
        modules produce no offer — there is nothing to heal.

    .OUTPUTS
        pscustomobject per unsatisfied module: Name, Action (Install|Upgrade),
        RequiredVersion, InstalledVersion, Source, SourceLocation, Command, Offer.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [pscustomobject[]] $Status = (Get-M365ModuleStatus)
    )

    foreach ($item in $Status) {
        if ($item.Satisfied) { continue }   # healthy — nothing to heal

        $action = if ($item.Installed) { 'Upgrade' } else { 'Install' }

        # Deep link to the exact pinned package, and the exact remedy command.
        # CurrentUser scope only — the app never elevates (design tenet / NFR-1).
        $sourceLocation = "https://www.powershellgallery.com/packages/$($item.Name)/$($item.RequiredVersion)"
        $command = "Install-Module -Name $($item.Name) -RequiredVersion $($item.RequiredVersion) -Scope CurrentUser -Repository PSGallery"

        $offer = if ($item.Installed) {
            "$($item.Name) v$($item.InstalledVersion) is older than the required v$($item.RequiredVersion). It can be updated from the PowerShell Gallery. Update it now (user scope)?"
        } else {
            "$($item.Name) is not installed. It's available from the PowerShell Gallery (v$($item.RequiredVersion)). Install it now (user scope)?"
        }

        [pscustomobject]@{
            Name             = $item.Name
            Action           = $action
            RequiredVersion  = $item.RequiredVersion
            InstalledVersion = $item.InstalledVersion
            Source           = 'PSGallery'
            SourceLocation   = $sourceLocation
            Command          = $command
            Offer            = $offer
        }
    }
}

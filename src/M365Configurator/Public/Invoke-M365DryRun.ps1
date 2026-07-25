#requires -Version 7.6

function Invoke-M365DryRun {
    <#
    .SYNOPSIS
        Previews what a profile would change against the connected tenant — the
        owner-facing dry-run entry point (MCA-17; FR-8, NFR-9; ADR-0012 CLI-first).

    .DESCRIPTION
        Loads a profile (from a path, or takes an already-loaded object), computes
        the plan with the change engine (Get-M365Plan), prints a readable rendering
        for visual inspection (NFR-9), and returns the structured plan object for
        scripting. It changes NOTHING: the engine only ever calls handler Get seams,
        never Set (FR-8).

        The profile importer and control registry are injected seams (defaults: the
        real Import-M365Profile and Get-M365ControlRegistry), so the whole flow is
        unit-testable with fake controls and no tenant, no files.

    .OUTPUTS
        pscustomobject (PSTypeName 'M365Configurator.Plan') — also rendered to the
        host.

    .EXAMPLE
        Connect-M365Graph
        Invoke-M365DryRun -ProfilePath ./profiles/security-baseline.yaml
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path', Position = 0)]
        [string] $ProfilePath,

        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [Alias('Profile')]
        $InputObject,

        # The connected session, passed to each handler's Get seam.
        $Session,

        # Injected control set; defaults to the real registry.
        [AllowNull()]
        $Registry,

        # Seam: loads + validates a profile from a path. Default is the real importer.
        [scriptblock] $Importer = { param([string] $Path) Import-M365Profile -Path $Path },

        # Per-client renames of name-scoped controls (MCA-16; FR-7, D9): control id
        # -> replacement name. Rewrites the profile's name-bearing setting AND
        # threads the effective name through a shallow session copy, so a
        # name-scoped control's Get seam still finds the (renamed) tenant object.
        [hashtable] $NameOverride
    )

    $profileObject =
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            Write-Verbose "Dry-run: loading profile from '$ProfilePath'."
            & $Importer $ProfilePath
        }
        else {
            $InputObject
        }

    if ($NameOverride -and $NameOverride.Count -gt 0) {
        $renamed = Set-M365ProfileNameOverride -InputObject $profileObject -NameOverride $NameOverride
        $profileObject = $renamed.Profile
        $Session = Set-M365SessionNameOverride -Session $Session -NameOverride $renamed.NameOverride
    }

    Write-Verbose 'Dry-run: computing plan (no changes are applied).'
    $plan = Get-M365Plan -Profile $profileObject -Session $Session -Registry $Registry

    foreach ($line in (Format-M365Plan -Plan $plan)) { Write-Host $line }

    $attention = @($plan.Items | Where-Object { $_.Action -ne 'NoChange' }).Count
    Write-Verbose "Dry-run: $($plan.Signal) - $attention of $(@($plan.Items).Count) control(s) need attention."

    $plan
}

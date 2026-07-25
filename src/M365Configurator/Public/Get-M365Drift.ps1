#requires -Version 7.6

function Get-M365Drift {
    <#
    .SYNOPSIS
        Scans a connected tenant against a saved profile and reports drift —
        the owner-facing drift-detection entry point (MCA-19; FR-10, NFR-9).

    .DESCRIPTION
        D6: drift is the dry-run plan re-labelled — zero new diff logic.
        Loads a profile (from a path, or takes an already-loaded object),
        computes the plan with the change engine (Get-M365Plan), and projects
        each plan item's Action to a drift Status: NoChange -> InSync,
        Create/Update -> Drifted, Blocked -> Blocked, Unsupported ->
        Unsupported. Prints a readable rendering for visual inspection
        (NFR-9) and returns the structured report for scripting. It changes
        NOTHING: Get-M365Plan only ever calls handler Get seams, never Set.

        The profile importer and control registry are injected seams
        (defaults: the real Import-M365Profile and Get-M365ControlRegistry),
        so the whole flow is unit-testable with fake controls and no tenant,
        no files.

    .OUTPUTS
        pscustomobject (PSTypeName 'M365Configurator.DriftReport') — also
        rendered to the host. ProfileName, Signal ('InSync' |
        'NeedsAttention'; NeedsAttention when ANY item is Drifted, Blocked,
        or Unsupported), Summary (per-Status counts), Items[] each { Id,
        Title, Provider, Status, Changes, Gate }.

    .EXAMPLE
        Connect-M365ExchangeOnline
        Get-M365Drift -ProfilePath ./profiles/security-baseline.yaml
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
        [scriptblock] $Importer = { param([string] $Path) Import-M365Profile -Path $Path }
    )

    $profileObject =
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            Write-Verbose "Drift: loading profile from '$ProfilePath'."
            & $Importer $ProfilePath
        }
        else {
            $InputObject
        }

    Write-Verbose 'Drift: computing plan (read-only; no changes are applied).'
    $plan = Get-M365Plan -Profile $profileObject -Session $Session -Registry $Registry

    $statusMap = @{ NoChange = 'InSync'; Create = 'Drifted'; Update = 'Drifted'; Blocked = 'Blocked'; Unsupported = 'Unsupported' }
    $summary = [ordered]@{ InSync = 0; Drifted = 0; Blocked = 0; Unsupported = 0 }
    $items = [System.Collections.Generic.List[object]]::new()

    foreach ($planItem in @($plan.Items)) {
        $status = $statusMap[$planItem.Action]
        $summary[$status]++
        $items.Add([pscustomobject]@{
                PSTypeName = 'M365Configurator.DriftItem'
                Id       = $planItem.Id
                Title    = $planItem.Title
                Provider = $planItem.Provider
                Status   = $status
                Changes  = @($planItem.Changes)
                Gate     = $planItem.Gate
            })
    }

    $signal = if ($summary.Drifted -or $summary.Blocked -or $summary.Unsupported) { 'NeedsAttention' } else { 'InSync' }

    $report = [pscustomobject]@{
        PSTypeName  = 'M365Configurator.DriftReport'
        ProfileName = $plan.ProfileName
        Signal      = $signal
        Summary     = [pscustomobject] $summary
        Items       = $items.ToArray()
    }

    foreach ($line in (Format-M365DriftReport -Report $report)) { Write-Host $line }

    $attention = @($report.Items | Where-Object { $_.Status -ne 'InSync' }).Count
    Write-Verbose "Drift: $($report.Signal) - $attention of $(@($report.Items).Count) control(s) drifted/gated."

    $report
}

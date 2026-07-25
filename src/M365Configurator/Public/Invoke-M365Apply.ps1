#requires -Version 7.6

function Invoke-M365Apply {
    <#
    .SYNOPSIS
        Applies a profile to the connected tenant, gated on an explicit
        -Approve and a clean plan (MCA-18; FR-9, NFR-6; ADR-0012 CLI-first).

    .DESCRIPTION
        Recomputes the plan the same way Invoke-M365DryRun does — never trusts
        a stale plan — and renders it. Without -Approve, nothing is applied;
        this doubles as a final preview of exactly what -Approve would do.
        With -Approve, the tenant is touched only if the plan contains no
        Blocked or Unsupported items (no partial application on a plan that
        still needs attention apply itself can't resolve — NFR-6); otherwise
        it throws, naming the offending control(s). Applying is delegated to
        Invoke-M365PlanApplication (D1), which fails fast on the first
        per-item error and reports every item's outcome rather than letting
        the exception escape (FR-9).

        The profile importer and control registry are injected seams, as in
        Invoke-M365DryRun, so the whole flow is unit-testable with fake
        controls and no tenant, no files. The registry is resolved once (to
        the real Get-M365ControlRegistry when not supplied) and reused for
        both the plan and the apply, so the same control ids and handlers are
        in play throughout a single call.

    .OUTPUTS
        Without -Approve: pscustomobject (PSTypeName 'M365Configurator.Plan').
        With -Approve: pscustomobject (PSTypeName 'M365Configurator.ApplyResult').
        Both are also rendered to the host.

    .EXAMPLE
        Connect-M365Graph
        Invoke-M365Apply -ProfilePath ./profiles/security-baseline.yaml -Approve
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path', Position = 0)]
        [string] $ProfilePath,

        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [Alias('Profile')]
        $InputObject,

        # The connected session, passed to each handler's Get/Set seam.
        $Session,

        # Injected control set; defaults to the real registry.
        [AllowNull()]
        $Registry,

        # Seam: loads + validates a profile from a path. Default is the real importer.
        [scriptblock] $Importer = { param([string] $Path) Import-M365Profile -Path $Path },

        # Explicit go-ahead (FR-9): without it, nothing is applied.
        [switch] $Approve
    )

    $profileObject =
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            Write-Verbose "Apply: loading profile from '$ProfilePath'."
            & $Importer $ProfilePath
        }
        else {
            $InputObject
        }

    # Resolved once and reused for the plan AND the apply, so both stages agree
    # on exactly which handlers exist for which control ids.
    $effectiveRegistry = if ($null -eq $Registry) { Get-M365ControlRegistry } else { $Registry }

    Write-Verbose 'Apply: computing plan (no changes are applied yet).'
    $plan = Get-M365Plan -Profile $profileObject -Session $Session -Registry $effectiveRegistry

    foreach ($line in (Format-M365Plan -Plan $plan)) { Write-Host $line }

    if (-not $Approve) {
        Write-Warning 'Apply: -Approve was not supplied; nothing was applied. Re-run with -Approve to apply this plan.'
        return $plan
    }

    $ungated = @($plan.Items | Where-Object { $_.Action -in @('Blocked', 'Unsupported') })
    if ($ungated.Count -gt 0) {
        $offenders = ($ungated | ForEach-Object { "$($_.Id) ($($_.Action))" }) -join ', '
        throw "Refusing to apply: the plan contains control(s) that need attention before they can be applied: $offenders."
    }

    Write-Verbose 'Apply: plan is clean and approved — applying.'
    $result = Invoke-M365PlanApplication -Plan $plan -Session $Session -Registry $effectiveRegistry

    foreach ($line in (Format-M365ApplyResult -Result $result)) { Write-Host $line }

    $attention = @($result.Items | Where-Object { $_.Outcome -ne 'Skipped' }).Count
    Write-Verbose "Apply: $($result.Outcome) - $attention of $(@($result.Items).Count) control(s) touched."

    $result
}

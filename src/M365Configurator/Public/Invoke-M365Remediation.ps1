#requires -Version 7.6

function Invoke-M365Remediation {
    <#
    .SYNOPSIS
        Previews and, on approval, applies exactly the drifted subset of a
        profile against the connected tenant (MCA-20; FR-11, NFR-6).

    .DESCRIPTION
        D7: remediation is apply-the-drifted-subset — no new diff or apply
        logic. Computes the full plan the same way Invoke-M365DryRun/
        Invoke-M365Apply do, refuses (throws) if any item is Blocked or
        Unsupported (the same all-or-nothing gate as apply — a plan that
        still needs attention can't be half-remediated), then builds a
        sub-plan of only the Create/Update items, preserving the order the
        full plan's dependency sort already established (a dependency that
        is itself NoChange is correctly absent from the sub-plan — it needs
        no re-apply).

        Without -Approve: renders the drifted-subset preview and returns it
        (a 'M365Configurator.Plan'-typed object, named "<profile> (remediation)"
        so it reads distinctly from a full dry-run); nothing is touched. With
        -Approve: hands the sub-plan to Invoke-M365PlanApplication (MCA-18,
        D1) — the exact same per-item, fail-fast application loop apply
        uses, so remediation inherits its NFR-6 guarantees for free. Because
        the sub-plan is deterministic (same drift in, same items out) so is
        the remediation (FR-11); re-running after a successful remediation
        recomputes a plan with no more drift, satisfying idempotence.

        The profile importer and control registry are injected seams, as in
        Invoke-M365Apply, so the whole flow is unit-testable with fake
        controls and no tenant, no files.

    .OUTPUTS
        Without -Approve: pscustomobject (PSTypeName 'M365Configurator.Plan')
        — the drifted-subset preview. With -Approve: pscustomobject
        (PSTypeName 'M365Configurator.ApplyResult'). Both are also rendered
        to the host.

    .EXAMPLE
        Connect-M365Graph
        Invoke-M365Remediation -ProfilePath ./profiles/security-baseline.yaml -Approve
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

        # Explicit go-ahead (FR-9-style): without it, nothing is applied.
        [switch] $Approve
    )

    $profileObject =
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            Write-Verbose "Remediation: loading profile from '$ProfilePath'."
            & $Importer $ProfilePath
        }
        else {
            $InputObject
        }

    # Resolved once and reused for the plan AND the apply, so both stages agree
    # on exactly which handlers exist for which control ids.
    $effectiveRegistry = if ($null -eq $Registry) { Get-M365ControlRegistry } else { $Registry }

    Write-Verbose 'Remediation: computing the full plan.'
    $plan = Get-M365Plan -Profile $profileObject -Session $Session -Registry $effectiveRegistry

    $ungated = @($plan.Items | Where-Object { $_.Action -in @('Blocked', 'Unsupported') })
    if ($ungated.Count -gt 0) {
        $offenders = ($ungated | ForEach-Object { "$($_.Id) ($($_.Action))" }) -join ', '
        throw "Refusing to remediate: the plan contains control(s) that need attention before they can be remediated: $offenders."
    }

    $drifted = @($plan.Items | Where-Object { $_.Action -in @('Create', 'Update') })
    $summary = [ordered]@{ NoChange = 0; Create = 0; Update = 0; Blocked = 0; Unsupported = 0 }
    foreach ($item in $drifted) { $summary[$item.Action]++ }
    $remediationPlan = [pscustomobject]@{
        PSTypeName  = 'M365Configurator.Plan'
        ProfileName = "$($plan.ProfileName) (remediation)"
        Signal      = if ($drifted.Count -gt 0) { 'NeedsAttention' } else { 'Pass' }
        Summary     = [pscustomobject] $summary
        Items       = $drifted
    }

    foreach ($line in (Format-M365Plan -Plan $remediationPlan)) { Write-Host $line }

    if (-not $Approve) {
        Write-Warning 'Remediation: -Approve was not supplied; nothing was applied. Re-run with -Approve to remediate this drift.'
        return $remediationPlan
    }

    Write-Verbose "Remediation: $($drifted.Count) drifted control(s) approved — applying."
    $result = Invoke-M365PlanApplication -Plan $remediationPlan -Session $Session -Registry $effectiveRegistry

    foreach ($line in (Format-M365ApplyResult -Result $result)) { Write-Host $line }

    $result
}

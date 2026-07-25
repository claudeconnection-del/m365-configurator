#requires -Version 7.6

function Invoke-M365PlanApplication {
    <#
    .SYNOPSIS
        Applies the Create/Update items of a plan against the connected tenant,
        per-item, in order, stopping at the first failure (MCA-18; FR-9, NFR-6).

    .DESCRIPTION
        The private engine both Invoke-M365Apply (D1) and Invoke-M365Remediation
        (D7) share. Iterates Plan.Items in the order the plan already
        established (Get-M365Plan's dependency sort): NoChange items are
        Skipped without invoking Set; Create/Update items resolve their handler
        from -Registry by id (a missing handler is a caller/registry
        inconsistency — fails loud, NFR-6) and invoke its Set seam with the
        plan item's stashed Desired/Current, so nothing is re-read from the
        tenant between planning and applying.

        Fail-fast: the first Set that throws stops further application. That
        item is reported Failed (with the exception message); every item after
        it is NotAttempted — the loop never silently continues past a failure
        into a half-applied state (NFR-6), and the exception itself never
        escapes this function (FR-9's per-item report is the failure surface).
        Items before the failure that already applied stay Applied; nothing is
        rolled back (no transactional guarantee is offered or implied).

        A plan item whose Action is Blocked or Unsupported has no business
        reaching this function — Invoke-M365Apply and Invoke-M365Remediation
        both refuse to call it on such a plan — so encountering one here means
        a caller failed to gate first, and this fails loud rather than silently
        skipping or half-applying it.

    .OUTPUTS
        pscustomobject (PSTypeName 'M365Configurator.ApplyResult'): ProfileName,
        Outcome ('Applied' | 'Failed' | 'NothingToDo'), Items[]. Each item: Id,
        Title, Action, Outcome ('Applied' | 'Failed' | 'Skipped' |
        'NotAttempted'), Detail, Error.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] $Plan,

        # The connected session, passed to each handler's Set seam.
        $Session,

        [Parameter(Mandatory)] $Registry
    )

    $handlers = @{}
    foreach ($handler in @($Registry)) { $handlers[$handler.Id] = $handler }

    $items  = [System.Collections.Generic.List[object]]::new()
    $failed = $false

    foreach ($planItem in @($Plan.Items)) {
        if ($failed) {
            $items.Add([pscustomobject]@{
                    Id = $planItem.Id; Title = $planItem.Title; Action = $planItem.Action
                    Outcome = 'NotAttempted'; Detail = $null; Error = $null
                })
            continue
        }

        if ($planItem.Action -eq 'NoChange') {
            $items.Add([pscustomobject]@{
                    Id = $planItem.Id; Title = $planItem.Title; Action = $planItem.Action
                    Outcome = 'Skipped'; Detail = $null; Error = $null
                })
        }
        elseif ($planItem.Action -in @('Create', 'Update')) {
            if (-not $handlers.ContainsKey($planItem.Id)) {
                throw "Cannot apply control '$($planItem.Id)': no handler is registered for it in the supplied registry."
            }
            $handler = $handlers[$planItem.Id]
            try {
                $detail = & $handler.Set $Session $planItem.Desired $planItem.Current
                $items.Add([pscustomobject]@{
                        Id = $planItem.Id; Title = $planItem.Title; Action = $planItem.Action
                        Outcome = 'Applied'; Detail = $detail; Error = $null
                    })
            }
            catch {
                $failed = $true
                $items.Add([pscustomobject]@{
                        Id = $planItem.Id; Title = $planItem.Title; Action = $planItem.Action
                        Outcome = 'Failed'; Detail = $null; Error = $_.Exception.Message
                    })
            }
        }
        else {
            throw "Cannot apply control '$($planItem.Id)': its plan Action is '$($planItem.Action)', which must be resolved (Blocked/Unsupported items need to be gated before Invoke-M365PlanApplication is called)."
        }
    }

    $outcome =
        if (@($items | Where-Object Outcome -eq 'Failed').Count -gt 0) { 'Failed' }
        elseif (@($items | Where-Object Outcome -eq 'Applied').Count -gt 0) { 'Applied' }
        else { 'NothingToDo' }

    [pscustomobject]@{
        PSTypeName  = 'M365Configurator.ApplyResult'
        ProfileName = $Plan.ProfileName
        Outcome     = $outcome
        Items       = $items.ToArray()
    }
}

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

        Audit trail (MCA-35, D10): every run emits one 'run-started' record
        (runId, profile name, actor, item count), one 'apply-item' record per
        plan item (controlId, outcome, the item's Changes, the error message
        when Failed), and one 'run-finished' record (overall outcome, per-
        outcome counts) — all sharing the same runId and actor, via the
        injected -AuditWriter seam (default: Write-M365AuditRecord).

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

        [Parameter(Mandatory)] $Registry,

        # Injected audit sink: receives one [hashtable] record per call. Default
        # persists it via Write-M365AuditRecord (JSONL; NFR-1-guarded).
        [scriptblock] $AuditWriter = { param($Record) Write-M365AuditRecord -Record $Record }
    )

    $handlers = @{}
    foreach ($handler in @($Registry)) { $handlers[$handler.Id] = $handler }

    $runId = [guid]::NewGuid().ToString()
    $actor = Get-M365MapValue (Get-M365MapValue $Session 'Graph') 'Account'

    & $AuditWriter @{
        timestamp   = [DateTime]::UtcNow.ToString('o')
        actor       = $actor
        runId       = $runId
        action      = 'run-started'
        controlId   = $null
        outcome     = $null
        changes     = @()
        error       = $null
        profileName = $Plan.ProfileName
        itemCount   = @($Plan.Items).Count
    }

    $items  = [System.Collections.Generic.List[object]]::new()
    $failed = $false

    foreach ($planItem in @($Plan.Items)) {
        if ($failed) {
            $outcome = 'NotAttempted'; $detail = $null; $itemError = $null
            $items.Add([pscustomobject]@{
                    Id = $planItem.Id; Title = $planItem.Title; Action = $planItem.Action
                    Outcome = $outcome; Detail = $detail; Error = $itemError
                })
        }
        elseif ($planItem.Action -eq 'NoChange') {
            $outcome = 'Skipped'; $detail = $null; $itemError = $null
            $items.Add([pscustomobject]@{
                    Id = $planItem.Id; Title = $planItem.Title; Action = $planItem.Action
                    Outcome = $outcome; Detail = $detail; Error = $itemError
                })
        }
        elseif ($planItem.Action -in @('Create', 'Update')) {
            if (-not $handlers.ContainsKey($planItem.Id)) {
                throw "Cannot apply control '$($planItem.Id)': no handler is registered for it in the supplied registry."
            }
            $handler = $handlers[$planItem.Id]
            try {
                $detail = & $handler.Set $Session $planItem.Desired $planItem.Current
                $outcome = 'Applied'; $itemError = $null
                $items.Add([pscustomobject]@{
                        Id = $planItem.Id; Title = $planItem.Title; Action = $planItem.Action
                        Outcome = $outcome; Detail = $detail; Error = $itemError
                    })
            }
            catch {
                $failed = $true
                $outcome = 'Failed'; $detail = $null; $itemError = $_.Exception.Message
                $items.Add([pscustomobject]@{
                        Id = $planItem.Id; Title = $planItem.Title; Action = $planItem.Action
                        Outcome = $outcome; Detail = $detail; Error = $itemError
                    })
            }
        }
        else {
            throw "Cannot apply control '$($planItem.Id)': its plan Action is '$($planItem.Action)', which must be resolved (Blocked/Unsupported items need to be gated before Invoke-M365PlanApplication is called)."
        }

        & $AuditWriter @{
            timestamp = [DateTime]::UtcNow.ToString('o')
            actor     = $actor
            runId     = $runId
            action    = 'apply-item'
            controlId = $planItem.Id
            outcome   = $outcome
            changes   = @($planItem.Changes)
            error     = $itemError
        }
    }

    $outcome =
        if (@($items | Where-Object Outcome -eq 'Failed').Count -gt 0) { 'Failed' }
        elseif (@($items | Where-Object Outcome -eq 'Applied').Count -gt 0) { 'Applied' }
        else { 'NothingToDo' }

    & $AuditWriter @{
        timestamp = [DateTime]::UtcNow.ToString('o')
        actor     = $actor
        runId     = $runId
        action    = 'run-finished'
        controlId = $null
        outcome   = $outcome
        changes   = @()
        error     = $null
        counts    = [ordered]@{
            Applied      = @($items | Where-Object Outcome -eq 'Applied').Count
            Skipped      = @($items | Where-Object Outcome -eq 'Skipped').Count
            Failed       = @($items | Where-Object Outcome -eq 'Failed').Count
            NotAttempted = @($items | Where-Object Outcome -eq 'NotAttempted').Count
        }
    }

    [pscustomobject]@{
        PSTypeName  = 'M365Configurator.ApplyResult'
        ProfileName = $Plan.ProfileName
        Outcome     = $outcome
        Items       = $items.ToArray()
    }
}

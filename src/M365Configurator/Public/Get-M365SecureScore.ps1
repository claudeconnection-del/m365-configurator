#requires -Version 7.0

function Get-M365SecureScore {
    <#
    .SYNOPSIS
        Captures the tenant Microsoft Secure Score as a read-only verification
        report, for the audit record at apply boundaries (MCA-29, AUD-3).

    .DESCRIPTION
        Secure Score is a pre/post-apply **verification & reporting** signal, not a
        configuration target. It is computed by Microsoft and changes daily, so it
        must **never** appear in a profile as desired state, and must **never** be a
        drift target (research 01 §4.7; research 05 R8). Accordingly this function
        is a plain reader: it has no Compare/Set seam and returns a report, not a
        control handler — it is deliberately not a New-M365Control (ADR-0013).

        The intended use is to bracket an apply: capture -Boundary Pre before and
        -Boundary Post after, and record both currentScore values in the structured
        audit log (NFR-5) so an operator can see the score move. The label is
        optional — a standalone capture needs none.

        Graph returns one daily snapshot per call to Get-MgSecuritySecureScore; when
        several are returned this projects the most recent by CreatedDateTime. The
        output is stable-ordered (control scores sorted by name) for readable visual
        inspection (NFR-9), and carries no secrets (Secure Score exposes none).

        The tenant read and the capture clock are injected as scriptblock seams so
        the projection is unit-testable without a tenant or a wall clock. The
        default reader calls the real Get-MgSecuritySecureScore (Microsoft.Graph.Security,
        scope SecurityEvents.Read.All).

    .OUTPUTS
        pscustomobject: Service, Kind='report', Boundary, CapturedAt, SnapshotId,
        SnapshotDate, TenantId, CurrentScore, MaxScore, Percentage, ActiveUserCount,
        ControlScores[]. No Set/Compare — read-only by construction.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # Optional apply-boundary label for the audit record. Omitted for a
        # standalone capture.
        [ValidateSet('Pre', 'Post')]
        [string] $Boundary,

        # Seam: reads Secure Score snapshots from the tenant. Default targets the
        # documented Graph cmdlet; -Top 1 asks for just the latest daily snapshot.
        [scriptblock] $ScoreReader = { Get-MgSecuritySecureScore -Top 1 },

        # Seam: supplies the capture timestamp. Injected so CapturedAt is
        # deterministic in tests.
        [scriptblock] $Clock = { Get-Date }
    )

    # Read snapshots and pick the most recent. A capture that returns nothing is a
    # blank verification signal, not a valid "score is null" — fail loud (NFR-6).
    $snapshots = @(& $ScoreReader)
    if ($snapshots.Count -eq 0) {
        throw 'Secure Score capture failed: no Secure Score snapshot was returned by the tenant.'
    }

    $latest = $snapshots |
        Sort-Object -Property @{ Expression = { Get-M365ObjectProperty $_ 'CreatedDateTime' } } -Descending |
        Select-Object -First 1

    $currentScore = Get-M365ObjectProperty $latest 'CurrentScore'
    $maxScore     = Get-M365ObjectProperty $latest 'MaxScore'

    # Percentage is a convenience for the report; guard against an absent or zero
    # max (a fresh tenant can report 0) rather than dividing by zero.
    $percentage = if ($null -ne $maxScore -and [double] $maxScore -ne 0) {
        [math]::Round(([double] $currentScore / [double] $maxScore) * 100, 1)
    } else {
        $null
    }

    # Normalize the per-control breakdown into a small, stable, name-sorted shape.
    # Order by control name so re-captures diff cleanly on visual inspection (NFR-9).
    $controlScores = @(
        foreach ($raw in @(Get-M365ObjectProperty $latest 'ControlScores')) {
            if ($null -eq $raw) { continue }
            [pscustomobject]@{
                Name     = Get-M365ObjectProperty $raw 'ControlName'
                Category = Get-M365ObjectProperty $raw 'ControlCategory'
                Score    = Get-M365ObjectProperty $raw 'Score'
            }
        }
    ) | Sort-Object -Property Name

    $boundaryText = if ($Boundary) { $Boundary } else { '(none)' }
    Write-Verbose "Captured Secure Score: $currentScore / $maxScore (boundary: $boundaryText)."

    [pscustomobject]@{
        Service         = 'MicrosoftGraph'
        Kind            = 'report'   # read-only: never a desired-state or drift target
        Boundary        = if ($Boundary) { $Boundary } else { $null }
        CapturedAt      = & $Clock
        SnapshotId      = Get-M365ObjectProperty $latest 'Id'
        SnapshotDate    = Get-M365ObjectProperty $latest 'CreatedDateTime'
        TenantId        = Get-M365ObjectProperty $latest 'AzureTenantId'
        CurrentScore    = $currentScore
        MaxScore        = $maxScore
        Percentage      = $percentage
        ActiveUserCount = Get-M365ObjectProperty $latest 'ActiveUserCount'
        ControlScores   = @($controlScores)
    }
}

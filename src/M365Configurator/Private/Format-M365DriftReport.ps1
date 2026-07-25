#requires -Version 7.6

function Format-M365DriftReport {
    <#
    .SYNOPSIS
        Renders a drift report (from Get-M365Drift) as readable, stable-ordered
        text lines for visual inspection (NFR-9).

    .DESCRIPTION
        Mirrors Format-M365Plan's shape exactly (D6: drift is the plan
        re-labelled) but over Status instead of Action: one header line, one
        line per control (a status glyph + id + title + status, plus the gate
        reason when blocked/unsupported), indented `field: from -> to` change
        lines, and a footer verdict with per-status counts. Pure and
        deterministic.

        Glyphs: `=` InSync · `~` Drifted · `!` Blocked · `?` Unsupported.

        Internal helper; not exported.

    .OUTPUTS
        [string[]] — the rendered lines.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $Report
    )

    $glyph = @{ InSync = '='; Drifted = '~'; Blocked = '!'; Unsupported = '?' }

    "Drift report: $($Report.ProfileName)"

    $items = @($Report.Items)
    if ($items.Count -eq 0) {
        "  (profile declares no controls)"
    }
    foreach ($item in $items) {
        $head = "  [{0}] {1,-6} {2}  -  {3}" -f $glyph[$item.Status], $item.Id, $item.Title, $item.Status
        if ($item.Gate) { $head += " ($($item.Gate))" }
        $head
        foreach ($change in @($item.Changes)) {
            if ($null -eq $change) { continue }   # defensive: never crash the render on a stray null
            "        {0}: {1} -> {2}" -f $change.Path, $change.From, $change.To
        }
    }

    $s = $Report.Summary
    $verdict = if ($Report.Signal -eq 'InSync') { 'IN SYNC' } else { 'NEEDS ATTENTION' }
    "Result: $verdict - $($s.Drifted) drifted, $($s.InSync) in-sync, $($s.Blocked) blocked, $($s.Unsupported) unsupported ($($items.Count) control(s))"
}

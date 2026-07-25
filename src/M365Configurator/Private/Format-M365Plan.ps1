#requires -Version 7.0

function Format-M365Plan {
    <#
    .SYNOPSIS
        Renders a plan (from Get-M365Plan) as readable, stable-ordered text lines
        for visual inspection (NFR-9).

    .DESCRIPTION
        One header line, one line per control (an action glyph + id + title + action,
        plus the gate reason when blocked/unsupported), indented `field: from -> to`
        lines for each change, and a footer verdict with per-action counts. Pure and
        deterministic: same plan in, same lines out — so it is diff-stable and unit
        testable without capturing host output.

        Glyphs: `=` NoChange · `+` Create · `~` Update · `!` Blocked · `?` Unsupported.

        Internal helper; not exported.

    .OUTPUTS
        [string[]] — the rendered lines.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $Plan
    )

    $glyph = @{ NoChange = '='; Create = '+'; Update = '~'; Blocked = '!'; Unsupported = '?' }

    "Dry-run plan: $($Plan.ProfileName)"

    $items = @($Plan.Items)
    if ($items.Count -eq 0) {
        "  (profile declares no controls)"
    }
    foreach ($item in $items) {
        $head = "  [{0}] {1,-6} {2}  -  {3}" -f $glyph[$item.Action], $item.Id, $item.Title, $item.Action
        if ($item.Gate) { $head += " ($($item.Gate))" }
        $head
        foreach ($change in @($item.Changes)) {
            "        {0}: {1} -> {2}" -f $change.Path, $change.From, $change.To
        }
    }

    $s = $Plan.Summary
    $verdict = if ($Plan.Signal -eq 'Pass') { 'PASS' } else { 'NEEDS ATTENTION' }
    "Result: $verdict - $($s.Update) update, $($s.Create) create, $($s.NoChange) no-change, $($s.Blocked) blocked, $($s.Unsupported) unsupported ($($items.Count) control(s))"
}

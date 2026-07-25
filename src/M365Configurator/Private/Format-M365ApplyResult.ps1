#requires -Version 7.6

function Format-M365ApplyResult {
    <#
    .SYNOPSIS
        Renders an apply result (from Invoke-M365PlanApplication) as readable,
        stable-ordered text lines for visual inspection (NFR-9).

    .DESCRIPTION
        Mirrors Format-M365Plan: one header line, one line per item (an
        outcome glyph + id + title + outcome, plus the captured error when
        Failed), and a footer verdict with per-outcome counts. Pure and
        deterministic: same result in, same lines out.

        Glyphs: `+` Applied · `-` Skipped · `x` Failed · `.` NotAttempted.

        Internal helper; not exported.

    .OUTPUTS
        [string[]] — the rendered lines.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $Result
    )

    $glyph = @{ Applied = '+'; Skipped = '-'; Failed = 'x'; NotAttempted = '.' }

    "Apply: $($Result.ProfileName)"

    $items = @($Result.Items)
    if ($items.Count -eq 0) {
        "  (nothing to apply)"
    }
    foreach ($item in $items) {
        $head = "  [{0}] {1,-6} {2}  -  {3}" -f $glyph[$item.Outcome], $item.Id, $item.Title, $item.Outcome
        if ($item.Outcome -eq 'Failed' -and $item.Error) { $head += " ($($item.Error))" }
        $head
    }

    $applied      = @($items | Where-Object Outcome -eq 'Applied').Count
    $skipped      = @($items | Where-Object Outcome -eq 'Skipped').Count
    $failed       = @($items | Where-Object Outcome -eq 'Failed').Count
    $notAttempted = @($items | Where-Object Outcome -eq 'NotAttempted').Count

    $verdict = switch ($Result.Outcome) {
        'Applied'     { 'APPLIED' }
        'Failed'      { 'FAILED' }
        'NothingToDo' { 'NOTHING TO DO' }
    }
    "Result: $verdict - $applied applied, $skipped skipped, $failed failed, $notAttempted not-attempted ($($items.Count) control(s))"
}

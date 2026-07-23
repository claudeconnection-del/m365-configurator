#requires -Version 7.0

function ConvertTo-M365CanonicalJson {
    <#
    .SYNOPSIS
        Renders a profile (or any config object) to its canonical JSON form:
        sorted keys, sorted arrays, stable formatting.

    .DESCRIPTION
        The single canonical form for profiles (ADR-0008). Profiles are authored
        and shared as YAML, but every comparison — dry-run, drift, "did anything
        change?" — runs against this deterministic JSON so that:

          * semantically-equal profiles produce byte-identical output, and
          * a re-save of unchanged tenant state is a clean (empty) diff (NFR-9).

        Keys are sorted, arrays are ordered by content (via
        ConvertTo-M365SortedObject), and the JSON is emitted with stable
        indentation. Pure and side-effect-free.

    .OUTPUTS
        [string] canonical JSON.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        $InputObject
    )

    $sorted = ConvertTo-M365SortedObject $InputObject
    # Depth 64 comfortably covers nested control settings; indented for readable,
    # line-oriented diffs. ConvertTo-Json preserves [ordered] key order in PS7.
    ConvertTo-Json -InputObject $sorted -Depth 64
}

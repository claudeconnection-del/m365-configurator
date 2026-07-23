#requires -Version 7.0

function ConvertTo-M365SortedObject {
    <#
    .SYNOPSIS
        Recursively returns a copy of an object with dictionary keys sorted and
        arrays ordered deterministically.

    .DESCRIPTION
        The engine behind the canonical profile form (ADR-0008): a profile that is
        semantically identical must serialize identically, so drift/dry-run diffs
        are meaningful and a re-save of unchanged state is byte-stable (NFR-9).

          * Dictionaries / pscustomobjects -> an [ordered] map with keys sorted
            ascending (ordinal), values recursively sorted.
          * Arrays / lists -> elements recursively sorted, then the array itself
            ordered by each element's canonical string. Sorting is for determinism
            of the canonical form, not to preserve authoring order (the canonical
            form exists for equality/diff, not for display).
          * Scalars (including strings) -> returned unchanged.

        Internal helper; not exported. Strict-mode safe.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $InputObject
    )

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $sorted = [ordered]@{}
        foreach ($key in ($InputObject.Keys | Sort-Object -CaseSensitive)) {
            $sorted[[string] $key] = ConvertTo-M365SortedObject $InputObject[$key]
        }
        return $sorted
    }

    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $sorted = [ordered]@{}
        foreach ($name in ($InputObject.PSObject.Properties.Name | Sort-Object -CaseSensitive)) {
            $sorted[$name] = ConvertTo-M365SortedObject $InputObject.$name
        }
        return $sorted
    }

    # Arrays / lists, but NOT strings (which are IEnumerable over chars).
    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $items = @(foreach ($element in $InputObject) { ConvertTo-M365SortedObject $element })
        # Order by each element's canonical string so equal sets collapse to one form.
        $ordered = $items | Sort-Object -CaseSensitive -Property { $_ | ConvertTo-Json -Depth 64 -Compress }
        return @($ordered)
    }

    # Scalar (string, number, bool, …) — unchanged.
    return $InputObject
}

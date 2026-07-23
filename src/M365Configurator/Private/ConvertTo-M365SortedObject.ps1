#requires -Version 7.0

function ConvertTo-M365SortedObject {
    <#
    .SYNOPSIS
        Recursively returns a copy of an object with dictionary keys sorted
        (ordinal) and arrays ordered deterministically, preserving array-ness.

    .DESCRIPTION
        The engine behind the canonical profile form (ADR-0008): a profile that is
        semantically identical must serialize identically, so drift/dry-run diffs
        are meaningful and a re-save of unchanged state is byte-stable (NFR-9).

          * Dictionaries / pscustomobjects -> an [ordered] map with keys sorted
            by ORDINAL string comparison (byte-stable across machines/cultures),
            values recursively sorted.
          * Arrays / lists -> elements recursively sorted, then ordered by each
            element's canonical string (ordinal). Array-ness is preserved for
            every length: an empty array stays [], a single-element array stays a
            one-element array (not a scalar), nested arrays are NOT flattened, and
            $null elements are NOT dropped. Sorting is for determinism of the
            canonical form, not to preserve authoring order (the canonical form
            exists for equality/diff, not for display) — so a `settings` array
            whose element order is semantically significant must not be modelled
            as a bare array.
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
        $keys = [System.Collections.Generic.List[string]]::new()
        foreach ($key in $InputObject.Keys) { $keys.Add([string] $key) }
        $keys.Sort([System.StringComparer]::Ordinal)

        $sorted = [ordered]@{}
        foreach ($key in $keys) { $sorted[$key] = ConvertTo-M365SortedObject -InputObject $InputObject[$key] }
        return $sorted
    }

    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $names = [System.Collections.Generic.List[string]]::new()
        foreach ($name in $InputObject.PSObject.Properties.Name) { $names.Add([string] $name) }
        $names.Sort([System.StringComparer]::Ordinal)

        $sorted = [ordered]@{}
        foreach ($name in $names) { $sorted[$name] = ConvertTo-M365SortedObject -InputObject $InputObject.$name }
        return $sorted
    }

    # Arrays / lists, but NOT strings (which are IEnumerable over chars).
    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        # Decorate each (recursively-sorted) element with an ordinal sort key, then
        # order by it. A List preserves nested arrays and $null elements (unlike
        # @(foreach ...) which flattens and drops nulls).
        $pairs = [System.Collections.Generic.List[object]]::new()
        foreach ($element in $InputObject) {
            $sortedElement = ConvertTo-M365SortedObject -InputObject $element
            $sortKey = if ($null -eq $sortedElement) { 'null' } else { [string] ($sortedElement | ConvertTo-Json -Depth 64 -Compress) }
            $pairs.Add([pscustomobject]@{ Value = $sortedElement; SortKey = $sortKey })
        }
        $pairs.Sort([System.Comparison[object]] {
                param($a, $b) [System.StringComparer]::Ordinal.Compare($a.SortKey, $b.SortKey)
            })

        $result = [System.Collections.Generic.List[object]]::new()
        foreach ($pair in $pairs) { $result.Add($pair.Value) }

        # Unary comma prevents the single-element/empty array from being unwrapped
        # to a scalar/$null on return (the collapse bug this design must avoid).
        return , $result.ToArray()
    }

    # Scalar (string, number, bool, …) — unchanged.
    return $InputObject
}

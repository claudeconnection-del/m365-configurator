#requires -Version 7.0

function Get-M365ControlChange {
    <#
    .SYNOPSIS
        The default control comparison: the fields a profile declares that differ
        from current tenant state, as readable change records (ADR-0013, ADR-0008).

    .DESCRIPTION
        Desired-state semantics: only the fields the profile actually declares are
        compared — extra fields present in current state are not "changes" the
        profile intends. A field differs when its canonical JSON differs (ADR-0008),
        so the answer is byte-stable and value-type-insensitive ($true vs 'true' vs 1
        are judged by their canonical form, not PowerShell's loose equality).

        Emits one record per differing field: Path (the field), From (current), To
        (desired) — the shape the plan renderer prints (NFR-9). No difference emits
        nothing, which the engine reads as NoChange.

        Internal helper; not exported.

    .OUTPUTS
        pscustomobject per differing field: Path, From, To. Nothing when identical.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()] $Desired,
        [AllowNull()] $Current
    )

    $keys =
        if ($Desired -is [System.Collections.IDictionary]) { @($Desired.Keys) }
        elseif ($Desired -is [System.Management.Automation.PSCustomObject]) { @($Desired.PSObject.Properties.Name) }
        else { @() }

    foreach ($key in $keys) {
        $want = Get-M365MapValue $Desired ([string] $key)
        $have = Get-M365MapValue $Current ([string] $key)
        if ((ConvertTo-M365CanonicalJson $want) -ne (ConvertTo-M365CanonicalJson $have)) {
            [pscustomobject]@{ Path = [string] $key; From = $have; To = $want }
        }
    }
}

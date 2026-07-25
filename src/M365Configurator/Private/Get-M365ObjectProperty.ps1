#requires -Version 7.6

function Get-M365ObjectProperty {
    <#
    .SYNOPSIS
        Reads a named property from an object, returning $null if it is absent.

    .DESCRIPTION
        A strict-mode-safe property accessor. Under Set-StrictMode -Version Latest
        (which this module enforces at load), reading a property that does not
        exist throws. When we project third-party objects — e.g. Get-MgContext's
        auth context or Get-ConnectionInformation's EXO connection — into our own
        secret-free state reports, a field the current SDK version happens not to
        expose must yield $null, not crash a connection report.

        Internal helper; not exported.

    .OUTPUTS
        The property value, or $null when the property is not present.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $InputObject,

        [Parameter(Mandatory)]
        [string] $Name
    )

    if ($null -eq $InputObject) { return $null }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) { $property.Value } else { $null }
}

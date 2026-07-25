#requires -Version 7.6

function Get-M365MapValue {
    <#
    .SYNOPSIS
        Reads a key from either a dictionary or a pscustomobject, returning $null
        when absent. Companion Test-M365MapHasKey reports presence.

    .DESCRIPTION
        Profiles arrive either as ordered dictionaries (parsed from YAML) or as
        pscustomobjects (built in code). These helpers read both shapes uniformly
        and strict-mode-safely, so the validator and engine don't care which form
        a profile is in.

        Internal helpers; not exported.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Map,
        [Parameter(Mandatory)] [string] $Key
    )

    if ($null -eq $Map) { return $null }
    if ($Map -is [System.Collections.IDictionary]) {
        if ($Map.Contains($Key)) { return $Map[$Key] } else { return $null }
    }
    return Get-M365ObjectProperty $Map $Key
}

function Test-M365MapHasKey {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Map,
        [Parameter(Mandatory)] [string] $Key
    )

    if ($null -eq $Map) { return $false }
    if ($Map -is [System.Collections.IDictionary]) { return $Map.Contains($Key) }
    if ($Map -is [System.Management.Automation.PSCustomObject]) {
        return $null -ne $Map.PSObject.Properties[$Key]
    }
    return $false
}

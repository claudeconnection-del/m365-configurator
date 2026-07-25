#requires -Version 7.6

function Set-M365SessionNameOverride {
    <#
    .SYNOPSIS
        Returns a shallow copy of a session augmented with a NameOverride
        member, for the -NameOverride wiring shared by Invoke-M365DryRun,
        Invoke-M365Apply, and Get-M365Drift (MCA-16; FR-7, D9).

    .DESCRIPTION
        A name-scoped control's Get seam has no access to the profile's
        desired settings (ADR-0013), so the effective per-client name has to
        be threaded through the connected session instead
        ($Session.NameOverride). The session may be $null, a hashtable (as
        in tests and hand-built callers), or the pscustomobject
        New-M365Session returns — this handles all three withOUT mutating
        the caller's original session object (a shallow copy is enough:
        only a new top-level member is being added).

        Internal helper shared by the three owner-facing entry points; not
        exported.

    .OUTPUTS
        The augmented session copy (same shape as the input: hashtable in,
        hashtable out; pscustomobject in, pscustomobject out; $null in,
        hashtable out).
    #>
    [CmdletBinding()]
    param(
        [AllowNull()] $Session,
        [Parameter(Mandatory)] [hashtable] $NameOverride
    )

    $copy =
        if ($null -eq $Session) { @{} }
        elseif ($Session -is [System.Collections.IDictionary]) { $Session.Clone() }
        else { $Session.PSObject.Copy() }

    if ($copy -is [System.Collections.IDictionary]) {
        $copy['NameOverride'] = $NameOverride
    }
    else {
        Add-Member -InputObject $copy -NotePropertyName 'NameOverride' -NotePropertyValue $NameOverride -Force
    }

    $copy
}

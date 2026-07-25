#requires -Version 7.6

function Set-M365ProfileNameOverride {
    <#
    .SYNOPSIS
        Rewrites the name-bearing setting of name-scoped controls in a copy of
        a profile, for per-client renames on apply (MCA-16; FR-7, D9).

    .DESCRIPTION
        Name-scoped controls (a Conditional Access policy matched by
        displayName, an EXO policy matched by name) ship the reference
        profile's well-known name. A client may already use a different name
        for the equivalent tenant object, or simply prefer one — this lets a
        caller supply `<controlId> = <newName>` pairs and get back a profile
        where those controls' name-bearing setting is replaced, WITHOUT
        mutating the caller's original profile object (only the overridden
        controls, and the top-level controls array, are copied; everything
        else is passed through).

        The id -> name-bearing-settings-key map is maintained here as the
        single source of truth for which controls are name-scoped; controls
        added later that are name-scoped extend it. An id in `-NameOverride`
        that isn't in this map is a caller mistake (there is nothing to
        rewrite) — this throws rather than silently no-op-ing (NFR-6).

        Also returns the (validated) override map unchanged, as
        `NameOverride`, because the caller still needs it: a name-scoped
        control's `Get` seam matches the CURRENT tenant object by name, and
        the ADR-0013 Get seam has no access to the profile's desired
        settings — so the effective name additionally has to be threaded
        through the connected session (`$Session.NameOverride`), which the
        three owner-facing entry points (Invoke-M365DryRun/Apply,
        Get-M365Drift) do themselves on a shallow session copy.

    .OUTPUTS
        pscustomobject: Profile (the rewritten profile), NameOverride (the
        validated override map, passed through for the caller to also thread
        onto the session).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] $InputObject,
        [Parameter(Mandatory)] [hashtable] $NameOverride
    )

    # id -> name-bearing settings key. Extend this as name-scoped controls land.
    $nameBearingKey = @{
        'ID-2'  = 'displayName'
        'ID-3'  = 'displayName'
        'MDO-4' = 'name'
    }

    foreach ($id in $NameOverride.Keys) {
        if (-not $nameBearingKey.ContainsKey($id)) {
            throw "Cannot remap control '$id': it is not a name-scoped control (no name-bearing settings key is registered for it)."
        }
    }

    function Copy-M365Map {
        param($Map)
        $copy = [ordered]@{}
        $keys = if ($Map -is [System.Collections.IDictionary]) { @($Map.Keys) } else { @($Map.PSObject.Properties.Name) }
        foreach ($key in $keys) { $copy[[string] $key] = Get-M365MapValue $Map ([string] $key) }
        $copy
    }

    $newControls = [System.Collections.Generic.List[object]]::new()
    foreach ($control in @(Get-M365MapValue $InputObject 'controls')) {
        $id = [string] (Get-M365MapValue $control 'id')

        if ($NameOverride.ContainsKey($id)) {
            $newName = $NameOverride[$id]
            $key     = $nameBearingKey[$id]

            $newSettings = Copy-M365Map (Get-M365MapValue $control 'settings')
            $newSettings[$key] = $newName

            $newControl = Copy-M365Map $control
            $newControl['settings'] = $newSettings
            if (Test-M365MapHasKey $control 'name') { $newControl['name'] = $newName }

            $newControls.Add($newControl)
        }
        else {
            $newControls.Add($control)
        }
    }

    $newProfile = Copy-M365Map $InputObject
    $newProfile['controls'] = $newControls.ToArray()

    [pscustomobject]@{
        Profile      = $newProfile
        NameOverride = $NameOverride
    }
}

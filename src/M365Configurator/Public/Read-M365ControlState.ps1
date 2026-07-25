#requires -Version 7.6

function Read-M365ControlState {
    <#
    .SYNOPSIS
        Reads every in-scope control's current tenant state — the real
        -ControlReader Save-M365Profile was built to receive (MCA-36; D11).

    .DESCRIPTION
        For each control in -Registry (default: the real
        Get-M365ControlRegistry): a control whose RequiredCapabilities aren't
        satisfied by -Session.Capabilities is skipped (Write-Verbose) —
        reading it would throw against a disconnected/under-licensed
        provider, not something to surface as a save failure. Otherwise its
        Get seam is invoked; a $null result (e.g. an absent CA policy) is
        also skipped (Write-Verbose) — you cannot save what does not exist.

        Every other control emits a descriptor: id, provider, and settings —
        a COPY of the Get projection with the reserved stash key 'id'
        removed. Some collection controls (D2) stash the tenant policy's own
        id in their projection so Set can PATCH by it; that id is a
        tenant-specific GUID and must never be persisted into a shareable,
        portable profile (NFR-1/FR-5). The Get seam's returned object is
        never mutated — the stash key is dropped from a fresh copy.

        This is deliberately Public, not Private, despite reading like an
        engine-internal piece: it must be directly callable both by end
        users driving Save-M365Profile interactively (-ControlReader
        { Read-M365ControlState -Session $session }) and by
        scripts/m365config.ps1, which runs outside the module and cannot
        resolve a private, unexported function by name.

    .OUTPUTS
        hashtable[] — each { id; provider; settings }, one per readable
        in-scope control. Feeds Save-M365Profile's -ControlReader.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        $Session,

        # Injected control set; defaults to the real registry.
        [AllowNull()]
        $Registry
    )

    if ($null -eq $Registry) { $Registry = Get-M365ControlRegistry }

    $sessionCaps = @(if ($null -ne $Session) { Get-M365MapValue $Session 'Capabilities' })

    foreach ($control in @($Registry)) {
        $missing = @($control.RequiredCapabilities | Where-Object { $_ -notin $sessionCaps })
        if ($missing.Count -gt 0) {
            Write-Verbose "Read-M365ControlState: skipping '$($control.Id)' — missing capability: $($missing -join ', ')."
            continue
        }

        $current = & $control.Get $Session
        if ($null -eq $current) {
            Write-Verbose "Read-M365ControlState: skipping '$($control.Id)' — nothing to save (Get returned nothing)."
            continue
        }

        # A fresh copy, minus the reserved 'id' stash key — never mutate what Get returned.
        $settings = @{}
        if ($current -is [System.Collections.IDictionary]) {
            foreach ($key in $current.Keys) { if ($key -ne 'id') { $settings[[string] $key] = $current[$key] } }
        }
        elseif ($current -is [System.Management.Automation.PSCustomObject]) {
            foreach ($prop in $current.PSObject.Properties) { if ($prop.Name -ne 'id') { $settings[$prop.Name] = $prop.Value } }
        }
        else {
            $settings = $current
        }

        @{ id = $control.Id; provider = $control.Provider; settings = $settings }
    }
}

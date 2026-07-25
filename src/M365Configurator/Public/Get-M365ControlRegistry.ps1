#requires -Version 7.0

function Get-M365ControlRegistry {
    <#
    .SYNOPSIS
        Returns the set of known control handlers — the registry seam the change
        engine resolves controls through by id (ADR-0013).

    .DESCRIPTION
        The engine takes its handler set as an injected parameter defaulting to this
        registry, so it is unit-testable with in-memory fake controls and no tenant.
        This function assembles the real providers' controls and enforces the one
        invariant the engine relies on: control ids are UNIQUE — a duplicate id is a
        packaging fault and fails loud here (NFR-6), never silently shadowing another.

        v1 slice: currently the Graph ID-1 security-defaults singleton; further Graph
        (MCA-4) and Exchange Online (MCA-5) controls register here as they land, each
        an additive one-line entry (ADR-0013).

    .OUTPUTS
        pscustomobject[] (each PSTypeName 'M365Configurator.Control').
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $controls = @(
        New-M365SecurityDefaultsControl
    )

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($control in $controls) {
        if (-not $seen.Add($control.Id)) {
            throw "Control registry is malformed: duplicate control id '$($control.Id)'."
        }
    }

    $controls
}

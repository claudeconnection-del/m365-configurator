#requires -Version 7.6

function Import-M365Profile {
    <#
    .SYNOPSIS
        Loads a profile from a file (a saved profile or an exported single file),
        validates it against schema v1, and returns the profile object.

    .DESCRIPTION
        The load/import half of MCA-15 (FR-6; ADR-0009). It reads the file, parses
        the YAML, and validates against schema v1 — rejecting loudly (NFR-6) any
        file that is:

          * missing / unreadable,
          * malformed YAML (ConvertFrom-M365ProfileYaml throws), or
          * schema-invalid, INCLUDING carrying any credential-shaped field
            (config-only — the guard that makes importing a shared/exported file
            safe; NFR-1).

        A valid profile is returned as an object (ordered maps) ready to feed dry-
        run / apply. The file read is an injected seam for testability; the
        default reads UTF-8 text from disk.

    .OUTPUTS
        The validated profile object.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path,

        [scriptblock] $Reader = {
            param([string] $FilePath)
            if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
                throw "Profile file not found: '$FilePath'."
            }
            Get-Content -LiteralPath $FilePath -Raw
        }
    )

    Write-Verbose "Importing profile from '$Path'."
    $text = & $Reader $Path

    # Parse (throws loudly on malformed YAML — NFR-6).
    $profile = ConvertFrom-M365ProfileYaml $text

    # Validate against schema v1; refuse anything invalid or credential-bearing.
    $validation = Test-M365Profile -Profile $profile
    if (-not $validation.Valid) {
        throw "Profile at '$Path' is not a valid schema-v1 profile and was rejected: $($validation.Errors -join '; ')."
    }

    Write-Verbose "  Imported '$(Get-M365MapValue $profile 'name')' ($(@(Get-M365MapValue $profile 'controls').Count) control(s))."
    $profile
}

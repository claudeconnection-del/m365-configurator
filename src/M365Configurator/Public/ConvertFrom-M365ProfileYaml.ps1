#requires -Version 7.6

function ConvertFrom-M365ProfileYaml {
    <#
    .SYNOPSIS
        Parses profile YAML text into an object (ordered maps), via the pinned
        powershell-yaml parser.

    .DESCRIPTION
        The read side of the YAML authoring surface (ADR-0008). Malformed YAML
        surfaces loudly as a terminating error (NFR-6) rather than a silent $null,
        so a bad profile file fails fast at load.

        Returned maps use ordered dictionaries; feed the result to
        ConvertTo-M365CanonicalJson for the deterministic comparison form or to
        Test-M365Profile for schema validation.

    .OUTPUTS
        The parsed object (ordered dictionaries / arrays / scalars).
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string] $Yaml
    )

    Import-M365YamlModule
    # -Ordered keeps key order stable through the round-trip; ConvertFrom-Yaml
    # throws on malformed input, which we let propagate (loud, fast — NFR-6).
    ConvertFrom-Yaml -Yaml $Yaml -Ordered
}

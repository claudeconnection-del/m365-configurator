#requires -Version 7.6

function ConvertTo-M365ProfileYaml {
    <#
    .SYNOPSIS
        Serializes a profile object to human-readable YAML (the authoring/sharing
        form; ADR-0008).

    .DESCRIPTION
        Profiles are authored and shared as YAML for reviewability (comments, low
        noise, block structure — NFR-9). This canonicalizes the object first
        (sorted keys/arrays via ConvertTo-M365SortedObject) so the emitted YAML is
        deterministic and a re-save of unchanged state is byte-stable, then hands
        off to the pinned powershell-yaml serializer.

    .OUTPUTS
        [string] YAML.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        $InputObject
    )

    Import-M365YamlModule
    $sorted = ConvertTo-M365SortedObject $InputObject
    ConvertTo-Yaml $sorted
}

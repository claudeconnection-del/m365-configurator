#requires -Version 7.0

function Get-M365Profile {
    <#
    .SYNOPSIS
        Lists the saved profiles available under a profile directory.

    .DESCRIPTION
        The "select from a list" half of MCA-15 (FR-6). It enumerates profile
        files (*.yaml / *.yml) under -ProfileDirectory and returns a lightweight
        descriptor per profile — enough for a CLI to present a picker (ADR-0012)
        without parsing every file. A missing or empty directory yields nothing
        (not an error): "no profiles yet" is a normal state.

        Loading and validating a chosen profile is Import-M365Profile's job.

    .OUTPUTS
        pscustomobject per profile: Name, Path.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $ProfileDirectory = 'profiles',

        # Injected for testability; default enumerates the filesystem.
        [scriptblock] $Lister = {
            param([string] $Directory)
            if (Test-Path -LiteralPath $Directory) {
                Get-ChildItem -LiteralPath $Directory -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Extension -in '.yaml', '.yml' }
            }
        }
    )

    foreach ($file in @(& $Lister $ProfileDirectory)) {
        [pscustomobject]@{
            Name = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            Path = $file.FullName
        }
    }
}

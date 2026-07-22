#requires -Version 7.0
<#
    M365Configurator — root module.

    Dot-sources every function under Public/ and Private/ and exports the public
    ones. Keeping one function per file (named after the function) keeps the
    module readable and diff-friendly (NFR-9).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$publicDir  = Join-Path $PSScriptRoot 'Public'
$privateDir = Join-Path $PSScriptRoot 'Private'

$public  = @(Get-ChildItem -Path $publicDir  -Filter '*.ps1' -ErrorAction SilentlyContinue)
$private = @(Get-ChildItem -Path $privateDir -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in @($private + $public)) {
    . $file.FullName
}

# Guard against an empty Public/ dir: property access on an empty array throws
# under StrictMode, and Export-ModuleMember with no names would hide everything.
$publicFunctionNames = @($public | ForEach-Object { $_.BaseName })
if ($publicFunctionNames.Count -gt 0) {
    Export-ModuleMember -Function $publicFunctionNames
}

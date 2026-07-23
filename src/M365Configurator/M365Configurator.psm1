#requires -Version 7.0
<#
    M365Configurator — root module.

    Convention: one function per file under Public/ (exported) or Private/
    (internal), named after the function — keeps the module readable and
    diff-friendly (NFR-9).

    The module manifest's FunctionsToExport is the SINGLE source of truth for the
    public surface. This loader enforces that contract loudly (NFR-6): the
    declared exports and the Public/*.ps1 files must match exactly, or import
    fails fast with a clear message rather than silently exporting the wrong set.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$publicDir  = Join-Path $PSScriptRoot 'Public'
$privateDir = Join-Path $PSScriptRoot 'Private'

# Public/ is part of the module and must exist; a missing dir is a packaging
# fault, not something to shrug off (loud, fast failure — NFR-6).
if (-not (Test-Path -LiteralPath $publicDir)) {
    throw "M365Configurator is malformed: required public function directory not found at '$publicDir'."
}

# Private/ is legitimately optional (may be empty early in the build).
$private = if (Test-Path -LiteralPath $privateDir) {
    @(Get-ChildItem -LiteralPath $privateDir -Filter '*.ps1')
} else {
    @()
}
$public = @(Get-ChildItem -LiteralPath $publicDir -Filter '*.ps1')

# Wrap each operand in @() at the point of addition: a single-file Get-ChildItem
# result assigned out of an if-expression unwraps to a scalar, and scalar + array
# throws. @($private) + @($public) is array-safe for 0, 1, or many files. (Order
# is immaterial — every file only defines functions, nothing runs at dot-source.)
foreach ($file in (@($private) + @($public))) {
    . $file.FullName
}

# Enforce manifest <-> Public/ agreement so the export list can never silently
# drift (the reviewer reproduced this trap): every declared export needs a file,
# every file needs to be declared.
$manifest    = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'M365Configurator.psd1')
$declared    = @($manifest.FunctionsToExport)
$onDisk      = @($public | ForEach-Object { $_.BaseName })
$missingFile = @($declared | Where-Object { $_ -notin $onDisk })
$undeclared  = @($onDisk   | Where-Object { $_ -notin $declared })

if ($missingFile.Count -gt 0) {
    throw "Manifest FunctionsToExport lists function(s) with no Public/ file: $($missingFile -join ', ')."
}
if ($undeclared.Count -gt 0) {
    throw "Public/ has function(s) not declared in the manifest FunctionsToExport: $($undeclared -join ', ')."
}

Export-ModuleMember -Function $declared

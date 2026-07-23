#requires -Version 7.0

function Import-M365YamlModule {
    <#
    .SYNOPSIS
        Ensures the powershell-yaml cmdlets are available before use.

    .DESCRIPTION
        The YAML authoring surface (ADR-0008) depends on the pinned powershell-yaml
        module. Its pinned presence is the module lifecycle's job (MCA-2 —
        Get-M365RequiredModule / Initialize-M365Module); this helper just makes the
        cmdlets loadable at call time and fails loudly if the module is genuinely
        absent (NFR-6), rather than letting a later ConvertFrom-Yaml surface a
        confusing "command not found".

        Internal helper; not exported.
    #>
    [CmdletBinding()]
    param()

    if (Get-Command -Name 'ConvertFrom-Yaml' -ErrorAction SilentlyContinue) { return }

    try {
        Import-Module -Name 'powershell-yaml' -ErrorAction Stop
    }
    catch {
        throw "The 'powershell-yaml' module is required for profile YAML but could not be loaded. Run the module bootstrap (Initialize-M365Module) first. Underlying error: $($_.Exception.Message)"
    }
}

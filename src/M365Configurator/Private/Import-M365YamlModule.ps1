#requires -Version 7.6

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

    # Load the pinned version specifically, so that if several are installed we
    # bind to the declared pin (single source of truth) rather than the highest.
    $pin = (Get-M365RequiredModule | Where-Object { $_.Name -eq 'powershell-yaml' } | Select-Object -First 1).Version

    try {
        if ($pin) {
            Import-Module -Name 'powershell-yaml' -RequiredVersion $pin -ErrorAction Stop
        }
        else {
            Import-Module -Name 'powershell-yaml' -ErrorAction Stop
        }
    }
    catch {
        throw "The 'powershell-yaml' module is required for profile YAML but could not be loaded. Run the module bootstrap (Initialize-M365Module) first. Underlying error: $($_.Exception.Message)"
    }
}

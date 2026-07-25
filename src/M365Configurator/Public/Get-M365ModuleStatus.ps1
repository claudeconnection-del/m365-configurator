#requires -Version 7.6

function Get-M365ModuleStatus {
    <#
    .SYNOPSIS
        Reports, for each required module, whether an installed version satisfies
        the pinned version.

    .DESCRIPTION
        Pure decision logic for the detect/idempotency step of the module
        lifecycle (FR-1, NFR-7). For every required module it looks up the
        installed versions and decides whether the pin is satisfied.

        The installed-module lookup is injected via -InstalledLookup so this
        logic is testable without touching the machine's module state or the
        PowerShell Gallery. The default reads the real environment.

    .OUTPUTS
        pscustomobject per required module: Name, RequiredVersion, Installed,
        InstalledVersion, Satisfied.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [pscustomobject[]] $Required = (Get-M365RequiredModule),

        [scriptblock] $InstalledLookup = { param($Name) Get-Module -ListAvailable -Name $Name }
    )

    foreach ($module in $Required) {
        $found = @(& $InstalledLookup $module.Name)

        # Highest installed version wins (a machine may hold several side by side).
        $highest = $found |
            Where-Object { $_.Version } |
            Sort-Object -Property Version -Descending |
            Select-Object -First 1

        $installed = $null -ne $highest
        $installedVersion = if ($installed) { [version] $highest.Version } else { $null }
        $requiredVersion  = [version] $module.Version

        # Satisfied means the pin (or newer) is present, so install can be skipped
        # (idempotency). Upgrades past the pin are a deliberate edit to the
        # required-module list, not something detection should force.
        $satisfied = $installed -and ($installedVersion -ge $requiredVersion)

        # State names the exact relationship to the pin so a newer-than-pinned
        # install is visible/auditable (NFR-7) rather than silently "satisfied":
        #   Missing | Older | Match | Newer
        $state =
            if (-not $installed)                        { 'Missing' }
            elseif ($installedVersion -eq $requiredVersion) { 'Match' }
            elseif ($installedVersion -gt $requiredVersion) { 'Newer' }
            else                                        { 'Older' }

        [pscustomobject]@{
            Name             = $module.Name
            RequiredVersion  = $module.Version
            Installed        = $installed
            InstalledVersion = if ($installedVersion) { $installedVersion.ToString() } else { $null }
            Satisfied        = $satisfied
            State            = $state
        }
    }
}

#requires -Version 7.0

function Initialize-M365Module {
    <#
    .SYNOPSIS
        Orchestrates the required-module lifecycle: detect -> offer -> (consented)
        install -> import -> report resolved versions. Idempotent and audit-logged.

    .DESCRIPTION
        The top of the module lifecycle for MCA-2 (FR-1). It composes the pieces
        that already exist as pure functions:

          1. Detect  — Get-M365ModuleStatus decides, per required module, whether
                       the pin is already met (idempotency; NFR-7).
          2. Offer   — for anything unsatisfied, Get-M365ModuleRemediation turns
                       the gap into a consent-ready, non-elevating fix (ADR-0011).
          3. Consent — the offer is put to the caller; nothing is installed
                       without an explicit "yes" (dry-run -> gated apply).
          4. Install — on consent, install to CurrentUser scope, pinned via the
                       exact -RequiredVersion. The app never elevates (NFR-1).
          5. Import  — load the module and read back the resolved version.
          6. Report  — one record per required module describing what happened.

        Re-running when everything is already satisfied installs nothing and asks
        for no consent — it is a no-op apart from importing and reporting.

        All side effects are injected as scriptblock seams so this orchestration
        is unit-testable without touching the machine, prompting a human, or
        reaching the PowerShell Gallery:

          -InstalledLookup   how installed versions are discovered (flows into
                             Get-M365ModuleStatus).
          -Consent           given a remediation offer, returns $true/$false.
                             Default prompts interactively.
          -Installer         given a remediation offer, performs the install.
                             Default runs Install-Module at CurrentUser scope.
          -Importer          given a name + minimum version, imports and returns
                             the loaded module (with its resolved .Version).
                             Default runs Import-Module.

    .OUTPUTS
        pscustomobject per required module: Name, RequiredVersion, State, Action
        (AlreadySatisfied | Installed | Upgraded | Declined | Failed),
        ResolvedVersion, Imported, Satisfied, Detail.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [pscustomobject[]] $Required = (Get-M365RequiredModule),

        [scriptblock] $InstalledLookup = { param($Name) Get-Module -ListAvailable -Name $Name },

        [scriptblock] $Consent = {
            param($Offer)
            # Interactive, explicit opt-in. The interface layer normally supplies
            # its own consent seam; this is the sane console default.
            $answer = Read-Host "$($Offer.Offer) [y/N]"
            $answer -match '^\s*(y|yes)\s*$'
        },

        [scriptblock] $Installer = {
            param($Offer)
            # CurrentUser only, pinned to the exact version — never elevates.
            Install-Module -Name $Offer.Name -RequiredVersion $Offer.RequiredVersion `
                -Scope CurrentUser -Repository PSGallery -AllowClobber -Force
        },

        [scriptblock] $Importer = {
            param($Name, $MinimumVersion)
            Import-Module -Name $Name -MinimumVersion $MinimumVersion -PassThru -ErrorAction Stop |
                Sort-Object Version -Descending |
                Select-Object -First 1
        }
    )

    # Step 1 — detect. One status record per required module.
    $status = Get-M365ModuleStatus -Required $Required -InstalledLookup $InstalledLookup

    # Step 2 — offers, keyed by module name for quick lookup below.
    $offers = @{}
    foreach ($offer in Get-M365ModuleRemediation -Status $status) {
        $offers[$offer.Name] = $offer
    }

    foreach ($item in $status) {
        Write-Verbose "Module $($item.Name): pinned v$($item.RequiredVersion); detected state '$($item.State)' (installed: '$($item.InstalledVersion)')."

        $action          = $null
        $detail          = $null
        $imported        = $false
        $resolvedVersion = $null
        $shouldImport    = $item.Satisfied   # only import once we know it's satisfied

        if ($item.Satisfied) {
            # Idempotent path: the pin is already met, nothing to install.
            $action = 'AlreadySatisfied'
            Write-Verbose "  $($item.Name) already satisfies the pin (v$($item.RequiredVersion)) — no install needed."
        }
        else {
            # Step 3 — put the self-healing offer to the caller.
            $offer = $offers[$item.Name]
            Write-Verbose "  $($item.Name) is unsatisfied ($($offer.Action)); presenting remediation offer."

            if (& $Consent $offer) {
                # Step 4 — consented install (CurrentUser, pinned).
                Write-Verbose "  Consent granted — $($offer.Command)"
                try {
                    & $Installer $offer
                    $action       = if ($offer.Action -eq 'Upgrade') { 'Upgraded' } else { 'Installed' }
                    $shouldImport = $true
                    Write-Verbose "  $($item.Name) $($action.ToLower()) to v$($item.RequiredVersion)."
                }
                catch {
                    # Loud, but don't dead-end the whole run (NFR-6): record and move on.
                    $action = 'Failed'
                    $detail = $_.Exception.Message
                    Write-Warning "  $($item.Name) install failed: $detail"
                }
            }
            else {
                # Gated apply: no consent, no change. Self-healing offered, declined.
                $action = 'Declined'
                $detail = 'Remediation offered but consent was declined.'
                Write-Warning "  $($item.Name) remediation declined — module remains unsatisfied."
            }
        }

        # Step 5 — import and read back the resolved version.
        if ($shouldImport) {
            try {
                $loaded = & $Importer $item.Name ([version] $item.RequiredVersion)
                if ($loaded -and $loaded.Version) {
                    $imported        = $true
                    $resolvedVersion = ([version] $loaded.Version).ToString()
                    Write-Verbose "  $($item.Name) imported; resolved version v$resolvedVersion."
                }
                else {
                    $action = 'Failed'
                    $detail = 'Import returned no module.'
                    Write-Warning "  $($item.Name) import returned nothing."
                }
            }
            catch {
                $action = 'Failed'
                $detail = $_.Exception.Message
                Write-Warning "  $($item.Name) import failed: $detail"
            }
        }

        # A module is satisfied at the end only if it imported at (or above) the pin.
        $satisfied = $imported -and ([version] $resolvedVersion -ge [version] $item.RequiredVersion)

        # Step 6 — report.
        [pscustomobject]@{
            Name             = $item.Name
            RequiredVersion  = $item.RequiredVersion
            State            = $item.State
            Action           = $action
            ResolvedVersion  = $resolvedVersion
            Imported         = $imported
            Satisfied        = $satisfied
            Detail           = $detail
        }
    }
}

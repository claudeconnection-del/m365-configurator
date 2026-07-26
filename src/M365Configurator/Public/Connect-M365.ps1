#requires -Version 7.6

function Connect-M365 {
    <#
    .SYNOPSIS
        Authenticate once, get a ready-to-use session — combines
        Connect-M365Graph, Connect-M365ExchangeOnline, and New-M365Session
        into a single call (owner feedback, 2026-07-26: wiring those three
        together by hand every time was real friction).

    .DESCRIPTION
        Connects both Microsoft Graph and Exchange Online by default and
        returns the resulting Session (New-M365Session), so the normal path
        from a fresh shell to "I can dry-run a profile" is one line:
        `$session = Connect-M365`.

        -GraphOnly / -ExoOnly connect just one provider; the other half is
        passed to New-M365Session as $null, exactly as if the caller had
        connected only one provider by hand. This function adds no new
        connection behavior of its own — it only sequences the two existing,
        already-hardened connect functions and reports what happened.

        Prints a plain-language summary of what connected via the Information
        stream (visible by default, unlike the connect functions' -Verbose-only
        detail) — connecting silently and leaving the caller to guess whether
        anything happened is exactly the gap this exists to close (this is
        especially easy to hit on an Entra-joined device, where
        Connect-MgGraph's device-code prompt can be satisfied silently via
        Windows SSO/broker with no visible prompt at all).

    .OUTPUTS
        pscustomobject (PSTypeName 'M365Configurator.Session') — see
        New-M365Session.

    .EXAMPLE
        $session = Connect-M365
        ./scripts/m365config.ps1 dryrun -ProfilePath ./profiles/security-baseline.yaml -Session $session

    .EXAMPLE
        $session = Connect-M365 -GraphOnly -Scopes 'Policy.Read.All'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # Connect Graph only; Exo is $null in the resulting session.
        [switch] $GraphOnly,

        # Connect Exchange Online only; Graph is $null in the resulting session.
        [switch] $ExoOnly,

        # Graph passthrough (Connect-M365Graph).
        [string[]] $Scopes = @(),
        [string] $TenantId,

        # Shared: both connect functions accept the same DeviceCode/Interactive vocabulary.
        [ValidateSet('DeviceCode', 'Interactive')]
        [string] $Method = 'DeviceCode',

        # EXO passthrough (Connect-M365ExchangeOnline).
        [string] $Organization,
        [string] $UserPrincipalName,
        [string] $ModuleBasePath
    )

    if ($GraphOnly -and $ExoOnly) {
        throw "Connect-M365: -GraphOnly and -ExoOnly are mutually exclusive (omit both to connect both)."
    }

    $graph = $null
    if (-not $ExoOnly) {
        $graph = Connect-M365Graph -Scopes $Scopes -TenantId $TenantId -Method $Method
        Write-Information "Connected to Microsoft Graph as $($graph.Account) (tenant $($graph.TenantId))." -InformationAction Continue
    }

    $exo = $null
    if (-not $GraphOnly) {
        $exo = Connect-M365ExchangeOnline -Organization $Organization -UserPrincipalName $UserPrincipalName -Method $Method -ModuleBasePath $ModuleBasePath
        Write-Information "Connected to Exchange Online as $($exo.UserPrincipalName) (org $($exo.Organization))." -InformationAction Continue
    }

    $session = New-M365Session -Graph $graph -Exo $exo
    Write-Information "Session ready — capabilities: $($session.Capabilities -join ', ')." -InformationAction Continue
    $session
}

#requires -Version 7.0

function Connect-M365ExchangeOnline {
    <#
    .SYNOPSIS
        Establishes an Exchange Online session on demand, consistent with the
        Graph auth model — modern auth, tokens in memory only.

    .DESCRIPTION
        The Exchange Online half of the connection foundation (MCA-11; FR-2,
        NFR-1; ADR-0001). It wraps Connect-ExchangeOnline (EXO V3, REST-based)
        and holds to the same security posture as Connect-M365Graph:

          * **Device code is the default flow** (-Device) — no in-container
            browser needed (research 04 §3.2/§6.2). Interactive browser sign-in
            is opt-in via -Method Interactive.
          * **The legacy/plaintext paths are never used**: -UseRPSSession
            (deprecated remote PowerShell) and -Credential / -InlineCredential
            (which force a SecureString that is plaintext on Linux and defeat
            MFA — research 04 §3.2/§8) are deliberately absent from the call.
          * **-ShowBanner:$false** for clean audit logs.
          * **-EXOModuleBasePath** (when supplied) redirects the auto-generated
            proxy-cmdlet modules and logs to an ephemeral path so teardown is a
            single delete and nothing leaks into a shared /tmp (research 04 §3.3).

        EXO V3 holds its MSAL tokens in memory for the connection; there is no
        on-disk token cache to opt out of the way Graph's -ContextScope Process
        does. Connection state is projected through a secret-free allowlist.

        Note: Security & Compliance PowerShell (Connect-IPPSSession) is out of
        scope on Linux (research 05 §4.3) — this covers Exchange Online only.

        Connect / connection-read are injected scriptblock seams for unit testing
        without a tenant or a device-code prompt.

    .OUTPUTS
        pscustomobject: Service, Connected, UserPrincipalName, Organization,
        State, ConnectionId, Method. No secrets.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $Organization,

        [string] $UserPrincipalName,

        [ValidateSet('DeviceCode', 'Interactive')]
        [string] $Method = 'DeviceCode',

        # Ephemeral path for EXO's proxy-cmdlet modules + logs (-EXOModuleBasePath).
        [string] $ModuleBasePath,

        # Seam: performs the sign-in given the resolved parameter splat.
        [scriptblock] $Connector = {
            param([hashtable] $ConnectParams)
            Connect-ExchangeOnline @ConnectParams
        },

        # Seam: enumerates active REST connections (Get-ConnectionInformation).
        [scriptblock] $ConnectionReader = { Get-ConnectionInformation }
    )

    # Build the sign-in parameters. Note what is deliberately NOT here:
    # -UseRPSSession, -Credential, -InlineCredential (all NFR-1 hazards).
    $connectParams = @{
        ShowBanner = $false
    }
    if ($Method -eq 'DeviceCode')  { $connectParams.Device            = $true }
    if ($Organization)             { $connectParams.Organization      = $Organization }
    if ($UserPrincipalName)        { $connectParams.UserPrincipalName = $UserPrincipalName }
    if ($ModuleBasePath)           { $connectParams.EXOModuleBasePath = $ModuleBasePath }

    $orgText = if ($Organization) { $Organization } else { '(default)' }
    Write-Verbose "Connecting to Exchange Online — method: $Method; tokens in-memory; organization: $orgText."

    & $Connector $connectParams

    # A successful sign-in must yield an active REST connection; its absence is a
    # real failure, not a "connected" result (loud/fast — NFR-6).
    $connection = @(& $ConnectionReader) | Select-Object -Last 1
    if (-not $connection) {
        throw 'Exchange Online connection failed: no active Exchange Online connection was established.'
    }

    # Project a secret-free view — only known-safe fields; a token on the
    # connection object can never leak through here.
    $state = [pscustomobject]@{
        Service           = 'ExchangeOnline'
        Connected         = $true
        UserPrincipalName = Get-M365ObjectProperty $connection 'UserPrincipalName'
        Organization      = Get-M365ObjectProperty $connection 'Organization'
        State             = Get-M365ObjectProperty $connection 'State'
        ConnectionId      = Get-M365ObjectProperty $connection 'ConnectionId'
        Method            = $Method
    }

    Write-Verbose "  Connected to Exchange Online as $($state.UserPrincipalName) (org $($state.Organization); state $($state.State))."
    $state
}

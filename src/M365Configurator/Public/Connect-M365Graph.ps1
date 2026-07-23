#requires -Version 7.0

function Connect-M365Graph {
    <#
    .SYNOPSIS
        Establishes a Microsoft Graph session on demand, with tokens held in
        process memory only.

    .DESCRIPTION
        The Graph half of the connection foundation (MCA-10; FR-2, NFR-1;
        ADR-0001). It wraps Connect-MgGraph and enforces the project's security
        tenet at the point of sign-in:

          * **-ContextScope Process is mandatory and not caller-overridable.**
            The default (CurrentUser) writes the MSAL token cache — access AND
            refresh tokens — to disk, which on headless Linux is unencrypted
            (research 04 §2.3/§2.4). Process scope keeps tokens in memory only;
            they die with the process. This is the single most important
            "no credentials on disk" control (NFR-1).
          * **Device code is the default flow** — no in-container browser needed
            (research 04 §6.2). Interactive browser sign-in is opt-in via
            -Method Interactive for when the tool runs on a workstation.

        Connection state is reported through a secret-free allowlist — never a
        token, never the whole context object — so nothing sensitive reaches the
        pipeline, logs, or profiles (NFR-1/NFR-5).

        The sign-in and context-read are injected as scriptblock seams so the
        logic is unit-testable without a tenant, a browser, or a device-code
        prompt. The defaults call the real Connect-MgGraph / Get-MgContext.

        Note: this only ends up with tokens in memory. Purging any accidental
        on-disk residue (the documented Disconnect-MgGraph cache bug) is the job
        of credential cleanup (MCA-12), not connect.

    .OUTPUTS
        pscustomobject: Service, Connected, Account, TenantId, Scopes, AuthType,
        ContextScope, Method, Environment. No secrets.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]] $Scopes = @(),

        [string] $TenantId,

        [ValidateSet('DeviceCode', 'Interactive')]
        [string] $Method = 'DeviceCode',

        # Seam: performs the sign-in given the resolved parameter splat. The
        # default enforces -ContextScope Process (memory-only tokens).
        [scriptblock] $Connector = {
            param([hashtable] $ConnectParams)
            Connect-MgGraph @ConnectParams
        },

        # Seam: reads the resulting auth context (Get-MgContext by default).
        [scriptblock] $ContextReader = { Get-MgContext }
    )

    # Build the sign-in parameters. -ContextScope Process is fixed here, not taken
    # from the caller — memory-only tokens are non-negotiable (NFR-1).
    $connectParams = @{
        ContextScope = 'Process'
        NoWelcome    = $true
    }
    if ($Scopes)   { $connectParams.Scopes   = $Scopes }
    if ($TenantId) { $connectParams.TenantId = $TenantId }
    if ($Method -eq 'DeviceCode') { $connectParams.UseDeviceCode = $true }

    $scopeText  = if ($Scopes)   { $Scopes -join ', ' } else { '(default)' }
    $tenantText = if ($TenantId) { $TenantId }          else { '(default)' }
    Write-Verbose "Connecting to Microsoft Graph — method: $Method; token scope: Process (memory-only); tenant: $tenantText."
    Write-Verbose "  Requested delegated scopes: $scopeText."

    & $Connector $connectParams

    # A successful sign-in must leave an auth context; its absence is a real
    # failure, not something to report as "connected" (loud/fast — NFR-6).
    $context = & $ContextReader
    if (-not $context) {
        throw 'Microsoft Graph connection failed: no authentication context was established.'
    }

    # Project a secret-free view. Only these known-safe fields are surfaced — a
    # token on the context (or any future field) can never leak through here.
    $state = [pscustomobject]@{
        Service      = 'MicrosoftGraph'
        Connected    = $true
        Account      = Get-M365ObjectProperty $context 'Account'
        TenantId     = Get-M365ObjectProperty $context 'TenantId'
        Scopes       = @(Get-M365ObjectProperty $context 'Scopes')
        AuthType     = Get-M365ObjectProperty $context 'AuthType'
        ContextScope = Get-M365ObjectProperty $context 'ContextScope'
        Method       = $Method
        Environment  = Get-M365ObjectProperty $context 'Environment'
    }

    Write-Verbose "  Connected as $($state.Account) (tenant $($state.TenantId); auth $($state.AuthType)); $(@($state.Scopes).Count) scope(s) granted."
    $state
}

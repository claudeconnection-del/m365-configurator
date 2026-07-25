#requires -Version 7.6

function Disconnect-M365Graph {
    <#
    .SYNOPSIS
        Tears down the current Microsoft Graph session and verifies the in-memory
        context is cleared.

    .DESCRIPTION
        The disconnect half of MCA-10 (FR-2, NFR-1). It ends the active Graph
        session via Disconnect-MgGraph and confirms the auth context is gone.

        Idempotent: with no active context it is a clean no-op (nothing to tear
        down), so it is safe to call unconditionally — including from a cleanup
        finally-block.

        Scope boundary: Disconnect-MgGraph is necessary but NOT sufficient for
        the "no credentials on disk" tenet — it clears the in-memory context but
        leaves any persisted MSAL cache files on disk (documented SDK bug,
        research 04 §4.1). Because Connect-M365Graph pins -ContextScope Process
        there should be no such file, but the belt-and-braces on-disk purge +
        full verification is owned by credential cleanup (MCA-12). This function
        deliberately stops at session teardown and its verification.

        The disconnect and context-read are injected seams for unit testing
        without a live session.

    .OUTPUTS
        pscustomobject: Service, Connected, WasConnected, Account. No secrets.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [scriptblock] $Disconnector = { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null },

        [scriptblock] $ContextReader = { Get-MgContext }
    )

    $before = & $ContextReader
    if (-not $before) {
        Write-Verbose 'Microsoft Graph: no active context — disconnect is a no-op.'
        return [pscustomobject]@{
            Service      = 'MicrosoftGraph'
            Connected    = $false
            WasConnected = $false
            Account      = $null
        }
    }

    $account = Get-M365ObjectProperty $before 'Account'
    Write-Verbose "Disconnecting Microsoft Graph session (account: $account)."
    & $Disconnector

    # Verify the teardown actually took — a surviving context means tokens may
    # still be live, which must fail loud rather than be reported as clean (NFR-6).
    $after = & $ContextReader
    if ($after) {
        throw 'Microsoft Graph disconnect failed: an authentication context is still present.'
    }
    Write-Verbose '  Graph context cleared. (On-disk MSAL cache purge is handled by credential cleanup — MCA-12.)'

    [pscustomobject]@{
        Service      = 'MicrosoftGraph'
        Connected    = $false
        WasConnected = $true
        Account      = $account
    }
}

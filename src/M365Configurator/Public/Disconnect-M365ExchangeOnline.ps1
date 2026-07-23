#requires -Version 7.0

function Disconnect-M365ExchangeOnline {
    <#
    .SYNOPSIS
        Tears down active Exchange Online sessions and verifies no connection
        remains.

    .DESCRIPTION
        The disconnect half of MCA-11 (FR-2, NFR-1). It ends active Exchange
        Online REST connections via Disconnect-ExchangeOnline (-Confirm:$false
        for non-interactive teardown) and confirms Get-ConnectionInformation
        reports nothing left.

        Idempotent: with no active connection it is a clean no-op, so it is safe
        to call unconditionally — including from a cleanup finally-block.

        Scope boundary: Disconnect-ExchangeOnline clears the in-memory tokens and
        connections but can leave the auto-generated proxy-cmdlet modules
        (tmpEXO*.psm1) and log files on disk (research 04 §4.2). Those are code /
        diagnostics, not secrets; removing that filesystem residue is owned by
        credential cleanup (MCA-12). This function stops at session teardown and
        its verification.

        Disconnect / connection-read are injected seams for unit testing.

    .OUTPUTS
        pscustomobject: Service, Connected, WasConnected. No secrets.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [scriptblock] $Disconnector = { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue },

        [scriptblock] $ConnectionReader = { Get-ConnectionInformation }
    )

    $before = @(& $ConnectionReader)
    if ($before.Count -eq 0) {
        Write-Verbose 'Exchange Online: no active connection — disconnect is a no-op.'
        return [pscustomobject]@{
            Service      = 'ExchangeOnline'
            Connected    = $false
            WasConnected = $false
        }
    }

    Write-Verbose "Disconnecting Exchange Online ($($before.Count) active connection(s))."
    & $Disconnector

    # Verify the teardown took — a surviving connection means tokens may still be
    # live, which must fail loud rather than report as clean (NFR-6).
    $after = @(& $ConnectionReader)
    if ($after.Count -gt 0) {
        throw 'Exchange Online disconnect failed: an active connection is still present.'
    }
    Write-Verbose '  Exchange Online connections cleared. (Temp proxy-module/log purge is handled by credential cleanup — MCA-12.)'

    [pscustomobject]@{
        Service      = 'ExchangeOnline'
        Connected    = $false
        WasConnected = $true
    }
}

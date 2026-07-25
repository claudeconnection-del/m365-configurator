#requires -Version 7.6

function Invoke-M365ExoCommand {
    <#
    .SYNOPSIS
        The module's single Exchange Online call seam (D5) — resolves and
        invokes an EXO cmdlet by name, mirroring Invoke-M365GraphRequest
        (ADR-0014).

    .DESCRIPTION
        Every EXO control handler issues its cmdlet call through here rather
        than calling the cmdlet directly by name in the handler body, so the
        EXO touch-point lives in one place and tests mock a single
        module-owned command instead of every real EXO cmdlet individually.

        The named command is resolved at call time (Get-Command), not
        imported or referenced at parse time: the EXO module
        (ExchangeOnlineManagement) is a runtime prerequisite handled by the
        module preflight (ADR-0011) — missing it fails loud here, at the
        point of use, with PowerShell's own command-not-found error, rather
        than at module import.

        Internal helper; not exported.

    .OUTPUTS
        Whatever the resolved command returns.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [hashtable] $Parameters = @{}
    )

    $command = Get-Command -Name $Name -ErrorAction Stop
    & $command @Parameters
}

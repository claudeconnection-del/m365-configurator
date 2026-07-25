#requires -Version 7.0

function Invoke-M365GraphRequest {
    <#
    .SYNOPSIS
        The module's single Microsoft Graph call seam — a thin wrapper over
        Invoke-MgGraphRequest (ADR-0014).

    .DESCRIPTION
        Every Graph control handler issues its raw REST call through here rather
        than calling the SDK cmdlet directly, so the Graph touch-point lives in ONE
        place — the future home of paging (`@odata.nextLink`), retry, and Graph-error
        interpretation — and the tests mock a single module-owned command.

        Raw REST keeps the Graph dependency to the one pinned module we already
        require, Microsoft.Graph.Authentication (ADR-0014; NFR-3), instead of
        pulling in a typed sub-module per control.

        Internal helper; not exported.

    .OUTPUTS
        Whatever Invoke-MgGraphRequest returns — a hashtable for GET, nothing for a
        204 write.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')]
        [string] $Method,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Uri,

        [hashtable] $Body
    )

    $params = @{ Method = $Method; Uri = $Uri }
    if ($PSBoundParameters.ContainsKey('Body')) { $params.Body = $Body }

    Invoke-MgGraphRequest @params
}

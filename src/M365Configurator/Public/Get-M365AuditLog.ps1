#requires -Version 7.6

function Get-M365AuditLog {
    <#
    .SYNOPSIS
        Reads a day's structured audit log, optionally filtered by control id
        (MCA-35; D10, FR-12).

    .DESCRIPTION
        The read half of the audit log (Write-M365AuditRecord is the write
        half). Resolves the same directory precedence as the writer
        (-LogDirectory, then $env:M365_CONFIGURATOR_LOG_DIR, then './logs'),
        reads 'm365config-audit-<Date>.jsonl' (default: today, UTC), and
        deserializes each line.

        A day with no log file is not an error — it means nothing was ever
        applied that day — so it returns an empty result with a verbose note
        rather than throwing.

    .OUTPUTS
        pscustomobject per record (parsed JSON), optionally filtered to those
        whose controlId matches -ControlId. Empty array when the day's log
        file doesn't exist.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $Date = ([DateTime]::UtcNow.ToString('yyyyMMdd')),

        [string] $ControlId,

        [string] $LogDirectory
    )

    $directory =
        if ($LogDirectory) { $LogDirectory }
        elseif ($env:M365_CONFIGURATOR_LOG_DIR) { $env:M365_CONFIGURATOR_LOG_DIR }
        else { './logs' }

    $path = Join-Path $directory "m365config-audit-$Date.jsonl"

    if (-not (Test-Path -LiteralPath $path)) {
        Write-Verbose "No audit log for $Date at '$path' — a day with nothing applied has no log."
        return @()
    }

    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($line in Get-Content -LiteralPath $path) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $records.Add(($line | ConvertFrom-Json))
    }

    $result = if ($ControlId) { @($records | Where-Object { $_.controlId -eq $ControlId }) } else { $records.ToArray() }
    @($result)
}

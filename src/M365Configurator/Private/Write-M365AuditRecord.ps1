#requires -Version 7.6

function Write-M365AuditRecord {
    <#
    .SYNOPSIS
        Appends one structured audit record to the day's append-only JSONL log
        (MCA-35; D10, NFR-5, FR-12).

    .DESCRIPTION
        The append-only writer both the apply engine (one record per applied
        item, plus a run-started/run-finished pair) and any other future caller
        use. Every record is scanned with Find-M365SecretKey before it is
        written — a credential-shaped key anywhere in the record throws and
        nothing is written (NFR-1 backstop; audit logs are exactly the kind of
        long-lived, widely-read artifact a leaked secret must never reach).

        The log directory resolves in this order: the explicit -LogDirectory
        parameter, then the $env:M365_CONFIGURATOR_LOG_DIR environment
        variable, then './logs'. The directory is created if it doesn't exist.
        The file is named 'm365config-audit-<yyyyMMdd>.jsonl' using the current
        UTC date, so a run spanning midnight UTC splits across two files — an
        accepted, documented tradeoff for keeping the file name pure and
        deterministic from "now".

        -Record is typed [System.Collections.IDictionary] rather than
        [hashtable] deliberately: a [hashtable]-typed parameter converts an
        [ordered] dictionary into an unordered Hashtable at bind time, whose
        enumeration order is hash-seed-dependent and differs across process
        runs — scrambling the JSONL field order (a readability/NFR-9
        regression for a human-audited log). IDictionary accepts the caller's
        [ordered] hashtable as-is, so ConvertTo-Json emits keys in the order
        the caller built them, deterministically.

        Internal helper; not exported.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Record,

        [string] $LogDirectory
    )

    $secretHits = @(Find-M365SecretKey -InputObject $Record)
    if ($secretHits.Count -gt 0) {
        throw "Refusing to write an audit record carrying credential-shaped key(s): $($secretHits -join ', ')."
    }

    $directory =
        if ($LogDirectory) { $LogDirectory }
        elseif ($env:M365_CONFIGURATOR_LOG_DIR) { $env:M365_CONFIGURATOR_LOG_DIR }
        else { './logs' }

    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $fileName = "m365config-audit-$([DateTime]::UtcNow.ToString('yyyyMMdd')).jsonl"
    $path     = Join-Path $directory $fileName
    $line     = ConvertTo-Json -InputObject $Record -Compress -Depth 8

    Add-Content -LiteralPath $path -Value $line -Encoding utf8
}

#requires -Version 7.6
<#
    Tests for the audit-log writer (MCA-35; D10, NFR-1, NFR-5): an append-only,
    secret-free JSONL record per applied item / run, written by
    Write-M365AuditRecord. It's private, so tests run InModuleScope (matching
    tests/Invoke-M365Apply.Tests.ps1's convention for private engine pieces).
    Every write is TestDrive-scoped so nothing touches the real filesystem.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force
}

Describe 'Write-M365AuditRecord' {

    It 'throws and writes nothing when the record carries a credential-shaped key (NFR-1 backstop)' {
        InModuleScope M365Configurator {
            $dir    = Join-Path "$TestDrive" 'secret'
            $record = @{ action = 'apply-item'; controlId = 'X'; clientSecret = 'shhh' }

            { Write-M365AuditRecord -Record $record -LogDirectory $dir } | Should -Throw '*clientSecret*'

            @(Get-ChildItem -LiteralPath "$TestDrive" -Recurse -File -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        }
    }

    It 'appends one JSONL line per call, each independently parseable' {
        InModuleScope M365Configurator {
            $dir = Join-Path "$TestDrive" 'jsonl'

            Write-M365AuditRecord -Record @{ action = 'run-started'; runId = 'r1' } -LogDirectory $dir
            Write-M365AuditRecord -Record @{ action = 'run-finished'; runId = 'r1' } -LogDirectory $dir

            $expectedFile = "m365config-audit-$([DateTime]::UtcNow.ToString('yyyyMMdd')).jsonl"
            $path = Join-Path $dir $expectedFile

            $lines = @(Get-Content -LiteralPath $path)
            $lines.Count | Should -Be 2

            $parsed = @($lines | ForEach-Object { $_ | ConvertFrom-Json })
            $parsed[0].action | Should -Be 'run-started'
            $parsed[1].action | Should -Be 'run-finished'
        }
    }

    It 'creates the log directory when it does not already exist' {
        InModuleScope M365Configurator {
            $dir = Join-Path "$TestDrive" 'does' 'not' 'exist' 'yet'

            Write-M365AuditRecord -Record @{ action = 'run-started' } -LogDirectory $dir

            Test-Path -LiteralPath $dir -PathType Container | Should -BeTrue
        }
    }

    It 'preserves the caller''s key order in the written JSONL line (readable, deterministic audit trail — NFR-9)' {
        InModuleScope M365Configurator {
            $dir = Join-Path "$TestDrive" 'ordered'

            # A [hashtable]-typed -Record parameter would silently convert this
            # [ordered] dictionary to an unordered Hashtable, scrambling field
            # order across process runs — Write-M365AuditRecord must accept it
            # as-is (IDictionary) so the caller's order survives verbatim.
            Write-M365AuditRecord -Record ([ordered]@{ z = 1; a = 2; m = 3; timestamp = 'x' }) -LogDirectory $dir

            $expectedFile = "m365config-audit-$([DateTime]::UtcNow.ToString('yyyyMMdd')).jsonl"
            $line = Get-Content -LiteralPath (Join-Path $dir $expectedFile)

            $line | Should -Be '{"z":1,"a":2,"m":3,"timestamp":"x"}'
        }
    }

    It 'honors the M365_CONFIGURATOR_LOG_DIR environment variable when -LogDirectory is not supplied' {
        InModuleScope M365Configurator {
            $dir = Join-Path "$TestDrive" 'env-dir'
            $previous = $env:M365_CONFIGURATOR_LOG_DIR
            try {
                $env:M365_CONFIGURATOR_LOG_DIR = $dir
                Write-M365AuditRecord -Record @{ action = 'run-started' }

                $expectedFile = "m365config-audit-$([DateTime]::UtcNow.ToString('yyyyMMdd')).jsonl"
                Test-Path -LiteralPath (Join-Path $dir $expectedFile) | Should -BeTrue
            }
            finally {
                $env:M365_CONFIGURATOR_LOG_DIR = $previous
            }
        }
    }
}

#requires -Version 7.6
<#
    Tests for Get-M365AuditLog (MCA-35; D10, FR-12): reads/filters the day's
    JSONL audit log. Tenant-free — fixture files are written directly into
    TestDrive.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force

    function New-M365AuditLogFixture {
        param([string] $Directory, [string] $Date, [object[]] $Records)
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
        $path = Join-Path $Directory "m365config-audit-$Date.jsonl"
        $lines = $Records | ForEach-Object { ConvertTo-Json -InputObject $_ -Compress -Depth 8 }
        Set-Content -LiteralPath $path -Value $lines -Encoding utf8
        $path
    }
}

Describe 'Get-M365AuditLog' {

    It 'reads and parses every record for the given day' {
        $dir = Join-Path "$TestDrive" 'read'
        New-M365AuditLogFixture -Directory $dir -Date '20260701' -Records @(
            @{ action = 'run-started'; controlId = $null }
            @{ action = 'apply-item'; controlId = 'ID-2' }
            @{ action = 'run-finished'; controlId = $null }
        )

        $result = Get-M365AuditLog -Date '20260701' -LogDirectory $dir

        @($result).Count | Should -Be 3
        $result[1].controlId | Should -Be 'ID-2'
    }

    It 'filters by control id' {
        $dir = Join-Path "$TestDrive" 'filter'
        New-M365AuditLogFixture -Directory $dir -Date '20260701' -Records @(
            @{ action = 'apply-item'; controlId = 'ID-2' }
            @{ action = 'apply-item'; controlId = 'AM-2' }
            @{ action = 'apply-item'; controlId = 'ID-2' }
        )

        $result = @(Get-M365AuditLog -Date '20260701' -ControlId 'ID-2' -LogDirectory $dir)

        $result.Count | Should -Be 2
        $result | ForEach-Object { $_.controlId | Should -Be 'ID-2' }
    }

    It 'returns an empty result without throwing when the day has no log file' {
        $dir = Join-Path "$TestDrive" 'missing'

        { $script:result = @(Get-M365AuditLog -Date '19990101' -LogDirectory $dir -ErrorAction Stop) } | Should -Not -Throw

        $script:result | Should -BeNullOrEmpty
    }
}

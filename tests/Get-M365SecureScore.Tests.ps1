#requires -Version 7.0
<#
    Tests for Get-M365SecureScore — the read-only Secure Score capture (MCA-29,
    AUD-3; FR-4 read). Secure Score is a pre/post-apply VERIFICATION signal, never
    a desired-state or drift target — it is computed by Microsoft and changes daily
    (research 01 §4.7, research 05 R8). These tests pin that contract: the function
    projects a snapshot into a stable, secret-free report and never exposes a
    Set/Compare seam.

    The tenant read (Get-MgSecuritySecureScore) and the capture clock are injected
    as seams, so the projection logic is exercised with no tenant and no wall clock.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force

    # A fixed capture clock so CapturedAt is deterministic in every test.
    $script:clock = { [datetime]::new(2026, 7, 25, 12, 0, 0, [DateTimeKind]::Utc) }

    # One SDK-shaped snapshot (Graph PowerShell returns PascalCase properties).
    $script:oneSnapshot = {
        [pscustomobject]@{
            Id              = '2026-07-24_tenantguid'
            AzureTenantId   = '11111111-2222-3333-4444-555555555555'
            CreatedDateTime = [datetime]::new(2026, 7, 24, 0, 0, 0, [DateTimeKind]::Utc)
            CurrentScore    = 47.0
            MaxScore        = 60.0
            ActiveUserCount = 12
            ControlScores   = @(
                [pscustomobject]@{ ControlName = 'MFARegistrationV2'; ControlCategory = 'Identity'; Score = 8.0 }
                [pscustomobject]@{ ControlName = 'BlockLegacyAuthentication'; ControlCategory = 'Identity'; Score = 0.0 }
            )
        }
    }
}

Describe 'Get-M365SecureScore' {

    It 'projects a snapshot into a read-only report (score, tenant, users)' {
        $report = Get-M365SecureScore -ScoreReader $script:oneSnapshot -Clock $script:clock

        $report.Service         | Should -Be 'MicrosoftGraph'
        $report.Kind            | Should -Be 'report'
        $report.SnapshotId      | Should -Be '2026-07-24_tenantguid'
        $report.TenantId        | Should -Be '11111111-2222-3333-4444-555555555555'
        $report.CurrentScore    | Should -Be 47.0
        $report.MaxScore        | Should -Be 60.0
        $report.ActiveUserCount | Should -Be 12
        $report.SnapshotDate    | Should -Be ([datetime]::new(2026, 7, 24, 0, 0, 0, [DateTimeKind]::Utc))
        $report.CapturedAt      | Should -Be ([datetime]::new(2026, 7, 25, 12, 0, 0, [DateTimeKind]::Utc))
    }

    It 'computes Percentage from current/max, rounded to one decimal' {
        $report = Get-M365SecureScore -ScoreReader $script:oneSnapshot -Clock $script:clock

        # 47 / 60 = 78.33... -> 78.3
        $report.Percentage | Should -Be 78.3
    }

    It 'yields a null Percentage when MaxScore is zero (no divide-by-zero)' {
        $reader = { [pscustomobject]@{ Id = 's'; CurrentScore = 0.0; MaxScore = 0.0; CreatedDateTime = $script:clock.Invoke() } }

        $report = Get-M365SecureScore -ScoreReader $reader -Clock $script:clock

        $report.Percentage | Should -BeNullOrEmpty
    }

    It 'captures the most recent snapshot when the reader returns several' {
        $reader = {
            @(
                [pscustomobject]@{ Id = 'old'; CurrentScore = 40.0; MaxScore = 60.0; CreatedDateTime = [datetime]::new(2026, 7, 22, 0, 0, 0, [DateTimeKind]::Utc) }
                [pscustomobject]@{ Id = 'new'; CurrentScore = 50.0; MaxScore = 60.0; CreatedDateTime = [datetime]::new(2026, 7, 24, 0, 0, 0, [DateTimeKind]::Utc) }
                [pscustomobject]@{ Id = 'mid'; CurrentScore = 45.0; MaxScore = 60.0; CreatedDateTime = [datetime]::new(2026, 7, 23, 0, 0, 0, [DateTimeKind]::Utc) }
            )
        }

        $report = Get-M365SecureScore -ScoreReader $reader -Clock $script:clock

        $report.SnapshotId   | Should -Be 'new'
        $report.CurrentScore | Should -Be 50.0
    }

    It 'normalizes control scores into a stable, name-sorted list' {
        $report = Get-M365SecureScore -ScoreReader $script:oneSnapshot -Clock $script:clock

        $report.ControlScores            | Should -HaveCount 2
        # Sorted by name for stable, inspectable output (NFR-9): Block... before MFA...
        $report.ControlScores[0].Name    | Should -Be 'BlockLegacyAuthentication'
        $report.ControlScores[0].Category | Should -Be 'Identity'
        $report.ControlScores[0].Score   | Should -Be 0.0
        $report.ControlScores[1].Name    | Should -Be 'MFARegistrationV2'
    }

    It 'returns an empty control list (not null) when the snapshot has no control scores' {
        $reader = { [pscustomobject]@{ Id = 's'; CurrentScore = 10.0; MaxScore = 20.0; CreatedDateTime = $script:clock.Invoke() } }

        $report = Get-M365SecureScore -ScoreReader $reader -Clock $script:clock

        # Assert on the value itself: piping an empty array sends zero objects and
        # would unwrap to $null, so check the stored property directly.
        $report.ControlScores -is [array] | Should -BeTrue
        @($report.ControlScores).Count    | Should -Be 0
    }

    It 'stamps the apply-boundary label when one is supplied' {
        $pre  = Get-M365SecureScore -Boundary Pre  -ScoreReader $script:oneSnapshot -Clock $script:clock
        $post = Get-M365SecureScore -Boundary Post -ScoreReader $script:oneSnapshot -Clock $script:clock

        $pre.Boundary  | Should -Be 'Pre'
        $post.Boundary | Should -Be 'Post'
    }

    It 'leaves Boundary null for a standalone (unlabelled) capture' {
        $report = Get-M365SecureScore -ScoreReader $script:oneSnapshot -Clock $script:clock

        $report.Boundary | Should -BeNullOrEmpty
    }

    It 'fails loud when no snapshot is returned — a blank verification signal is a failure (NFR-6)' {
        $reader = { @() }

        { Get-M365SecureScore -ScoreReader $reader -Clock $script:clock } |
            Should -Throw -ExpectedMessage '*no Secure Score snapshot*'
    }

    It 'is a read-only report: it exposes neither a Set nor a Compare seam' {
        $report = Get-M365SecureScore -ScoreReader $script:oneSnapshot -Clock $script:clock

        $report.PSObject.Properties.Name | Should -Not -Contain 'Set'
        $report.PSObject.Properties.Name | Should -Not -Contain 'Compare'
    }

    It 'defaults the score reader to the real Get-MgSecuritySecureScore cmdlet' {
        # We cannot hit a tenant here, but we can prove the default seam targets the
        # documented cmdlet (research 01 §4.7) rather than something else.
        $default = (Get-Command Get-M365SecureScore).Parameters['ScoreReader'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.PSDefaultValueAttribute] }

        # The default value's text must name the Graph Secure Score cmdlet.
        (Get-Command Get-M365SecureScore).ScriptBlock.ToString() |
            Should -Match 'Get-MgSecuritySecureScore'
    }
}

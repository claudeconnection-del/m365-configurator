#requires -Version 7.6
<#
    Tests for Get-M365SecureScore — the read-only Secure Score capture (MCA-29,
    AUD-3; FR-4 read). Secure Score is a pre/post-apply VERIFICATION signal, never
    a desired-state or drift target — it is computed by Microsoft and changes daily
    (research 01 §4.7, research 05 R8). These tests pin that contract: the function
    projects a snapshot into a stable, secret-free report and never exposes a
    Set/Compare seam.

    The tenant read and the capture clock are injected as seams, so the projection
    logic is exercised with no tenant and no wall clock. The DEFAULT reader goes
    through the module Graph seam (Invoke-M365GraphRequest, ADR-0014) — pinned by
    a module-scoped mock test, so no typed Graph sub-module is ever required.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force

    # A fixed capture clock so CapturedAt is deterministic in every test.
    $script:clock = { [datetime]::new(2026, 7, 25, 12, 0, 0, [DateTimeKind]::Utc) }

    # One raw-REST-shaped snapshot: the ADR-0014 seam returns hashtables keyed
    # with Graph's camelCase JSON names. (Other fixtures below use PascalCase
    # pscustomobjects on purpose — the projection reads both shapes.)
    $script:oneSnapshot = {
        @{
            id              = '2026-07-24_tenantguid'
            azureTenantId   = '11111111-2222-3333-4444-555555555555'
            createdDateTime = [datetime]::new(2026, 7, 24, 0, 0, 0, [DateTimeKind]::Utc)
            currentScore    = 47.0
            maxScore        = 60.0
            activeUserCount = 12
            controlScores   = @(
                @{ controlName = 'MFARegistrationV2'; controlCategory = 'Identity'; score = 8.0 }
                @{ controlName = 'BlockLegacyAuthentication'; controlCategory = 'Identity'; score = 0.0 }
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
        $reader = { [pscustomobject]@{ Id = 's'; CurrentScore = 0.0; MaxScore = 0.0; CreatedDateTime = [datetime]::new(2026, 7, 25, 0, 0, 0, [DateTimeKind]::Utc) } }

        $report = Get-M365SecureScore -ScoreReader $reader -Clock $script:clock

        $report.Percentage | Should -BeNullOrEmpty
    }

    It 'fails loud when a snapshot carries no readable score — [double]$null would report a false 0% (NFR-6)' {
        $reader = { [pscustomobject]@{ Id = 's'; MaxScore = 60.0; CreatedDateTime = [datetime]::new(2026, 7, 25, 0, 0, 0, [DateTimeKind]::Utc) } }

        { Get-M365SecureScore -ScoreReader $reader -Clock $script:clock } |
            Should -Throw -ExpectedMessage '*readable currentScore/maxScore*'
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
        $reader = { [pscustomobject]@{ Id = 's'; CurrentScore = 10.0; MaxScore = 20.0; CreatedDateTime = [datetime]::new(2026, 7, 25, 0, 0, 0, [DateTimeKind]::Utc) } }

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

    It 'is read-only by construction: no Set/Compare parameters, and AUD-3 is not a registered control' {
        # The meaningful assertions: the FUNCTION offers no write seams, and the
        # registry never treats Secure Score as a desired-state control (research
        # 05 R8). Asserting on the report object alone would be a tautology.
        $parameters = (Get-Command Get-M365SecureScore).Parameters.Keys
        $parameters | Should -Not -Contain 'Set'
        $parameters | Should -Not -Contain 'Compare'

        @(Get-M365ControlRegistry).Id | Should -Not -Contain 'AUD-3'

        $report = Get-M365SecureScore -ScoreReader $script:oneSnapshot -Clock $script:clock
        $report.PSObject.TypeNames | Should -Contain 'M365Configurator.SecureScoreReport'
    }

    It 'defaults the score reader to the module Graph seam (ADR-0014): GET v1.0/security/secureScores?$top=1, unwrapping value' {
        # createdDateTime is an ISO-8601 STRING here on purpose — that is the real
        # shape a raw-REST hashtable carries (Graph JSON has no date type).
        Mock Invoke-M365GraphRequest -ModuleName M365Configurator {
            @{
                value = @(
                    @{ id = 'seam'; currentScore = 12.0; maxScore = 48.0; createdDateTime = '2026-07-24T00:00:00Z' }
                )
            }
        }

        $report = Get-M365SecureScore -Clock $script:clock

        # Exact-match the URI: a -match pattern would also accept a beta endpoint,
        # a missing $top, or the interpolated-away '?=1' that double-quoting the
        # URI in the implementation would produce. Single quotes here too.
        Should -Invoke Invoke-M365GraphRequest -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Uri -eq 'v1.0/security/secureScores?$top=1'
        }
        $report.SnapshotId   | Should -Be 'seam'
        $report.CurrentScore | Should -Be 12.0
        $report.Percentage   | Should -Be 25.0

        # The ISO string is normalized to a UTC [datetime] preserving the instant —
        # a plain [datetime] cast would yield Kind=Local and shift it (NFR-5).
        $report.SnapshotDate      | Should -Be ([datetime]::new(2026, 7, 24, 0, 0, 0, [DateTimeKind]::Utc))
        $report.SnapshotDate.Kind | Should -Be ([System.DateTimeKind]::Utc)
    }
}

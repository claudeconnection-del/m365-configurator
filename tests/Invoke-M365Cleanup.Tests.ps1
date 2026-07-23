#requires -Version 7.0
<#
    Tests for Invoke-M365Cleanup — verified credential cleanup on disconnect /
    session end (MCA-12; FR-3, NFR-1). It is the aggregate teardown the app runs
    in a finally-block and at process start: tear down live connections, purge any
    on-disk token-cache residue, dispose in-memory secrets, then VERIFY nothing
    remains — failing loud if it does (research 04 §5; NFR-6).

    Because Disconnect-MgGraph does not delete the persisted MSAL cache (documented
    bug, research §4.1) and EXO leaves temp proxy modules behind (§4.2), cleanup
    is deliberately belt-and-braces: it does not trust the disconnects, it
    re-checks. All side effects — disconnect, context/connection reads, file
    removal, residue test, secret disposal — are injected seams so the routine is
    unit-tested without a tenant or touching real cache locations.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force
}

Describe 'Invoke-M365Cleanup' {

    BeforeEach {
        $script:graphDisc = $false
        $script:exoDisc   = $false
        $script:disposed  = $false
    }

    It 'tears down both services, purges cache paths, and verifies clean' {
        # Real temp files stand in for on-disk cache residue; the default remover
        # and residue-test seams must actually delete and then confirm them gone.
        $dir  = Join-Path ([System.IO.Path]::GetTempPath()) ("m365clean-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $dir | Out-Null
        $f1 = Join-Path $dir 'ecache.bin3'; Set-Content -Path $f1 -Value 'token'
        $f2 = Join-Path $dir '.IdentityService'; New-Item -ItemType Directory -Path $f2 | Out-Null

        $result = Invoke-M365Cleanup `
            -GraphDisconnector  { $script:graphDisc = $true } `
            -ExoDisconnector    { $script:exoDisc = $true } `
            -GraphContextReader { $null } `
            -ExoConnectionReader { @() } `
            -CachePath @($f1, $f2) `
            -SecretDisposer { $script:disposed = $true }

        $script:graphDisc | Should -BeTrue
        $script:exoDisc   | Should -BeTrue
        $script:disposed  | Should -BeTrue
        Test-Path $f1     | Should -BeFalse   # actually deleted
        Test-Path $f2     | Should -BeFalse
        $result.Clean     | Should -BeTrue

        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'is a safe no-op when nothing is connected and no cache exists (idempotent)' {
        $result = Invoke-M365Cleanup `
            -GraphDisconnector  { $script:graphDisc = $true } `
            -ExoDisconnector    { $script:exoDisc = $true } `
            -GraphContextReader { $null } `
            -ExoConnectionReader { @() } `
            -CachePath @()

        $result.Clean       | Should -BeTrue
        $result.GraphCleared | Should -BeTrue
        $result.ExoCleared   | Should -BeTrue
    }

    It 'fails loud if a Graph auth context survives cleanup (NFR-6)' {
        { Invoke-M365Cleanup `
            -GraphDisconnector  { } `
            -ExoDisconnector    { } `
            -GraphContextReader { [pscustomobject]@{ Account = 'admin@contoso' } } `
            -ExoConnectionReader { @() } `
            -CachePath @() } |
            Should -Throw -ExpectedMessage '*residue*'
    }

    It 'fails loud if an Exchange Online connection survives cleanup (NFR-6)' {
        { Invoke-M365Cleanup `
            -GraphDisconnector  { } `
            -ExoDisconnector    { } `
            -GraphContextReader { $null } `
            -ExoConnectionReader { [pscustomobject]@{ ConnectionId = 'x' } } `
            -CachePath @() } |
            Should -Throw -ExpectedMessage '*residue*'
    }

    It 'fails loud if on-disk cache residue remains after removal (NFR-6)' {
        # A no-op remover leaves the file in place; the residue test must catch it.
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("m365clean-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $dir | Out-Null
        $f = Join-Path $dir 'mg.msal.cache.cae'; Set-Content -Path $f -Value 'refresh-token'

        { Invoke-M365Cleanup `
            -GraphDisconnector  { } `
            -ExoDisconnector    { } `
            -GraphContextReader { $null } `
            -ExoConnectionReader { @() } `
            -CachePath @($f) `
            -Remover { param($Path) } } |   # deliberately does nothing
            Should -Throw -ExpectedMessage '*residue*'

        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'completes cleanup even when a disconnector throws (best-effort teardown)' {
        # A disconnect that errors must not stop file purge or verification — the
        # routine is what runs in a finally-block, so it cannot itself dead-end.
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("m365clean-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $dir | Out-Null
        $f = Join-Path $dir 'ecache.bin3'; Set-Content -Path $f -Value 'token'

        $result = Invoke-M365Cleanup `
            -GraphDisconnector  { throw 'graph disconnect blew up' } `
            -ExoDisconnector    { throw 'exo disconnect blew up' } `
            -GraphContextReader { $null } `
            -ExoConnectionReader { @() } `
            -CachePath @($f)

        Test-Path $f  | Should -BeFalse   # purge still happened
        $result.Clean | Should -BeTrue

        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'reports without leaking secrets and names the paths it purged' {
        $result = Invoke-M365Cleanup `
            -GraphDisconnector  { } -ExoDisconnector { } `
            -GraphContextReader { $null } -ExoConnectionReader { @() } `
            -CachePath @('/tmp/does-not-exist-xyz')

        $result.PSObject.Properties.Name | Should -Contain 'Clean'
        $result.PSObject.Properties.Name | Should -Contain 'PathsPurged'
        $result.PathsPurged | Should -Contain '/tmp/does-not-exist-xyz'
    }
}

#requires -Version 7.6
<#
    Tests for Connect-M365Graph / Disconnect-M365Graph — establishing and tearing
    down a Microsoft Graph session on demand, with tokens held in memory ONLY
    (MCA-10; FR-2, NFR-1; ADR-0001).

    The security-critical control (research 04 §2.3): every Connect-MgGraph call
    MUST pass -ContextScope Process so tokens live in process memory and die with
    it — never the on-disk MSAL cache the default CurrentUser scope would write.
    Device code is the container default; interactive browser is opt-in.

    The sign-in and context-read side effects are injected as scriptblock seams so
    the logic is testable without a real tenant, a browser, or a device-code
    prompt. A separate test drives the *real* default connector (Connect-MgGraph
    mocked in module scope) to prove the enforced flags on the actual code path.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force

    # A stand-in Graph auth context shaped like the real Get-MgContext output
    # (Microsoft.Graph.PowerShell.Authentication.AuthContext). The last three are
    # the genuine secret-bearing fields that object carries — they must NEVER
    # surface in the reported state.
    $script:fakeContext = [pscustomobject]@{
        Account               = 'admin@contoso.onmicrosoft.com'
        TenantId              = '11111111-2222-3333-4444-555555555555'
        Scopes                = @('Policy.Read.All', 'Directory.Read.All')
        AuthType              = 'Delegated'
        ContextScope          = 'Process'
        Environment           = 'Global'
        ClientSecret          = 'SECRET-CLIENT-DO-NOT-LEAK'
        Certificate           = 'CERT-OBJECT-DO-NOT-LEAK'
        CertificateThumbprint = 'AABBCCDD-DO-NOT-LEAK'
    }
}

Describe 'Connect-M365Graph' {

    BeforeEach { $script:captured = $null }

    It 'always requests the memory-only Process context scope (never CurrentUser)' {
        $connector = { param($ConnectParams) $script:captured = $ConnectParams }
        $reader    = { $script:fakeContext }

        $null = Connect-M365Graph -Scopes 'Policy.Read.All' -TenantId 'contoso' `
            -Connector $connector -ContextReader $reader

        $script:captured.ContextScope | Should -Be 'Process'
        $script:captured.Keys         | Should -Not -Contain 'AccessToken'
    }

    It 'defaults to device-code flow (container-friendly, no browser)' {
        $connector = { param($ConnectParams) $script:captured = $ConnectParams }
        $reader    = { $script:fakeContext }

        $null = Connect-M365Graph -Connector $connector -ContextReader $reader

        $script:captured.UseDeviceCode | Should -BeTrue
    }

    It 'omits the device-code switch when interactive browser flow is requested' {
        $connector = { param($ConnectParams) $script:captured = $ConnectParams }
        $reader    = { $script:fakeContext }

        $null = Connect-M365Graph -Method Interactive -Connector $connector -ContextReader $reader

        $script:captured.Keys | Should -Not -Contain 'UseDeviceCode'
    }

    It 'passes the requested scopes and tenant through to the sign-in' {
        $connector = { param($ConnectParams) $script:captured = $ConnectParams }
        $reader    = { $script:fakeContext }

        $null = Connect-M365Graph -Scopes 'Policy.Read.All', 'Directory.Read.All' -TenantId 'contoso' `
            -Connector $connector -ContextReader $reader

        $script:captured.Scopes   | Should -Be @('Policy.Read.All', 'Directory.Read.All')
        $script:captured.TenantId | Should -Be 'contoso'
    }

    It 'reports connection state as exactly a secret-free allowlist (NFR-1)' {
        $connector = { param($ConnectParams) }
        $reader    = { $script:fakeContext }

        $state = Connect-M365Graph -Connector $connector -ContextReader $reader

        $state.Connected | Should -BeTrue
        $state.Account   | Should -Be 'admin@contoso.onmicrosoft.com'
        $state.TenantId  | Should -Be '11111111-2222-3333-4444-555555555555'
        $state.Scopes    | Should -Contain 'Policy.Read.All'

        # The projection is a positive allowlist: the reported object carries
        # exactly these fields and nothing else — so the real secret-bearing
        # context fields (ClientSecret/Certificate/CertificateThumbprint) are
        # structurally excluded, and no plaintext secret marker survives.
        $expected = @('Service', 'Connected', 'Account', 'TenantId', 'Scopes', 'AuthType', 'ContextScope', 'Method', 'Environment')
        $state.PSObject.Properties.Name | Should -Be $expected
        foreach ($secret in 'ClientSecret', 'Certificate', 'CertificateThumbprint') {
            $state.PSObject.Properties.Name | Should -Not -Contain $secret
        }
        ($state | Out-String) | Should -Not -Match 'DO-NOT-LEAK'
    }

    It 'fails loud when sign-in yields no context (NFR-6)' {
        $connector = { param($ConnectParams) }   # "succeeds" but establishes nothing
        $reader    = { $null }

        { Connect-M365Graph -Connector $connector -ContextReader $reader } |
            Should -Throw -ExpectedMessage '*no authentication context*'
    }

    It 'drives the REAL default connector with -ContextScope Process, never CurrentUser' {
        # Exercise the built-in connector (not a fake) to prove the enforced
        # security flags on the actual Connect-MgGraph call. Mocked in module scope
        # so nothing reaches Microsoft.
        Mock -ModuleName M365Configurator Connect-MgGraph { }

        $null = Connect-M365Graph -Scopes 'Policy.Read.All' -ContextReader { $script:fakeContext }

        Should -Invoke -ModuleName M365Configurator Connect-MgGraph -Times 1 -Exactly -ParameterFilter {
            $ContextScope -eq 'Process' -and $UseDeviceCode -eq $true
        }
        Should -Invoke -ModuleName M365Configurator Connect-MgGraph -Times 0 -Exactly -ParameterFilter {
            $ContextScope -eq 'CurrentUser'
        }
    }
}

Describe 'Disconnect-M365Graph' {

    It 'is a no-op when there is no active context (idempotent)' {
        $disconnectCalled = $false
        $disconnector = { $script:disconnectCalled = $true }
        $reader       = { $null }

        $result = Disconnect-M365Graph -Disconnector $disconnector -ContextReader $reader

        $script:disconnectCalled | Should -BeFalse
        $result.WasConnected     | Should -BeFalse
        $result.Connected        | Should -BeFalse
    }

    It 'tears down an active session and verifies the context is cleared' {
        # Reader returns a context first (connected), then $null (after disconnect).
        $script:calls = 0
        $reader = {
            $script:calls++
            if ($script:calls -eq 1) { $script:fakeContext } else { $null }
        }
        $disconnected = $false
        $disconnector = { $script:disconnected = $true }

        $result = Disconnect-M365Graph -Disconnector $disconnector -ContextReader $reader

        $script:disconnected | Should -BeTrue
        $result.WasConnected | Should -BeTrue
        $result.Connected    | Should -BeFalse
        $result.Account      | Should -Be 'admin@contoso.onmicrosoft.com'
    }

    It 'fails loud if a context survives the teardown (NFR-6)' {
        $reader       = { $script:fakeContext }   # never clears
        $disconnector = { }                        # pretends to disconnect

        { Disconnect-M365Graph -Disconnector $disconnector -ContextReader $reader } |
            Should -Throw -ExpectedMessage '*still present*'
    }
}

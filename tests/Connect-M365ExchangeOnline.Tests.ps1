#requires -Version 7.0
<#
    Tests for Connect-M365ExchangeOnline / Disconnect-M365ExchangeOnline — the
    Exchange Online half of the connection foundation (MCA-11; FR-2, NFR-1;
    ADR-0001), consistent with the Graph auth model.

    Design source: research 04 §3/§4.2. EXO V3 is REST-based with in-memory MSAL
    tokens. Device code is the container default (-Device); the banner is
    suppressed; the deprecated remote-PowerShell mode (-UseRPSSession) and the
    plaintext-on-Linux credential paths (-Credential / -InlineCredential) are
    never used. Get-ConnectionInformation (not Get-PSSession) enumerates active
    REST connections; Disconnect-ExchangeOnline -Confirm:$false tears them down.
    Security & Compliance (Connect-IPPSSession) is out of scope on Linux.

    Side effects (connect, disconnect, connection-read) are injected seams; a
    dedicated test drives the real default connector (Connect-ExchangeOnline
    mocked in module scope) to prove the enforced flags on the actual call path.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force

    # A stand-in shaped like the real Get-ConnectionInformation output
    # (Microsoft.Exchange.Management.ExoPowershellSnapin.ConnectionInformation).
    # AppId / TenantID / ConnectionUri are genuine fields on that object that we
    # deliberately DON'T surface — they must not leak into the reported state.
    $script:fakeConn = [pscustomobject]@{
        ConnectionId      = 'abc-123'
        State             = 'Connected'
        UserPrincipalName = 'admin@contoso.onmicrosoft.com'
        Organization      = 'contoso.onmicrosoft.com'
        ConnectionUri     = 'https://outlook.office365.com'
        AppId             = 'app-id-DO-NOT-LEAK'
        TenantID          = 'tenant-id-DO-NOT-LEAK'
        TokenStatus       = 'Active-DO-NOT-LEAK'
    }
}

Describe 'Connect-M365ExchangeOnline' {

    BeforeEach { $script:captured = $null }

    It 'defaults to device-code flow with the banner suppressed (container-friendly)' {
        $connector = { param($ConnectParams) $script:captured = $ConnectParams }
        $reader    = { $script:fakeConn }

        $null = Connect-M365ExchangeOnline -Organization 'contoso.onmicrosoft.com' `
            -Connector $connector -ConnectionReader $reader

        $script:captured.Device      | Should -BeTrue
        $script:captured.ShowBanner  | Should -BeFalse
    }

    It 'never uses deprecated remote PowerShell or plaintext credential paths (NFR-1)' {
        $connector = { param($ConnectParams) $script:captured = $ConnectParams }
        $reader    = { $script:fakeConn }

        $null = Connect-M365ExchangeOnline -Connector $connector -ConnectionReader $reader

        $script:captured.Keys | Should -Not -Contain 'UseRPSSession'
        $script:captured.Keys | Should -Not -Contain 'Credential'
        $script:captured.Keys | Should -Not -Contain 'InlineCredential'
    }

    It 'omits the device switch when interactive browser flow is requested' {
        $connector = { param($ConnectParams) $script:captured = $ConnectParams }
        $reader    = { $script:fakeConn }

        $null = Connect-M365ExchangeOnline -Method Interactive -Connector $connector -ConnectionReader $reader

        $script:captured.Keys | Should -Not -Contain 'Device'
    }

    It 'passes organization, UPN, and the ephemeral module base path through' {
        $connector = { param($ConnectParams) $script:captured = $ConnectParams }
        $reader    = { $script:fakeConn }

        $null = Connect-M365ExchangeOnline -Organization 'contoso.onmicrosoft.com' `
            -UserPrincipalName 'admin@contoso.onmicrosoft.com' -ModuleBasePath '/run/exo' `
            -Connector $connector -ConnectionReader $reader

        $script:captured.Organization      | Should -Be 'contoso.onmicrosoft.com'
        $script:captured.UserPrincipalName | Should -Be 'admin@contoso.onmicrosoft.com'
        $script:captured.EXOModuleBasePath | Should -Be '/run/exo'
    }

    It 'reports connection state as exactly a secret-free allowlist (NFR-1)' {
        $connector = { param($ConnectParams) }
        $reader    = { $script:fakeConn }

        $state = Connect-M365ExchangeOnline -Connector $connector -ConnectionReader $reader

        $state.Connected         | Should -BeTrue
        $state.UserPrincipalName | Should -Be 'admin@contoso.onmicrosoft.com'
        $state.Organization      | Should -Be 'contoso.onmicrosoft.com'

        # Positive allowlist: the reported object carries exactly these fields, so
        # the connection object's other fields (AppId/TenantID/ConnectionUri/…)
        # are structurally excluded and no marker value survives.
        $expected = @('Service', 'Connected', 'UserPrincipalName', 'Organization', 'State', 'ConnectionId', 'Method')
        $state.PSObject.Properties.Name | Should -Be $expected
        foreach ($field in 'AppId', 'TenantID', 'ConnectionUri', 'TokenStatus') {
            $state.PSObject.Properties.Name | Should -Not -Contain $field
        }
        ($state | Out-String) | Should -Not -Match 'DO-NOT-LEAK'
    }

    It 'fails loud when the connection is not established (NFR-6)' {
        $connector = { param($ConnectParams) }
        $reader    = { @() }   # no connection

        { Connect-M365ExchangeOnline -Connector $connector -ConnectionReader $reader } |
            Should -Throw -ExpectedMessage '*no active Exchange Online connection*'
    }

    It 'drives the REAL default connector with -Device and -ShowBanner:$false, never a plaintext credential' {
        Mock -ModuleName M365Configurator Connect-ExchangeOnline { }

        $null = Connect-M365ExchangeOnline -Organization 'contoso.onmicrosoft.com' `
            -ConnectionReader { $script:fakeConn }

        Should -Invoke -ModuleName M365Configurator Connect-ExchangeOnline -Times 1 -Exactly -ParameterFilter {
            $Device -eq $true -and $ShowBanner -eq $false
        }
        # The real NFR-1 hazards that STILL exist in EXO V3 are the plaintext-on-
        # Linux credential paths (-UseRPSSession was removed in the V3 line, so a
        # filter on it would be a tautology). Prove neither is ever passed.
        Should -Invoke -ModuleName M365Configurator Connect-ExchangeOnline -Times 0 -Exactly -ParameterFilter {
            $null -ne $Credential -or $InlineCredential -eq $true
        }
    }

    It 'reports the most-recent connection when several are active (multi-connection)' {
        $conns = @(
            [pscustomobject]@{ ConnectionId = 'old'; State = 'Connected'; UserPrincipalName = 'first@contoso'; Organization = 'contoso.onmicrosoft.com' }
            [pscustomobject]@{ ConnectionId = 'new'; State = 'Connected'; UserPrincipalName = 'admin@contoso'; Organization = 'contoso.onmicrosoft.com' }
        )
        $state = Connect-M365ExchangeOnline -Connector { param($p) } -ConnectionReader { $conns }

        $state.ConnectionId      | Should -Be 'new'
        $state.UserPrincipalName | Should -Be 'admin@contoso'
    }
}

Describe 'Disconnect-M365ExchangeOnline' {

    It 'is a no-op when there is no active connection (idempotent)' {
        $script:disconnectCalled = $false
        $disconnector = { $script:disconnectCalled = $true }
        $reader       = { @() }

        $result = Disconnect-M365ExchangeOnline -Disconnector $disconnector -ConnectionReader $reader

        $script:disconnectCalled | Should -BeFalse
        $result.WasConnected     | Should -BeFalse
        $result.Connected        | Should -BeFalse
    }

    It 'tears down an active connection and verifies it is cleared' {
        $script:calls = 0
        $reader = {
            $script:calls++
            if ($script:calls -eq 1) { $script:fakeConn } else { @() }
        }
        $script:disconnected = $false
        $disconnector = { $script:disconnected = $true }

        $result = Disconnect-M365ExchangeOnline -Disconnector $disconnector -ConnectionReader $reader

        $script:disconnected | Should -BeTrue
        $result.WasConnected | Should -BeTrue
        $result.Connected    | Should -BeFalse
    }

    It 'fails loud if a connection survives the teardown (NFR-6)' {
        $reader       = { $script:fakeConn }   # never clears
        $disconnector = { }

        { Disconnect-M365ExchangeOnline -Disconnector $disconnector -ConnectionReader $reader } |
            Should -Throw -ExpectedMessage '*still present*'
    }

    It 'tears down all connections when several are active (multi-connection)' {
        $script:calls = 0
        $reader = {
            $script:calls++
            if ($script:calls -eq 1) {
                @(
                    [pscustomobject]@{ ConnectionId = 'a' }
                    [pscustomobject]@{ ConnectionId = 'b' }
                )
            } else { @() }
        }
        $script:disconnected = $false
        $disconnector = { $script:disconnected = $true }

        $result = Disconnect-M365ExchangeOnline -Disconnector $disconnector -ConnectionReader $reader

        $script:disconnected | Should -BeTrue
        $result.WasConnected | Should -BeTrue
        $result.Connected    | Should -BeFalse
    }
}

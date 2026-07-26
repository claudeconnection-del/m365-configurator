#requires -Version 7.6
<#
    Tests for Connect-M365: a single call combining Connect-M365Graph +
    Connect-M365ExchangeOnline + New-M365Session into one "authenticate, get
    a ready session" entry point (owner feedback 2026-07-26: the three-call
    boilerplate to get from a fresh shell to a usable Session was real
    friction). Tenant-free: all three underlying calls are mocked
    module-scoped.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force
}

Describe 'Connect-M365' {

    BeforeEach {
        Mock Connect-M365Graph -ModuleName M365Configurator {
            [pscustomobject]@{ Service = 'MicrosoftGraph'; Connected = $true; Account = 'admin@contoso.com'; TenantId = 'contoso' }
        }
        Mock Connect-M365ExchangeOnline -ModuleName M365Configurator {
            [pscustomobject]@{ Service = 'ExchangeOnline'; Connected = $true; UserPrincipalName = 'admin@contoso.com'; Organization = 'contoso.onmicrosoft.com' }
        }
        Mock New-M365Session -ModuleName M365Configurator {
            [pscustomobject]@{ PSTypeName = 'M365Configurator.Session'; Graph = $Graph; Exo = $Exo; Capabilities = @('graph', 'exo') }
        }
    }

    It 'connects both Graph and Exchange Online by default, then builds the session' {
        $result = Connect-M365 -InformationAction Ignore

        Should -Invoke Connect-M365Graph -ModuleName M365Configurator -Times 1 -Exactly
        Should -Invoke Connect-M365ExchangeOnline -ModuleName M365Configurator -Times 1 -Exactly
        Should -Invoke New-M365Session -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Graph.Service -eq 'MicrosoftGraph' -and $Exo.Service -eq 'ExchangeOnline'
        }
        $result.PSObject.TypeNames | Should -Contain 'M365Configurator.Session'
        $result.Capabilities | Should -Contain 'graph'
        $result.Capabilities | Should -Contain 'exo'
    }

    It '-GraphOnly connects only Graph and passes a $null Exo through to New-M365Session' {
        $null = Connect-M365 -GraphOnly -InformationAction Ignore

        Should -Invoke Connect-M365Graph -ModuleName M365Configurator -Times 1 -Exactly
        Should -Invoke Connect-M365ExchangeOnline -ModuleName M365Configurator -Times 0 -Exactly
        Should -Invoke New-M365Session -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $null -eq $Exo
        }
    }

    It '-ExoOnly connects only Exchange Online and passes a $null Graph through to New-M365Session' {
        $null = Connect-M365 -ExoOnly -InformationAction Ignore

        Should -Invoke Connect-M365ExchangeOnline -ModuleName M365Configurator -Times 1 -Exactly
        Should -Invoke Connect-M365Graph -ModuleName M365Configurator -Times 0 -Exactly
        Should -Invoke New-M365Session -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $null -eq $Graph
        }
    }

    It 'throws when -GraphOnly and -ExoOnly are both supplied, before connecting anything' {
        { Connect-M365 -GraphOnly -ExoOnly -InformationAction Ignore } | Should -Throw '*mutually exclusive*'

        Should -Invoke Connect-M365Graph -ModuleName M365Configurator -Times 0 -Exactly
        Should -Invoke Connect-M365ExchangeOnline -ModuleName M365Configurator -Times 0 -Exactly
    }

    It 'forwards Graph-specific parameters (and the shared -Method) to Connect-M365Graph' {
        $null = Connect-M365 -Scopes @('Policy.Read.All') -TenantId 'contoso.onmicrosoft.com' -Method Interactive -InformationAction Ignore

        Should -Invoke Connect-M365Graph -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            ($Scopes -join ',') -eq 'Policy.Read.All' -and $TenantId -eq 'contoso.onmicrosoft.com' -and $Method -eq 'Interactive'
        }
    }

    It 'forwards EXO-specific parameters (and the shared -Method) to Connect-M365ExchangeOnline' {
        $null = Connect-M365 -Organization 'contoso.onmicrosoft.com' -UserPrincipalName 'admin@contoso.com' -ModuleBasePath '/tmp/exo' -Method Interactive -InformationAction Ignore

        Should -Invoke Connect-M365ExchangeOnline -ModuleName M365Configurator -Times 1 -Exactly -ParameterFilter {
            $Organization -eq 'contoso.onmicrosoft.com' -and $UserPrincipalName -eq 'admin@contoso.com' -and $ModuleBasePath -eq '/tmp/exo' -and $Method -eq 'Interactive'
        }
    }

    It 'prints a clear, non-verbose summary of what connected (observability -- no more silent "did it work?")' {
        $null = Connect-M365 -InformationVariable infoRecords -InformationAction SilentlyContinue

        $joined = ($infoRecords | ForEach-Object { "$_" }) -join "`n"
        $joined | Should -Match 'Microsoft Graph'
        $joined | Should -Match 'Exchange Online'
    }
}

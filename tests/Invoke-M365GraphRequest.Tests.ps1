#requires -Version 7.6
<#
    Tests for Invoke-M365GraphRequest — the module's single Microsoft Graph call
    seam over Invoke-MgGraphRequest (ADR-0014). The SDK cmdlet is the mocked
    boundary; no tenant is contacted.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force
}

Describe 'Invoke-M365GraphRequest' {

    It 'forwards method + uri to Invoke-MgGraphRequest and returns its response' {
        InModuleScope M365Configurator {
            Mock Invoke-MgGraphRequest { @{ isEnabled = $true } }

            $result = Invoke-M365GraphRequest -Method GET -Uri 'v1.0/policies/x'

            Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'GET' -and $Uri -eq 'v1.0/policies/x'
            }
            $result['isEnabled'] | Should -BeTrue
        }
    }

    It 'forwards the request body on a write' {
        InModuleScope M365Configurator {
            Mock Invoke-MgGraphRequest { }

            Invoke-M365GraphRequest -Method PATCH -Uri 'v1.0/policies/x' -Body @{ isEnabled = $false }

            Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Body.isEnabled -eq $false
            }
        }
    }

    It 'omits Body entirely when none is supplied (clean GET)' {
        InModuleScope M365Configurator {
            Mock Invoke-MgGraphRequest { }

            Invoke-M365GraphRequest -Method GET -Uri 'v1.0/policies/x'

            Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter {
                -not $PSBoundParameters.ContainsKey('Body')
            }
        }
    }

    It 'rejects an unsupported HTTP method (loud, fast — NFR-6)' {
        InModuleScope M365Configurator {
            { Invoke-M365GraphRequest -Method FETCH -Uri 'v1.0/x' } | Should -Throw
        }
    }
}

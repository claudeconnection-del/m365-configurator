@{
    RootModule        = 'M365Configurator.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '7683d159-d912-4758-bd60-dad5ac074357'
    Author            = 'm365-configurator contributors'
    Description       = 'Portable, profile-driven configurator for Microsoft 365 (Graph + Exchange Online).'
    PowerShellVersion = '7.0'

    # Exported functions are declared explicitly per public file; the root module
    # also calls Export-ModuleMember. Keep this list in sync as public functions land.
    FunctionsToExport = @('Get-M365RequiredModule', 'Get-M365ModuleStatus', 'Get-M365ModuleRemediation', 'Initialize-M365Module')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            ProjectUri = 'https://github.com/claudeconnection-del/m365-configurator'
            LicenseUri = 'https://www.apache.org/licenses/LICENSE-2.0'
        }
    }
}

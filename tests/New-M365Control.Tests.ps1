#requires -Version 7.0
<#
    Tests for New-M365Control — the constructor/validator for a control handler,
    the unit of provider knowledge for exactly one control (ADR-0013; MCA-6).

    A handler is a plain object with a fixed shape (Id, Provider, Shape, Title,
    RequiredCapabilities, DependsOn, Get, Compare, Set). This constructor is the
    single place the contract shape is defined and validated, so a malformed
    handler fails loud at construction (NFR-6) rather than deep inside the engine.

    Pure and tenant-free: Get/Set/Compare are scriptblock seams, never invoked here.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force
}

Describe 'New-M365Control' {

    It 'builds a handler carrying every contract field' {
        $get = { param($Session) @{} }
        $set = { param($Session, $Desired, $Current) $null }

        $control = New-M365Control -Id 'ID-2' -Provider 'graph' -Shape 'collection' `
            -Title 'Block legacy authentication' -Get $get -Set $set

        $control.Id       | Should -Be 'ID-2'
        $control.Provider | Should -Be 'graph'
        $control.Shape    | Should -Be 'collection'
        $control.Title    | Should -Be 'Block legacy authentication'
        $control.Get      | Should -Be $get
        $control.Set      | Should -Be $set
    }

    It 'tags the object with the control type name for the engine to recognise' {
        $control = New-M365Control -Id 'ID-1' -Provider 'graph' -Shape 'singleton' `
            -Title 'Security defaults' -Get { param($Session) } -Set { param($Session, $Desired, $Current) }

        $control.PSObject.TypeNames | Should -Contain 'M365Configurator.Control'
    }

    It 'defaults RequiredCapabilities and DependsOn to empty arrays, and Compare to null' {
        $control = New-M365Control -Id 'CON-1' -Provider 'graph' -Shape 'singleton' `
            -Title 'Restrict user consent' -Get { param($Session) } -Set { param($Session, $Desired, $Current) }

        , $control.RequiredCapabilities | Should -BeOfType [array]
        $control.RequiredCapabilities.Count | Should -Be 0
        , $control.DependsOn | Should -BeOfType [array]
        $control.DependsOn.Count | Should -Be 0
        $control.Compare | Should -BeNullOrEmpty
    }

    It 'carries a custom Compare and declared capabilities/dependencies when provided' {
        $compare = { param($Desired, $Current) @{ Action = 'NoChange' } }

        $control = New-M365Control -Id 'ID-2' -Provider 'graph' -Shape 'collection' `
            -Title 'Block legacy auth' -Get { param($Session) } -Set { param($Session, $Desired, $Current) } `
            -Compare $compare -RequiredCapabilities @('EntraIdP2') -DependsOn @('ID-1')

        $control.Compare              | Should -Be $compare
        $control.RequiredCapabilities | Should -Be @('EntraIdP2')
        $control.DependsOn            | Should -Be @('ID-1')
    }

    It 'rejects an unknown provider (loud, fast — NFR-6)' {
        { New-M365Control -Id 'X' -Provider 'sharepoint' -Shape 'singleton' -Title 'X' `
            -Get { param($Session) } -Set { param($Session, $Desired, $Current) } } | Should -Throw
    }

    It 'rejects an unknown shape' {
        { New-M365Control -Id 'X' -Provider 'graph' -Shape 'magic' -Title 'X' `
            -Get { param($Session) } -Set { param($Session, $Desired, $Current) } } | Should -Throw
    }

    It 'rejects an empty id and an empty title' {
        { New-M365Control -Id '' -Provider 'graph' -Shape 'singleton' -Title 'X' `
            -Get { param($Session) } -Set { param($Session, $Desired, $Current) } } | Should -Throw
        { New-M365Control -Id 'X' -Provider 'graph' -Shape 'singleton' -Title '' `
            -Get { param($Session) } -Set { param($Session, $Desired, $Current) } } | Should -Throw
    }

    It 'requires Get and Set to be provided' {
        { New-M365Control -Id 'X' -Provider 'graph' -Shape 'singleton' -Title 'X' `
            -Set { param($Session, $Desired, $Current) } } | Should -Throw
        { New-M365Control -Id 'X' -Provider 'graph' -Shape 'singleton' -Title 'X' `
            -Get { param($Session) } } | Should -Throw
    }
}

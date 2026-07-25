#requires -Version 7.0

function New-M365Control {
    <#
    .SYNOPSIS
        Constructs and validates a control handler — the unit of provider
        knowledge for exactly one control (ADR-0013).

    .DESCRIPTION
        A control handler is a plain object with a fixed shape that the change
        engine (MCA-6) drives uniformly, so the engine stays provider-agnostic
        and each control is testable in isolation. This constructor is the single
        place the contract is defined and validated: a malformed handler fails
        loud here (NFR-6), not deep inside a dry-run or apply.

        The contract:

          Id                   framework/local control id (e.g. 'MS.AAD.1.1', 'ID-2')
          Provider             'graph' | 'exo'
          Shape                'singleton' | 'collection' | 'policy-rule' | 'preset'
          Title                human label for readable plan/drift output (NFR-9)
          RequiredCapabilities license/platform gates surfaced in dry-run (MCA-21)
          DependsOn            control ids that must be planned/applied first
          Get      { param($Session) }                   -> current settings (secret-free)
          Compare  { param($Desired, $Current) }         -> { Action; Changes } (optional;
                                                             engine falls back to canonical diff)
          Set      { param($Session, $Desired, $Current) } -> per-item apply result

        Get/Set/Compare are scriptblock seams: the engine injects the connected
        session, and tests exercise the handler with no tenant.

    .OUTPUTS
        pscustomobject (PSTypeName 'M365Configurator.Control').
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Id,
        [Parameter(Mandatory)] [ValidateSet('graph', 'exo')] [string] $Provider,
        [Parameter(Mandatory)] [ValidateSet('singleton', 'collection', 'policy-rule', 'preset')] [string] $Shape,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Title,
        [Parameter(Mandatory)] [scriptblock] $Get,
        [Parameter(Mandatory)] [scriptblock] $Set,
        [scriptblock] $Compare,
        [string[]] $RequiredCapabilities = @(),
        [string[]] $DependsOn = @()
    )

    [pscustomobject]@{
        PSTypeName           = 'M365Configurator.Control'
        Id                   = $Id
        Provider             = $Provider
        Shape                = $Shape
        Title                = $Title
        RequiredCapabilities = @($RequiredCapabilities)
        DependsOn            = @($DependsOn)
        Get                  = $Get
        Compare              = $Compare
        Set                  = $Set
    }
}

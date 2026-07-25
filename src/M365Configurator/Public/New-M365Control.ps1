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
        session, and tests exercise the handler with no tenant. Because the
        engine invokes them positionally, each seam must declare exactly the
        param() signature above — enforced here at construction.

    .OUTPUTS
        pscustomobject (PSTypeName 'M365Configurator.Control').
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [ValidatePattern('\S')] [string] $Id,
        [Parameter(Mandatory)] [ValidateSet('graph', 'exo')] [string] $Provider,
        [Parameter(Mandatory)] [ValidateSet('singleton', 'collection', 'policy-rule', 'preset')] [string] $Shape,
        [Parameter(Mandatory)] [ValidatePattern('\S')] [string] $Title,
        [Parameter(Mandatory)] [scriptblock] $Get,
        [Parameter(Mandatory)] [scriptblock] $Set,
        [scriptblock] $Compare,
        [string[]] $RequiredCapabilities = @(),
        [string[]] $DependsOn = @()
    )

    # The engine invokes the seams positionally, so a scriptblock that does not
    # declare the contract's param() seam would mis-bind silently ($Session
    # lands in $args) and only surface deep inside a dry-run or apply. Reject
    # it here instead (NFR-6).
    $seams = @(
        @{ Name = 'Get'; Block = $Get; Params = @('Session') }
        @{ Name = 'Set'; Block = $Set; Params = @('Session', 'Desired', 'Current') }
    )
    if ($Compare) {
        $seams += @{ Name = 'Compare'; Block = $Compare; Params = @('Desired', 'Current') }
    }
    foreach ($seam in $seams) {
        $paramBlock = $seam.Block.Ast.ParamBlock
        $declared = @()
        if ($null -ne $paramBlock) {
            $declared = @($paramBlock.Parameters.Name.VariablePath.UserPath)
        }
        $expected = @($seam.Params)
        $matching = ($declared.Count -eq $expected.Count)
        for ($i = 0; $matching -and $i -lt $expected.Count; $i++) {
            $matching = ($declared[$i] -eq $expected[$i])
        }
        if (-not $matching) {
            $signature = 'param(${0})' -f ($expected -join ', $')
            throw ("Control '{0}': the {1} seam must declare {2} (ADR-0013); got param({3})." -f `
                    $Id, $seam.Name, $signature, (@($declared | ForEach-Object { "`$$_" }) -join ', '))
        }
    }

    [pscustomobject]@{
        PSTypeName           = 'M365Configurator.Control'
        Id                   = $Id
        Provider             = $Provider
        Shape                = $Shape
        Title                = $Title
        RequiredCapabilities = @($RequiredCapabilities | Where-Object { $null -ne $_ })
        DependsOn            = @($DependsOn | Where-Object { $null -ne $_ })
        Get                  = $Get
        Compare              = $Compare
        Set                  = $Set
    }
}

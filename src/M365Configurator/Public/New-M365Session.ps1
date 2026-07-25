#requires -Version 7.6

function New-M365Session {
    <#
    .SYNOPSIS
        Aggregates the connect-state objects into the session the change
        engine gates controls on (MCA-21; D8) — the piece that makes
        Session.Capabilities real.

    .DESCRIPTION
        Connection-presence and license-derived capability strings, so
        Get-M365Plan's existing capability gate (MCA-17) actually blocks a
        control whose prerequisite (a connection, a license tier, a Defender
        plan) isn't met, instead of the gate having nothing to check against.

        Capability vocabulary (lowercase, canonical): `graph`, `exo` (present
        when the respective connect-state object's Connected field is true —
        Connect-M365Graph / Connect-M365ExchangeOnline's secret-free output),
        `entra-id-p1`, `entra-id-p2`, `defender-office365` (license-derived,
        only ever probed when `graph` is present — there is no other way to
        read `/subscribedSkus`). GCC/national-cloud `*_GOV` service plan
        variants are out of v1 scope and deliberately not matched.

        The license probe is an injected scriptblock seam (default: a raw
        Graph read via the ADR-0014 seam), so this is unit-testable with a
        fake SKU response and no tenant.

    .OUTPUTS
        pscustomobject (PSTypeName 'M365Configurator.Session'): Graph, Exo
        (verbatim passthrough of what was supplied), Capabilities
        (sorted, unique string[]).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # Output of Connect-M365Graph, or $null if not connected.
        $Graph,

        # Output of Connect-M365ExchangeOnline, or $null if not connected.
        $Exo,

        # Seam: reads the tenant's licensed SKUs. Default hits Graph directly
        # — only invoked when the graph capability is present.
        [scriptblock] $LicenseReader = {
            Invoke-M365GraphRequest -Method GET -Uri 'v1.0/subscribedSkus'
        }
    )

    $caps = [System.Collections.Generic.List[string]]::new()
    if ($Graph -and (Get-M365MapValue $Graph 'Connected')) { $caps.Add('graph') }
    if ($Exo -and (Get-M365MapValue $Exo 'Connected')) { $caps.Add('exo') }

    if ($caps.Contains('graph')) {
        $skus = & $LicenseReader
        $plans = @(
            foreach ($sku in @(Get-M365MapValue $skus 'value')) {
                foreach ($plan in @(Get-M365MapValue $sku 'servicePlans')) {
                    Get-M365MapValue $plan 'servicePlanName'
                }
            }
        )
        if ($plans -contains 'AAD_PREMIUM')    { $caps.Add('entra-id-p1') }
        if ($plans -contains 'AAD_PREMIUM_P2') { $caps.Add('entra-id-p2') }
        if (@('THREAT_INTELLIGENCE', 'ATP_ENTERPRISE') | Where-Object { $plans -contains $_ }) {
            $caps.Add('defender-office365')
        }
    }

    [pscustomobject]@{
        PSTypeName   = 'M365Configurator.Session'
        Graph        = $Graph
        Exo          = $Exo
        Capabilities = @($caps | Sort-Object -Unique)
    }
}

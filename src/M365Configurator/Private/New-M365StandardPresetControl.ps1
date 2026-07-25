#requires -Version 7.6

function New-M365StandardPresetControl {
    <#
    .SYNOPSIS
        Builds the MDO-1 (Standard preset security policy) control handler —
        the flagship EXO control on the ADR-0013 contract (MCA-30; SCuBA
        MS.DEFENDER.1.1-1.5).

    .DESCRIPTION
        One rule toggle delivers Microsoft-maintained anti-spam, anti-malware,
        anti-phishing, Safe Links, and Safe Attachments settings — the
        highest-value, lowest-effort EXO control in the v1 slice.

        Modeled as a **rule-state + coverage check**, not a field-by-field
        settings diff (D2/research 05 R6): preset settings are Microsoft-owned
        and not meaningfully diffable, so this control's entire vocabulary is
        the EOP and ATP rule states.

        Mechanism (verified against Microsoft Learn, exchangepowershell,
        2026-07-25): `Get-EOPProtectionPolicyRule` / `Get-ATPProtectionPolicyRule`
        `-Identity 'Standard Preset Security Policy'` each report `State`
        (`Enabled`|`Disabled`); `Enable-`/`Disable-EOPProtectionPolicyRule` and
        the ATP equivalents flip it. Issued through the EXO seam
        (Invoke-M365ExoCommand, D5).

        **The rules do not exist until the preset has been turned on once in
        the Defender portal** — Microsoft documents the portal as the ONLY
        supported way to create them (`New-*ProtectionPolicyRule` exists but
        is explicitly not recommended, and needs policy names embedding an
        unpredictable timestamp). `Get` maps that absence to state
        `NotPresent` by catching ONLY the well-known "object ... couldn't be
        found" failure and rethrowing anything else (NFR-6 — no silent
        catches): a permissions error or a real outage must never be
        misreported as "the preset was never touched".

        `Set` refuses to programmatically initialise an absent preset: this
        control is deliberately **NOT self-healing** (ADR-0011) — its
        consented-fix offer IS the portal instruction in the thrown message,
        because there is no supported programmatic fix.

        RequiredCapabilities: `exo` (the connection) AND `defender-office365`
        (the ATP rule and its cmdlets need Defender for Office 365 — an
        EOP-only tenant is out of v1 scope for this control; MCA-21 supplies
        both). No DependsOn.

        Internal helper; assembled into the provider set by
        Get-M365ControlRegistry.

    .OUTPUTS
        pscustomobject (PSTypeName 'M365Configurator.Control').
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    New-M365Control -Id 'MDO-1' -Provider 'exo' -Shape 'preset' `
        -Title 'Standard preset security policy' `
        -RequiredCapabilities @('exo', 'defender-office365') `
        -Get {
            param($Session)
            $ruleName = 'Standard Preset Security Policy'

            # Not-found detection matches Exchange's well-known
            # ManagementObjectNotFoundException phrasing case-insensitively;
            # anything else (permissions, outage) rethrows rather than being
            # silently folded into "absent" (NFR-6).
            try {
                $eopRule  = Invoke-M365ExoCommand -Name 'Get-EOPProtectionPolicyRule' -Parameters @{ Identity = $ruleName }
                $eopState = [string] (Get-M365MapValue $eopRule 'State')
            }
            catch {
                if ($_.Exception.Message -match "couldn.t be found|not found") { $eopState = 'NotPresent' } else { throw }
            }

            try {
                $atpRule  = Invoke-M365ExoCommand -Name 'Get-ATPProtectionPolicyRule' -Parameters @{ Identity = $ruleName }
                $atpState = [string] (Get-M365MapValue $atpRule 'State')
            }
            catch {
                if ($_.Exception.Message -match "couldn.t be found|not found") { $atpState = 'NotPresent' } else { throw }
            }

            @{ eopRuleState = $eopState; atpRuleState = $atpState }
        } `
        -Set {
            param($Session, $Desired, $Current)
            $ruleName = 'Standard Preset Security Policy'
            $commandFor = @{
                eopRuleState = @{ Enabled = 'Enable-EOPProtectionPolicyRule'; Disabled = 'Disable-EOPProtectionPolicyRule' }
                atpRuleState = @{ Enabled = 'Enable-ATPProtectionPolicyRule'; Disabled = 'Disable-ATPProtectionPolicyRule' }
            }

            $changed = [System.Collections.Generic.List[string]]::new()
            foreach ($key in @('eopRuleState', 'atpRuleState')) {
                if (-not (Test-M365MapHasKey $Desired $key)) { continue }
                $want = Get-M365MapValue $Desired $key
                $have = Get-M365MapValue $Current $key
                if ($want -eq $have) { continue }

                if ($want -eq 'Enabled' -and $have -eq 'NotPresent') {
                    throw "MDO-1: the Standard preset has never been initialised on this tenant — enable it once in the Defender portal (Policies & rules -> Threat policies -> Preset security policies); creating it programmatically requires authoring the full policy set, which is out of v1 scope."
                }

                Invoke-M365ExoCommand -Name $commandFor[$key][$want] -Parameters @{ Identity = $ruleName }
                $changed.Add($key)
            }

            @{ Id = 'MDO-1'; Outcome = 'Applied'; Rules = @($changed.ToArray()) }
        }
}

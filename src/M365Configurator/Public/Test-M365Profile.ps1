#requires -Version 7.0

function Test-M365Profile {
    <#
    .SYNOPSIS
        Validates a profile object against schema v1, returning a structured
        result (does not throw).

    .DESCRIPTION
        The schema gate for the profile engine (MCA-13; FR-5, NFR-1). Schema v1:

          Top level: schemaVersion ('1.0'), name, framework, frameworkVersion,
          controls (array).

          Each control: id (framework control ID, e.g. MS.AAD.1.1), framework,
          frameworkVersion (pinned), provider ('graph' | 'exo'), settings (map).
          name is optional (used by name-scoped controls).

          Config-only: NO credential-shaped field may appear anywhere — that guard
          (Find-M365SecretKey) is what lets import safely accept shared files.

        Pure and non-mutating: returns { Valid; Errors } so callers decide how loud
        to be (import/apply throw on Valid=$false; NFR-6). Accepts profiles as
        ordered dictionaries (parsed YAML) or pscustomobjects (built in code).

    .OUTPUTS
        pscustomobject: Valid ([bool]), Errors ([string[]]).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # -Profile alias kept for readability at call sites; the variable is named
        # $InputObject to avoid shadowing the automatic $PROFILE variable.
        [Parameter(Mandatory, Position = 0)]
        [Alias('Profile')]
        [AllowNull()]
        $InputObject
    )

    $errors = [System.Collections.Generic.List[string]]::new()

    if ($null -eq $InputObject) {
        return [pscustomobject]@{ Valid = $false; Errors = @('profile is null') }
    }

    # --- top-level required fields -------------------------------------------
    foreach ($field in 'schemaVersion', 'name', 'framework', 'frameworkVersion', 'controls') {
        if (-not (Test-M365MapHasKey $InputObject $field)) {
            $errors.Add("missing required field '$field'")
            continue
        }
        # string fields must be non-empty; 'controls' may be an (empty) array.
        if ($field -ne 'controls') {
            $value = Get-M365MapValue $InputObject $field
            if ($null -eq $value -or ('' -eq [string] $value)) {
                $errors.Add("required field '$field' is empty")
            }
        }
    }

    $schemaVersion = Get-M365MapValue $InputObject 'schemaVersion'
    if ($schemaVersion -and [string] $schemaVersion -ne '1.0') {
        $errors.Add("unsupported schemaVersion '$schemaVersion' (expected '1.0')")
    }

    # --- controls -------------------------------------------------------------
    $controls = Get-M365MapValue $InputObject 'controls'
    if ($controls -and (Test-M365MapHasKey $InputObject 'controls')) {
        $index = 0
        foreach ($control in @($controls)) {
            foreach ($field in 'id', 'framework', 'frameworkVersion', 'provider', 'settings') {
                if (-not (Test-M365MapHasKey $control $field)) {
                    $errors.Add("control[$index] missing required field '$field'")
                    continue
                }
                # The string-valued fields must also be non-empty; a present-but-
                # null/empty id or provider is as invalid as an absent one.
                if ($field -ne 'settings') {
                    $value = Get-M365MapValue $control $field
                    if ($null -eq $value -or ('' -eq [string] $value)) {
                        $errors.Add("control[$index] required field '$field' is empty")
                    }
                }
            }
            $provider = Get-M365MapValue $control 'provider'
            if ($provider -and [string] $provider -notin 'graph', 'exo') {
                $errors.Add("control[$index] has unknown provider '$provider' (expected 'graph' or 'exo')")
            }
            $index++
        }
    }

    # --- config-only: no credential-shaped fields anywhere (NFR-1) -----------
    foreach ($hit in @(Find-M365SecretKey -InputObject $InputObject)) {
        $errors.Add("credential-shaped field not allowed (profiles are config-only): '$hit'")
    }

    [pscustomobject]@{
        Valid  = ($errors.Count -eq 0)
        Errors = @($errors)
    }
}

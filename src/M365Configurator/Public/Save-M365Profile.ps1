#requires -Version 7.0

function Save-M365Profile {
    <#
    .SYNOPSIS
        Persists the current in-scope tenant configuration as a named, versioned,
        config-only profile (YAML authored, canonical form).

    .DESCRIPTION
        The save half of the profile engine (MCA-14; FR-5; ADR-0008/0009). It:

          1. Reads the in-scope controls' current state from the connected tenant
             via the injected -ControlReader. Each returned control descriptor
             carries id, provider ('graph'|'exo'), settings, and optionally name;
             Save stamps the pinned framework + frameworkVersion onto every one
             (single pinned version per profile — NFR-7).
          2. Assembles a schema-v1 profile document.
          3. Validates it (Test-M365Profile) and REFUSES to write if it is invalid
             or carries any credential-shaped field — a secret read back from a
             tenant must never be persisted (NFR-1). Nothing is written on failure.
          4. Serializes to canonical YAML (byte-stable, so re-saving unchanged
             state is a clean diff — NFR-9) and writes it via the injected -Writer.

        The tenant read and the file write are injected seams: the real Graph/EXO
        providers (MCA-4/5) plug into -ControlReader later; -Writer defaults to a
        UTF-8, no-trailing-newline file write.

    .OUTPUTS
        pscustomobject: Name, Path, Profile, Canonical. No secrets.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Framework,
        [Parameter(Mandatory)] [string] $FrameworkVersion,

        # Returns the in-scope controls' current tenant state (id/provider/settings,
        # optional name). Injected so this is testable without a live tenant.
        [Parameter(Mandatory)] [scriptblock] $ControlReader,

        # Directory profiles are written under (ADR-0009 ships the reference
        # baseline in-repo under profiles/).
        [string] $ProfileDirectory = 'profiles',

        # Explicit output path; overrides the name-derived default when supplied.
        [string] $Path,

        # Writes the profile file. Default: UTF-8, no trailing newline (byte-stable).
        [scriptblock] $Writer = {
            param([string] $FilePath, [string] $Content)
            Set-Content -LiteralPath $FilePath -Value $Content -NoNewline -Encoding utf8
        }
    )

    # 1) Read tenant state and 2) assemble the schema-v1 document. The pinned
    #    framework version is stamped onto every control from the parameters.
    $controls = foreach ($raw in @(& $ControlReader)) {
        $control = [ordered]@{
            id               = Get-M365MapValue $raw 'id'
            framework        = $Framework
            frameworkVersion = $FrameworkVersion
            provider         = Get-M365MapValue $raw 'provider'
        }
        # Note: not $name — PowerShell variables are case-insensitive, so a $name
        # here would clobber the $Name parameter.
        $controlName = Get-M365MapValue $raw 'name'
        if ($null -ne $controlName -and '' -ne [string] $controlName) { $control['name'] = $controlName }
        $control['settings'] = Get-M365MapValue $raw 'settings'
        $control
    }

    $profile = [ordered]@{
        schemaVersion    = '1.0'
        name             = $Name
        framework        = $Framework
        frameworkVersion = $FrameworkVersion
        controls         = @($controls)
    }

    # 3) Validate before writing. An invalid or credential-bearing profile must
    #    fail loud and write nothing (NFR-1/NFR-6).
    $validation = Test-M365Profile -Profile $profile
    if (-not $validation.Valid) {
        throw "Refusing to save profile '$Name': it is not a valid schema-v1 profile. $($validation.Errors -join '; ')."
    }

    # 4) Serialize (canonical → byte-stable) and write.
    $yaml = ConvertTo-M365ProfileYaml $profile
    $resolvedPath = if ($Path) { $Path } else { Join-Path $ProfileDirectory "$Name.yaml" }

    Write-Verbose "Saving profile '$Name' ($(@($controls).Count) control(s), $Framework $FrameworkVersion) to '$resolvedPath'."
    & $Writer $resolvedPath $yaml

    [pscustomobject]@{
        Name      = $Name
        Path      = $resolvedPath
        Profile   = $profile
        Canonical = ConvertTo-M365CanonicalJson $profile
    }
}

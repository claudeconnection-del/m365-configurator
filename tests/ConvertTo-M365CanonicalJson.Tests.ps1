#requires -Version 7.0
<#
    Tests for the profile canonicalization core (MCA-13; FR-5, NFR-9; ADR-0008).
    Profiles are authored/shared in YAML but canonicalized to JSON internally —
    stable key ordering, sorted arrays — so drift/dry-run diffs are deterministic
    and a re-save of unchanged state is byte-stable.

    ConvertTo-M365CanonicalJson is the one canonical form. ConvertTo/-From
    -M365ProfileYaml wrap the pinned powershell-yaml parser for the authoring
    surface; the key property tested here is a LOSSLESS YAML <-> canonical-JSON
    round-trip (ADR-0008), verified via the canonical form so it is independent of
    the serializer's own key ordering.
#>

BeforeAll {
    $manifest = Join-Path $PSScriptRoot '..' 'src' 'M365Configurator' 'M365Configurator.psd1'
    Import-Module $manifest -Force

    $script:sampleProfile = [ordered]@{
        schemaVersion    = '1.0'
        name             = 'security-baseline'
        framework        = 'SCuBA'
        frameworkVersion = '1.5.0'
        controls         = @(
            [ordered]@{ id = 'MS.AAD.1.1'; framework = 'SCuBA'; frameworkVersion = '1.5.0'; provider = 'graph'; name = 'Block legacy auth'; settings = [ordered]@{ state = 'enabled' } }
            [ordered]@{ id = 'MS.EXO.4.1'; framework = 'SCuBA'; frameworkVersion = '1.5.0'; provider = 'exo';   settings = [ordered]@{ enabled = $true } }
        )
    }
}

Describe 'ConvertTo-M365CanonicalJson' {

    It 'orders object keys deterministically regardless of input order' {
        $a = [ordered]@{ zebra = 1; alpha = 2; mike = 3 }
        $b = [ordered]@{ mike = 3; zebra = 1; alpha = 2 }

        (ConvertTo-M365CanonicalJson $a) | Should -Be (ConvertTo-M365CanonicalJson $b)
        # Keys appear in sorted order in the output.
        $json = ConvertTo-M365CanonicalJson $a
        $json.IndexOf('alpha') | Should -BeLessThan $json.IndexOf('mike')
        $json.IndexOf('mike')  | Should -BeLessThan $json.IndexOf('zebra')
    }

    It 'sorts arrays so semantically-equal profiles canonicalize identically' {
        $x = [ordered]@{ controls = @('b', 'a', 'c') }
        $y = [ordered]@{ controls = @('c', 'b', 'a') }

        (ConvertTo-M365CanonicalJson $x) | Should -Be (ConvertTo-M365CanonicalJson $y)
    }

    It 'is stable across repeated calls (byte-identical) for the same input' {
        $first  = ConvertTo-M365CanonicalJson $script:sampleProfile
        $second = ConvertTo-M365CanonicalJson $script:sampleProfile

        $first | Should -Be $second
    }

    It 'treats a nested control array of objects deterministically by content' {
        $reordered = [ordered]@{
            schemaVersion    = '1.0'
            name             = 'security-baseline'
            framework        = 'SCuBA'
            frameworkVersion = '1.5.0'
            controls         = @(
                [ordered]@{ id = 'MS.EXO.4.1'; framework = 'SCuBA'; frameworkVersion = '1.5.0'; provider = 'exo';   settings = [ordered]@{ enabled = $true } }
                [ordered]@{ id = 'MS.AAD.1.1'; framework = 'SCuBA'; frameworkVersion = '1.5.0'; provider = 'graph'; name = 'Block legacy auth'; settings = [ordered]@{ state = 'enabled' } }
            )
        }

        # Same controls, opposite order → identical canonical form.
        (ConvertTo-M365CanonicalJson $reordered) | Should -Be (ConvertTo-M365CanonicalJson $script:sampleProfile)
    }
}

Describe 'YAML to canonical JSON round-trip (ADR-0008)' {

    It 'round-trips a profile through YAML losslessly (canonical forms match)' {
        $yaml       = ConvertTo-M365ProfileYaml $script:sampleProfile
        $reparsed   = ConvertFrom-M365ProfileYaml $yaml

        (ConvertTo-M365CanonicalJson $reparsed) | Should -Be (ConvertTo-M365CanonicalJson $script:sampleProfile)
    }

    It 'produces YAML a human can read (block structure, not inline JSON)' {
        $yaml = ConvertTo-M365ProfileYaml $script:sampleProfile

        $yaml | Should -Match 'name:\s*security-baseline'
        $yaml | Should -Match 'framework:\s*SCuBA'
    }

    It 'ConvertFrom rejects malformed YAML loudly (NFR-6)' {
        { ConvertFrom-M365ProfileYaml "key: [unclosed" } | Should -Throw
    }
}

#requires -Version 7.0

function Find-M365SecretKey {
    <#
    .SYNOPSIS
        Recursively finds credential-shaped key names anywhere in an object,
        returning their dotted paths.

    .DESCRIPTION
        Profiles are config-only — never credentials (FR-5, NFR-1). This is the
        scanner behind that guarantee: it walks dictionaries, pscustomobjects, and
        arrays and reports any key whose (punctuation-stripped, lower-cased) name
        matches a credential pattern, so the validator can reject a profile that
        carries a secret before it is ever written or applied.

        The pattern set is deliberately conservative — it targets actual
        credential material (secret/password/token/key/thumbprint/…) and avoids
        broad words like bare "certificate" that legitimately appear in config
        (e.g. requireCertificate). It matches key NAMES, never values.

        Internal helper; not exported. Emits one dotted path per hit.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $InputObject,
        [string] $Path = ''
    )

    if ($null -eq $InputObject) { return }

    $patterns = @(
        'secret', 'password', 'passwd', 'pwd', 'credential', 'apikey',
        'accesstoken', 'refreshtoken', 'idtoken', 'bearertoken',
        'privatekey', 'connectionstring', 'thumbprint', 'saskey', 'sharedkey'
    )

    $emitForKey = {
        param($keyName, $childPath, $value)
        $normalized = ([string] $keyName).ToLowerInvariant() -replace '[^a-z0-9]', ''
        foreach ($pattern in $patterns) {
            if ($normalized -like "*$pattern*") { $childPath; break }
        }
        Find-M365SecretKey -InputObject $value -Path $childPath
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            $childPath = if ($Path) { "$Path.$key" } else { [string] $key }
            & $emitForKey $key $childPath $InputObject[$key]
        }
    }
    elseif ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        foreach ($name in $InputObject.PSObject.Properties.Name) {
            $childPath = if ($Path) { "$Path.$name" } else { $name }
            & $emitForKey $name $childPath $InputObject.$name
        }
    }
    elseif ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $index = 0
        foreach ($element in $InputObject) {
            Find-M365SecretKey -InputObject $element -Path "$Path[$index]"
            $index++
        }
    }
    # scalars: nothing to scan
}

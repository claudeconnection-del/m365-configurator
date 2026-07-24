#requires -Version 7.0

function Test-M365CredentialKeyName {
    <#
    .SYNOPSIS
        Reports whether a key NAME denotes credential material (true) versus a
        policy/config setting that merely mentions one (false).

    .DESCRIPTION
        The rule (name-based, never value-based): tokenise the key into words
        (camelCase / snake_case / kebab-case / dotted / digits) and treat it as a
        credential if its HEAD (last) word is secret material, or its last two
        words / whole name form a known credential compound. So clientSecret,
        password, passphrase, apiToken, accessKey, connectionString are flagged,
        while accessTokenLifetime, apiKeyEnforced, requireSecretRotation are not.

        Internal helper; not exported.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $KeyName)

    $headNouns = @(
        'secret', 'password', 'passphrase', 'pwd', 'token', 'credential',
        'credentials', 'thumbprint', 'pfx'
    )
    $compounds = @(
        'apikey', 'privatekey', 'secretkey', 'accesskey', 'sharedkey', 'saskey',
        'encryptionkey', 'signingkey', 'connectionstring', 'clientsecret'
    )

    $spaced = ($KeyName -creplace '([a-z0-9])([A-Z])', '$1 $2') -replace '[^A-Za-z0-9]+', ' '
    $tokens = @($spaced.ToLowerInvariant() -split '\s+' | Where-Object { $_ })
    if ($tokens.Count -eq 0) { return $false }

    $last    = $tokens[-1]
    $whole   = -join $tokens
    $lastTwo = if ($tokens.Count -ge 2) { $tokens[-2] + $tokens[-1] } else { '' }

    ($last -in $headNouns) -or ($whole -in $compounds) -or ($lastTwo -in $compounds)
}

function Find-M365SecretKey {
    <#
    .SYNOPSIS
        Recursively finds credential-shaped key names anywhere in an object,
        returning their dotted paths.

    .DESCRIPTION
        Profiles are config-only — never credentials (FR-5, NFR-1). This scanner
        walks dictionaries, pscustomobjects, and arrays and reports any key whose
        NAME denotes credential material (see Test-M365CredentialKeyName), so the
        validator can reject a profile carrying a secret before it is written or
        applied.

          * flagged: clientSecret, password, passphrase, apiKey, accessToken,
            refreshToken, authToken, sasToken, certificateThumbprint,
            connectionString, privateKey, accessKey, …
          * NOT flagged: accessTokenLifetime, refreshTokenLifetime,
            requireSecretRotation, apiKeyEnforced, connectionStringRequired.

        Matches names, never values: a secret hidden under an innocuous key name
        is out of scope by design.

        Internal helper; not exported. Emits one dotted path per hit.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $InputObject,
        [string] $Path = ''
    )

    if ($null -eq $InputObject) { return }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            $childPath = if ($Path) { "$Path.$key" } else { [string] $key }
            if (Test-M365CredentialKeyName -KeyName ([string] $key)) { $childPath }
            Find-M365SecretKey -InputObject $InputObject[$key] -Path $childPath
        }
    }
    elseif ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        foreach ($name in $InputObject.PSObject.Properties.Name) {
            $childPath = if ($Path) { "$Path.$name" } else { $name }
            if (Test-M365CredentialKeyName -KeyName $name) { $childPath }
            Find-M365SecretKey -InputObject $InputObject.$name -Path $childPath
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

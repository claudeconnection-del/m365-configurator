#requires -Version 7.0

function Test-M365CredentialKeyName {
    <#
    .SYNOPSIS
        Reports whether a key NAME denotes credential material (true) versus a
        policy/config setting that merely mentions one (false).

    .DESCRIPTION
        Name-based, never value-based. Tokenise the key into words (camelCase /
        snake_case / kebab-case / dotted / digits), then decide in three steps:

          1. Compute a compound match on the FULL token list — any adjacent word
             pair (or the whole name) that joins to a known credential phrase
             (apiKey, privateKey, connectionString, symmetricKey, sshKey, …). Done
             first so a material word that is itself part of a compound
             (connectionString) is not lost by the peeling in step 2.
          2. Peel trailing qualifier words to find the real head:
               * a trailing POLICY / metadata word (lifetime, rotation, enforced,
                 policy, state, type, endpoint, name, …) means the field is a
                 setting ABOUT a credential, not a secret — return false outright
                 (accessTokenLifetime, apiKeyEnforced, requireSecretRotation,
                 tokenEndpoint, certificateBasedAuthConfiguration);
               * a trailing MATERIAL word (text, value, data, string, hash, pem,
                 id, …) names the stored/encoded FORM of a secret — peel it to
                 expose the head (secretText, tokenString, accessKeyId, password_hash).
          3. Flag if the exposed head word is credential material (secret,
             password, token, certificate, thumbprint, …) OR step 1 found a compound.

        Bias is deliberately toward FALSE POSITIVES over false negatives: this is
        the NFR-1 backstop keeping secrets out of shared, config-only profiles, so
        an over-eager rejection (rename the field) beats a leaked credential.
        So clientSecret, secretText, apiKeyData, connectionString, sshKey are
        flagged; accessTokenLifetime, apiKeyEnforced, clientId, tokenEndpoint are not.

        Internal helper; not exported.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $KeyName)

    # Head words that, when they are the subject of the name, ARE the secret.
    $headNouns = @(
        'secret', 'password', 'passphrase', 'pwd', 'token', 'credential',
        'credentials', 'thumbprint', 'pfx', 'certificate', 'cert'
    )
    # Multi-word credential phrases whose individual words are not head nouns.
    $compounds = @(
        'apikey', 'privatekey', 'secretkey', 'accesskey', 'sharedkey', 'saskey',
        'encryptionkey', 'signingkey', 'symmetrickey', 'sshkey', 'connectionstring',
        'clientsecret'
    )
    # Trailing words meaning "a policy / metadata ABOUT a credential" — their
    # presence recontextualises the whole name as a setting, not a secret.
    $policyQualifiers = @(
        'lifetime', 'lifetimes', 'rotation', 'enforced', 'enforcement', 'required',
        'require', 'expiry', 'expiration', 'expires', 'enabled', 'disabled', 'count',
        'days', 'hours', 'minutes', 'seconds', 'interval', 'frequency', 'policy',
        'policies', 'state', 'status', 'type', 'kind', 'mode', 'format', 'allowed',
        'supported', 'configuration', 'config', 'setting', 'settings', 'threshold',
        'name', 'names', 'label', 'url', 'uri', 'endpoint'
    )
    # Trailing words denoting the stored/encoded FORM of a secret — peel them to
    # expose the real head, which may still be credential material.
    $materialQualifiers = @(
        'text', 'value', 'values', 'data', 'string', 'hash', 'pem', 'der', 'blob',
        'bytes', 'byte', 'b64', 'base64', 'encoded', 'raw', 'plaintext', 'cleartext',
        'material', 'id', 'ids', 'content', 'contents'
    )

    $spaced = ($KeyName -creplace '([a-z0-9])([A-Z])', '$1 $2') -replace '[^A-Za-z0-9]+', ' '
    $tokens = @($spaced.ToLowerInvariant() -split '\s+' | Where-Object { $_ })
    if ($tokens.Count -eq 0) { return $false }

    # 1. Compound match on the FULL token list (before any peeling).
    $hasCompound = (-join $tokens) -in $compounds
    for ($i = 0; -not $hasCompound -and $i -lt $tokens.Count - 1; $i++) {
        if (($tokens[$i] + $tokens[$i + 1]) -in $compounds) { $hasCompound = $true }
    }

    # 2. Peel trailing qualifiers. A policy qualifier short-circuits to "not a
    #    credential"; material qualifiers are stripped to expose the head.
    $core = [System.Collections.Generic.List[string]]::new([string[]] $tokens)
    while ($core.Count -gt 0) {
        $tail = $core[$core.Count - 1]
        if ($tail -in $policyQualifiers) { return $false }
        if ($tail -in $materialQualifiers) { $core.RemoveAt($core.Count - 1); continue }
        break
    }

    # 3. Flag on an exposed credential head word, or a compound found in step 1.
    $headIsCredential = ($core.Count -gt 0) -and ($core[$core.Count - 1] -in $headNouns)
    $headIsCredential -or $hasCompound
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

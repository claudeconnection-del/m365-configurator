#requires -Version 7.6

function Invoke-M365Cleanup {
    <#
    .SYNOPSIS
        Verified credential cleanup: tear down connections, purge any on-disk
        token-cache residue, dispose in-memory secrets, and confirm nothing is
        left — failing loud if it is.

    .DESCRIPTION
        The credential-hygiene backstop for the connection foundation (MCA-12;
        FR-3, NFR-1). It is designed to be run in a finally-block around every
        session AND at process start, so no credential residue can survive
        between sessions (research 04 §5).

        It is deliberately belt-and-braces and does NOT trust the disconnects,
        because the SDKs leave residue behind (research §4):

          1. Best-effort teardown of Graph and Exchange Online. Errors here are
             swallowed — a failed/absent disconnect must not stop the purge (this
             routine runs in a finally-block; it cannot itself dead-end).
          2. Purge known on-disk cache paths. Disconnect-MgGraph does not delete
             the persisted MSAL cache (documented bug, §4.1); with -ContextScope
             Process there should be nothing, but we remove the known locations
             anyway as defense-in-depth. Wildcards are supported (e.g. tmpEXO*).
          3. Dispose any in-memory secrets the caller holds (SecureString is NOT
             encrypted on Linux — §8), then force a GC.
          4. VERIFY: re-read the Graph context and EXO connections and re-test
             every cache path. Any residue is collected and thrown as one loud
             failure (NFR-6) — partial/silent cleanup is not acceptable.

        Every side effect is an injected scriptblock seam so the routine is
        unit-testable without a tenant or touching real cache locations; the
        defaults perform the real teardown/purge described above.

    .OUTPUTS
        pscustomobject: Service, GraphCleared, ExoCleared, PathsPurged, Clean.
        No secrets. Throws (does not return) when residue remains.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [scriptblock] $GraphDisconnector  = { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null },

        [scriptblock] $ExoDisconnector    = { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue },

        [scriptblock] $GraphContextReader  = { Get-MgContext },

        [scriptblock] $ExoConnectionReader = { Get-ConnectionInformation },

        # Known on-disk token-cache / temp locations to purge (research §2.4/§5).
        # Overridable so tests can target a scratch dir; wildcards allowed.
        [string[]] $CachePath = @(
            (Join-Path $HOME '.graph')                        # legacy: ecache.bin3
            (Join-Path $HOME '.local/share/.IdentityService') # MSAL ext (Linux/macOS)
            (Join-Path $HOME '.IdentityService')              # alternate location
            (Join-Path ([System.IO.Path]::GetTempPath()) 'tmpEXO*')  # EXO proxy modules (default temp)
        ),

        # If Connect-M365ExchangeOnline redirected EXO's proxy modules/logs via
        # -ModuleBasePath (research §6.3, e.g. /run/exo), those tmpEXO* files land
        # OUTSIDE the default temp dir. Pass the same path here so they are purged
        # and verified too — otherwise cleanup could report clean while they remain.
        [string] $ExoModuleBasePath,

        # Removes one path (wildcards allowed). Default: real, error-tolerant delete.
        [scriptblock] $Remover = { param($Path) Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue },

        # Tests whether a path still has anything (wildcards allowed).
        [scriptblock] $ResidueTest = { param($Path) Test-Path -Path $Path },

        # Disposes any in-memory secrets the caller created. Default: nothing —
        # our connect functions hold no secrets (tokens live inside MSAL).
        [scriptblock] $SecretDisposer = { }
    )

    # 1) Best-effort teardown. Swallow errors — a finally-block cleanup cannot
    #    itself throw here, or it would mask the original error and skip the purge.
    Write-Verbose 'Cleanup: tearing down Microsoft Graph session (best-effort).'
    try { & $GraphDisconnector } catch { Write-Verbose "  Graph disconnect reported: $($_.Exception.Message)" }

    Write-Verbose 'Cleanup: tearing down Exchange Online session (best-effort).'
    try { & $ExoDisconnector } catch { Write-Verbose "  Exchange Online disconnect reported: $($_.Exception.Message)" }

    # Effective purge/verify set = the known cache paths plus, when EXO's temp was
    # redirected at connect time, that location's proxy modules (research §6.3).
    $targets = [System.Collections.Generic.List[string]]::new()
    $targets.AddRange([string[]] $CachePath)
    if ($ExoModuleBasePath) {
        $targets.Add((Join-Path $ExoModuleBasePath 'tmpEXO*'))
    }

    # 2) Purge known on-disk cache/temp locations.
    foreach ($path in $targets) {
        Write-Verbose "Cleanup: purging cache path '$path'."
        try { & $Remover $path } catch { Write-Verbose "  Remove reported: $($_.Exception.Message)" }
    }

    # 3) Dispose in-memory secrets, then force a collection. SecureString is
    #    plaintext-in-memory on Linux, so explicit disposal + GC is the best we
    #    can do (research §8); ephemeral container FS is the final backstop.
    try { & $SecretDisposer } catch { Write-Verbose "  Secret disposal reported: $($_.Exception.Message)" }
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()

    # 4) Verify — collect ALL residue, then fail loud once with the full picture.
    $graphContext = & $GraphContextReader
    $exoConns     = @(& $ExoConnectionReader)

    $residue = [System.Collections.Generic.List[string]]::new()
    if ($graphContext)       { $residue.Add('Microsoft Graph auth context still present') }
    if ($exoConns.Count -gt 0) { $residue.Add("Exchange Online connection(s) still present ($($exoConns.Count))") }
    foreach ($path in $targets) {
        if (& $ResidueTest $path) { $residue.Add("on-disk residue at '$path'") }
    }

    if ($residue.Count -gt 0) {
        throw "M365 credential cleanup FAILED — residue remains: $($residue -join '; ')."
    }

    Write-Verbose 'Cleanup: verified clean — no context, no connections, no cache residue.'
    [pscustomobject]@{
        Service      = 'M365'
        GraphCleared = -not $graphContext
        ExoCleared   = ($exoConns.Count -eq 0)
        PathsPurged  = @($targets)
        Clean        = $true
    }
}

# Research 04 — Authentication & Credential Cleanup (Graph + Exchange Online)

> **Scope.** How `Microsoft.Graph` (Connect-MgGraph) and `ExchangeOnlineManagement`
> (Connect-ExchangeOnline) authenticate, where they persist tokens/session state,
> what disconnect actually clears, and how to guarantee **zero credential residue
> between sessions** inside an ephemeral Linux/PowerShell 7 container.
>
> **Tenet under test:** *SECURITY IS PARAMOUNT — no credentials persisted to disk,
> full credential cleanup between sessions, nothing phones home* (VISION.md;
> REQUIREMENTS.md **FR-3**, **NFR-1**).
>
> **Decisions this informs:** OPEN-QUESTIONS **Q4** (auth method), **Q5** (cert
> handling), **Q3** (container runtime model).
>
> Date: 2026-07-22 · Status: research (feeds an ADR in `docs/decisions/`)

---

## TL;DR — the load-bearing findings

1. **`Connect-MgGraph` persists a token cache to disk BY DEFAULT.** The default
   `-ContextScope CurrentUser` writes the MSAL token cache (access + **refresh**
   tokens) to disk so sign-in survives across PowerShell sessions. This directly
   violates our tenet unless overridden. **Fix: always pass `-ContextScope
   Process`** → tokens live only in the current process's memory and die with it.
2. **`Disconnect-MgGraph` does NOT delete the on-disk MSAL cache.** It clears the
   in-memory context and the auth-record file, but the persisted MSAL cache files
   remain on disk (documented bug, [issue #3648](https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/3648)).
   So even a "correct" disconnect can leave refresh tokens behind if you ever used
   `CurrentUser`. We must **also delete the cache files ourselves**.
3. **On headless Linux/containers, MSAL cannot encrypt the cache** (no D-Bus/X11/
   keyring for libsecret). It errors or falls back to a **plaintext** token file.
   This makes on-disk caching in a container doubly unacceptable — reinforcing
   "in-memory only + wipe."
4. **`Connect-ExchangeOnline` (EXO V3) is REST-based**, holds tokens in memory
   (MSAL), and writes **auto-generated proxy-cmdlet modules to a temp dir**
   (`tmpEXO*.psm1`). Those temp modules are code, not secrets, but should still be
   redirected (`-EXOModuleBasePath`) and cleaned. `Disconnect-ExchangeOnline`
   clears connections + cache but can leave temp module files behind.
5. **SecureString is NOT encrypted at rest on Linux/macOS.** On non-Windows,
   `SecureString` is effectively plaintext in memory. Treat any secret we handle
   as plaintext and null/dispose it explicitly.
6. **Device-code flow (`-UseDeviceCode` / `-Device`) is the right container
   default** — no in-container browser needed; the operator authenticates on their
   own machine. Interactive browser flow generally cannot work from a headless
   container.

---

## 1. Module & runtime context

| Item | Value |
| --- | --- |
| Graph auth cmdlets | `Microsoft.Graph.Authentication` module (`Connect-MgGraph`, `Disconnect-MgGraph`, `Get-MgContext`) |
| EXO module | `ExchangeOnlineManagement` — "EXO V3" (REST-based for all cmdlets since Oct 2023) |
| Runtime | PowerShell 7 on Linux, in a container |
| Auth (decided) | Interactive delegated (browser) **+** device code; **memory-only tokens** |
| Underlying auth lib | **MSAL** (Microsoft Authentication Library) for both modules |

Both modules obtain tokens via **MSAL**, so MSAL's caching model is the crux of
the "no credentials on disk" question. ([Connect-MgGraph docs](https://learn.microsoft.com/powershell/module/microsoft.graph.authentication/connect-mggraph?view=graph-powershell-1.0);
[About the EXO module](https://learn.microsoft.com/powershell/exchange/exchange-online-powershell-v2?view=exchange-ps))

---

## 2. `Connect-MgGraph`

### 2.1 Authentication flows (delegated)

| Flow | Command | Container-friendly? |
| --- | --- | --- |
| Interactive browser | `Connect-MgGraph -Scopes "Policy.Read.All"` | ❌ needs a local browser / WAM broker |
| **Device code** | `Connect-MgGraph -Scopes "Policy.Read.All" -UseDeviceCode` | ✅ operator opens URL on their own machine |
| Bring-your-own token | `Connect-MgGraph -AccessToken $secure` | ✅ but token supplied externally (SecureString) |

App-only / cert / managed-identity / client-secret parameter sets also exist but
are **out of MVP scope** (decision: interactive delegated + device code only). They
are noted here only so we don't accidentally trip into a cert-on-disk path.

```powershell
# Interactive (browser) — only viable when a browser is reachable
Connect-MgGraph -Scopes "Policy.Read.All","Policy.ReadWrite.ConditionalAccess" `
                -TenantId $TenantId -ContextScope Process -NoWelcome

# Device code — the container default
Connect-MgGraph -Scopes "Policy.Read.All","Policy.ReadWrite.ConditionalAccess" `
                -TenantId $TenantId -UseDeviceCode -ContextScope Process -NoWelcome
```

### 2.2 Key parameters that matter for us

| Parameter | Why it matters |
| --- | --- |
| `-Scopes <string[]>` | Delegated permissions to consent to; request **least privilege** (see §8). |
| `-TenantId <string>` | Pin the target tenant (also accepts `common`/`organizations`). Avoids wrong-tenant sign-in. |
| `-UseDeviceCode` | Device-code flow (aliases: `-DeviceCode`, `-Device`, `-UseDeviceAuthentication`). No browser control needed. |
| `-ContextScope Process` | **Critical.** Keeps auth context/token in the current process only — *not* persisted for the user across sessions. |
| `-NoWelcome` | Suppresses the banner (cleaner audit logs; no functional security effect). |
| `-ClientId` | Use our own app registration instead of the shared "Microsoft Graph PowerShell" app (tighter, isolatable consent). Recommended eventually. |

### 2.3 How Connect-MgGraph caches tokens — the deep dive

**Default behavior persists to disk.** Microsoft's docs state plainly:

> "sign-in persists across PowerShell sessions because Microsoft Graph PowerShell
> securely caches the token when using the default `CurrentUser` context scope. If
> you use the `-ContextScope Process` parameter with `Connect-MgGraph`, sign-in
> only persists for the current PowerShell session."
> — [Authentication module cmdlets in Microsoft Graph PowerShell](https://learn.microsoft.com/powershell/microsoftgraph/authentication-commands?view=graph-powershell-1.0)

So there are two modes:

| `-ContextScope` | Where the token cache lives | Survives process exit? | Our verdict |
| --- | --- | --- | --- |
| `CurrentUser` (**default**) | **On disk** (MSAL cache file, see below) | **Yes** — persists across sessions | ❌ violates "no credentials on disk" |
| `Process` | **In memory**, tied to the MSAL app object in the process | No — erased when the process ends | ✅ required for our tenet |

MSAL's in-memory cache lifetime equals the MSAL application object's lifetime; when
the process ends the cache is erased and re-auth is required
([Token caching in MSAL — In-memory cache](https://learn.microsoft.com/entra/msal/javascript/node/caching#in-memory-cache)).
`-ContextScope Process` is what pins us to that behavior.

### 2.4 WHERE the on-disk cache lives (if `CurrentUser` is ever used)

The exact path/filename has changed across SDK versions, so a robust cleanup must
target **all** known variants. The cache holds access **and refresh** tokens
(≈ several KB per account; refresh tokens are the dangerous part —
[token cache size / contents](https://learn.microsoft.com/entra/msal/dotnet/how-to/token-cache-serialization#size-approximations)).

| SDK era | Folder | File(s) | Source |
| --- | --- | --- | --- |
| Older `Microsoft.Graph` v1.x | `~/.graph` (`%USERPROFILE%\.graph` on Windows) | `ecache.bin3` | [issue #2215](https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/2215) |
| Current (MSAL cache extensions) | `.IdentityService` under the user's local-app-data dir | `mg.msal.cache.cae`, `mg.msal.cache.nocae` | [issue #3648](https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/3648) |

Platform base directories for the `.IdentityService` cache (MSAL.NET extensions):

| OS | Typical base | Protection |
| --- | --- | --- |
| Windows | `%LOCALAPPDATA%\.IdentityService\` | DPAPI (encrypted) |
| macOS | `~/.local/share/.IdentityService/` (or Keychain) | Keychain |
| **Linux** | `~/.local/share/.IdentityService/` (also seen at `~/.IdentityService`) | **libsecret** — *if available*; otherwise **plaintext** |

> **Container red flag.** On Linux, MSAL's encrypted cache uses **libsecret**,
> which "doesn't work properly without a GUI"/keyring; keyrings fail in headless
> mode (SSH/containers) because of a D-Bus/X11 dependency ("Cannot autolaunch
> D-Bus without X11"). MSAL then errors or **falls back to a plaintext token
> file**. ([MSAL.NET issue #3033](https://github.com/AzureAD/microsoft-authentication-library-for-dotnet/issues/3033);
> [MSAL extensions on Linux background](https://learn.microsoft.com/entra/msal/javascript/node/caching#in-memory-cache))
> Conclusion: **never let a container use `CurrentUser`** — the cache would land
> on disk *unencrypted*.

### 2.5 Forcing in-memory / ephemeral only

1. **Always `-ContextScope Process`.** Primary control. Tokens never touch disk.
2. **Redirect `$HOME` to an ephemeral, wiped-on-exit dir** (belt-and-braces). Both
   `~/.graph` and `~/.local/share/.IdentityService` derive from `$HOME`/local-app
   data, so a per-session `HOME` on a `tmpfs` means any accidental persistence is
   RAM-backed and vanishes on teardown.
3. **Container ephemerality** (see §7): the container filesystem itself is
   discarded per engagement, so even a stray cache file cannot outlive the session.

There is **no** `Connect-MgGraph` switch that says "cache in RAM only" other than
`-ContextScope Process`; treat that flag as mandatory in our code path.

---

## 3. `Connect-ExchangeOnline` (EXO V3)

### 3.1 What kind of connection it is

- **REST API connections for all cmdlets since Oct 2023** — no remote PowerShell,
  no WinRM Basic auth, no runspace setup. "More secure: built-in support for modern
  authentication and no dependence on the remote PowerShell session."
  ([About the EXO module](https://learn.microsoft.com/powershell/exchange/exchange-online-powershell-v2?view=exchange-ps))
- `-UseRPSSession` (the old remote-PowerShell mode) is **deprecated** — do not use.
- Uses **MSAL** for token acquisition; tokens are held **in memory** for the
  connection.

### 3.2 Flows

| Flow | Command | Container-friendly? |
| --- | --- | --- |
| Interactive (modern auth, MFA) | `Connect-ExchangeOnline -UserPrincipalName admin@contoso.com` | ❌ needs browser/WAM |
| **Device code** | `Connect-ExchangeOnline -Device` (PS 7.0.3+ / module 2.0.4+) | ✅ "computers that don't have web browsers" |
| Inline credential | `Connect-ExchangeOnline -InlineCredential` | ⚠️ prompts for user/pass in the console — **basic-cred pattern, avoid** |
| `-Credential $cred` | Pre-built PSCredential | ⚠️ handles a plaintext-on-Linux SecureString — avoid |
| `-AccessToken` | Externally supplied token | ✅ but token supplied by us |

```powershell
# Device code — container default
Connect-ExchangeOnline -Device -ShowBanner:$false `
    -EXOModuleBasePath /run/exo -LogDirectoryPath /run/exo/logs
```

Per docs, `-Device` "returns a URL and unique code… open the URL in a browser on
any computer, and then enter the unique code… the session in the PowerShell 7
window is authenticated via the regular Microsoft Entra authentication flow."
([Connect-ExchangeOnline](https://learn.microsoft.com/powershell/module/exchangepowershell/connect-exchangeonline?view=exchange-ps))

`-InlineCredential` / `-Credential` accept username+password directly. That is a
legacy-shaped pattern, defeats MFA, and forces us to hold a `SecureString` that is
**plaintext on Linux** (§9). **Do not use these in the tool.**

### 3.3 Temp files and session state it creates

| Artifact | Where | Contains | Control |
| --- | --- | --- | --- |
| Auto-generated proxy-cmdlet module | Temp dir, `tmpEXO*.psm1` (e.g. `%TEMP%`/`$env:TMPDIR`) | **Code** (cmdlet stubs), not secrets | **`-EXOModuleBasePath <path>`** redirects these |
| Log files | Default temp / `LogDirectoryPath` | Connection diagnostics (avoid enabling secret-y logging) | **`-LogDirectoryPath <path>`**, `-LogLevel` |
| MSAL token(s) | In-memory for the connection | Access/refresh tokens | Held in process; cleared by disconnect |

- The module writes `tmpEXO*.psm1` proxy modules to the temp directory; in
  constrained environments these are known to accumulate
  ([vscode-powershell #4074](https://github.com/PowerShell/vscode-powershell/issues/4074)).
- **`-EXOModuleBasePath`** (newer module versions) lets us **store those temp EXO
  module files in a custom path** — point it at our ephemeral dir so cleanup is
  trivial and nothing lands in a shared `/tmp`.
- **WAM:** `-DisableWAM` disables Web Account Manager broker sign-in (only relevant
  on Windows/where WAM is present; useful to force plain interactive/device flows).
- **`Get-ConnectionInformation`** enumerates active REST connections —
  `Get-PSSession` does **not** show REST connections, so this is the cmdlet to
  audit/verify open EXO connections before cleanup.

---

## 4. Disconnect: what each cmdlet actually clears

### 4.1 `Disconnect-MgGraph`

| Clears | Leaves behind |
| --- | --- |
| In-memory auth context (`Get-MgContext` → null) | **On-disk MSAL cache files** (`mg.msal.cache.*` / `ecache.bin3`) if `CurrentUser` was used |
| The auth-record file | Refresh tokens inside those cache files |
| Ends session for the current context scope | — |

Docs frame it as "clears the cached token and ends the session for the current
context scope"
([auth-commands](https://learn.microsoft.com/powershell/microsoftgraph/authentication-commands?view=graph-powershell-1.0)).
But the **documented bug** ([#3648](https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/3648))
is precise: `LogoutAsync()` "only clears the in-memory cache, nullifies the
AuthContext/GraphHttpClient, and deletes the authentication record file. The
disk-persisted files persist unchanged." A later `Connect-MgGraph` can then
**silently reuse cached tokens without a prompt**.

➡️ **Implication:** `Disconnect-MgGraph` is necessary but **not sufficient** for
our tenet. Because we will use `-ContextScope Process` there should be *no* disk
cache to begin with — but our cleanup routine must still proactively delete the
known cache paths as defense-in-depth.

### 4.2 `Disconnect-ExchangeOnline`

| Clears | Leaves behind |
| --- | --- |
| "Disconnects any connections and clears the cache" (in-memory tokens/session) | Temp proxy-cmdlet modules (`tmpEXO*.psm1`) can remain on disk |
| After disconnect, no org cmdlets run | Log files under the log dir |

Docs: "This cmdlet disconnects any connections and clears the cache. After a
successful disconnect, you can't successfully run any cmdlets for your
organization."
([Disconnect-ExchangeOnline](https://learn.microsoft.com/powershell/module/exchangepowershell/disconnect-exchangeonline?view=exchange-ps))
Use `-Confirm:$false` for non-interactive teardown. The in-memory token is cleared;
the **temp module files/logs are filesystem residue** we must remove.

---

## 5. Concrete cleanup routine (outline)

Design goal: after `Invoke-Cleanup`, a filesystem + memory scan finds **no tokens,
no cache files, no lingering connections**. Order matters (disconnect → delete →
null → GC).

```powershell
function Invoke-M365Cleanup {
    [CmdletBinding()]
    param()

    # 1) Tear down live connections (idempotent; swallow "already disconnected")
    try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch {}
    try {
        if (Get-ConnectionInformation -ErrorAction SilentlyContinue) {
            Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
        }
    } catch {}

    # 2) Delete Graph MSAL on-disk cache (defense-in-depth; should be empty when
    #    -ContextScope Process is used, but Disconnect-MgGraph won't remove it).
    $graphCachePaths = @(
        (Join-Path $HOME '.graph'),                                   # legacy: ecache.bin3
        (Join-Path $HOME '.local/share/.IdentityService'),           # MSAL ext (Linux/macOS)
        (Join-Path $HOME '.IdentityService')                         # alt location
    )
    foreach ($p in $graphCachePaths) {
        if (Test-Path $p) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # 3) Delete EXO temp proxy modules + logs (redirected via -EXOModuleBasePath)
    foreach ($p in @('/run/exo', $env:TMPDIR, '/tmp')) {
        if ($p -and (Test-Path $p)) {
            Get-ChildItem $p -Filter 'tmpEXO*' -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # 4) Null out any in-memory secrets/SecureStrings we created, then GC.
    #    SecureString is NOT encrypted on Linux — dispose explicitly.
    foreach ($name in 'AccessToken','ClientSecret','Cred') {
        $v = Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
        if ($v) {
            if ($v.Value -is [System.Security.SecureString]) { $v.Value.Dispose() }
            Set-Variable -Name $name -Scope Script -Value $null
        }
    }
    [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers()

    # 5) Verify (loud failure if anything remains — NFR-6)
    if (Get-MgContext -ErrorAction SilentlyContinue) { throw 'CLEANUP FAILED: Graph context still present' }
    if (Get-ConnectionInformation -ErrorAction SilentlyContinue) { throw 'CLEANUP FAILED: EXO connection still present' }
    foreach ($p in $graphCachePaths) { if (Test-Path $p) { throw "CLEANUP FAILED: $p" } }
}
```

Run this in a `finally` block around every session, **and** on process start
(clean slate), **and** rely on container teardown as the final backstop.

**Cleanup layers (why we do all of them):**

| Layer | Mechanism | Guards against |
| --- | --- | --- |
| Prefer in-memory | `-ContextScope Process` (Graph); EXO tokens are in-memory | Anything ever being written |
| Explicit disconnect | `Disconnect-MgGraph`, `Disconnect-ExchangeOnline -Confirm:$false` | Live tokens/connections |
| File deletion | Remove `.graph` / `.IdentityService` / `tmpEXO*` | The `Disconnect-MgGraph` disk-cache bug; EXO temp residue |
| Memory hygiene | Dispose SecureStrings, null vars, GC | Plaintext-on-Linux secrets lingering |
| Ephemeral FS + fresh `$HOME` | tmpfs / discarded container layer | Everything above, as backstop |
| Verify + fail loud | Re-check context/connections/paths | Silent partial cleanup (NFR-6) |

---

## 6. Container implications

### 6.1 Browser (interactive) flow from a container — limitations

- Interactive sign-in needs a **local browser** (or the WAM broker on Windows).
  A headless Linux container has neither, so the browser flow generally **cannot
  complete in-container**.
- Workarounds (X-forwarding, mounting a browser, port-forwarding the localhost
  redirect to the host) add dependencies and fragility — at odds with **NFR-3
  minimal dependencies** and **NFR-4 portability**.

### 6.2 Device code flow — the recommended container default

- No in-container browser required. The tool prints a URL + code; the **operator
  authenticates on their own trusted machine**; the container receives the token.
- Supported by **both** modules (`Connect-MgGraph -UseDeviceCode`,
  `Connect-ExchangeOnline -Device`).
- Token lands **in process memory** (with `-ContextScope Process` for Graph) and
  is wiped on cleanup / container exit.

> **Recommendation:** **Device code is the default** in the container.
> Offer interactive browser only as an opt-in for when someone runs the tool
> outside a container (e.g. a consultant's workstation with a browser).

### 6.3 Filesystem strategy

| Control | Setting |
| --- | --- |
| Ephemeral container FS | One container per engagement; discard on exit (aligns with Q3 one-shot model). |
| Fresh, RAM-backed `$HOME` | Mount `$HOME` (or at least `~/.local/share`) as `tmpfs`; set a per-session `HOME`. |
| Redirect EXO temp | `-EXOModuleBasePath /run/exo` (a tmpfs path) + `-LogDirectoryPath` under it. |
| No secret volumes | Never bind-mount a host dir that MSAL could cache into. |
| `read_only` rootfs + tmpfs mounts | Container rootfs read-only; only explicit tmpfs paths writable → cache literally cannot persist. |

Because both Graph (`CurrentUser`) and EXO temp files derive from `$HOME`/temp, a
RAM-backed `$HOME` + read-only rootfs means **even a bug that tries to persist a
token writes to RAM that vanishes on teardown**.

---

## 7. Least-privilege permissions

### 7.1 Graph delegated scopes for the security-baseline slice (Q6)

Request the **minimum** scopes per operation; prefer `.Read.*` for dry-run/drift,
escalate to `.ReadWrite.*` only on apply. ([Graph permissions reference](https://learn.microsoft.com/graph/permissions-reference);
Microsoft: "request the least privileged permissions that your app needs.")

| Baseline area | Read (dry-run / drift) | Write (apply / remediate) |
| --- | --- | --- |
| Conditional Access | `Policy.Read.ConditionalAccess` (delegated `633e0fce-8c58-4cfb-9495-12bbd5a24f7c`) or broader `Policy.Read.All` | `Policy.ReadWrite.ConditionalAccess` (delegated `ad902697-1014-4ef5-81ef-2b4301988e8c`) |
| Authentication methods policy | `Policy.Read.AuthenticationMethod` (delegated `a6ff13ac-1851-4993-8ca9-a671d70de2d5`) | `Policy.ReadWrite.AuthenticationMethod` (delegated `7e823077-d88e-468f-a337-e18f1f0e6c7c`) |
| Broad policy read (fallback) | `Policy.Read.All` (delegated `572fea84-0151-49b2-9301-11cb16974376`) | — (avoid a broad write scope) |
| Directory objects (users/groups referenced by policies) | `Directory.Read.All` | `Directory.ReadWrite.All` (only if we create/modify objects) |

Notes:
- Many of these require **admin consent**; `Policy.Read.ConditionalAccess`
  (delegated) notably does **not** require admin consent for read.
- Split read vs write so **dry-run/drift only ever needs read scopes** — a natural
  fit for FR-8/FR-10 and least privilege.
- Consider a **dedicated app registration** (`-ClientId`) so consent is scoped to
  our tool, not the shared multi-tenant "Microsoft Graph PowerShell" app.

### 7.2 Exchange Online roles (for anti-phishing / anti-spam baseline)

EXO is **RBAC-role** based, not Graph scopes. Anti-phish policies use
`*-AntiPhishPolicy`/`*-AntiPhishRule`; anti-spam uses
`*-HostedContentFilterPolicy`/`*-HostedContentFilterRule`.
([anti-phishing configure](https://learn.microsoft.com/defender-office-365/anti-phishing-policies-eop-configure);
[anti-spam configure](https://learn.microsoft.com/defender-office-365/anti-spam-policies-configure))

| Need | Role group(s) |
| --- | --- |
| Read-only (dry-run / drift) | **Global Reader**, **Security Reader**, or **View-Only Organization Management** |
| Add/modify/delete policies (apply) | **Organization Management** or **Security Administrator** |

Prefer assigning the operator the **least** of these that covers the intended
action; drift/dry-run should run under a read-only role.

---

## 8. SecureString / plaintext pitfalls on PowerShell 7 / Linux

| Pitfall | Detail | Mitigation |
| --- | --- | --- |
| **SecureString not encrypted off-Windows** | Per .NET, "the contents of a SecureString are not encrypted on non-Windows systems." On Linux it is effectively plaintext in process memory. ([ConvertTo-SecureString notes](https://learn.microsoft.com/powershell/module/microsoft.powershell.security/convertto-securestring?view=powershell-7.6)) | Minimize lifetime; `Dispose()` + null + GC (see §5); never write it out. |
| **`ConvertFrom-SecureString` to a file** | Produces an "encrypted standard string… stored in a file for later use" — but on Linux the DPAPI protection isn't there; it's portable/weak. | **Never persist** secrets this way (NFR-1). |
| **`-AsPlainText`** | `ConvertTo-SecureString -AsPlainText` bypasses protection; flagged as an **error** by PSScriptAnalyzer (`AvoidUsingConvertToSecureStringWithPlainText`). | Don't use; use `Read-Host -AsSecureString` or token flows. |
| **Plaintext in logs/history** | Plain text "can show up in event logs and command history logs." | Never echo secrets; scrub logs (NFR-5 "without logging secrets"). |
| **`-InlineCredential`/`-Credential` (EXO)** | Forces us to hold a username/password SecureString (plaintext on Linux) and defeats MFA. | Use device-code/interactive delegated only. |
| **`.NET` guidance** | .NET recommends **against SecureString for new development**; it's kept for back-compat and to avoid *accidental* console/log exposure — not as real at-rest protection. ([PowerShell advisory guidelines](https://learn.microsoft.com/powershell/scripting/developer/cmdlet/advisory-development-guidelines?view=powershell-7.6#code-guidelines)) | Assume any secret == plaintext in RAM; keep the window tiny and wipe. |

**Bottom line:** on Linux, "SecureString" buys us *accidental-exposure* protection,
not real encryption. Our security therefore rests on **not persisting**, **short
in-memory lifetime**, **explicit disposal**, and **ephemeral RAM-backed FS** — not
on SecureString semantics.

---

## 9. Key takeaways / recommendations

1. **Mandate `-ContextScope Process` on every `Connect-MgGraph` call.** This is the
   single most important control for "no tokens on disk." Enforce it in code + a
   lint/review check (NFR-1).
2. **Default to device-code flow in the container** (`-UseDeviceCode` / `-Device`);
   expose interactive browser only for non-container use.
3. **Treat `Disconnect-*` as necessary-but-insufficient.** Always follow with
   explicit deletion of Graph cache paths and EXO temp files (the
   `Disconnect-MgGraph` disk-cache bug is real and current).
4. **Redirect EXO temp/logs** with `-EXOModuleBasePath` and `-LogDirectoryPath`
   into a tmpfs path so cleanup is one `rm -rf` and nothing leaks to `/tmp`.
5. **Make `$HOME` (or `~/.local/share`) a per-session tmpfs and run a read-only
   rootfs.** Any accidental persistence is then RAM-backed and dies on teardown.
6. **Never use `-InlineCredential`/`-Credential`/`-AccessToken`-from-file or any
   `-AsPlainText` path.** Keep secrets to MSAL-managed in-memory tokens.
7. **Ship a single `Invoke-M365Cleanup`** (§5) run in `finally`, at process start,
   and verified with loud failure (NFR-6). Container discard is the final backstop.
8. **Least privilege by phase:** dry-run/drift uses read scopes/roles only; apply
   escalates to write. Consider a dedicated app registration for scoped consent.
9. **On Linux, don't rely on SecureString for at-rest security** — it isn't
   encrypted. Rely on non-persistence + disposal + ephemeral FS.

---

## 10. Open questions / risks

| # | Question / risk | Notes |
| --- | --- | --- |
| R1 | Exact Linux path of the current MSAL `.IdentityService` cache can vary by module/MSAL version. | Cleanup must be **path-tolerant** (glob known bases); verify empirically at build time by connecting with `CurrentUser` once in a throwaway container and listing created files. |
| R2 | Does EXO V3 ever persist an MSAL token to disk (vs. purely in-memory)? | Docs imply in-memory for the connection; **confirm empirically** on Linux (inspect FS after connect). If it uses the same MSAL extensions, the §2.4 headless-plaintext concern applies to EXO too. |
| R3 | `-EXOModuleBasePath` availability is version-gated. | Pin a module version that supports it (NFR-7); fall back to setting `$env:TMPDIR` to a tmpfs if unavailable. |
| R4 | Device-code flow requires the operator to have an interactive-capable machine + the app allowed for device-code/public-client flows; some tenants **block device-code** via Conditional Access. | Detect and message clearly; offer interactive fallback (loud failure, NFR-6). |
| R5 | Refresh-token lifetime if any cache ever persisted. | Refresh tokens can be long-lived; a single leaked cache file is high impact → this is *why* file deletion + ephemeral FS are non-negotiable. |
| R6 | GC/dispose does not guarantee prompt zeroing of managed string copies in RAM. | Accept residual risk; minimize by ephemeral process/container lifetime. |
| R7 | Using the shared "Microsoft Graph PowerShell" first-party app means consent is broad/tenant-wide. | Evaluate a dedicated app registration (Q4/Q5) to scope consent and enable per-tool revocation. |

---

## 11. Sources

**Microsoft Graph PowerShell (auth + cache)**
- Connect-MgGraph reference — https://learn.microsoft.com/powershell/module/microsoft.graph.authentication/connect-mggraph?view=graph-powershell-1.0
- Disconnect-MgGraph reference — https://learn.microsoft.com/powershell/module/microsoft.graph.authentication/disconnect-mggraph?view=graph-powershell-1.0
- Authentication module cmdlets (ContextScope, caching, Disconnect) — https://learn.microsoft.com/powershell/microsoftgraph/authentication-commands?view=graph-powershell-1.0
- Issue #3648 — Disconnect-MgGraph does not clear the persisted MSAL token cache (cache file names/paths) — https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/3648
- Issue #2215 — `.graph`/`ecache.bin3` token cache folder reference — https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/2215
- Issue #279 — request to move token caching off disk / in-memory only — https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/279

**MSAL caching model + headless Linux**
- Token caching in MSAL (in-memory cache lifetime) — https://learn.microsoft.com/entra/msal/javascript/node/caching#in-memory-cache
- Token cache serialization (size / refresh-token contents) — https://learn.microsoft.com/entra/msal/dotnet/how-to/token-cache-serialization#size-approximations
- MSAL.NET issue #3033 — encrypted token cache on Linux without GUI (libsecret/D-Bus/X11, plaintext fallback) — https://github.com/AzureAD/microsoft-authentication-library-for-dotnet/issues/3033

**Exchange Online PowerShell**
- Connect-ExchangeOnline reference (`-Device`, `-InlineCredential`, `-UseRPSSession`, `-EXOModuleBasePath`, `-DisableWAM`) — https://learn.microsoft.com/powershell/module/exchangepowershell/connect-exchangeonline?view=exchange-ps
- Disconnect-ExchangeOnline reference — https://learn.microsoft.com/powershell/module/exchangepowershell/disconnect-exchangeonline?view=exchange-ps
- About the EXO module (REST connections, Get-ConnectionInformation, temp module path) — https://learn.microsoft.com/powershell/exchange/exchange-online-powershell-v2?view=exchange-ps
- Connect to Security & Compliance PowerShell (disconnect guidance) — https://learn.microsoft.com/powershell/exchange/connect-to-scc-powershell?view=exchange-ps
- vscode-powershell #4074 — EXO module caches `tmpEXO*` files to temp — https://github.com/PowerShell/vscode-powershell/issues/4074

**Least privilege**
- Microsoft Graph permissions reference (Policy.*ConditionalAccess, Policy.*AuthenticationMethod identifiers) — https://learn.microsoft.com/graph/permissions-reference
- Configure anti-phishing policies (EOP) — https://learn.microsoft.com/defender-office-365/anti-phishing-policies-eop-configure
- Configure anti-spam policies — https://learn.microsoft.com/defender-office-365/anti-spam-policies-configure

**SecureString / plaintext on Linux**
- ConvertTo-SecureString (not encrypted on non-Windows) — https://learn.microsoft.com/powershell/module/microsoft.powershell.security/convertto-securestring?view=powershell-7.6
- PSScriptAnalyzer: AvoidUsingConvertToSecureStringWithPlainText — https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/rules/avoidusingconverttosecurestringwithplaintext?view=ps-modules
- PowerShell advisory development guidelines (SecureString caveats) — https://learn.microsoft.com/powershell/scripting/developer/cmdlet/advisory-development-guidelines?view=powershell-7.6#code-guidelines
- .NET System.Security.SecureString remarks — https://learn.microsoft.com/dotnet/api/system.security.securestring

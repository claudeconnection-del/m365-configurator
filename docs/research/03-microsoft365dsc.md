# Research 03 — Microsoft365DSC as the primary configuration engine

> **Phase 1 research** for `m365-configurator`. Scope: an engineering spike on
> whether **Microsoft365DSC (M365DSC)** can be our primary configuration engine —
> how it works end-to-end (export → MOF → LCM → drift/report), and whether it can
> run under our target runtime and honour our security tenets. This is the
> **pivotal** research track: it directly feeds the accept/reject decision on
> ADR-0002.
>
> **Tenets under test:** NFR-4 (containerized & portable, target **Linux +
> PowerShell 7**); NFR-1 / FR-3 (**no credentials persisted to disk**, memory-only,
> full cleanup) reconciled against ADR-0001; NFR-3 (minimal dependencies); NFR-7
> (pinned versions / syntax stability); NFR-6 (loud/fast failure); NFR-9
> (readability).
>
> **Decisions this informs:** **ADR-0002** (evaluate M365DSC as engine — status
> *Proposed*), **OPEN-QUESTIONS Q7** (DSC direction), **Q3** (container runtime
> model).
>
> **Author:** research sub-agent · **Date:** 2026-07-22 · M365DSC release line
> observed: **v1.26.x** (PowerShell Gallery, July 2026) [19].
>
> Every nontrivial claim is cited inline `[n]`; see [Sources](#19-sources).
> Microsoft Graph, Exchange Online, and auth-lifecycle/credential-cleanup are
> covered in sibling docs (01 Graph surface, 02 EXO surface, 04 auth & cleanup) —
> this doc builds on them and does not duplicate them.

---

## Contents

1. [How to read this doc](#1-how-to-read-this-doc)
2. [What Microsoft365DSC is, end-to-end](#2-what-microsoft365dsc-is-end-to-end)
3. [Runtime: PowerShell 7 / Linux vs Windows — the central question](#3-runtime-powershell-7--linux-vs-windows--the-central-question)
4. [Auth model vs ADR-0001](#4-auth-model-vs-adr-0001)
5. [MOF & credential handling vs no-persisted-secrets](#5-mof--credential-handling-vs-no-persisted-secrets)
6. [Drift detection & remediation fit (FR-8/FR-10/FR-11)](#6-drift-detection--remediation-fit-fr-8fr-10fr-11)
7. [Dependency footprint (NFR-3)](#7-dependency-footprint-nfr-3)
8. [Resource coverage for the MVP baseline](#8-resource-coverage-for-the-mvp-baseline)
9. [Recommendation & container strategy](#9-recommendation--container-strategy)
10. [Open questions / risks (what the container proof must verify)](#10-open-questions--risks-what-the-container-proof-must-verify)
11. [Sources](#11-sources)

---

## 1. How to read this doc

- **"M365DSC"** = the `Microsoft365DSC` PowerShell module. **"DSC"** = the
  underlying PowerShell Desired State Configuration framework it is built on.
- **"LCM"** = the DSC **Local Configuration Manager**, the on-box engine that
  applies a compiled MOF and runs the periodic consistency check.
- M365DSC layers three things on top of DSC: (a) **ReverseDSC** export (tenant →
  `.ps1` blueprint), (b) hundreds of **DSC resources** wrapping Graph/EXO/Teams/
  SPO/etc. cmdlets, and (c) **reporting/monitoring** helpers. Each interacts with
  our runtime and security tenets differently, so we evaluate them separately —
  the export/report layer and the apply/monitor layer have **very different**
  runtime and security profiles, and conflating them is the main trap.
- Verdicts are tagged **[VERIFIED]** (primary source fetched), **[LIKELY]**
  (strong convergent evidence, not a single authoritative page), or **[UNVERIFIED
  — prove in container]**.

---

## 2. What Microsoft365DSC is, end-to-end

M365DSC is an open-source PowerShell module built on DSC that lets you "write a
definition for how your Microsoft 365 tenant should be configured, automate the
deployment of that configuration and ensure the monitoring of the defined
configuration" [1]. It spans a broad workload set — **Azure AD / Entra ID,
Exchange Online, SharePoint, OneDrive, Teams, Security & Compliance, Intune, Power
Platform, Defender, Sentinel, Fabric, Viva, Azure DevOps** [1] — far wider than
our MVP baseline (ADR-0003).

The end-to-end lifecycle, and how each stage maps to our FRs:

| Stage | M365DSC mechanism | Maps to |
|---|---|---|
| **Export / blueprint** | `Export-M365DSCConfiguration` (ReverseDSC): connect, extract, emit a `.ps1` DSC configuration + `ConfigurationData.psd1` | FR-4, FR-5 |
| **Compile** | Execute the `.ps1` → DSC compiles a **MOF** (`localhost.mof`) into a folder named after the configuration [7] | (internal) |
| **Apply** | `Start-DscConfiguration -Path <folder> -Wait -Force` → the **LCM** calls each resource's `Set` [7] | FR-9 |
| **Test / drift** | `Test-DscConfiguration` (LCM) or the offline **delta report** | FR-8, FR-10 |
| **Monitor / remediate** | LCM consistency check every **15 min**; `ApplyAndAutoCorrect` re-applies desired state [9] | FR-10, FR-11 |
| **Report** | `New-M365DSCDeltaReport`, `Assert-M365DSCBlueprint`, `New-M365DSCReportFromConfiguration` → HTML | FR-8, FR-10, NFR-9 |

### 2.1 Export (`Export-M365DSCConfiguration`)

The entry point for ReverseDSC export: it "validates authentication inputs,
resolves target resources, executes extraction, and returns the generated
configuration content" [6]. Key parameters: `-Components` / `-Workloads` (scope
the extract, e.g. `AAD`, `EXO`), `-Mode` (`Default`/`Full`), `-Path`/`-FileName`
(output), and a `-TokenReplacement` option to map values to variables [6]. Output
is a **`.ps1` DSC configuration file** (plus `ConfigurationData.psd1`) written to
`-Path` [6]. This exported blueprint is exactly the "reusable, reviewable profile"
our vision calls for — **and it is the most portable, least Windows-bound part of
M365DSC** (see §3, §9).

### 2.2 Compile → MOF → apply

Applying is pure DSC: "the first step … is to compile the configuration file into
a MOF file. Doing so simply involves executing the `.ps1` file" [7]. Then
`Start-DscConfiguration -Path C:\…\M365TenantConfig -Wait -Verbose -Force`
hands the MOF to the **LCM**, which "does the heavy lifting" of calling each
resource to reach desired state [7]. On completion the apply also **configures the
LCM to wake every 15 minutes** and re-check the tenant for drift [7][9].

### 2.3 Reporting & assertion helpers

- **`New-M365DSCDeltaReport -Source a.ps1 -Destination b.ps1 -OutputPath
  d.html`** — an **offline** engine that compares two exported configurations and
  emits an HTML diff of missing / additional / different items; `-DriftOnly`
  filters to drift. It "requires no active connection to the DSC engine or tenant
  during the report generation phase — only the previously exported configuration
  files" [10]. **This is the key finding for our fallback:** the diff engine is
  independent of the LCM and therefore of Windows (see §9).
- **`Assert-M365DSCBlueprint -BluePrintUrl … -OutputReportPath …`** — exports the
  live tenant, then delta-reports it against a known-good blueprint (a live
  connection is needed for the export half) [3][10].
- **`New-M365DSCReportFromConfiguration`** — renders a single exported
  configuration into a human-readable report (HTML/Excel/JSON) [10].

---

## 3. Runtime: PowerShell 7 / Linux vs Windows — the central question

**This is the question ADR-0002 hinges on. Verdict up front: the M365DSC _apply_
and _monitor_ path is effectively Windows-only; Linux + PowerShell 7 (our NFR-4
target) is _not_ a working host for the full engine today. Only the _export_ and
_offline reporting_ layer is plausibly cross-platform.** The reasoning, from
primary sources:

### 3.1 M365DSC's apply/monitor is DSC 1.1 + the LCM

M365DSC's documented apply and monitor flow uses **`Start-DscConfiguration`**, the
**LCM**, and the LCM's built-in 15-minute consistency check [7][9]. That machinery
is the **DSC 1.1** engine. Microsoft removed it from the cross-platform successor:
in **DSC 2.0** (the version shipped for PowerShell 7.2+), the following are
**removed** — `Start-DscConfiguration`, `Test-DscConfiguration`,
`Get-DscConfiguration`, `Set-DscLocalConfigurationManager`, `Publish-`/`Restore-`/
`Update-DscConfiguration` — **along with "the pull server" and "the local
configuration manager (LCM)"** [17]. DSC 2.0 states plainly: "The only way to use
DSC Resources in 2.0 is with the `Invoke-DscResource` cmdlet or Azure machine
configuration," and "If you aren't using Azure machine configuration, you should
use DSC 1.1" [17].

**Consequence:** the cmdlets M365DSC's apply/monitor depend on **do not exist**
in the PowerShell-7-native DSC module. On Windows, PowerShell 7 can still reach
the DSC 1.1 LCM by delegating into Windows PowerShell 5.1 (the compat shim), so
apply/monitor works **on Windows** under pwsh 7. On **Linux there is no Windows
PowerShell and no LCM**, so `Start-DscConfiguration` and the consistency check
have nothing to run against. **[VERIFIED]** that the LCM is absent from DSC 2.0/
PS7; **[LIKELY]** that this makes M365DSC apply/monitor unavailable on Linux.

### 3.2 DSC v3 does not rescue this

DSC **v3** is cross-platform ("works on Linux, macOS, and Windows") and can invoke
classic PSDSC resources [18] — which sounds promising — but it "no longer includes
or supports the Local Configuration Manager (LCM)" and "isn't compatible with MOF
files"; configuration documents are JSON/YAML instead [18]. So DSC v3 removes the
_exact_ two things M365DSC's apply relies on (the LCM and MOF). M365DSC would need
substantial re-architecture to target DSC v3; it does not today [18][9]. DSC v3 is
therefore **not** a near-term path to running M365DSC on Linux.

### 3.3 M365DSC's own PowerShell-7 guidance is Windows-shaped

M365DSC "supports running PowerShell 7+" but with prerequisites that betray a
Windows assumption [2][2b]:

- Install is expected via **Windows PowerShell 5.1** first, then "flip to
  PowerShell 7+ once the prerequisite modules are properly installed" [2b].
- "Microsoft365DSC currently requires dependencies to be installed under the
  `C:\Program Files\WindowsPowerShell\Modules` folders" [2b] — a Windows path.
- **PnP.PowerShell** "needs to be loaded using Windows PowerShell … using the
  `-UseWindowsPowerShell` switch, and requires the modules to be located under
  `C:\Program Files\WindowsPowerShell`" [2b]. `-UseWindowsPowerShell` is a
  Windows-only compatibility shim (it proxies to a Windows PowerShell 5.1
  process); it cannot work on Linux.
- "Starting with PowerShell 7.2, the core Desired State Configuration module
  (PSDesiredStateConfiguration) has been decoupled … and now needs to be
  installed separately" [2b] — and that separate module is the LCM-less DSC 2.0
  (§3.1).

Every OS-specific reference in that page targets Windows; **Linux/macOS are not
mentioned as supported** [2][2b].

### 3.4 Empirically, the module fails to load on Linux today

A user on **RHEL 9.1 / PowerShell 7.3.3** reported that `Microsoft365DSC` installs
but **fails to import** with "The given assembly name was invalid"; the issue is
labelled *Core Engine* / *Pending Information* and shows no resolution [14]. A
separate report shows **`Update-M365DSCDependencies` breaking on PowerShell Core**
(macOS): it looks for module files under `netCore` paths / `.Format.ps1xml` that
don't exist on the Unix layout and errors during the unload/reload cycle [15]. And
the LCM export path assumes local admin ("Cannot export Local Configuration
Manager settings. This process isn't executed with Administrative Privileges!"),
another Windows/LCM-shaped assumption [16]. **[VERIFIED]** these reports exist and
are unresolved; they corroborate that a Linux + pwsh 7 host is not a working
target out of the box.

### 3.5 Runtime verdict

| Layer | Windows PS 5.1 | Windows + pwsh 7 | **Linux + pwsh 7 (our target)** |
|---|---|---|---|
| Install / dependencies | Works [2b][3] | Works (install via 5.1) [2b] | **Breaks today** [14][15] |
| **Export** (`Export-M365DSCConfiguration`) | Works | Works | **Unproven; blocked by import/PnP** [14][2b] |
| Compile → MOF | Works | Works | No LCM/DSC-1.1 target |
| **Apply** (`Start-DscConfiguration`) | Works [7] | Works via compat [7] | **Not available (no LCM)** [17] |
| **Monitor** (15-min LCM check) | Works [9] | Works via compat [9] | **Not available (no LCM)** [17][9] |
| **Offline delta report** | Works | Works | **Plausible (no LCM needed)** [10] |

**Bottom line for ADR-0002 / Q3:** running M365DSC as a full engine on our
preferred **Linux + pwsh 7** container is **not viable today**. A **Windows-based
container** (Windows PowerShell 5.1 present, or pwsh 7 with the Windows compat
shim) is the only host where the whole export→apply→monitor loop is known to
work — this is the "acceptable fallback" ADR-0002 anticipated, at real cost to
NFR-4 portability and image size (a Windows base image is multi-GB and cannot run
under a plain Linux Docker host without Windows containers).

---

## 4. Auth model vs ADR-0001

ADR-0001 fixes our auth to **interactive delegated (browser) + device code,
tokens memory-only, no secret on disk** (see sibling 04). M365DSC's supported auth
methods are a poor match.

### 4.1 What M365DSC supports

The documented authentication methods (per resource and for export) are [4][5]:

| Method | Parameters | Fits ADR-0001? |
|---|---|---|
| User credentials | `-Credential` (PSCredential) | ⚠️ **MFA not supported** for apply [4] |
| Service principal + secret | `-ApplicationId -TenantId -ApplicationSecret` | ❌ app-only; secret is a persisted-secret problem |
| Service principal + cert **thumbprint** | `-ApplicationId -TenantId -CertificateThumbprint` | ❌ app-only; private key in machine cert store (§5) |
| Service principal + cert **file** | `-ApplicationId -TenantId -CertificatePath -CertificatePassword` | ❌ app-only; PFX + password on disk |
| Managed identity | `-ManagedIdentity -TenantId` | ❌ Azure-hosted only |
| Access tokens | `-AccessTokens` (e.g. from `Get-AzAccessToken`) | ⚠️ token supplied externally |

**There is no device-code flow and no interactive-delegated browser flow** in the
documented method set [5]. This is the single biggest compatibility gap with
ADR-0001.

### 4.2 The MFA / unattended tension

M365DSC states its position explicitly: "Since Desired State Configuration is an
unattended process, the use of Multi-Factor Authentication for user credentials is
**not supported** by Microsoft365DSC. The only exception here is creating an
**Export** of an existing tenant. Most often this is an interactive process where
the ask for a second factor is possible" [4]. It "strongly recommends service
principal" auth because it is more granular and avoids "sending high-privileged
credentials across the wire" [4].

Read carefully, this means:

- **Export** can run interactively (a `-Credential` prompt that may satisfy MFA) —
  partially compatible with our interactive posture, but it is a
  username/password `PSCredential`, **not** the browser/device-code delegated flow
  ADR-0001 mandates, and on Linux a `PSCredential` SecureString is plaintext in
  memory (sibling 04 §8).
- **Apply / monitor** are "unattended" and therefore effectively require
  **app-only cert or secret** auth. Delegated interactive/device-code is **not a
  usable path for a full apply**.

### 4.3 Verdict (auth)

**M365DSC as an apply engine effectively requires app-only certificate auth**,
which ADR-0001 explicitly **defers** (Q5) and only permits if certs are
"runtime-supplied and never persisted." A certificate-thumbprint flow needs the
private key present in a machine/user cert store for the LCM to use during the
15-minute checks (§5) — i.e. a long-lived credential at rest, which collides with
FR-3/NFR-1. **[VERIFIED]** no device-code/interactive-delegated method exists;
**[VERIFIED]** apply is documented as unattended/app-only. Adopting M365DSC as the
apply engine would force us to **re-open ADR-0001** for app-only cert auth. This
is exactly the "risk to reconcile" ADR-0001 flagged.

---

## 5. MOF & credential handling vs no-persisted-secrets

DSC's MOF model is fundamentally at odds with NFR-1 ("credentials/tokens are never
written to disk, logs, profiles, or telemetry") and FR-3.

### 5.1 What lands on disk

| Artifact | Contains | On disk? |
|---|---|---|
| Exported `.ps1` blueprint | Configuration; **may embed secrets** unless `-TokenReplacement`/app-only used | Yes (`-Path`) [6] |
| `ConfigurationData.psd1` | Node data, cert-file reference | Yes [8] |
| Compiled **`localhost.mof`** | Full desired state **including credentials** | Yes [7][8] |
| `M365DSC.cer` (if secured) | Public encryption cert | Yes [8] |
| Machine cert store private key (cert-thumbprint auth) | The app's private key | Yes (cert store) |

### 5.2 Plaintext-by-default, cert-encryption as the only mitigation

By default, when credentials are used, "these credentials will be stored as **plain
text in the resulting MOF file**, which is a big security concern" [8]. This is
the classic DSC `PSDscAllowPlainTextPassword` behaviour. The only supported
mitigation is **certificate encryption**: `Set-M365DSCAgentCertificateConfiguration`
"automatically generates an encryption certificate and configures the PowerShell
DSC engine (LCM) on the system to use it," writes an `M365DSC.cer`, updates
`ConfigurationData.psd1` to reference it, and thereafter encrypts credentials in
the MOF [8]. Note that this mitigation **configures the LCM** — i.e. it is
**Windows-only** (§3) and produces **more** on-disk artifacts (a cert), not fewer.

Independently, DSC 2.0 lists "Using credentials in DSC Configuration blocks" as an
**unsupported** feature [17], underlining that the credential-in-MOF pattern is a
DSC-1.1-era construct with no clean forward path.

### 5.3 Verdict (MOF/credentials)

Even in its "secure" configuration, M365DSC's model requires **either** an
encrypted-but-decryptable MOF on disk plus a decryption cert in the machine store,
**or** app-only cert-thumbprint auth with a private key resident in the cert store
for unattended re-checks. **Both leave a decryptable credential at rest**, which is
a **direct conflict with NFR-1/FR-3**. Our credential-cleanup routine (sibling 04
§5) would additionally have to scrub MOFs, `ConfigurationData.psd1`, `M365DSC.cer`,
exported `.ps1` blueprints, and the cert store — a materially larger and more
error-prone attack surface than the memory-only Graph/EXO token model in 04.
**[VERIFIED]** plaintext-by-default and cert-encryption mechanics.

> Mitigating stance if adopted: run **export-only** with app-registration
> cert auth where the cert is **injected at runtime into an ephemeral, tmpfs-backed
> store** and wiped on teardown (sibling 04 §6.3), never compile a MOF that embeds
> a `-Credential`, and treat the exported `.ps1` as config-only after scrubbing
> secret-bearing properties. This shrinks — but does not eliminate — the conflict.

---

## 6. Drift detection & remediation fit (FR-8/FR-10/FR-11)

M365DSC offers **two distinct** drift mechanisms with very different runtime and
determinism profiles.

### 6.1 LCM-based test/monitor (Windows-only)

- **`Test-DscConfiguration`** asks the LCM whether the node is in desired state
  (boolean; `-Detailed` lists in/out-of-state resources). It is a **drift check**,
  not a property-level preview of the changes an apply would make.
- **Monitoring mode:** after an apply, the LCM "wakes every 15 minutes" and
  re-checks the tenant; drift is written to the **Windows Event Viewer** `M365DSC`
  log with per-component / per-property detail [9]. The `ConfigurationMode`
  governs behaviour: `ApplyAndMonitor` (log only) vs **`ApplyAndAutoCorrect`**
  ("automatically … fix a detected drift and bring the tenant back into its
  desired state") [9].
- All of this requires the **LCM** → **Windows-only** (§3), and the Event-Viewer
  sink is Windows-only, which is awkward for our structured, retrievable audit-log
  requirement (NFR-5) and cross-platform readability (NFR-9).

### 6.2 Offline delta report (cross-platform)

`New-M365DSCDeltaReport` compares two exported `.ps1` files and emits an HTML diff
of missing/additional/different items, with `-DriftOnly` — **no LCM, no live
connection during report generation** [10]. Combined with a fresh
`Export-M365DSCConfiguration` of the live tenant, this yields a
**export-current → diff-against-blueprint** flow that is essentially the same
`Get → normalize → diff → render` pattern sibling 01 §6 concluded we must build
ourselves anyway. It maps cleanly onto **FR-8 dry-run** and **FR-10 drift**, and
is the one drift feature that could run on Linux.

### 6.3 How "dry-run" maps onto DSC semantics

DSC has no true server-side "what-if" (mirroring the Graph `-WhatIf` gap in
sibling 01 §6). The honest mapping is:

| Our need | Best DSC mapping | Caveat |
|---|---|---|
| **FR-8 dry-run preview** | export live → `New-M365DSCDeltaReport` vs blueprint | offline diff, cross-platform [10] |
| **FR-10 drift scan** | same delta report, or LCM `Test` (Windows) | delta report has known false-positive bugs [10] |
| **FR-11 deterministic remediation** | `Start-DscConfiguration` re-apply (idempotent per-resource `Set`) | LCM/Windows; ordering not strongly deterministic |

### 6.4 Determinism caveats

Remediation determinism depends on each resource's `Test`/`Set` being correct.
There are **documented false-drift bugs** in the delta/compare path — e.g.
resources reported as different because of differing `ResourceID`s, or CA-policy
exclusions/multiple-assignment cases producing spurious "different" / "no
discrepancies" results [10]. M365DSC exports also do not generally emit
cross-resource `DependsOn`, so apply ordering (e.g. security-defaults-off before
CA policies, named-locations before CA — sibling 01 §7) is **not** guaranteed the
way our own ordered apply plan would guarantee it. **[LIKELY]** M365DSC meets
FR-11 "idempotent per resource" but **not** our stronger "deterministic, ordered,
previewable" bar without extra work.

---

## 7. Dependency footprint (NFR-3)

The current pinned dependency manifest (`Dependencies/Manifest.psd1`, Dev branch)
lists **14 modules** [11]:

| Module | Pinned version | Purpose |
|---|---|---|
| Az.Accounts | 5.3.2 | Azure auth/context |
| Az.ResourceGraph | 1.2.1 | Azure resource queries |
| Az.Resources | 9.0.1 | Azure resource mgmt |
| Az.Subscription | 0.12.0 | Subscription APIs |
| Az.Security | 1.8.0 | Defender for Cloud |
| Az.SecurityInsights | 3.2.1 | Sentinel |
| DSCParser | 3.0.0.5 | Parse DSC `.ps1` (delta report) |
| ExchangeOnlineManagement | 3.9.2 | EXO / Defender for O365 (see sibling 02) |
| Microsoft.Graph.Authentication | 2.35.1 | Graph auth + `Invoke-MgGraphRequest` |
| MicrosoftTeams | 7.6.0 | Teams |
| MSCloudLoginAssistant | 1.1.71 | Unified sign-in across workloads |
| PnP.PowerShell | 1.12.0 | SharePoint/OneDrive (Windows compat, §3) |
| ReverseDSC | 2.0.0.34 | Export engine |
| PSParallelPipeline | 1.2.5 | Parallel extraction |

Notable, and **better than folklore suggests**: current M365DSC depends on only
**`Microsoft.Graph.Authentication`** (not the ~30–40 Graph sub-modules that
sibling 01 §2.2 flagged as a 947 MB footprint) — it calls Graph via
`Invoke-MgGraphRequest`/REST rather than the per-workload SDK modules [11]. The
older docs still say M365DSC pulls "a dozen Microsoft Graph PowerShell modules"
[3]; that is **stale** relative to the pinned manifest [11]. **[VERIFIED]** the
14-module manifest; **[UNVERIFIED — prove in container]** the total on-disk size
(the `Microsoft365DSC` module itself carries thousands of resources and is large;
plus Az.* + Teams + PnP + EXO). Measure it in the proof.

**Against NFR-3:** 14 pinned transitive modules (several unrelated to our MVP —
Teams, PnP, Az.SecurityInsights, PowerApps) plus the giant M365DSC module is
**far** heavier than the **4-module** Graph slice sibling 01 §2.3 recommends
(`Authentication` + `Identity.SignIns` + `Security` + `DirectoryManagement`) plus
`ExchangeOnlineManagement`. M365DSC does **not** support installing only the
resources we use — the module ships monolithically. Pinning is well-supported
(`Update-M365DSCDependencies` reads the manifest and installs exact versions;
`Update-M365DSCModule` upgrades the set) which helps **NFR-7**, but the sheer
count works against **NFR-3**.

---

## 8. Resource coverage for the MVP baseline

Coverage for our ADR-0003 security-baseline areas is **strong** — this is
M365DSC's home turf. Verified resource mappings:

| MVP baseline area (ADR-0003) | M365DSC resource(s) | Verified |
|---|---|---|
| Conditional Access | `AADConditionalAccessPolicy` (DisplayName/State/BuiltInControls/ClientAppTypes/Include-Exclude Users·Groups·Roles·Apps/AuthenticationStrength) | [12] |
| Authentication methods | `AADAuthenticationMethodPolicy` + per-method (`…Authenticator/Email/Fido2/Sms/Software/Temporary/Voice/X509`) | [1] |
| Tenant user/consent settings | `AADAuthorizationPolicy` | [1] |
| Anti-spam (EOP) | `EXOHostedContentFilterPolicy` (+ rule) | [13] |
| Anti-phishing | `EXOAntiPhishPolicy` (+ rule) | [1] |
| Anti-malware | `EXOMalwareFilterPolicy` | [1] |
| Safe Links | `EXOSafeLinksPolicy` (+ rule) | [1] |
| Safe Attachments | `EXOSafeAttachmentPolicy` (+ rule) | [1] |
| Defender / Sentinel | Defender + Sentinel workloads listed | [1] |

Two observations tying back to siblings:

1. The `AADConditionalAccessPolicy` resource is **keyed by `DisplayName`** [12] —
   exactly the name-as-identity model sibling 01 §7 and 02 identified, and the
   reason **FR-7 name-remapping** exists. M365DSC would inherit the same
   match-by-name idempotency behaviour we would have to build ourselves.
2. The EXO resources wrap the same policy+rule cmdlet pairs sibling 02 catalogued;
   note sibling 02 §TL;DR's caveat that **Security & Compliance PowerShell is not
   available on Linux** — reinforcing §3 here.

**Verdict:** resource coverage is **not** a blocker; if M365DSC were viable on our
runtime with compatible auth, it would cover the MVP baseline with essentially no
custom resource work. The blockers are runtime (§3), auth (§4), and credentials
(§5) — not coverage.

---

## 9. Recommendation & container strategy

**Decision-grade recommendation for ADR-0002: do NOT adopt Microsoft365DSC as the
primary _apply_ engine for the MVP. Move ADR-0002 toward _reject-as-primary-engine_,
and instead adopt the "custom Graph/EXO engine that reuses DSC concepts" fallback
that ADR-0002 already names — while _selectively reusing_ M365DSC's export and
offline-diff tooling where it is cheap and cross-platform.**

Rationale, weighted:

1. **Runtime (NFR-4) is the hard blocker.** The apply/monitor loop needs the DSC
   1.1 LCM, which is Windows-only; DSC 2.0/PS7 removed it and DSC v3 abandons
   MOF+LCM entirely [17][18]. Our stated target is **Linux + pwsh 7**; M365DSC
   would force a **Windows container** (ADR-0002's "acceptable fallback"),
   sacrificing portability and multiplying image size. Even the export layer is
   currently broken to import on Linux [14][15].
2. **Auth (ADR-0001) conflicts.** No device-code / interactive-delegated apply
   path; apply is app-only-cert in practice [4][5]. Adopting M365DSC re-opens a
   settled decision.
3. **Credentials/MOF (NFR-1) conflict.** Plaintext-by-default MOFs; the only
   mitigation adds a decryptable cert on disk and an LCM config [8][17].
4. **Coverage is great, but coverage is not the binding constraint** (§8).

### 9.1 What we should reuse from M365DSC (optional, low-commitment)

- **`Export-M365DSCConfiguration`** as a *seed* for building known-good baseline
  profiles during authoring (run once, on a trusted Windows box, to bootstrap our
  own profile schema). It is not on the runtime hot path, so its Windows-ness is
  tolerable.
- **`New-M365DSCDeltaReport`** semantics as a *design reference* for our own diff
  renderer — it is offline and cross-platform [10] and validates the
  export→diff→render approach sibling 01 §6 already prescribes.

### 9.2 Recommended container strategy (Q3)

- **Primary:** a **single Linux + PowerShell 7** one-shot container running our
  **custom Graph/EXO engine** (`Microsoft.Graph.*` slice per sibling 01 §2.3 +
  `ExchangeOnlineManagement` per 02), device-code auth + memory-only tokens per
  ADR-0001/04. This satisfies NFR-3/NFR-4/NFR-1 cleanly.
- **Optional Windows side-container (authoring only):** if we want M365DSC export
  as a profile seed, isolate it in a throwaway **Windows** container used **only**
  at authoring time, never in the operator apply path — keeping the Windows/LCM/
  MOF concerns off the production runtime.

### 9.3 If the owner still wants M365DSC as the engine

Then ADR-0002 must accept its consequences explicitly: (a) a **Windows** container
base (NFR-4 exception), (b) **re-open ADR-0001** for runtime-injected **app-only
cert** auth, (c) an expanded cleanup routine covering MOF/cert/blueprint/cert-store
(NFR-1), and (d) a heavier dependency set (NFR-3 exception). All four should be
weighed against the custom engine's modest extra build cost. The owner's past
difficulty running M365DSC (per ADR-0002 context, "mostly via a Parallels VM on
macOS") is consistent with §3's finding that it is Windows-bound — a clean Windows
container would help, but does not remove the auth/credential conflicts.

---

## 10. Open questions / risks (what the container proof must verify)

The hands-on container proof ADR-0002 requires should treat these as its test
matrix. Each is a claim I could **not** fully verify from documentation alone.
A runnable harness for exactly this matrix lives at
[`spikes/03-microsoft365dsc-container-proof/`](../../spikes/03-microsoft365dsc-container-proof/).

| # | Question / risk | How to prove |
|---|---|---|
| R1 | **Does `Export-M365DSCConfiguration` run at all on Linux + pwsh 7?** #3144 says import fails today [14]. | In a Linux/pwsh7 container, `Import-Module Microsoft365DSC` then export a single AAD component; capture the exact failure or success. |
| R2 | **Can any _apply_ happen on Linux** (e.g. via `Invoke-DscResource` rather than `Start-DscConfiguration`)? DSC 2.0 keeps `Invoke-DscResource` [17]; unclear if M365DSC resources work through it headless. | Attempt `Invoke-DscResource -Method Set` against one M365DSC resource on Linux; record result. |
| R3 | **Total on-disk footprint** of `Microsoft365DSC` + the 14 deps [11]. | `Measure` the module tree size in the built image; compare to the ~5-module custom slice. |
| R4 | **Does the pinned Graph dependency really stay at `Microsoft.Graph.Authentication` only** [11], or do resources pull more Graph modules at runtime? | Inventory loaded modules after an export. |
| R5 | **Cert-thumbprint auth without a persisted key** — can the LCM re-check every 15 min if the cert lives only in an ephemeral/tmpfs store? | Test app-only cert auth with a runtime-injected cert; verify whether monitoring survives, and what remains on disk. |
| R6 | **MOF contents under app-only auth** — does a compiled MOF still embed any secret when no `-Credential` is used (only thumbprint)? [8] | Compile a MOF with cert-thumbprint auth; grep the MOF for secrets/thumbprints. |
| R7 | **Delta-report false positives** for our exact baseline resources (CA exclusions, multi-assignment) [10]. | Export twice with no change; confirm a clean "no discrepancies" for AAD CA + EXO policies. |
| R8 | **Windows container size/licensing** if the fallback is chosen. | Build a Windows-base image; record size and base-image licensing constraints. |
| R9 | **Version drift** — the manifest/versions here are the **Dev branch** [11] and release line **v1.26.x** [19]; pin and re-verify against the exact shipped version (NFR-7). | Snapshot `Manifest.psd1` from the pinned release, not Dev. |

---

## 11. Sources

Official Microsoft365DSC docs (`microsoft365dsc.com`), the
`microsoft/Microsoft365DSC` GitHub repo, and Microsoft Learn. All pages fetched
2026-07-22 unless noted. Community pages are labelled as such (none load-bearing
here).

1. What is Microsoft365DSC? (workloads; export/deploy/monitor; drift actions) —
   https://microsoft365dsc.com/home/what-is-M365DSC/
2. PowerShell 7+ Support (rendered) —
   https://microsoft365dsc.com/user-guide/get-started/powershell7-support/
   - 2b. PowerShell 7+ Support (raw, Dev branch — verbatim quotes: Windows PS 5.1
     to install, `C:\Program Files\WindowsPowerShell\Modules`, PnP
     `-UseWindowsPowerShell`, PSDesiredStateConfiguration decoupled at 7.2) —
     https://raw.githubusercontent.com/microsoft/Microsoft365DSC/Dev/docs/docs/user-guide/get-started/powershell7-support.md
3. How to Install (prereqs; `Update-M365DSCDependencies` /
   `Update-M365DSCModule`; legacy "a dozen Graph modules" note) —
   https://microsoft365dsc.com/user-guide/get-started/how-to-install/
4. Authentication and Permissions (MFA not supported for credentials except
   export; service-principal recommendation) —
   https://microsoft365dsc.com/user-guide/get-started/authentication-and-permissions/
5. Authentication Examples (6 methods; no device-code/interactive-delegated) —
   https://microsoft365dsc.com/user-guide/get-started/authentication-examples/
6. Export-M365DSCConfiguration (ReverseDSC entry point; params; `.ps1` output;
   `-TokenReplacement`) —
   https://microsoft365dsc.com/user-guide/cmdlets/Export-M365DSCConfiguration/
7. Deploying Configurations (compile `.ps1` → `localhost.mof`;
   `Start-DscConfiguration`; LCM 15-min check) —
   https://microsoft365dsc.com/user-guide/get-started/deploying-configurations/
8. Securing your Compiled Configuration (plaintext creds in MOF by default;
   `Set-M365DSCAgentCertificateConfiguration`; `M365DSC.cer`) —
   https://microsoft365dsc.com/user-guide/get-started/securing-configurations/
9. Monitoring for Configuration Drifts (LCM every 15 min; Event Viewer `M365DSC`;
   `ApplyAndAutoCorrect`) —
   https://microsoft365dsc.com/user-guide/get-started/monitoring-drifts/
10. Comparing Configurations / `New-M365DSCDeltaReport` (offline HTML diff, no LCM;
    `-Source`/`-Destination`/`-OutputPath`/`-DriftOnly`; known false-positive
    issues #3544/#4796/#1815) —
    https://microsoft365dsc.com/user-guide/get-started/comparing-configurations/
11. Dependency manifest (Dev branch — 14 pinned modules; Graph = Authentication
    only) —
    https://raw.githubusercontent.com/microsoft/Microsoft365DSC/Dev/Modules/Microsoft365DSC/Dependencies/Manifest.psd1
12. Resource: AADConditionalAccessPolicy (params; keyed by DisplayName; auth
    methods) — https://microsoft365dsc.com/resources/azure-ad/AADConditionalAccessPolicy/
13. Resource: EXOHostedContentFilterPolicy (anti-spam params; auth methods) —
    https://microsoft365dsc.com/resources/exchange/EXOHostedContentFilterPolicy/
14. Issue #3144 — "PowerShell 7 Linux (RHEL 9.1) — not able to load module
    microsoft365dsc" ("given assembly name was invalid"; Core Engine / Pending
    Information; unresolved) —
    https://github.com/microsoft/Microsoft365DSC/issues/3144
15. Issue #5601 — "Update-M365DSCDependencies broken on PowerShell core" (Unix
    `netCore`/`.Format.ps1xml` path failures) —
    https://github.com/Microsoft365DSC/Microsoft365DSC/issues/5601
16. Issue #4010 — LCM export requires admin privileges warning (Windows/LCM-shaped
    assumption) — https://github.com/microsoft/Microsoft365DSC/issues/4010
17. Desired State Configuration 2.0 (LCM, `Start-`/`Test-DscConfiguration` etc.
    removed; only `Invoke-DscResource`; credentials-in-config unsupported; use DSC
    1.1 otherwise) — https://learn.microsoft.com/en-us/powershell/dsc/overview?view=dsc-2.0
18. Announcing Microsoft DSC v3.0 (no LCM; not MOF-compatible; cross-platform; can
    invoke classic PSDSC resources; JSON/YAML documents) —
    https://devblogs.microsoft.com/powershell/announcing-dsc-v3/
19. PowerShell Gallery — Microsoft365DSC (release line v1.26.x observed July 2026)
    — https://www.powershellgallery.com/packages/Microsoft365DSC/

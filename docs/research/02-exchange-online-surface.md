# Research 02 — Exchange Online Management (EXO) configuration surface

> **Purpose.** Map the configurable surface of the `ExchangeOnlineManagement`
> PowerShell module — including the Microsoft Defender for Office 365 email
> policies that are managed *through* EXO — so we can model it as reusable
> profiles with dry-run, drift detection, and deterministic remediation.
>
> **Audience.** Design/build of m365-configurator. Read alongside
> [`REQUIREMENTS.md`](../REQUIREMENTS.md) (esp. FR-4, FR-5, FR-7, FR-8, FR-10,
> FR-11, NFR-1, NFR-7) and [`OPEN-QUESTIONS.md`](../OPEN-QUESTIONS.md) (Q4 auth,
> Q6 MVP surface, Q7 DSC).
>
> **Status.** Research only. No tenant was contacted; every claim is cited to
> Microsoft Learn. Cmdlet *behaviour* is stable, but exact parameter *lists*
> drift release-to-release — pin the module version (NFR-7) and re-verify
> parameters against the pinned version before shipping.
>
> **Date.** 2026-07-22. Module facts reflect EXO module **v3.x** (V3 / "EXO V3").

---

## TL;DR — what matters for our design

1. **One module, REST-backed, Linux-friendly.** `ExchangeOnlineManagement` v3
   uses REST API connections for **all** cmdlets (since 2023); the old WinRM
   Remote PowerShell (RPS) transport is retired. It runs on **PowerShell 7 on
   Linux**, which fits our containerized tenet.
2. **Auth matches our decision.** `Connect-ExchangeOnline` supports interactive
   browser SSO (default in PS7) and **`-Device`** device code — both
   memory-only, MFA-capable, no secret on disk. `Disconnect-ExchangeOnline`
   tears the session down.
3. **The whole email-security baseline is one consistent pattern:** almost every
   protection is a **policy object (settings) + rule object (scoping/priority)**
   pair. Understanding this pairing is the single most important thing for our
   profile model and drift engine.
4. **Policies and rules are name-scoped, tenant-unique objects** — this is
   exactly what FR-7 "name remapping" exists for. Names are also the join key
   between a policy and its rule, and the identity we diff against.
5. **`-WhatIf` is nearly universal** on write cmdlets (great for FR-8 dry-run),
   with a few notable exceptions (e.g. `Set-ExternalInOutlook`). `Get-*` cmdlets
   are read-only (safe for FR-10 drift scans).
6. **Big caveat for Linux containers:** Security & Compliance PowerShell
   (`Connect-IPPSSession`) is **not available on Linux or macOS** in PS7. The
   email-security baseline lives in *Exchange Online* PowerShell (Linux OK), but
   DLP / retention / sensitivity labels / audit-retention policies live in S&C
   and would need Windows. Scope the MVP (Q6) around EXO-native surface.

---

## 1. The `ExchangeOnlineManagement` module

### 1.1 What it is

The module (a.k.a. **EXO V3** since 2022) is the single supported way to reach
all Exchange cloud PowerShell endpoints: **Exchange Online PowerShell**,
**Security & Compliance PowerShell**, and PowerShell for the built-in security
add-on for on-premises mailboxes. It uses modern authentication and works with
or without MFA. [[about-module]]

**REST API connections for all cmdlets since 2023.** Every cmdlet now runs over
REST instead of the legacy WinRM Remote PowerShell (RPS) runspace. Benefits
called out by Microsoft: [[about-module]]

- **More secure** — built-in modern auth, no dependence on a remote PowerShell
  runspace, and **no Basic auth in WinRM** required on the client.
- **More reliable** — transient network/large-query failures use built-in retries.
- **Better performance** — no PowerShell runspace to set up.

REST cmdlets keep the **same names and parameters** as their historical RPS
counterparts, so scripts don't change. Two consequences for us:

- `Invoke-Command` does **not** work over REST connections (workarounds exist). [[about-module]]
- REST cmdlets have a **15-minute timeout**, which can bite bulk operations
  (batch large writes). [[about-module]]
- `-UseRPSSession` still appears in `Connect-ExchangeOnline` syntax, but RPS as a
  transport is retired — treat REST as the only mode. [[connect-syntax]]

Three cmdlet "flavours" coexist, per Microsoft's own comparison: [[about-module]]

| Flavour | Security | Performance | Reliability | Functionality |
| --- | --- | --- | --- | --- |
| Remote PowerShell cmdlets (legacy) | Least secure | Low | Least reliable | All params/props |
| `Get-EXO*` cmdlets (9 optimized) | Highly secure | High | Highly reliable | **Limited** params/props |
| REST API cmdlets (default) | Highly secure | Medium | Highly reliable | All params/props |

> **Design note.** The nine `Get-EXO*` cmdlets (`Get-EXOMailbox`,
> `Get-EXORecipient`, `Get-EXOCasMailbox`, `Get-EXOMailboxPermission`,
> `Get-EXORecipientPermission`, `Get-EXOMailboxStatistics`,
> `Get-EXOMailboxFolderStatistics`, `Get-EXOMailboxFolderPermission`,
> `Get-EXOMobileDeviceStatistics`) are for **bulk recipient reads**, not for the
> policy surface below. Our security-baseline drift scans use the regular
> `Get-*Policy` / `Get-*Rule` cmdlets, which expose **all** properties — which is
> what we need for faithful diffing. [[about-module]]

### 1.2 Connecting — the auth methods that matter to us (Q4)

`Connect-ExchangeOnline` creates the session. The methods relevant to our
"delegated interactive + device code, memory only" decision: [[connect-cmdlet]] [[connect-steps]]

| Method | Command (illustrative) | Notes for us |
| --- | --- | --- |
| **Interactive browser SSO** | `Connect-ExchangeOnline -UserPrincipalName adam@contoso.com` | Default in PS7 — opens the system browser for SSO/MFA. REST mode, no WinRM Basic auth. [[connect-steps]] |
| **Device code** | `Connect-ExchangeOnline -Device` | Prints a URL + code to enter on any device with a browser. Intended for hosts **without** a browser (our Linux container). Completes via normal Entra flow. **Primary auth path for the container.** [[connect-cmdlet]] |
| Inline credential | `Connect-ExchangeOnline -InlineCredential` | Prompts in the PS window; only for accounts scenario — avoid (encourages secret handling). [[connect-cmdlet]] |
| App-only (cert) | `-AppId -Certificate*/-CertificateThumbprint` | Unattended; needs a certificate. Out of MVP per our auth decision, but relevant to Q5 later. [[connect-syntax]] |
| Managed identity | `-ManagedIdentity` | Azure-hosted only; not our deployment model. [[connect-syntax]] |

Key selected `Connect-ExchangeOnline` parameters worth knowing: [[connect-syntax]]

- `-ExchangeEnvironmentName` — sovereign/gov clouds (e.g. `O365GermanyCloud`).
- `-CommandName <String[]>` — **load only the cmdlets we need**. Microsoft
  recommends this to avoid a memory leak when connecting/disconnecting
  repeatedly, and it speeds up connect. Directly useful for our
  connect/disconnect-per-action lifecycle (FR-2). [[about-module]]
- `-ShowBanner:$false`, `-SkipLoadingFormatData`, `-SkipLoadingCmdletHelp` —
  quieter/faster startup for scripted use.
- `-LogDirectoryPath`, `-LogLevel`, `-EnableErrorReporting` — client-side
  connection logging (useful for our audit story, but see NFR-1: make sure these
  logs never capture tokens; they're connection diagnostics, not secrets). [[about-module]]
- `-Prefix` — namespaces imported cmdlet nouns (e.g. `Get-EXOContoso...`);
  avoid unless we deliberately want isolation, since it changes cmdlet names.

**Session lifecycle & credential cleanup (NFR-1, NFR-3):**

- `Disconnect-ExchangeOnline` closes the session. [[about-module]]
- `Get-ConnectionInformation` replaces `Get-PSSession` for REST connections —
  use it to enumerate/verify active connections (e.g. confirm teardown). [[about-module]]
- The EXO module holds tokens **in memory** for the session; there is no
  documented on-disk credential cache for interactive/device-code flows, which
  aligns with NFR-1. We must still verify no token leaks into our own logs.

### 1.3 Platform support (containerized/Linux tenet, NFR-4)

Officially supported on **PowerShell 7 on Windows, Linux, and macOS**. Module
version is tied to PowerShell version by .NET assembly dependency — **this is a
version-pinning input (NFR-7)**: [[about-module]] [[about-module-os]]

| EXO module version | Requires PowerShell | .NET |
| --- | --- | --- |
| 3.10.0 (Jun 2026) or later | 7.6.0 (Mar 2026) or later | .NET 10.0 |
| 3.5.0 (May 2024) – 3.9.2 (Jan 2026) | 7.4.0 (Nov 2023) or later | .NET 8.0 |
| 3.0.0 (Sep 2022) – 3.4.0 (Oct 2023) | 7.2.0 – 7.3.7 | .NET 6.0 |

Linux specifics (Ubuntu 24.04 LTS example): 3.10.0+ → PS 7.6.0+; 3.5.0–3.9.2 →
PS 7.4.0+; 3.0.0–3.4.0 → PS 7.2.0–7.3.7. Behind a proxy on Linux, use module
**3.0.0 or later**. [[about-module-os]]

> **Critical Linux constraint.** `Connect-IPPSSession` — and therefore **Security
> & Compliance PowerShell** — is **not available in PowerShell 7 on Linux or
> macOS**. [[about-module-os]] The email-security baseline (anti-phish, anti-spam,
> anti-malware, Safe Links/Attachments, transport rules, DKIM, org config) all
> lives in **Exchange Online** PowerShell and works on Linux. But DLP,
> sensitivity labels, retention, and audit-*retention* policies live in **S&C**
> and would require Windows. This bounds our containerized MVP to the EXO-native
> surface (feeds Q6).

### 1.4 Footprint & dependencies (minimal-deps tenet, NFR-3)

- The module is installed from the **PowerShell Gallery**
  (`Install-Module ExchangeOnlineManagement`), consistent with NFR-2's single
  allowed egress for module install.
- REST connections **require the `PowerShellGet` and `PackageManagement`
  modules**. [[about-module]] Bundle/verify these in the container image.
- The module carries native .NET assemblies (hence the PS/.NET version coupling
  above) — the image must match the module's expected runtime.
- Recommendation: **pin `ExchangeOnlineManagement` to an exact version** and pin
  the matching PowerShell 7 base image; treat upgrades as deliberate, tested
  events (NFR-7).

---

## 2. The **policy + rule** pairing model (read this before modelling profiles)

Nearly every email protection in EOP/Defender is **two objects** in PowerShell,
even though the Defender portal presents them as one: [[antiphish-mdo]] [[antispam-configure]]

- **Policy object** — *the settings*: what protections are on, actions, thresholds.
- **Rule object** — *the scoping*: **priority** + recipient filters (who it
  applies to) + enabled/disabled state, and it **names the policy it binds to**.

What the portal hides but PowerShell exposes: [[antiphish-mdo]]

- Creating a "policy" in the portal actually creates **both** a rule and a policy
  **with the same name**.
- Editing in the portal splits automatically: name / priority / enabled /
  recipient filters → the **rule**; everything else → the **policy**.
- Deleting in the portal removes **both** at once.

In PowerShell you do it explicitly, and the ordering/coupling rules bite:

1. **Create policy first, then the rule** that references it by name. [[antiphish-mdo]]
2. A rule binds to **exactly one** policy; a policy can exist **unassociated**
   (invisible in the portal until a rule points at it). [[malware-newpolicy]]
3. **Remove is not cascading in PowerShell:** removing a policy does **not**
   remove its rule, and vice-versa. Orphaned rules/policies are harmless but
   confusing — clean up both. [[antispam-configure]] [[antiphish-eop]]
4. Enable/Disable is done on the **rule** (`Enable-/Disable-*Rule`), and that
   enables/disables the whole policy. [[antispam-configure]]

### 2.1 Default policies are special

Every category has a **default policy** that: applies to everyone, always has
the unmodifiable priority **`Lowest`**, has **no associated rule**, and **can't
be deleted**. You can only *modify* it. The `-MakeDefault` switch (on the `Set-`
policy cmdlet) promotes a custom policy to default — **PowerShell-only**. [[antiphish-eop]] [[antispam-configure]] [[malware-configure]]

> **Drift implication.** The default policy has no rule, so our model must treat
> "default policy" as a first-class, rule-less shape — don't assume every policy
> has a matching rule.

### 2.2 You cannot rename a policy

`Set-*Policy` cmdlets have **no `-Name` parameter**. When you "rename a policy"
in the portal you're only renaming the **rule**. Policies are renamed only by
recreate. [[antiphish-eop]] [[antispam-configure]] [[safeattach-configure]]

> **Name-remapping implication (FR-7).** See §5 — this is why remapping has to be
> done at *create* time, and why policy identity ≠ freely mutable.

---

## 3. Security-baseline areas — cmdlet map

Master table. All `New-*`/`Set-*`/`Remove-*`/`Enable-*`/`Disable-*` cmdlets are
Exchange write cmdlets and support **`-WhatIf` and `-Confirm`** (verified in
syntax for the representative cmdlets cited; see §4). `Get-*` are read-only.

| Area | Policy cmdlets | Rule cmdlets | `-WhatIf`? | Notes |
| --- | --- | --- | --- | --- |
| **Preset security policies** (Standard/Strict) | *(managed via rules)* | `Get/Enable/Disable-EOPProtectionPolicyRule`, `Get/Enable/Disable-ATPProtectionPolicyRule` | Yes | Turnkey MS-recommended baseline. Enable = enable the rule(s). [[preset]] [[enable-eop]] |
| **Anti-phishing** | `Get/New/Set/Remove-AntiPhishPolicy` | `Get/New/Set/Remove/Enable/Disable-AntiPhishRule` | Yes | Spoof, impersonation, mailbox intelligence, DMARC honoring. [[antiphish-mdo]] [[antiphish-eop]] |
| **Anti-spam (inbound)** | `Get/New/Set/Remove-HostedContentFilterPolicy` | `Get/New/Set/Remove/Enable/Disable-HostedContentFilterRule` | Yes | Spam/bulk actions, BCL threshold, ASF, quarantine tags. [[antispam-configure]] |
| **Anti-spam (outbound)** | `Get/New/Set/Remove-HostedOutboundSpamFilterPolicy` | `Get/New/Set/Remove/Enable/Disable-HostedOutboundSpamFilterRule` | Yes | Outbound limits, auto-forward control, notifications. **Sender** filters, not recipient. [[outbound-configure]] |
| **Anti-malware** | `Get/New/Set/Remove-MalwareFilterPolicy` | `Get/New/Set/Remove/Enable/Disable-MalwareFilterRule` | Yes | Common attachments filter, ZAP, notifications. [[malware-configure]] [[malware-newpolicy]] |
| **Safe Links** (Defender) | `Get/New/Set/Remove-SafeLinksPolicy` | `Get/New/Set/Remove/Enable/Disable-SafeLinksRule` | Yes | URL rewriting/detonation. Defender for Office 365 licence. [[safelinks-configure]] |
| **Safe Attachments** (Defender) | `Get/New/Set/Remove-SafeAttachmentPolicy` | `Get/New/Set/Remove/Enable/Disable-SafeAttachmentRule` | Yes | Detonation; Block/Allow/DynamicDelivery. Defender licence. [[safeattach-configure]] |
| **Transport / mail flow rules** | *(single object)* | `Get/New/Set/Remove/Enable/Disable-TransportRule` | Yes | **Not** the policy+rule split — one object with conditions/actions/priority. [[mailflow-manage]] [[mailflow-rules]] |
| **Organization config** | `Get/Set-OrganizationConfig` | — | Yes | Audit default, modern auth, MailTips, EWS, many org knobs. [[setorgconfig-syntax]] |
| **DKIM** | `Get/New/Set/Remove/Rotate-DkimSigningConfig` | — | Yes | Per-domain signing config; keyed by domain, not a free name. [[dkim-configure]] [[rotate-dkim]] |
| **Mailbox auditing** | `Get/Set-Mailbox` (`-AuditEnabled`, `-Audit*`), `Get/Set-OrganizationConfig` (`-AuditDisabled`) | — | Yes (`Set-Mailbox`) | Org default overrides per-mailbox on/off. [[audit-mailboxes]] |
| **Admin/mailbox audit search** | `Search-UnifiedAuditLog` (read), `Search-MailboxAuditLog`/`Search-AdminAuditLog` (deprecated) | — | N/A (read) | Use `Search-UnifiedAuditLog`; the older cmdlets are deprecated in cloud. [[audit-activities]] [[search-adminlog]] |
| **External sender ID** | `Get/Set-ExternalInOutlook` | — | **No `-WhatIf`** | Native Outlook "External" tag; org-wide + allow-list. [[extinoutlook]] |

### 3.1 Preset security policies — the fast baseline path

Standard/Strict preset policies are Microsoft-curated bundles. In PowerShell you
don't edit their settings; you **enable/disable the associated rules**: [[preset]] [[enable-eop]]

```powershell
# EOP-only tenant — turn on Standard preset:
Enable-EOPProtectionPolicyRule -Identity "Standard Preset Security Policy"

# Tenant with Defender for Office 365 — enable BOTH rules:
Enable-EOPProtectionPolicyRule -Identity "Standard Preset Security Policy"
Enable-ATPProtectionPolicyRule -Identity "Standard Preset Security Policy"

# Inspect:
Get-EOPProtectionPolicyRule -Identity "Strict Preset Security Policy"
Get-ATPProtectionPolicyRule -Identity "Strict Preset Security Policy"
```

The rule's **`State`** property (`Enabled`/`Disabled`) is the on/off signal. [[enable-atp]]

> **Design opportunity.** For a "security baseline first" MVP (Q6), supporting
> **"apply Standard/Strict preset"** is a very high-value, low-surface feature:
> few objects, deterministic, MS-maintained settings. It also sidesteps the
> policy/rule authoring complexity. Custom policies remain necessary for
> per-group tuning and for settings presets don't expose.

### 3.2 Anti-phishing — worked example of the pairing

```powershell
# 1) Policy (settings):
New-AntiPhishPolicy -Name "Baseline AntiPhish" -AdminDisplayName "Managed by m365-configurator" `
  -AuthenticationFailAction Quarantine        # + impersonation, mailbox intel, DMARC params

# 2) Rule (scope + priority), binds by policy name:
New-AntiPhishRule -Name "Baseline AntiPhish" -AntiPhishPolicy "Baseline AntiPhish" `
  -RecipientDomainIs (Get-AcceptedDomain).Name

# Read for drift:
Get-AntiPhishPolicy | Format-Table Name,IsDefault
Get-AntiPhishRule   | Format-Table Name,Priority,State
```

Notes: PowerShell-only options at create time are **`Enabled:$false`** and
**`Priority`** on the **rule**; a new policy is invisible in the portal until a
rule references it; `Set-AntiPhishPolicy` has no `-Name` (can't rename). [[antiphish-mdo]] [[antiphish-eop]]

### 3.3 Priority is a cascading, tenant-global integer

For every ruled category, `-Priority` is `0` = highest, and the max value
depends on how many rules exist. **Setting one rule's priority renumbers the
others** (a rule set to priority 2 pushes the old 2→3, 3→4, …). Same mechanic
for `Set-TransportRule -Priority`. [[antispam-configure]] [[mailflow-manage]]

> **Drift implication (big one).** Priority is **relative and mutable as a side
> effect**. Two tenets collide here: deterministic remediation (FR-11) vs. a
> field that reshuffles when neighbours change. See §6.

### 3.4 Transport rules differ — single object, rich condition/action model

`*-TransportRule` is **one** object (no policy/rule split). It carries
conditions, exceptions, actions, `-Priority` (0 = first), `-Enabled`,
`-Mode` (Enforce vs. audit/test), `-StopRuleProcessing`, `-SetAuditSeverity`,
`ActivationDate`/`ExpiryDate`, `-Comments`. Rules process in priority order and
`StopRuleProcessing` can short-circuit the rest. [[mailflow-rules]] [[mailflow-manage]]

> Changes can take **30 minutes** to take effect — matters for "verify after
> apply" UX, not for the write itself. [[mailflow-manage]]

### 3.5 Organization config — org-wide knobs (single object)

`Set-OrganizationConfig` is a large single-object surface. Baseline-relevant
parameters we've confirmed: [[setorgconfig-syntax]] [[modernauth]] [[audit-mailboxes]]

| Parameter | Meaning / baseline note |
| --- | --- |
| `-OAuth2ClientProfileEnabled` | Modern auth for Outlook (default `$true`). [[modernauth]] |
| `-AuditDisabled` | Org mailbox-audit default. `False` = auditing on by default (desired). [[audit-mailboxes]] |
| `-MailTipsExternalRecipientsTipsEnabled`, `-MailTipsAllTipsEnabled` | External-recipient MailTips. |
| `-EwsApplicationAccessPolicy`, `-EwsAllowList`, `-EwsBlockList`, `-EwsEnabled` | Restrict EWS app access. [[setorgconfig-syntax]] |
| `-ActivityBasedAuthenticationTimeout*` | OWA idle timeout. |
| `-DefaultAuthenticationPolicy` | Bind a tenant auth policy (e.g. block Basic auth). |
| `-ConnectorsEnabled`, `-AppsForOfficeEnabled`, `-SmtpActionableMessagesEnabled` | Attack-surface reductions. |

Read: `Get-OrganizationConfig | Format-List <props>`. **Gotcha:** `Get-` output
wraps multi-valued props in `{}`; **don't** feed those braces back into `Set-`. [[setorgconfig-desc]]

> Note the **naming asymmetry**: modern auth uses `-OAuth2ClientProfileEnabled`,
> not an obvious name. Our profile schema should map friendly names → exact
> parameter names and validate against the pinned module.

### 3.6 DKIM — per-domain, not free-named

DKIM config is keyed by **domain** (`-Identity <domain>`), so it's *named* but
the name is a real tenant domain, not an arbitrary label — **not** subject to
FR-7 remapping the way policy names are. [[dkim-configure]]

```powershell
Get-DkimSigningConfig | Format-List Name,Enabled,Status,Selector1CNAME,Selector2CNAME,`
  KeyCreationTime,RotateOnDate,SelectorBeforeRotateOnDate,SelectorAfterRotateOnDate
Set-DkimSigningConfig -Identity contoso.com -Enabled $true            # requires CNAMEs to exist
Rotate-DkimSigningConfig -Identity contoso.com -KeySize 2048          # supports -WhatIf
```

Operational realities for drift/remediation: enabling requires the two
`selectorN._domainkey` **CNAME records to already exist** at the registrar (else
error); **key rotation takes ~96 hours** to complete and blocks a second
rotation meanwhile. Treat rotation as a long-running, out-of-band action, not an
idempotent config value. [[dkim-configure]] [[rotate-dkim]]

### 3.7 Mailbox auditing & the audit log

- **Org default:** `Get-OrganizationConfig | Format-List AuditDisabled` →
  `False` means "mailbox auditing on by default" (overrides per-mailbox on/off,
  but not the per-mailbox *action* set). [[audit-mailboxes]]
- **Per mailbox:** `Set-Mailbox -Identity <id> -AuditEnabled $true -AuditOwner/-AuditDelegate/-AuditAdmin <actions>`.
- **Reading admin/mailbox activity:** use **`Search-UnifiedAuditLog`**
  (`-RecordType ExchangeAdmin` for admin cmdlet activity; up to ~30 min lag).
  `Search-MailboxAuditLog` and `Search-AdminAuditLog` are **deprecated in the
  cloud** — don't build on them. [[audit-activities]] [[search-adminlog]]

> For NFR-5 (audit-grade logging) we should log our *own* actions locally; the
> tenant's unified audit log is a separate, MS-side record we can *reference* but
> shouldn't depend on for our change log (30-min lag, retention limits).

### 3.8 External sender identification

`Set-ExternalInOutlook -Enabled $true` turns on the native "External" tag in
Outlook clients; `-AllowList` holds exceptions. **Disable any transport rule that
prepends "External" to subjects first**, to avoid duplication. **This cmdlet's
syntax has no `-WhatIf`/`-Confirm`** — an exception to the general rule (see §4). [[extinoutlook]] [[getextinoutlook]]

---

## 4. `-WhatIf` / `-Confirm` support (dry-run, FR-8)

- **Exchange write cmdlets support `-WhatIf` and `-Confirm`.** Confirmed in the
  published syntax for representative cmdlets across categories:
  `Set-HostedContentFilterRule`, `New-MalwareFilterRule`,
  `Rotate-DkimSigningConfig`, `Set-OrganizationConfig`,
  `Enable-EOPProtectionPolicyRule`, `Enable-ATPProtectionPolicyRule` all list
  `-WhatIf`. [[sethcfrule-syntax]] [[newmalwarerule-syntax]] [[rotate-dkim]] [[setorgconfig-syntax]] [[enable-eop]] [[enable-atp]]
- **`Get-*` cmdlets are read-only** — safe to run freely during drift scans
  (FR-10) with zero side effects.
- **Exceptions / cautions:**
  - `Set-ExternalInOutlook` — **no `-WhatIf`** in its syntax. Our dry-run must
    special-case this (compute the diff ourselves; don't rely on the cmdlet). [[extinoutlook]]
  - `-WhatIf` output is **human-readable prose**, not a structured diff. For
    FR-8/FR-9 per-item pass/fail and NFR-9 scannability, **prefer computing our
    own structured diff** from `Get-*` (desired vs. actual) and use `-WhatIf`
    only as a secondary confirmation, not the source of truth.
  - `-WhatIf` does **not** validate downstream dependencies (e.g. a rule
    referencing a not-yet-created policy) — our apply ordering must (policy →
    rule).

> **Recommendation.** Drive dry-run from **`Get-*` reads + our own diff engine**,
> optionally corroborated by `-WhatIf`. This gives deterministic, structured,
> reviewable output (FR-8, FR-11, NFR-9) and handles the no-`-WhatIf` cmdlets
> uniformly.

---

## 5. Naming & the "name remapping" feature (FR-7)

**Every policy and rule is a named object, and names are unique per tenant.**
Names do triple duty:

1. **Identity** — how you `Get`/`Set`/`Remove` an object (`-Identity <name>`).
2. **The join key** — a rule references its policy **by the policy's name**
   (`-AntiPhishPolicy "<name>"`, `-HostedContentFilterPolicy "<name>"`, …). [[antiphish-mdo]] [[antispam-configure]]
3. **The diff key** — our drift engine matches profile ⇄ tenant objects by name.

Implications for applying a profile to a **new** tenant (FR-7):

- **Collisions.** A profile's policy name may already exist in the target tenant
  (e.g. someone hand-made "Baseline AntiPhish"). Remapping to a unique name at
  apply time avoids clobbering, and the tool must surface the collision loudly
  (NFR-6) rather than silently overwrite.
- **Remap at create time only.** Because **policies can't be renamed**
  (`Set-*Policy` has no `-Name`; §2.2), the name must be chosen when the object
  is **created**. A profile can't "rename in place" during remediation — a rename
  is a delete+recreate (and thus re-scoping/re-prioritising the rule). [[antiphish-eop]] [[safeattach-configure]]
- **Keep policy+rule names paired.** The portal convention is that a policy and
  its rule share a name. If we remap, we should remap **both** consistently, and
  rewrite the rule's policy reference to the new policy name in the same
  operation, or we'll orphan the link.
- **Rules *can* be renamed** (`Set-*Rule -Name`, `Set-TransportRule -Name`), but
  renaming a rule doesn't rename its policy — so a "rename the rule only" path
  drifts the paired-name convention. Prefer paired remaps. [[antispam-configure]]
- **Reserved/immutable names.** Default policies (`Default`, always `Lowest`
  priority) and preset policies ("Standard/Strict Preset Security Policy") have
  fixed identities — **never remap these**; the profile model must flag them as
  system-owned. [[antiphish-eop]] [[preset]]
- **DKIM ≠ free names.** DKIM identities are **domains**, and mailbox/org configs
  are singletons or keyed by real recipient identity — these are **not** remap
  targets. Remapping applies specifically to the free-form policy/rule name
  categories. [[dkim-configure]]

> **Profile schema takeaway.** Model a nameable object as
> `{ type, name (remappable), settings, rule:{ name, priority, scope } }` and mark
> which types are remappable vs. system-owned. The remap operation is a *field on
> apply*, executed at object creation, that rewrites name + rule↔policy reference
> atomically.

---

## 6. Idempotency & drift-comparison gotchas

| Gotcha | Why it matters | Handling |
| --- | --- | --- |
| **Default policies have no rule** | Can't assume policy⇔rule 1:1; default has fixed `Lowest` priority and can't be deleted. [[antiphish-eop]] | Model rule-less policies; never try to create a rule/priority for a default. |
| **Priority is relative & cascades** | Setting one rule's priority renumbers neighbours; comparing absolute priority numbers across tenants is misleading. [[antispam-configure]] | Diff **relative order**, not absolute integers; remediate by reconstructing the whole ordered list, not per-item sets. |
| **Non-cascading remove** | Removing a policy leaves its rule (and vice-versa). [[antispam-configure]] | Remediation of a "remove" must delete both halves; drift scan should flag orphans. |
| **Create order dependency** | Rule referencing a missing policy fails. [[malware-newpolicy]] | Apply policy → rule; validate references before write. |
| **Can't rename policy** | "Name change" isn't an in-place edit. [[antiphish-eop]] | Treat name change as delete+recreate; warn it's destructive. |
| **Read-only / computed fields** | `Get-*` returns props that aren't settable (e.g. `IsDefault`, `Status`, `KeyCreationTime`, `WhenChanged`, GUIDs, `SelectorBeforeRotateOnDate`). [[dkim-configure]] | Diff only against a **known settable allow-list** per cmdlet; ignore computed props or we'll report false drift forever. |
| **Get output formatting** | Multi-valued props print with `{}`; enums/defaults may echo differently than input. [[setorgconfig-desc]] | Normalise both sides before compare (strip braces, canonicalise arrays/case/enums). |
| **Defaults not always echoed as input** | A param defaulted at create shows a value on read that we never set → looks like drift. | Baseline the profile against a real `Get-*` of a known-good tenant so "expected" includes effective defaults. |
| **`-WhatIf` is prose, not a diff** | Can't be parsed reliably for per-item status. [[sethcfrule-syntax]] | Build our own structured diff (see §4). |
| **Propagation lag** | Transport rules ~30 min; DKIM rotation ~96 h. [[mailflow-manage]] [[dkim-configure]] | "Applied" ≠ "effective"; don't verify-immediately for these; mark long-running. |
| **REST 15-min timeout** | Bulk writes can time out. [[about-module]] | Batch large operations; make apply resumable/idempotent. |

> **Idempotency posture.** `New-*` fails if the object exists; `Set-*` is the
> idempotent update. Our apply should: read → if absent `New-` → else `Set-`
> only the drifted settable fields → reconcile rule/priority last. This keeps
> re-runs safe (FR-1 "safe to re-run" mindset extended to config).

---

## 7. Least-privilege roles & permissions

Two permission systems intersect: **Exchange Online RBAC role groups** (govern
which EXO cmdlets/parameters you can run) and **Microsoft Entra directory roles**
(some EXO role groups are synchronised from Entra). Every EXO cmdlet page notes
"you need to be assigned permissions before you can run this cmdlet," and
Microsoft provides `Find the permissions required to run any Exchange cmdlet`. [[perms-exo]]

**Read-only (drift scan, FR-10) — least privilege:**

| Need | Role / role group |
| --- | --- |
| View all non-recipient EXO config | **View-Only Organization Management** role group (`View-Only Configuration` + `View-Only Recipients`). [[perms-exo]] [[viewonly-config]] |
| View security policy config (anti-phish/spam/malware/Safe*) | **Security Reader** role group (Entra **Security Reader**, synced). [[perms-exo]] |
| Broad read across M365 security | Entra **Global Reader**. [[entra-leastpriv]] |

**Write (apply/remediate, FR-9/FR-11):**

| Need | Role / role group |
| --- | --- |
| Manage EOP/Defender email policies & presets | **Security Administrator** role group (Entra **Security Administrator**, synced). [[perms-exo]] |
| Manage transport rules / mail flow | **Records Management** role group (includes `Transport Rules`) or **Organization Management**. [[perms-exo]] |
| Manage org config, DKIM, mailbox audit, recipients | **Organization Management** (Entra **Exchange Administrator** maps here) — broad; use sparingly. [[perms-exo]] |

Notes:

- **Delegated interactive/device-code auth means our effective permissions = the
  signed-in user's roles.** If the operator connects as Security Reader, `Set-*`
  simply won't be available (params hidden / access denied) — which is a *feature*
  for a "dry-run as read-only user, apply as admin" workflow. [[perms-exo]]
- Microsoft explicitly recommends **avoiding Global Administrator**; prefer the
  narrow role groups above. [[perms-exo]]
- **App-only RBAC** (`Test-ServicePrincipalAuthorization`, management scopes)
  exists for scoped app access — relevant later if we add cert/app auth (Q5),
  out of MVP. [[app-rbac]]

> **Recommendation.** Support (and document) a **two-persona** flow:
> **read persona** = Security Reader + View-Only Organization Management for
> drift scans; **write persona** = Security Administrator (+ Records Management
> for transport rules) for apply. This operationalises least privilege and lets
> dry-run run under credentials that *physically cannot* change anything.

---

## 8. Key takeaways / recommendations

1. **Adopt one mental model — policy(settings) + rule(scope/priority) — across
   the whole email-security surface.** Anti-phish/spam/malware/Safe
   Links/Attachments all follow it identically; transport rules and org/DKIM/
   audit are the exceptions. Build the profile schema around this shape. (§2, §3)
2. **Drive dry-run and drift from `Get-*` + our own structured diff**, not from
   `-WhatIf` prose. Corroborate with `-WhatIf` where present; special-case
   `Set-ExternalInOutlook` (no `-WhatIf`). (§4, §6)
3. **Diff only a curated, settable allow-list of fields per cmdlet**, normalise
   values (braces, arrays, enums, case), and exclude computed/read-only props —
   otherwise perpetual false drift. (§6)
4. **Treat priority as relative order, remediate by reconstructing the ordered
   list**, never by comparing absolute integers. (§3.3, §6)
5. **Make name-remapping a create-time, paired (policy+rule) operation**, flag
   system-owned names (default/preset/DKIM-domain) as non-remappable, and fail
   loud on collisions. (§5)
6. **Ship "apply Standard/Strict preset security policy" as a first MVP win** —
   smallest surface, deterministic, MS-maintained. Layer custom policies after.
   (§3.1, Q6)
7. **Pin `ExchangeOnlineManagement` + PowerShell 7 versions together** (they're
   coupled via .NET); bundle `PowerShellGet`/`PackageManagement`; use
   `-CommandName` to load only needed cmdlets. (§1.3, §1.4, NFR-7)
8. **Use device-code auth in the container**, connect/disconnect per action,
   verify teardown via `Get-ConnectionInformation`, and keep tokens out of our
   logs. (§1.2, NFR-1)
9. **Design a two-persona (read / write) permission story** so dry-run can run
   under credentials that cannot mutate the tenant. (§7)

## 9. Open questions / risks

- **R1 — S&C PowerShell not on Linux (high).** `Connect-IPPSSession` is
  unavailable in PS7 on Linux/macOS. Anything in Security & Compliance (DLP,
  sensitivity/retention labels, audit retention policies) is **out of reach from
  our Linux container**. Confirm the MVP baseline is EXO-native only, or accept a
  Windows execution path for S&C. (Feeds Q6.) [[about-module-os]]
- **R2 — Defender licensing (med).** Safe Links / Safe Attachments and parts of
  anti-phish (impersonation, mailbox intelligence) require **Defender for Office
  365** plans. Profiles must degrade gracefully / detect licence, or applying a
  baseline errors on tenants without the SKU. [[safelinks-configure]] [[safeattach-configure]]
- **R3 — Effective-defaults drift (med).** `Get-*` returns effective defaults we
  never set, which read as drift. Decide whether "expected" baselines are authored
  as full snapshots (from a golden tenant) or sparse overrides, and normalise
  accordingly. (§6)
- **R4 — Parameter surface churn (med, NFR-7).** Parameter *names/lists* change
  between module releases even though the pattern is stable. Pin + regenerate our
  parameter allow-lists from the pinned module's help; add a CI check that our
  schema matches the pinned cmdlets.
- **R5 — Priority reconciliation determinism (med).** Because priority cascades,
  remediating order changes can produce different intermediate states. Define a
  deterministic reconstruction algorithm (e.g. delete-and-reinsert in target
  order, or set priorities in a fixed pass) and test it. (§3.3)
- **R6 — Long-running/async operations (low-med).** DKIM rotation (~96 h) and
  transport-rule propagation (~30 min) break "apply then immediately verify."
  Model these as async with deferred verification. (§3.6, §3.4)
- **R7 — Orphan cleanup (low).** Non-cascading removes can leave orphan
  rules/policies from prior manual work. Drift scan should detect and offer
  cleanup. (§2, §6)
- **R8 — Should Microsoft365DSC own this surface? (open, Q7).** DSC already models
  EXO/Defender policies with export + drift. This research shows the raw cmdlet
  surface is very regular (policy+rule), so a hand-rolled engine is feasible; but
  DSC would save us the diff/normalisation work at the cost of a heavy dependency
  (conflicts with NFR-3) and the owner's noted setup difficulty. Decide in a
  dedicated ADR after a spike.

## 10. Sources

All Microsoft Learn, retrieved 2026-07-22.

- `[about-module]` / `[about-module-os]` — About the Exchange Online PowerShell module (REST, `Get-EXO*`, footprint, OS/version support): https://learn.microsoft.com/powershell/exchange/exchange-online-powershell-v2?view=exchange-ps
- `[connect-cmdlet]` / `[connect-syntax]` — Connect-ExchangeOnline (device code, parameters): https://learn.microsoft.com/powershell/module/exchangepowershell/connect-exchangeonline?view=exchange-ps
- `[connect-steps]` — Connect to Exchange Online PowerShell (browser SSO, `-Device`): https://learn.microsoft.com/powershell/exchange/connect-to-exchange-online-powershell?view=exchange-ps
- `[antiphish-mdo]` — Configure anti-phishing policies in Microsoft Defender for Office 365: https://learn.microsoft.com/defender-office-365/anti-phishing-policies-mdo-configure
- `[antiphish-eop]` — Configure anti-phishing policies for all cloud mailboxes (EOP): https://learn.microsoft.com/defender-office-365/anti-phishing-policies-eop-configure
- `[antispam-configure]` — Configure anti-spam policies: https://learn.microsoft.com/defender-office-365/anti-spam-policies-configure
- `[outbound-configure]` — Configure outbound spam policies: https://learn.microsoft.com/defender-office-365/outbound-spam-policies-configure
- `[malware-configure]` — Configure anti-malware policies: https://learn.microsoft.com/defender-office-365/anti-malware-policies-configure
- `[malware-newpolicy]` — New-MalwareFilterPolicy: https://learn.microsoft.com/powershell/module/exchangepowershell/new-malwarefilterpolicy?view=exchange-ps
- `[newmalwarerule-syntax]` — New-MalwareFilterRule (syntax incl. `-WhatIf`): https://learn.microsoft.com/powershell/module/exchangepowershell/new-malwarefilterrule?view=exchange-ps
- `[safelinks-configure]` — Set up Safe Links policies: https://learn.microsoft.com/defender-office-365/safe-links-policies-configure
- `[safeattach-configure]` — Set up Safe Attachments policies: https://learn.microsoft.com/defender-office-365/safe-attachments-policies-configure
- `[mailflow-manage]` — Manage mail flow rules in Exchange Online: https://learn.microsoft.com/exchange/security-and-compliance/mail-flow-rules/manage-mail-flow-rules
- `[mailflow-rules]` — Mail flow rules (transport rules) components: https://learn.microsoft.com/exchange/security-and-compliance/mail-flow-rules/mail-flow-rules
- `[setorgconfig-syntax]` / `[setorgconfig-desc]` — Set-OrganizationConfig: https://learn.microsoft.com/powershell/module/exchangepowershell/set-organizationconfig?view=exchange-ps
- `[modernauth]` — Enable/disable modern authentication in Exchange Online: https://learn.microsoft.com/exchange/clients-and-mobile-in-exchange-online/enable-or-disable-modern-authentication-in-exchange-online
- `[dkim-configure]` — Set up DKIM to sign mail from your cloud domain: https://learn.microsoft.com/defender-office-365/email-authentication-dkim-configure
- `[rotate-dkim]` — Rotate-DkimSigningConfig: https://learn.microsoft.com/powershell/module/exchangepowershell/rotate-dkimsigningconfig?view=exchange-ps
- `[audit-mailboxes]` — Manage mailbox auditing: https://learn.microsoft.com/purview/audit-mailboxes
- `[audit-activities]` — Audit log activities (Exchange admin/mailbox, `Search-UnifiedAuditLog`): https://learn.microsoft.com/purview/audit-log-activities
- `[search-adminlog]` — Search-AdminAuditLog (deprecated in cloud): https://learn.microsoft.com/powershell/module/exchangepowershell/search-adminauditlog?view=exchange-ps
- `[extinoutlook]` / `[getextinoutlook]` — Set-/Get-ExternalInOutlook: https://learn.microsoft.com/powershell/module/exchangepowershell/set-externalinoutlook?view=exchange-ps
- `[preset]` — Preset security policies in cloud organizations: https://learn.microsoft.com/defender-office-365/preset-security-policies
- `[enable-eop]` — Enable-EOPProtectionPolicyRule: https://learn.microsoft.com/powershell/module/exchangepowershell/enable-eopprotectionpolicyrule?view=exchange-ps
- `[enable-atp]` — Enable-ATPProtectionPolicyRule: https://learn.microsoft.com/powershell/module/exchangepowershell/enable-atpprotectionpolicyrule?view=exchange-ps
- `[sethcfrule-syntax]` — Set-HostedContentFilterRule (syntax incl. `-WhatIf`): https://learn.microsoft.com/powershell/module/exchangepowershell/set-hostedcontentfilterrule?view=exchange-ps
- `[perms-exo]` — Permissions in Exchange Online (role groups): https://learn.microsoft.com/exchange/permissions-exo/permissions-exo
- `[viewonly-config]` — View-Only Configuration role: https://learn.microsoft.com/exchange/view-only-configuration-role-exchange-2013-help
- `[app-rbac]` — Role Based Access Control for Applications in Exchange Online: https://learn.microsoft.com/exchange/permissions-exo/application-rbac
- `[entra-leastpriv]` — Least privileged roles by task in Microsoft Entra ID: https://learn.microsoft.com/entra/identity/role-based-access-control/delegate-by-task

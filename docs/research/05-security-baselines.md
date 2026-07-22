# Research 05 — Security baselines: from frameworks to a concrete MVP control list

> **Phase 1 research** for `m365-configurator`. Scope: turn the major M365
> **security-baseline frameworks** (CIS, CISA SCuBA, Microsoft) into a concrete,
> implementable **control list** for the MVP — one control per row, each with a
> recommended value, a framework citation, and the **enforcing cmdlet** (Graph
> vs Exchange Online / Defender), cross-referenced to the sibling surface docs.
>
> **Tenet / requirements informed:** FR-4 (config surface), FR-5 (profiles are
> config, never credentials), FR-8 (dry-run), FR-9 (apply), FR-10 (drift),
> FR-11 (remediation), FR-7 (name remapping); NFR-7 (pinned versions), NFR-9
> (readability).
> **Decisions informed:** ADR-0003 (MVP = security-baseline slice) and
> OPEN-QUESTIONS **Q6** (MVP surface).
>
> **Author:** research sub-agent · **Date:** 2026-07-22
>
> This doc does **not** re-derive the cmdlet surface — it maps controls onto the
> cmdlets already documented in `01-microsoft-graph-surface.md` [11] and
> `02-exchange-online-surface.md` [12], and cites the framework that calls for
> each control. Every nontrivial claim is cited inline `[n]`; see
> [Sources](#8-sources).

---

## Contents

1. [TL;DR](#tldr)
2. [Framework survey](#1-framework-survey)
3. [Concrete control list, by ADR-0003 scope area](#2-concrete-control-list-by-adr-0003-scope-area)
4. [Master mapping table](#3-master-mapping-table)
5. [Proposed v1 baseline set (the vertical slice)](#4-proposed-v1-baseline-set-the-vertical-slice)
6. [Key takeaways / recommendations](#5-key-takeaways--recommendations)
7. [Open questions / risks](#6-open-questions--risks)
8. [Sources](#8-sources)

---

## TL;DR

1. **Three frameworks, one shape.** CIS (community-consensus, L1/L2), CISA
   SCuBA (federal baselines with a machine-checkable tool, ScubaGear), and
   Microsoft's own guidance (security defaults, Conditional Access templates,
   Defender preset security policies) all converge on the same ~30 high-value
   controls. They differ mainly in **expression** and **stringency**, not
   intent. [1][3][8]
2. **SCuBA is our primary control catalogue.** Its policies have stable IDs
   (`MS.AAD.x`, `MS.EXO.x`, `MS.DEFENDER.x`), explicit SHALL/SHOULD language,
   are freely published, and map almost one-to-one onto the Graph/EXO cmdlets in
   docs 01/02 [5][6][7]. We use **CIS as a cross-check** and **Microsoft Learn as
   the authority on mechanism, defaults, and licensing** [1][8][9][10].
3. **~37 controls catalogued** across the five ADR-0003 areas. The single
   highest-value EXO win is **"enable the Standard/Strict preset security
   policy"** — one rule toggle delivers Microsoft-maintained anti-spam,
   anti-malware, anti-phishing, Safe Links and Safe Attachments settings
   [7][10][12].
4. **Split is roughly Graph 21 / EXO 13 / out-of-tool 3.** Identity, CA, auth
   methods, consent and Entra-side sharing are **Microsoft Graph** (doc 01);
   Defender email policies, external auto-forward, external-sender tagging,
   mailbox audit and unified-audit-log enablement are **Exchange Online** (doc
   02); SPF/DMARC (DNS) and SOC/SIEM log export are **outside** our config
   surface.
5. **A hard MVP boundary: Security & Compliance PowerShell is not on Linux.**
   Per doc 02, `Connect-IPPSSession` is unavailable in PS7 on Linux/macOS [12],
   so DLP (`MS.DEFENDER.4.x`), sensitivity/retention labels, **audit-log
   retention policies** (`MS.DEFENDER.6.3`) and some alert policies are **out of
   the containerized MVP**. The baseline is scoped to the EXO-native + Graph
   surface.
6. **Baseline values are opinionated and need per-client tuning** — every
   name-scoped policy is an FR-7 remap target, and dry-run (FR-8) is the safety
   net for the opinionated defaults. Framework **version drift** (CIS reorders
   and renumbers controls release-to-release) means the profile must pin a
   framework version (NFR-7).

---

## 1. Framework survey

### 1.1 CIS Microsoft 365 Foundations Benchmark

- **What it is.** A prescriptive, consensus-developed configuration benchmark
  for M365, published by the Center for Internet Security. Recommendations are
  organized by service / admin-center area (Microsoft Entra, Exchange Online,
  Microsoft Defender, Microsoft Purview, SharePoint/OneDrive, Teams, Power
  Platform) and each carries a **profile level** and an **assessment status**
  (Automated vs Manual) [1][2].
- **Levels.** **Level 1 (L1)** = "practical and minimally disruptive" essential
  hardening applied broadly; **Level 2 (L2)** = defence-in-depth for
  security-sensitive environments, accepting usability trade-offs [1][2].
- **Authority & cadence.** Community-consensus process; CIS publishes point and
  major releases roughly every few months. **v5.0.0 was released 2025-04-30**,
  described as six months of new guidance; newer major versions (v6.x and later)
  have since shipped [2]. The CIS benchmark landing page references mid-2026
  updates [1].
- **Expression.** A registration-gated PDF (free) plus CIS-CAT tooling; the
  document is prose recommendations with rationale, audit, and remediation
  steps — **not** a machine-readable policy file we can consume directly.
- **Drift caveat.** CIS **renumbers and re-scopes** between versions — e.g.
  v5.0.0 *removed* the "disable security defaults" recommendation and the "E3
  mailbox auditing" item (now on by default), and *added* device-code-flow
  blocking and system-preferred MFA as new L1 checks [2]. Our profiles must pin
  a specific CIS version, and control numbers must be verified against it.

### 1.2 CISA SCuBA — Secure Configuration Baselines for M365

- **What it is.** The Cybersecurity & Infrastructure Security Agency's **Secure
  Cloud Business Applications** project publishes **Secure Configuration
  Baselines (SCBs)** for M365, born out of the SolarWinds response and mandated
  for US federal civilian agencies but freely usable by anyone [3][4].
- **How it's expressed.** As **Markdown baseline documents** in the open-source
  `cisagov/ScubaGear` repo — one per product: `aad.md`, `exo.md`, `defender.md`,
  `sharepoint.md`, `teams.md`, `powerplatform.md`, `powerbi.md` [4]. Each policy
  has a **stable ID** (`MS.<PRODUCT>.<group>.<n>v<rev>`) and an explicit
  **SHALL / SHOULD** statement, e.g. `MS.AAD.1.1v1 "Legacy authentication SHALL
  be blocked."` [5].
- **The companion tool.** **ScubaGear** assesses a tenant: PowerShell queries
  M365 APIs, Open Policy Agent (OPA) compares against Rego policies written from
  the baseline docs, and it reports HTML/JSON/CSV [3]. This is *assessment*
  (drift-detection) only — it does **not** remediate — which is precisely the
  gap our tool's apply/remediate engine fills.
- **Authority & cadence.** CISA; versioned baselines (v1.0 released Dec 2023,
  iterated since) tied to ScubaGear releases [3][4].
- **Why we treat SCuBA as primary.** Stable IDs, unambiguous SHALL/SHOULD,
  freely published in Git (diffable, pinnable), and each policy already implies
  the exact Graph/EXO object we manage. It is the cleanest bridge between "a
  framework requirement" and "a cmdlet call."

### 1.3 Microsoft's own guidance

Microsoft ships several overlapping baseline mechanisms — these are the
**authority on the enforcing mechanism, defaults, and licensing**:

- **Security defaults.** A free-tier, tenant-wide **on/off** switch that
  enforces: MFA registration for all users, MFA for admins, MFA "when
  necessary" for users, **blocking legacy authentication**, **blocking device
  code flow**, and protecting privileged Azure Resource Manager access [8].
  Intended for organizations with no P1/P2 and no CA. **Security defaults and
  Conditional Access are mutually exclusive** — you disable one to use the other
  [8] (this ordering constraint is already flagged in doc 01 §4.5 [11]).
- **Conditional Access templates.** Preconfigured CA policies grouped into
  categories — the **"Secure foundation"** set is Microsoft's recommended base
  for all orgs: require MFA for admins, secure security-info registration,
  **block legacy authentication**, require MFA for admins on admin portals,
  require MFA for all users, require MFA for Azure management, require
  compliant/hybrid-joined device (or MFA) [9]. **Risk-based** templates (MFA for
  risky sign-ins, password change for high-risk users) and phishing-resistant
  MFA for admins are additional categories; risk-based policies **require Entra
  ID P2** [9]. Templates default to **report-only** mode and can be **exported
  as JSON** for programmatic use — directly useful to our profile importer [9].
- **Defender for Office 365 preset security policies.** **Standard**, **Strict**,
  and **Built-in protection** bundles of Microsoft-curated, mostly
  non-configurable settings spanning EOP (anti-spam, anti-malware,
  anti-phishing) and Defender (Safe Links, Safe Attachments) [10]. In PowerShell
  you enable them by turning on the associated **rules**
  (`Enable-EOPProtectionPolicyRule` / `Enable-ATPProtectionPolicyRule`) — no
  settings authoring required (doc 02 §3.1 [12]). Microsoft positions presets as
  the recommended baseline for most organizations [10].

### 1.4 How they overlap, and the primary source per area

The three frameworks agree on the core: MFA everywhere, block legacy auth,
restrict app consent, enable Defender email protection, turn on auditing. They
differ in **stringency** (SCuBA/CIS-L2 are stricter than security defaults) and
**expression** (SCuBA = machine-checkable IDs; CIS = prose PDF; Microsoft =
built-in toggles/templates).

| Scope area (ADR-0003) | Primary source | Cross-check | Authority on mechanism |
|---|---|---|---|
| Identity & Conditional Access | SCuBA `MS.AAD.1–3` [5] | CIS Entra L1/L2 [1] | MS security defaults + CA templates [8][9] |
| Authentication methods | SCuBA `MS.AAD.3.3–3.5` [5] | CIS Entra [1] | MS auth-methods policy (doc 01 §4.2 [11]) |
| Exchange / Defender for O365 | SCuBA `MS.DEFENDER.*`, `MS.EXO.*` [6][7] | CIS Defender/Exchange [1] | MS preset security policies [10] |
| Tenant sharing & app-consent | SCuBA `MS.AAD.5`, `MS.AAD.8` [5] | CIS Entra [1] | MS authorization/consent policy (doc 01 §4.3/§4.6 [11]) |
| Auditing & logging | SCuBA `MS.DEFENDER.6`, `MS.EXO.13` [6][7] | CIS L1 [1] | MS unified audit log / mailbox audit (doc 02 §3.7 [12]) |

**Decision:** treat **SCuBA as the canonical control catalogue** (stable IDs,
freely pinnable), **CIS as a secondary cross-check** for anything SCuBA omits or
under-specifies, and **Microsoft Learn as the source of truth for the enforcing
cmdlet, effective defaults, and licensing gates**.

---

## 2. Concrete control list, by ADR-0003 scope area

Legend for each control: **id** · what it is · **recommended setting** ·
framework ref · **mechanism** (Graph → doc 01, EXO → doc 02) · desired-state vs
read-only, and licensing notes.

> Recommended values below reflect the frameworks' *baseline* intent. They are
> **opinionated** and must be tunable per client (FR-7) and always previewed
> (FR-8). Exact CIS recommendation numbers are intentionally **not** cited (the
> PDF is version-gated and renumbers) — verify against the pinned CIS version
> (see §6).

### 2.1 Identity & Conditional Access

| id | Control | Recommended setting | Framework | Mechanism (doc) |
|---|---|---|---|---|
| **ID-1** | Security defaults state | **Disabled** when the profile ships CA policies (mutually exclusive) | MS security defaults [8]; SCuBA assumes CA | Graph singleton `Update-MgPolicyIdentitySecurityDefaultEnforcementPolicy` (01 §4.5) |
| **ID-2** | Block legacy authentication | CA policy, `clientAppTypes` = `exchangeActiveSync,other`, grant = `block`, all users | SCuBA `MS.AAD.1.1v1` [5]; CA "Block legacy auth" template [9] | Graph collection CA (01 §4.1) |
| **ID-3** | Require MFA for all users | CA policy, all users/all apps, grant = `mfa` | SCuBA `MS.AAD.3.2v2` [5]; CA "MFA for all users" [9] | Graph collection CA (01 §4.1) |
| **ID-4** | Require MFA for admins / Azure mgmt | CA policies targeting directory roles + the Azure-management app | CA "MFA for admins", "MFA for Azure management" [9]; SCuBA `MS.AAD.7.*` intent [5] | Graph collection CA (01 §4.1) |
| **ID-5** | Phishing-resistant MFA (priv. roles → all) | CA `grantControls.authenticationStrength` = phishing-resistant | SCuBA `MS.AAD.3.6v1` (priv), `3.1v1` (all) [5]; CA "phishing-resistant MFA for admins" [9] | Graph collection CA + auth-strength (01 §4.1) |
| **ID-6** | Block high-risk users & sign-ins | CA with `userRiskLevels`/`signInRiskLevels` = `high`, grant = `block` | SCuBA `MS.AAD.2.1v1`, `2.3v1` [5]; CA risk templates [9] | Graph collection CA (01 §4.1/§4.4) — **Entra ID P2** |
| **ID-7** | Block device code flow | CA transfer-method/authentication-flow condition = block device code | SCuBA `MS.AAD.3.9v1` [5]; MS security defaults (blocks device code) [8] | Graph collection CA (01 §4.1) — **verify condition field** |
| **ID-8** | Require managed/compliant device | CA grant = `compliantDevice`/`domainJoinedDevice` | SCuBA `MS.AAD.3.7v1` (SHOULD) [5]; CA compliant-device template [9] | Graph collection CA (01 §4.1) — **needs Intune; defer** |
| **ID-9** | Named locations (supporting) | Trusted-IP / country locations referenced by CA | supporting object for location-based CA [9] | Graph collection `*-MgIdentityConditionalAccessNamedLocation` (01 §4.1) |
| **ID-10** | Highly privileged role hygiene / PIM | 2–8 Global Admins; PIM eligible + approval + alerts | SCuBA `MS.AAD.7.1–7.9` [5] | Graph read for MVP; PIM writes = `Identity.Governance` (**later phase**, 01 §2.3) |

Notes: ID-2/3/4 are the **secure-foundation** core and the required-value floor.
ID-1 is a **prerequisite/ordering** control (security defaults must be off
before CA enforces — doc 01 §4.5 [11]). ID-6 and risk-based enforcement need
**P2**; the standalone Identity-Protection risk policies are retiring and must be
modelled **as CA**, per doc 01 §4.4 [11]. ID-10 is largely **read-only /
monitoring** for the MVP (role counts, PIM state); PIM configuration is deferred.

### 2.2 Authentication methods

| id | Control | Recommended setting | Framework | Mechanism (doc) |
|---|---|---|---|---|
| **AM-1** | Auth-methods migration state | **Migration Complete** (fully off the legacy MFA/SSPR settings) | SCuBA `MS.AAD.3.4v1` [5] | Graph singleton `Update-MgPolicyAuthenticationMethodPolicy` (01 §4.2) — **verify `policyMigrationState` field** |
| **AM-2** | Disable weak MFA methods | **SMS, Voice, Email OTP = disabled** as auth methods | SCuBA `MS.AAD.3.5v2` [5] | Graph per-method `Update-…AuthenticationMethodConfiguration` (01 §4.2) |
| **AM-3** | Enable phishing-resistant methods | FIDO2 / passkey / WHfB / certificate = enabled | SCuBA `MS.AAD.3.1v1` intent [5]; MS guidance | Graph per-method config (01 §4.2) |
| **AM-4** | Authenticator shows context | Number matching + app name & geo location on | SCuBA `MS.AAD.3.3v2` [5] | Graph `MicrosoftAuthenticator` method `featureSettings` (01 §4.2) — **verify field names** |
| **AM-5** | System-preferred MFA | Enabled | CIS v5 new L1 (community [2]); MS default | Graph auth-methods policy (01 §4.2) — **verify field** |

Notes: the whole area is the **auth-methods policy singleton + per-method
collection** shape (doc 01 §4.2 [11]); per-method PATCH is the idempotent unit.
AM-1 is effectively a one-way migration — treat as a guarded, high-impact toggle
in dry-run.

### 2.3 Exchange Online / Defender for Office 365

| id | Control | Recommended setting | Framework | Mechanism (doc) |
|---|---|---|---|---|
| **MDO-1** | Enable preset security policies | Enable **Standard** (and **Strict** for sensitive accounts) EOP + ATP rules; all users covered | SCuBA `MS.DEFENDER.1.1–1.5v1` [7]; MS presets [10] | EXO `Enable-EOPProtectionPolicyRule` / `Enable-ATPProtectionPolicyRule` (02 §3.1) — **Defender for ATP rule** |
| **MDO-2** | Anti-phishing (custom, if not presets) | Spoof intelligence on; impersonation + mailbox-intelligence for sensitive accounts/domains; unauth action quarantine | SCuBA `MS.DEFENDER.2.1–2.3v1` [7]; CIS [1] | EXO `New/Set-AntiPhishPolicy` + `*-AntiPhishRule` (02 §3.2) — **impersonation needs Defender** |
| **MDO-3** | Anti-spam inbound | Spam/high-confidence-spam → quarantine; bulk threshold set; ASF as per level | CIS [1]; SCuBA via presets [7] | EXO `New/Set-HostedContentFilterPolicy` + rule (02 §3) |
| **MDO-4** | Block external auto-forwarding | Outbound policy `AutoForwardingMode = Off` | SCuBA `MS.EXO.1.1v2` [6]; CIS [1] | EXO `New/Set-HostedOutboundSpamFilterPolicy` + rule (02 §3) |
| **MDO-5** | Anti-malware | Common-attachments filter on; ZAP on; notifications | CIS [1]; SCuBA via presets [7] | EXO `New/Set-MalwareFilterPolicy` + rule (02 §3) |
| **MDO-6** | Safe Links | URL rewrite/detonation on for email + Teams/Office | SCuBA via presets [7]; CIS [1] | EXO `New/Set-SafeLinksPolicy` + rule (02 §3) — **Defender licence** |
| **MDO-7** | Safe Attachments (email) | Detonation on; action Block | SCuBA via presets [7]; CIS [1] | EXO `New/Set-SafeAttachmentPolicy` + rule (02 §3) — **Defender licence** |
| **MDO-8** | Safe Attachments for SPO/OneDrive/Teams | Enabled | SCuBA `MS.DEFENDER.3.1v1` [7] | EXO `Set-AtpPolicyForO365` (**not in doc 02 — verify cmdlet**) — **Defender licence** |
| **MDO-9** | DKIM signing | Enabled for all custom domains | SCuBA `MS.EXO.3.1v1` (SHOULD) [6]; CIS [1] | EXO `Set-DkimSigningConfig` (02 §3.6) — **DNS CNAMEs must pre-exist; ~96 h rotation** |
| **MDO-10** | External sender warning | Native Outlook External tag on | SCuBA `MS.EXO.7.1v1` [6] | EXO `Set-ExternalInOutlook` (02 §3.8) — **no `-WhatIf`; compute own diff** |
| **MDO-11** | Disable SMTP AUTH (org) | `SmtpClientAuthenticationDisabled = $true` | SCuBA `MS.EXO.5.1v1` [6]; CIS [1] | EXO `Set-TransportConfig` (**not in doc 02 — verify cmdlet**) |
| **MDO-12** | SPF / DMARC | SPF `-all`; DMARC `p=reject` + reporting | SCuBA `MS.EXO.2.2v3`, `4.1–4.4` [6] | **DNS records — outside our config surface**; read/monitor only |

Notes: **MDO-1 is the flagship EXO control** — a rule toggle that delivers
MDO-3/5/6/7 (and much of MDO-2) as Microsoft-maintained settings, sidestepping
policy/rule authoring (doc 02 §3.1 [12]). Custom policies (MDO-2..MDO-7) follow
the **policy(settings) + rule(scope/priority)** pairing model that dominates doc
02 [12]. Defender-licensed items (impersonation, Safe Links, Safe Attachments)
must **detect licence and degrade** or the apply errors (doc 02 R2 [12]).
**SPF/DMARC (MDO-12) are DNS, not cmdlets** — the tool can *read/report* posture
but cannot *apply* them; DKIM (MDO-9) is the only email-auth item with a cmdlet,
and it is long-running/DNS-gated.

### 2.4 Tenant sharing & app-consent controls

| id | Control | Recommended setting | Framework | Mechanism (doc) |
|---|---|---|---|---|
| **CON-1** | Restrict user consent to apps | Consent limited to low-risk from verified publishers, or disabled | SCuBA `MS.AAD.5.2v1` [5]; CIS [1] | Graph singleton authorization policy `permissionGrantPoliciesAssigned` (01 §4.3/§4.6) |
| **CON-2** | Admin consent workflow | Enabled with reviewers | SCuBA `MS.AAD.5.3v1` [5] | Graph singleton `Set-MgPolicyAdminConsentRequestPolicy` (01 §4.6) |
| **CON-3** | Only admins register apps | `allowedToCreateApps = $false` | SCuBA `MS.AAD.5.1v1` [5]; CIS [1] | Graph singleton `Update-MgPolicyAuthorizationPolicy` (01 §4.3) |
| **CON-4** | Consent to risky apps off | `allowUserConsentForRiskyApps = $false` | MS recommendation (01 §4.3 [11]) | Graph singleton authorization policy (01 §4.3) |
| **SHR-1** | Restrict who can invite guests | `allowInvitesFrom` = admins / Guest Inviter role only | SCuBA `MS.AAD.8.2v1` [5] | Graph singleton authorization policy (01 §4.3) |
| **SHR-2** | Limit guest directory access | `guestUserRoleId` = restricted guest role | SCuBA `MS.AAD.8.1v1` [5] | Graph singleton authorization policy (01 §4.3) |
| **SHR-3** | Restrict guest invite domains | Allow-list authorized external domains | SCuBA `MS.AAD.8.3v1` (SHOULD) [5] | Graph B2B external-collaboration / cross-tenant settings (**adjacent to 01 §4.3 — verify cmdlet**) |
| **SHR-4** | EXO calendar/contact external sharing | Do not share contacts/calendar with all domains | SCuBA `MS.EXO.6.1v1`, `6.2v1` [6] | EXO `Set-SharingPolicy` (**not in doc 02 — verify cmdlet**) |

Notes: CON-1..CON-4 and SHR-1/SHR-2 all ride the **authorization-policy
singleton** (doc 01 §4.3 [11]) — inherently idempotent (PATCH), no name-scoping.
**SharePoint/OneDrive/Teams external-sharing** controls (SCuBA `sharepoint.md`,
`teams.md`) live in the SharePoint/Teams surface and are **out of the EXO+Graph
MVP** — defer.

### 2.5 Auditing & logging

| id | Control | Recommended setting | Framework | Mechanism (doc) |
|---|---|---|---|---|
| **AUD-1** | Unified audit log | Enabled tenant-wide | SCuBA `MS.DEFENDER.6.1v1` [7]; CIS [1] | EXO `Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true` (**not in doc 02 — verify; reads via `Search-UnifiedAuditLog`, 02 §3.7**) |
| **AUD-2** | Mailbox auditing | Org default on (`AuditDisabled = $false`) + per-mailbox actions | SCuBA `MS.EXO.13.1v1` [6]; CIS [1] | EXO `Set-OrganizationConfig` + `Set-Mailbox` (02 §3.7) |
| **AUD-3** | Secure Score capture | Record before/after each apply | verification signal (01 §4.7 [11]) | Graph `Get-MgSecuritySecureScore` (01 §4.7) — **read-only; not a drift target** |
| **AUD-4** | Security alerts enabled | Baseline alert policies on, routed to a monitored inbox/SIEM | SCuBA `MS.DEFENDER.5.1–5.2v1` [7]; `MS.AAD.7.7/7.8` [5] | Alert policies live in **Security & Compliance / portal — not on Linux pwsh** (see §4); **defer / monitor** |
| **AUD-5** | Ship logs to SOC/SIEM | Diagnostic export to SIEM | SCuBA `MS.AAD.4.1v1` [5] | Diagnostic-settings / log export — **outside config surface**; monitor only |
| **AUD-6** | Audit-log retention | ≥ OMB M-21-31 minimum duration | SCuBA `MS.DEFENDER.6.3v1` [7] | Retention policies live in **S&C PowerShell — not on Linux** (see §4); **defer** |

Notes: **AUD-1 and AUD-2 are EXO-native and in-scope** (Linux OK). **AUD-4 and
AUD-6 are Security & Compliance / portal surface and out of the Linux MVP** (doc
02 §1.3, R1 [12]). AUD-3 is our **verification/reporting** hook, never a
desired-state or drift target (score changes daily — doc 01 §4.7 [11]).

---

## 3. Master mapping table

Control → framework ref → mechanism (Graph vs EXO + cmdlet) → profile relevance.
Profile relevance columns: **DS?** = desired-state target (vs read-only/monitor);
**FR-7?** = name-scoped, so a remap target; **Shape** = singleton vs collection
vs policy+rule.

| id | Framework ref | Graph/EXO | Cmdlet (see doc) | DS? | FR-7? | Shape |
|---|---|---|---|---|---|---|
| ID-1 | MS security defaults [8] | Graph | `Update-MgPolicyIdentitySecurityDefaultEnforcementPolicy` (01 §4.5) | ✅ | – | singleton |
| ID-2 | SCuBA MS.AAD.1.1v1 [5] | Graph | `New/Update-MgIdentityConditionalAccessPolicy` (01 §4.1) | ✅ | ✅ | collection |
| ID-3 | SCuBA MS.AAD.3.2v2 [5] | Graph | CA policy (01 §4.1) | ✅ | ✅ | collection |
| ID-4 | CA templates [9] | Graph | CA policy (01 §4.1) | ✅ | ✅ | collection |
| ID-5 | SCuBA MS.AAD.3.1/3.6 [5] | Graph | CA + auth-strength (01 §4.1) | ✅ | ✅ | collection |
| ID-6 | SCuBA MS.AAD.2.1/2.3 [5] | Graph | CA risk conditions (01 §4.1/§4.4) — **P2** | ✅ | ✅ | collection |
| ID-7 | SCuBA MS.AAD.3.9v1 [5] | Graph | CA flow condition (01 §4.1) | ✅ | ✅ | collection |
| ID-8 | SCuBA MS.AAD.3.7v1 [5] | Graph | CA compliant-device (01 §4.1) — **Intune** | ⚠️ defer | ✅ | collection |
| ID-9 | supporting [9] | Graph | `*-MgIdentityConditionalAccessNamedLocation` (01 §4.1) | ✅ | ✅ | collection |
| ID-10 | SCuBA MS.AAD.7.* [5] | Graph | role reads; PIM = Governance (01 §2.3) | 🔎 read | – | collection |
| AM-1 | SCuBA MS.AAD.3.4v1 [5] | Graph | `Update-MgPolicyAuthenticationMethodPolicy` (01 §4.2) | ✅ | – | singleton |
| AM-2 | SCuBA MS.AAD.3.5v2 [5] | Graph | per-method config (01 §4.2) | ✅ | – | singleton+coll |
| AM-3 | SCuBA MS.AAD.3.1v1 [5] | Graph | per-method config (01 §4.2) | ✅ | – | singleton+coll |
| AM-4 | SCuBA MS.AAD.3.3v2 [5] | Graph | Authenticator featureSettings (01 §4.2) | ✅ | – | singleton+coll |
| AM-5 | CIS v5 (community) [2] | Graph | auth-methods policy (01 §4.2) | ✅ | – | singleton |
| MDO-1 | SCuBA MS.DEFENDER.1.* [7] | EXO | `Enable-EOP/ATPProtectionPolicyRule` (02 §3.1) | ✅ | ❌ system-owned | rule |
| MDO-2 | SCuBA MS.DEFENDER.2.* [7] | EXO | `New/Set-AntiPhishPolicy`+rule (02 §3.2) — **Defender** | ✅ | ✅ | policy+rule |
| MDO-3 | CIS [1] | EXO | `New/Set-HostedContentFilterPolicy`+rule (02 §3) | ✅ | ✅ | policy+rule |
| MDO-4 | SCuBA MS.EXO.1.1v2 [6] | EXO | `New/Set-HostedOutboundSpamFilterPolicy`+rule (02 §3) | ✅ | ✅ | policy+rule |
| MDO-5 | CIS [1] | EXO | `New/Set-MalwareFilterPolicy`+rule (02 §3) | ✅ | ✅ | policy+rule |
| MDO-6 | SCuBA presets [7] | EXO | `New/Set-SafeLinksPolicy`+rule (02 §3) — **Defender** | ✅ | ✅ | policy+rule |
| MDO-7 | SCuBA presets [7] | EXO | `New/Set-SafeAttachmentPolicy`+rule (02 §3) — **Defender** | ✅ | ✅ | policy+rule |
| MDO-8 | SCuBA MS.DEFENDER.3.1v1 [7] | EXO | `Set-AtpPolicyForO365` (**verify**) — **Defender** | ✅ | – | singleton |
| MDO-9 | SCuBA MS.EXO.3.1v1 [6] | EXO | `Set-DkimSigningConfig` (02 §3.6) | ⚠️ async | ❌ domain-keyed | per-domain |
| MDO-10 | SCuBA MS.EXO.7.1v1 [6] | EXO | `Set-ExternalInOutlook` (02 §3.8) — **no `-WhatIf`** | ✅ | – | singleton |
| MDO-11 | SCuBA MS.EXO.5.1v1 [6] | EXO | `Set-TransportConfig` (**verify**) | ✅ | – | singleton |
| MDO-12 | SCuBA MS.EXO.2/4.* [6] | DNS | none (registrar) | 🔎 monitor | – | n/a |
| CON-1 | SCuBA MS.AAD.5.2v1 [5] | Graph | authorization policy (01 §4.3/§4.6) | ✅ | – | singleton |
| CON-2 | SCuBA MS.AAD.5.3v1 [5] | Graph | `Set-MgPolicyAdminConsentRequestPolicy` (01 §4.6) | ✅ | – | singleton |
| CON-3 | SCuBA MS.AAD.5.1v1 [5] | Graph | `Update-MgPolicyAuthorizationPolicy` (01 §4.3) | ✅ | – | singleton |
| CON-4 | MS rec (01 §4.3 [11]) | Graph | authorization policy (01 §4.3) | ✅ | – | singleton |
| SHR-1 | SCuBA MS.AAD.8.2v1 [5] | Graph | authorization policy (01 §4.3) | ✅ | – | singleton |
| SHR-2 | SCuBA MS.AAD.8.1v1 [5] | Graph | authorization policy (01 §4.3) | ✅ | – | singleton |
| SHR-3 | SCuBA MS.AAD.8.3v1 [5] | Graph | B2B/cross-tenant settings (**verify**) | ✅ | ⚠️ domain-list | singleton |
| SHR-4 | SCuBA MS.EXO.6.1/6.2 [6] | EXO | `Set-SharingPolicy` (**verify**) | ✅ | ✅ | collection |
| AUD-1 | SCuBA MS.DEFENDER.6.1v1 [7] | EXO | `Set-AdminAuditLogConfig` (**verify**) | ✅ | – | singleton |
| AUD-2 | SCuBA MS.EXO.13.1v1 [6] | EXO | `Set-OrganizationConfig`/`Set-Mailbox` (02 §3.7) | ✅ | – | singleton/coll |
| AUD-3 | verification (01 §4.7 [11]) | Graph | `Get-MgSecuritySecureScore` (01 §4.7) | 🔎 read | – | report |
| AUD-4 | SCuBA MS.DEFENDER.5.* [7] | S&C | alert policies (**not on Linux**) | ⚠️ defer | – | collection |
| AUD-5 | SCuBA MS.AAD.4.1v1 [5] | export | diagnostic settings | 🔎 monitor | – | n/a |
| AUD-6 | SCuBA MS.DEFENDER.6.3v1 [7] | S&C | retention policy (**not on Linux**) | ⚠️ defer | – | collection |

**Split summary:** **Graph ≈ 20** (all Identity/CA, auth-methods, consent,
Entra-side sharing), **EXO ≈ 13** (Defender email policies, auto-forward,
external-sender tag, DKIM, mailbox audit, unified-audit enable, EXO sharing),
**out-of-tool / deferred ≈ 5** (SPF/DMARC DNS, SOC export, and the two
S&C-gated audit items).

---

## 4. Proposed v1 baseline set (the vertical slice)

The MVP should take a **small, deterministic, high-value subset** end-to-end
(save → dry-run → apply → drift → remediate). Chosen for: highest security
value, cleanest cmdlet surface, EXO-on-Linux compatibility, and minimal
licensing prerequisites.

### 4.1 v1 controls (ship these first)

| # | Control | Why it's in v1 |
|---|---|---|
| 1 | **ID-1** security defaults off (when shipping CA) | prerequisite/ordering; single Boolean |
| 2 | **ID-2** block legacy auth (CA) | top attack vector; secure-foundation core |
| 3 | **ID-3** require MFA all users (CA) | highest-value identity control |
| 4 | **AM-2** disable SMS/Voice/Email OTP | pure singleton PATCH; strengthens MFA |
| 5 | **CON-1 + CON-3** restrict user consent + only-admins-register | authorization-policy singleton; big blast-radius reduction |
| 6 | **CON-2** admin consent workflow | singleton; completes the consent story |
| 7 | **SHR-1** restrict guest inviters | singleton; low-risk, high-value |
| 8 | **MDO-1** enable Standard preset security policy | one rule toggle → anti-spam/malware/phish/Safe* |
| 9 | **MDO-4** block external auto-forwarding | classic exfiltration control; EXO policy+rule |
| 10 | **MDO-10** external sender warning | singleton; note the no-`-WhatIf` special-case |
| 11 | **AUD-1 + AUD-2** unified audit log + mailbox auditing | ensures the evidence trail exists |
| — | **AUD-3** Secure Score capture (read) | pre/post verification for the audit log |

This slice is **~11 write controls** spanning **both engines** (Graph singletons
+ one CA collection + EXO preset + one EXO policy+rule + EXO singletons) — enough
to exercise every mechanism class our profile/diff/apply engine must handle:
singleton PATCH, name-scoped collection (FR-7), the policy+rule pairing, the
preset rule toggle, and the no-`-WhatIf` special case.

### 4.2 Defer to later phases

- **Risk-based CA (ID-6), phishing-resistant auth strength (ID-5)** — need
  **Entra ID P2** and per-tenant risk tuning [9][11].
- **Managed-device CA (ID-8)** — needs **Intune** enrolment.
- **PIM / privileged-role governance (ID-10, MS.AAD.7.*)** — `Identity.Governance`
  module, a later phase per doc 01 §2.3 [11].
- **Custom Defender policies (MDO-2, MDO-6, MDO-7)** — needed only where presets
  don't fit or per-group tuning is required; several need a **Defender licence**.
- **DKIM (MDO-9)** — DNS-CNAME dependency and ~96 h rotation make it
  async/out-of-band [12].
- **SharePoint/OneDrive/Teams sharing, SPF/DMARC** — outside the EXO+Graph
  surface (SharePoint/Teams modules; DNS at registrar).

### 4.3 The Security & Compliance constraint on MVP scope

Per doc 02 §1.3 [12], **`Connect-IPPSSession` (Security & Compliance PowerShell)
is not available in PowerShell 7 on Linux/macOS.** This directly removes the
following framework controls from the containerized MVP:

- **DLP** — SCuBA `MS.DEFENDER.4.1–4.6` [7] (Purview DLP policies).
- **Audit-log retention policies** — SCuBA `MS.DEFENDER.6.3v1` [7] (OMB M-21-31
  duration) is set via S&C `*-UnifiedAuditLogRetentionPolicy`.
- **Sensitivity/retention labels** and likely the **alert policies** behind
  SCuBA `MS.DEFENDER.5.*` [7].

Crucially, ***enabling* the unified audit log (AUD-1) is Exchange-Online-side**
(`Set-AdminAuditLogConfig`) and stays in scope; only its **retention** is S&C.
The MVP baseline is therefore correctly scoped to **Graph + EXO-native**
controls, and the profile should mark S&C-gated controls as "requires Windows
execution path" rather than silently omitting them.

---

## 5. Key takeaways / recommendations

- **Adopt SCuBA IDs as the profile's control vocabulary.** They are stable,
  free, diffable, and map one-to-one onto the cmdlets in docs 01/02. Store each
  profile item tagged with its `MS.*` ID (and the pinned SCuBA/CIS version) so
  drift reports speak the framework's language [4][5][6][7].
- **Ship "enable the Standard preset security policy" as the marquee EXO win.**
  It is one rule toggle that delivers the bulk of the Defender email baseline
  with Microsoft-maintained settings — smallest surface, deterministic,
  highest value (doc 02 §3.1 [12]; MS presets [10]).
- **Lead identity with the CA secure-foundation trio** (block legacy auth, MFA
  all users, MFA for admins) plus the **authorization-policy consent/sharing
  singletons** — these are P1-friendly, high-value, and (for the singletons)
  inherently idempotent [8][9][5][11].
- **Encode the ordering constraints** the frameworks imply: security defaults
  **off** before CA enforces (ID-1 → ID-2/3), policy **before** rule for every
  EXO pairing, named locations before location-CA (docs 01 §4.5, 02 §2 [11][12]).
- **Two engines, one profile schema.** Graph objects are singletons/collections;
  EXO objects are policy+rule pairs. The profile model already anticipated both
  (docs 01/02) — the control list here confirms the split is ~20 Graph / ~13 EXO.
- **Licence- and platform-gate the apply.** Detect Defender/P2/Intune presence
  and the Linux-vs-Windows S&C boundary in **dry-run** and fail loud (NFR-6)
  rather than half-applying [9][10][12].
- **Pin the framework version in every profile** (NFR-7). CIS renumbers between
  releases and SCuBA revises policy `v` suffixes; a profile that doesn't record
  which version it targets can't produce a trustworthy compliance claim.
- **Treat opinionated values as remappable/tunable, previewed by dry-run.** Names
  (FR-7) and recommended values are per-client; dry-run (FR-8) is the guardrail
  that makes an opinionated baseline safe to apply.

## 6. Open questions / risks

- **R1 — Framework version drift (med, NFR-7).** CIS reorders and renumbers
  controls (v5.0.0 removed/added items [2]) and the exact current version could
  not be pinned from the registration-gated PDF in this pass; SCuBA revises `v`
  suffixes. **Verify every control number and recommended value against the
  pinned framework version** before shipping. The specific CIS recommendation
  IDs were deliberately left un-cited here for this reason.
- **R2 — Cmdlets referenced but not in docs 01/02 (med).** MDO-8
  (`Set-AtpPolicyForO365`), MDO-11 (`Set-TransportConfig`), SHR-3 (B2B/cross-
  tenant settings), SHR-4 (`Set-SharingPolicy`), and AUD-1
  (`Set-AdminAuditLogConfig`) are named from the framework/Microsoft docs but are
  **not** in the sibling surface docs. Confirm exact cmdlet, parameters, and
  `-WhatIf` support against the pinned modules; extend docs 01/02 if adopted.
- **R3 — Newer CA condition fields (med).** ID-7 (device-code-flow block) and
  AM-1 (`policyMigrationState`), AM-4 (Authenticator `featureSettings`), AM-5
  (system-preferred MFA) reference **specific field names not verified against a
  cmdlet reference** in this pass. Verify with `Find-MgGraphCommand`/the pinned
  SDK (doc 01 §3 [11]); some may be **beta-only**.
- **R4 — Licensing gating (med).** Risk-based CA (ID-6) needs **P2**;
  phishing-resistant strength and compliant-device CA need P2/Intune; Safe
  Links/Attachments and impersonation protection need **Defender for Office
  365**. Dry-run must detect the SKU and gate/annotate, or apply fails on
  under-licensed tenants (doc 02 R2 [12]).
- **R5 — Controls with no clean PowerShell/Linux surface (med).** SPF/DMARC are
  **DNS** (registrar, not our tool); DLP, audit retention, sensitivity/retention
  labels and some alert policies are **S&C-only → not on Linux** (doc 02 R1
  [12]); SOC/SIEM export (AUD-5) is diagnostic-settings, out of config scope.
  Decide per control: monitor-only, mark "needs Windows", or explicitly
  out-of-scope.
- **R6 — Preset vs custom drift semantics (med).** For MDO-1 the frameworks want
  a *state* ("preset enabled, all users covered"), but preset settings are
  Microsoft-owned and not diffable field-by-field — model preset controls as a
  **rule-state + coverage** check, not a settings diff (doc 02 §2.1, §3.1 [12]).
- **R7 — Opinionated values need per-client tuning (low-med).** Bulk thresholds,
  impersonation lists, guest-domain allow-lists, and quarantine actions are
  judgement calls. Reinforces FR-7 (remap names) and FR-8 (preview values) — the
  baseline ships defaults, not mandates.
- **R8 — Read-only vs desired-state confusion (low).** Secure Score (AUD-3),
  risky-user reads (ID-10), and DNS/SIEM posture are **monitoring**, not
  desired-state — they must never enter the drift-diff as config targets (doc 01
  §4.7 [11]).

---

## 8. Sources

Primary framework and vendor pages fetched 2026-07-22. Internal docs are sibling
research in this repo. Community sources are labelled.

1. **CIS Microsoft 365 Foundations Benchmark** (landing; levels, community
   consensus, mid-2026 updates) —
   https://www.cisecurity.org/benchmark/microsoft_365
2. **CIS M365 Benchmark v5.0.0 — what's new** (v5.0.0 released 2025-04-30; L1/L2;
   added device-code blocking & system-preferred MFA; removed security-defaults
   item) — *community* — https://mondoo.com/blog/microsoft-365-cis-benchmark-5-0-what-you-need-to-know
3. **CISA — Secure Cloud Business Applications (SCuBA) project** (authority,
   ScubaGear as OPA/Rego assessment tool) —
   https://www.cisa.gov/resources-tools/services/secure-cloud-business-applications-scuba-project
4. **cisagov/ScubaGear** (baseline docs per product: aad/exo/defender/sharepoint/
   teams/powerplatform/powerbi) —
   https://github.com/cisagov/ScubaGear/tree/main/PowerShell/ScubaGear/baselines
5. **SCuBA Microsoft Entra ID baseline** (`MS.AAD.*`: 1.1 legacy auth, 2.1/2.3
   risk, 3.1–3.9 MFA/auth-methods, 5.1–5.7 app registration/consent, 7.* priv
   roles, 8.* guests) —
   https://raw.githubusercontent.com/cisagov/ScubaGear/main/PowerShell/ScubaGear/baselines/aad.md
6. **SCuBA Exchange Online baseline** (`MS.EXO.*`: 1.1 auto-forward, 2.2 SPF, 3.1
   DKIM, 4.* DMARC, 5.1 SMTP AUTH, 6.* sharing, 7.1 external warnings, 13.1
   mailbox audit) —
   https://raw.githubusercontent.com/cisagov/ScubaGear/main/PowerShell/ScubaGear/baselines/exo.md
7. **SCuBA Defender baseline** (`MS.DEFENDER.*`: 1.* presets, 2.* impersonation,
   3.1 Safe Attachments SPO/ODB/Teams, 4.* DLP, 5.* alerts, 6.1/6.3 audit
   log/retention) —
   https://raw.githubusercontent.com/cisagov/ScubaGear/main/PowerShell/ScubaGear/baselines/defender.md
8. **Microsoft Entra security defaults** (MFA registration/admin/when-necessary,
   block legacy auth, block device code, protect ARM; mutually exclusive with CA;
   free tier) — https://learn.microsoft.com/en-us/entra/fundamentals/security-defaults
9. **Conditional Access templates** (secure-foundation / zero-trust / protect-
   administrator / emerging-threats categories; P2 for risk-based; report-only
   default; JSON export) —
   https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-conditional-access-policy-common
10. **Defender for Office 365 preset security policies** (Standard/Strict/Built-in
    protection; non-configurable curated settings; enable via
    EOP/ATP protection-policy rules) —
    https://learn.microsoft.com/en-us/defender-office-365/preset-security-policies
11. **Internal:** `docs/research/01-microsoft-graph-surface.md` — Graph cmdlet
    surface (CA, auth methods, authorization policy, security defaults, consent,
    risk, Secure Score).
12. **Internal:** `docs/research/02-exchange-online-surface.md` — EXO/Defender
    cmdlet surface (presets, policy+rule pairing, org config, DKIM, mailbox audit,
    external-sender tag; S&C-not-on-Linux constraint).
13. **Internal:** `docs/decisions/0003-mvp-scope-security-baseline-first.md` —
    ADR-0003 MVP scope; OPEN-QUESTIONS Q6.

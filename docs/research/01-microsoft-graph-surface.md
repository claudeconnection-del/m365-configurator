# Research 01 — Microsoft Graph PowerShell SDK: the tenant security-baseline surface

> **Phase 1 research** for `m365-configurator`. Scope: the Microsoft Graph
> PowerShell SDK (`Microsoft.Graph`) configuration surface relevant to a tenant
> **security baseline** — the modules, the read/write cmdlets, the least-privilege
> **delegated** scopes, dry-run reality, and the idempotency/drift gotchas that
> directly shape our profile, dry-run, and drift-detection engines.
>
> **Author:** research sub-agent · **Date:** 2026-07-22 · **API version:** Microsoft Graph **v1.0** (SDK v2.x)
>
> Every nontrivial claim is cited inline `[n]`; see [Sources](#sources).
> Exchange Online, Microsoft365DSC, and auth-lifecycle/credential-cleanup are covered in sibling research docs.

---

## Contents

1. [How to read this doc](#1-how-to-read-this-doc)
2. [Module structure & footprint](#2-module-structure--footprint-minimal-deps)
3. [Delegated auth & least-privilege scopes](#3-delegated-auth--least-privilege-scopes)
4. [Security-baseline areas in detail](#4-security-baseline-areas-in-detail)
5. [Master reference table](#5-master-reference-table)
6. [Dry-run reality: `-WhatIf` does not do what we need](#6-dry-run-reality--whatif-does-not-do-what-we-need)
7. [Idempotency & drift-comparison gotchas](#7-idempotency--drift-comparison-gotchas)
8. [Key takeaways / recommendations](#8-key-takeaways--recommendations)
9. [Open questions / risks](#9-open-questions--risks)
10. [Sources](#10-sources)

---

## 1. How to read this doc

- **Cmdlet naming** follows the SDK convention: `<Verb>-Mg<Path>`. `Get-` reads,
  `New-` creates (HTTP `POST`), `Update-` patches (HTTP `PATCH`), `Set-` replaces
  (`PUT`/`PATCH`), `Remove-` deletes (`DELETE`).
- **"Singleton"** = a tenant has exactly one instance (e.g. the authorization
  policy, security defaults). **"Collection"** = many instances keyed by `Id`
  (e.g. Conditional Access policies, named locations).
- **Scopes** listed are **delegated (work/school account)**, least-privileged
  first. Application (app-only) scopes are out of scope for the MVP per the
  device-code / interactive-delegated auth decision.

---

## 2. Module structure & footprint (minimal-deps)

### 2.1 Meta-module vs sub-modules

`Microsoft.Graph` is a **roll-up meta-module**: installing it pulls in **~40 sub-modules**
(Microsoft's own docs say "over 47 sub modules"; the shipped v2 count is in the
high-30s) as dependencies. A separate `Microsoft.Graph.Beta` roll-up mirrors it
against the beta endpoint. **We should target v1.0 only** — Microsoft explicitly
recommends v1.0 for scripts and warns beta "can change… without notice" [1].

> **Only cmdlets from the installed sub-modules are available.** Microsoft's
> install doc says plainly: *"Consider only installing the necessary modules,
> including `Microsoft.Graph.Authentication` which is installed by default when
> you opt to install the sub modules individually."* [1]

**`Microsoft.Graph.Authentication` is the mandatory core** — every other
sub-module depends on it, and it provides `Connect-MgGraph`, `Disconnect-MgGraph`,
`Get-MgContext`, `Invoke-MgGraphRequest`, and the discovery cmdlets
`Find-MgGraphCommand` / `Find-MgGraphPermission` [1][2][7].

### 2.2 Footprint — this is a real minimal-deps concern

- The full bundle has historically been **large and slow**: a Microsoft-tracked
  issue measured **33 modules / 4254 commands / 947 MB on disk** and flagged the
  performance hit "when modules are deployed into containers or serverless
  execution environments" [8a] — directly relevant to our containerized tenet.
- **SDK v2 roughly halved the size** and is "up to **58%** smaller" when using the
  v1-only module vs v1+beta [8b][8c].
- On Windows PowerShell 5.1 the full import can hit the `$MaximumFunctionCount`
  ceiling; **PowerShell 7 is the recommended runtime** and avoids this [1] — aligns
  with our "Linux + PowerShell 7" target.

### 2.3 Which sub-modules the security baseline actually needs

The MVP baseline maps to a **small, fixed set** of sub-modules — we do **not**
need the meta-module:

| Sub-module | Baseline areas it covers | Needed for MVP? |
|---|---|---|
| `Microsoft.Graph.Authentication` | Connect/disconnect, context, permission & command discovery | **Yes (core)** |
| `Microsoft.Graph.Identity.SignIns` | Conditional Access + named locations, auth-methods policy, authorization policy, security defaults, admin-consent-request & permission-grant policies, risky-users read | **Yes (does most of the work)** |
| `Microsoft.Graph.Security` | Secure Score + control profiles (read) | **Yes** |
| `Microsoft.Graph.Identity.DirectoryManagement` | Org/tenant settings, domains, directory roles | Likely (adjacent) |
| `Microsoft.Graph.Identity.Governance` | PIM, access reviews, entitlement mgmt | Later phase |
| `Microsoft.Graph.Users` / `.Groups` | Resolve users/groups referenced by policies (targets, exclusions) | As needed for name-remapping |

> **Takeaway for the build:** install and import **`Microsoft.Graph.Authentication` +
> `Microsoft.Graph.Identity.SignIns` + `Microsoft.Graph.Security`** (plus
> `.DirectoryManagement`) at **pinned versions**. That covers the entire baseline
> surface below while keeping the dependency set tiny, the container small, and
> import fast. This satisfies NFR-3 (minimal deps) and NFR-7 (pinned versions).

```powershell
# Selective, pinned install (illustrative)
$ver = '2.30.0'
'Microsoft.Graph.Authentication',
'Microsoft.Graph.Identity.SignIns',
'Microsoft.Graph.Security',
'Microsoft.Graph.Identity.DirectoryManagement' |
  ForEach-Object { Install-Module $_ -RequiredVersion $ver -Scope CurrentUser -Repository PSGallery }
```

---

## 3. Delegated auth & least-privilege scopes

- The SDK supports **delegated** and **app-only** auth; we use **delegated**
  (interactive browser + device code), consenting to scopes at connect time via
  `Connect-MgGraph -Scopes …` [2][7]. Graph PowerShell permissions are **not
  pre-authorized** — you request exactly what you need, and consent is incremental
  [9 migration-guide "least privilege"].
- **Read vs write scopes are distinct.** For a **dry-run / drift scan we only need
  the `*.Read.All` scopes**; we escalate to the narrower `*.ReadWrite.*` scopes
  **only when the operator chooses to apply**. This is a natural fit for our
  "dry-run before apply" flow and least-privilege posture.
- **Scope discovery is programmable** — we do not have to hard-code scope tables:
  - `Find-MgGraphCommand -Command <cmdlet> | Select -First 1 -ExpandProperty Permissions`
    returns the accepted scopes (and the API path) for any cmdlet [2][7].
  - `Find-MgGraphPermission <search>` resolves permission names/ids [2b].
  - Both live in `Microsoft.Graph.Authentication`, so they're always available.
- Consenting to these scopes generally requires an admin (Global Admin or
  Privileged Role Administrator) to grant [2].

> **Design note:** we can build our per-area scope map dynamically at runtime with
> `Find-MgGraphCommand`, then request the **union of the Read scopes** for a scan
> and the **union of the ReadWrite scopes** for an apply. This keeps the tool
> correct even if Microsoft adjusts a cmdlet's accepted scopes (supports NFR-7
> stability without hard-coding).

---

## 4. Security-baseline areas in detail

For each area: what it is, the cmdlets (read/write), module, delegated scopes,
singleton/collection shape, idempotency, `-WhatIf`, how a desired-state profile
maps to parameters, and drift gotchas.

> **`-WhatIf` / `-Confirm` note (applies to every write cmdlet below):** all
> `New-/Update-/Set-/Remove-` Mg cmdlets declare `SupportsShouldProcess`, so
> `-WhatIf` and `-Confirm` **exist** on all of them (verified in the syntax of the
> named-location, security-defaults, and auth-method-config cmdlets [4][6b][3b]).
> **But `-WhatIf` is local-only and near-useless as a real dry-run** — see
> [§6](#6-dry-run-reality--whatif-does-not-do-what-we-need).

---

### 4.1 Conditional Access policies (+ named locations)

**Module:** `Microsoft.Graph.Identity.SignIns` · **Shape:** collection (keyed by `Id`)

CA is the heart of the baseline (MFA enforcement, block legacy auth, device
compliance, location/risk gating). Since the standalone Identity-Protection risk
policies are retiring (see [§4.4](#44-identity-protection-risk-policies)),
**risk-based access is also modeled as CA policies** here.

| Operation | Cmdlet | HTTP | Delegated scope(s) |
|---|---|---|---|
| Read | `Get-MgIdentityConditionalAccessPolicy [-ConditionalAccessPolicyId <id>]` | GET | `Policy.Read.All` |
| Create | `New-MgIdentityConditionalAccessPolicy -BodyParameter <hash>` | POST | `Policy.ReadWrite.ConditionalAccess` |
| Update | `Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId <id> -BodyParameter <hash>` | PATCH | `Policy.ReadWrite.ConditionalAccess` |
| Delete | `Remove-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId <id>` | DELETE | `Policy.ReadWrite.ConditionalAccess` |
| Named locations | `Get/New/Update/Remove-MgIdentityConditionalAccessNamedLocation` | * | read `Policy.Read.All`; write `Policy.ReadWrite.ConditionalAccess` |

Scopes verified in the cmdlet reference [3][4].

**Desired-state → parameter mapping.** The policy is a nested object supplied as a
hashtable to `-BodyParameter`. Top-level: `displayName`, `state`
(`enabled`/`disabled`/`enabledForReportingButNotEnforced`), `conditions`,
`grantControls`, `sessionControls` [3].

```powershell
$params = @{
  displayName = "Require MFA for all users"
  state       = "enabled"
  conditions  = @{
    clientAppTypes = @("all")
    applications   = @{ includeApplications = @("All") }
    users          = @{ includeUsers = @("All"); excludeUsers = @($breakGlassId) }
  }
  grantControls = @{ operator = "OR"; builtInControls = @("mfa") }
}
New-MgIdentityConditionalAccessPolicy -BodyParameter $params
```

Key nested enums/fields from the model [3]:
- `conditions.clientAppTypes`: `all, browser, mobileAppsAndDesktopClients, exchangeActiveSync, other` (used to **block legacy auth**).
- `conditions.signInRiskLevels` / `userRiskLevels`: `low, medium, high, none, …` (risk-based CA; **requires Entra ID P2**).
- `conditions.locations.includeLocations` / `excludeLocations`: named-location `Id`s, plus keywords `All` / `AllTrusted`.
- `grantControls.builtInControls`: `block, mfa, compliantDevice, domainJoinedDevice, passwordChange, …`; `operator`: `AND`/`OR`.
- `grantControls.authenticationStrength`: reference to an authentication-strength policy.
- `sessionControls`: `signInFrequency`, `persistentBrowser`, `applicationEnforcedRestrictions`, `cloudAppSecurity`.

**Named locations** are polymorphic — the body **requires an `@odata.type`
discriminator** (`#microsoft.graph.ipNamedLocation` or
`#microsoft.graph.countryNamedLocation`), and IP ranges each need their own
`@odata.type` (`iPv4CidrRange` / `iPv6CidrRange`) [4].

**Idempotency & drift gotchas (CA):**
- **`New-` is not idempotent** — it always creates a *new* policy, so re-applying a
  profile silently produces **duplicates by display name**. Our engine must
  **match existing policies by `displayName`** and route to `Update-` vs `New-`.
- **Read-only fields** to strip before diffing: `id`, `createdDateTime`,
  `modifiedDateTime`, `templateId` [3].
- Policies reference **users/groups/roles/apps by GUID** (`includeGroups`,
  `excludeUsers`, `includeApplications`, …) — GUIDs differ per tenant, so these are
  prime targets for **name-remapping (FR-7)** when porting a profile.
- **Array ordering is not guaranteed**; empty vs null nested objects behave
  inconsistently on `PATCH` (known issues: setting `includeServicePrincipals=@()`
  or `$null` can result in an empty body / no-op or a schema error) [10a][10b].
  Normalize (sort arrays, drop nulls) before comparing.

---

### 4.2 Authentication methods policy (+ per-method configs)

**Module:** `Microsoft.Graph.Identity.SignIns` · **Shape:** singleton, with a
collection of per-method configurations

Controls which methods users can register/use (FIDO2, Microsoft Authenticator,
SMS, Temporary Access Pass, Email OTP, Voice, Software OATH, X.509) and the
registration-campaign / enforcement settings — the modern replacement for the
legacy per-method MFA settings.

| Operation | Cmdlet | Delegated scope(s) |
|---|---|---|
| Read whole policy | `Get-MgPolicyAuthenticationMethodPolicy` | `Policy.Read.All` *(or `Policy.ReadWrite.AuthenticationMethod`)* |
| Update whole policy | `Update-MgPolicyAuthenticationMethodPolicy -BodyParameter <hash>` | `Policy.ReadWrite.AuthenticationMethod` |
| Read one method | `Get-MgPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration -AuthenticationMethodConfigurationId <name>` | `Policy.Read.All` |
| Update one method | `Update-MgPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration -AuthenticationMethodConfigurationId <name> -BodyParameter <hash>` | `Policy.ReadWrite.AuthenticationMethod` |

Scopes verified in the cmdlet reference [5][5b].

- `-AuthenticationMethodConfigurationId` is the **method name**, e.g. `Fido2`,
  `MicrosoftAuthenticator`, `Sms`, `TemporaryAccessPass`, `Email`, `Voice`,
  `SoftwareOath`, `X509Certificate` [5b].
- **Per-method updates are the practical, idempotent unit** — patch one method's
  `state` (`enabled`/`disabled`) and `includeTargets`/`excludeTargets` rather than
  PATCHing the whole nested policy.
- On `GET`, `authenticationMethodConfigurations` is auto-expanded [5].

**Drift gotchas:** `displayName`, `description`, `policyVersion`,
`lastModifiedDateTime`, `id` are **read-only** [5] — exclude from diff. Each method
config is polymorphic (its own `@odata.type`), so profile storage should key
configs by method id and diff per-method.

---

### 4.3 Authorization policy (tenant default user settings)

**Module:** `Microsoft.Graph.Identity.SignIns` · **Shape:** singleton (id `authorizationPolicy`)

This one singleton carries a lot of high-value baseline hardening: what the
**default user role** may do, guest-invite policy, SSPR, and the **user app-consent
switch**.

| Operation | Cmdlet | Delegated scope(s) |
|---|---|---|
| Read | `Get-MgPolicyAuthorizationPolicy` | `Policy.Read.All` |
| Update | `Update-MgPolicyAuthorizationPolicy -BodyParameter <hash>` | `Policy.ReadWrite.Authorization` |

Scope for write verified in the cmdlet reference [6].

**Baseline-relevant fields** [6]:
- `defaultUserRolePermissions.allowedToCreateApps` — "Users can register applications" (harden → `$false`).
- `defaultUserRolePermissions.allowedToCreateSecurityGroups`
- `defaultUserRolePermissions.allowedToCreateTenants` — restrict non-admins creating tenants.
- `defaultUserRolePermissions.allowedToReadOtherUsers` — **do not set to `$false`** (Microsoft warning).
- `defaultUserRolePermissions.permissionGrantPoliciesAssigned` — **the user-consent control** (see [§4.6](#46-admin-consent--app-consent-policies)).
- `allowInvitesFrom` — who can invite guests.
- `allowUserConsentForRiskyApps` — keep `$false` (Microsoft recommendation).
- `allowedToUseSspr`, `allowEmailVerifiedUsersToJoinOrganization`, `blockMsolPowerShell`, `guestUserRoleId`.

```powershell
$params = @{
  defaultUserRolePermissions = @{ allowedToCreateApps = $false }
  allowUserConsentForRiskyApps = $false
}
Update-MgPolicyAuthorizationPolicy -BodyParameter $params
```

**Idempotency & drift gotchas:** singleton → **always `Update-` (PATCH), never
`New-`** → naturally idempotent. `PATCH` merges, so we can send only the fields we
manage. `description`/`displayName` are **required** on the object model but are
fixed system values — treat as read-only for drift. `guestUserRoleId` is a role
**template GUID** (well-known, tenant-independent), so it's safe across tenants.

---

### 4.4 Identity Protection risk policies

**Module:** `Microsoft.Graph.Identity.SignIns` · **Requires Entra ID P2**

> **Important status change:** the **standalone** Identity-Protection *user-risk*
> and *sign-in-risk* policies are **being retired — read-only since 2025, and stop
> enforcing on 1 October 2026.** Microsoft's guidance is to **migrate them into
> Conditional Access** (using the `userRiskLevels` / `signInRiskLevels` conditions
> covered in [§4.1](#41-conditional-access-policies--named-locations)) [11a][11b][11c].

**Consequence for us:** do **not** build a desired-state writer for the legacy risk
policy. Model risk enforcement as **CA policies** (§4.1). Keep two roles for the
Identity-Protection API here:

| Purpose | Cmdlet(s) | Delegated scope(s) |
|---|---|---|
| Read risky users (monitoring/audit) | `Get-MgRiskyUser`, `Get-MgRiskyUserHistory` | `IdentityRiskyUser.Read.All` |
| Read risk detections | `Get-MgRiskDetection` | `IdentityRiskEvent.Read.All` |
| Read risky service principals | `Get-MgRiskyServicePrincipal` | `IdentityRiskyServicePrincipal.Read.All` |
| Remediate (dismiss/confirm compromised) | `Invoke-MgDismissRiskyUser`, `Confirm-MgRiskyUserCompromised` | `IdentityRiskyUser.ReadWrite.All` |

> Scope names here follow the documented Identity-Protection permission set; confirm
> at build time with `Find-MgGraphCommand` (these were not each individually
> re-verified against a cmdlet reference page in this pass — see [§9](#9-open-questions--risks)).
> These reads feed **audit logging (NFR-5)** and dashboards, not the desired-state config.

---

### 4.5 Security defaults

**Module:** `Microsoft.Graph.Identity.SignIns` · **Shape:** singleton

The tenant-wide on/off switch for Microsoft's baseline protections.

| Operation | Cmdlet | Delegated scope(s) |
|---|---|---|
| Read | `Get-MgPolicyIdentitySecurityDefaultEnforcementPolicy` | `Policy.Read.All` |
| Update | `Update-MgPolicyIdentitySecurityDefaultEnforcementPolicy -BodyParameter @{ isEnabled = $false }` | `Policy.ReadWrite.SecurityDefaults` *(or `Policy.ReadWrite.ConditionalAccess`)* |

The only meaningful field is `isEnabled` (Boolean). Scopes verified in the cmdlet
reference [6b].

```powershell
Update-MgPolicyIdentitySecurityDefaultEnforcementPolicy -BodyParameter @{ isEnabled = $false }
```

- **Singleton → idempotent by construction** (PATCH only).
- **Mutual exclusivity:** security defaults and Conditional Access **cannot both be
  active**. A baseline that ships CA policies must first set
  `isEnabled = $false`, and our dry-run should **flag this dependency** so an apply
  doesn't half-succeed (NFR-6 loud/fast failure). Order matters in the apply plan.
- Read-only for drift: `id`, `displayName`, `description` [6b].

---

### 4.6 Admin consent / app consent policies

App/consent governance spans **three** related surfaces, all in
`Microsoft.Graph.Identity.SignIns`:

**(a) User-consent setting** — actually lives on the **authorization policy**
(§4.3): `defaultUserRolePermissions.permissionGrantPoliciesAssigned`. Format
`managePermissionGrantsForSelf.{policyId}`; an **empty list disables user consent
entirely** [6]. Example values: `managePermissionGrantsForSelf.microsoft-user-default-low`.

```powershell
# Restrict user consent to low-risk permissions from verified publishers
Update-MgPolicyAuthorizationPolicy -BodyParameter @{
  defaultUserRolePermissions = @{
    permissionGrantPoliciesAssigned = @("managePermissionGrantsForSelf.microsoft-user-default-low")
  }
}
# ...or disable user consent completely with @()
```

**(b) Admin-consent-request policy** — the "admin consent workflow" (users request,
admins approve).

| Operation | Cmdlet | Delegated scope(s) |
|---|---|---|
| Read | `Get-MgPolicyAdminConsentRequestPolicy` | `Policy.Read.All` (or `Policy.ReadWrite.ConsentRequest`) |
| Update | `Set-MgPolicyAdminConsentRequestPolicy -BodyParameter <hash>` | `Policy.ReadWrite.ConsentRequest` |

Read scopes verified in the cmdlet reference [12]. Fields: `isEnabled`,
`notifyReviewers`, `remindersEnabled`, `requestDurationInDays`, `reviewers[]`.
Singleton → idempotent (PATCH).

**(c) Permission-grant policies** — the app-consent policy *definitions* that (a)
references.

| Operation | Cmdlet | Delegated scope(s) |
|---|---|---|
| Read | `Get-MgPolicyPermissionGrantPolicy` | `Policy.Read.All` / `Policy.Read.PermissionGrant` |
| Create/Update/Delete | `New/Update/Remove-MgPolicyPermissionGrantPolicy` | `Policy.ReadWrite.PermissionGrant` |

> Built-in policies (`microsoft-user-default-low`, etc.) are usually just
> *referenced*, not authored; custom permission-grant policies are an advanced,
> later-phase concern.

---

### 4.7 Secure Score (read-only)

**Module:** `Microsoft.Graph.Security` · **Shape:** read-only time-series report

| Operation | Cmdlet | Delegated scope(s) |
|---|---|---|
| Read scores (daily snapshots) | `Get-MgSecuritySecureScore [-Top n]` | `SecurityEvents.Read.All` |
| Read control catalog | `Get-MgSecuritySecureScoreControlProfile [-SecureScoreControlProfileId <id>]` | `SecurityEvents.Read.All` |

Scopes and module verified in the cmdlet reference [13][13b]. Useful fields:
`currentScore`, `maxScore`, `activeUserCount`, `controlScores[]`
(`controlName`/`controlCategory`/`score`), `averageComparativeScores[]` (industry
benchmarks) [13b].

- **Read-only in practice.** Secure Score is *computed by Microsoft*; it is **not a
  desired-state target** and should never appear in a profile as something to
  "apply." (Auto-generated `New-`/`Update-MgSecuritySecureScore` cmdlets exist but
  are meaningless for configuration.)
- **Value to us:** a pre/post **verification & reporting** signal — capture
  `currentScore` before/after an apply for the audit log (NFR-5), and surface
  `controlScores` as "what the baseline still doesn't cover."
- **Not for drift comparison** — the score legitimately changes daily regardless of
  config, so diffing it would produce constant false-positive "drift."

---

## 5. Master reference table

| Area | Read cmdlet | Write cmdlet(s) | Module | Read scope | Write scope | Shape | `-WhatIf`? |
|---|---|---|---|---|---|---|---|
| Conditional Access | `Get-MgIdentityConditionalAccessPolicy` | `New-`/`Update-`/`Remove-MgIdentityConditionalAccessPolicy` | Identity.SignIns | `Policy.Read.All` | `Policy.ReadWrite.ConditionalAccess` | collection | present (local-only) |
| Named locations | `Get-MgIdentityConditionalAccessNamedLocation` | `New-`/`Update-`/`Remove-…NamedLocation` | Identity.SignIns | `Policy.Read.All` | `Policy.ReadWrite.ConditionalAccess` | collection | present (local-only) |
| Auth methods policy | `Get-MgPolicyAuthenticationMethodPolicy` (+ `…AuthenticationMethodConfiguration`) | `Update-MgPolicyAuthenticationMethodPolicy` (+ per-method) | Identity.SignIns | `Policy.Read.All` | `Policy.ReadWrite.AuthenticationMethod` | singleton + collection | present (local-only) |
| Authorization policy | `Get-MgPolicyAuthorizationPolicy` | `Update-MgPolicyAuthorizationPolicy` | Identity.SignIns | `Policy.Read.All` | `Policy.ReadWrite.Authorization` | singleton | present (local-only) |
| Security defaults | `Get-MgPolicyIdentitySecurityDefaultEnforcementPolicy` | `Update-MgPolicyIdentitySecurityDefaultEnforcementPolicy` | Identity.SignIns | `Policy.Read.All` | `Policy.ReadWrite.SecurityDefaults` | singleton | present (local-only) |
| Admin-consent-request | `Get-MgPolicyAdminConsentRequestPolicy` | `Set-MgPolicyAdminConsentRequestPolicy` | Identity.SignIns | `Policy.Read.All` | `Policy.ReadWrite.ConsentRequest` | singleton | present (local-only) |
| User consent / app-consent policy | `Get-MgPolicyAuthorizationPolicy` / `Get-MgPolicyPermissionGrantPolicy` | `Update-MgPolicyAuthorizationPolicy` / `New-/Update-MgPolicyPermissionGrantPolicy` | Identity.SignIns | `Policy.Read.All` | `Policy.ReadWrite.Authorization` / `Policy.ReadWrite.PermissionGrant` | singleton / collection | present (local-only) |
| Identity Protection (risk) | `Get-MgRiskyUser`, `Get-MgRiskDetection` | *(model via CA; remediate via `Invoke-MgDismissRiskyUser`)* | Identity.SignIns | `IdentityRiskyUser.Read.All`, `IdentityRiskEvent.Read.All` | `IdentityRiskyUser.ReadWrite.All` | collection | n/a for config |
| Secure Score | `Get-MgSecuritySecureScore`, `Get-MgSecuritySecureScoreControlProfile` | *(read-only)* | Security | `SecurityEvents.Read.All` | — | report | n/a |

*"present (local-only)"* = the `-WhatIf` switch exists but does not validate against
the tenant (see next section).

---

## 6. Dry-run reality: `-WhatIf` does not do what we need

This is the single most important finding for **FR-8 (dry run)** and **FR-10 (drift)**.

- Every write cmdlet has `-WhatIf`/`-Confirm` because the generated cmdlets declare
  `SupportsShouldProcess` [3b][4][6b]. **But** `-WhatIf` is the **stock PowerShell
  ShouldProcess** behavior: it short-circuits **before** the HTTP call and prints a
  generic *"Performing the operation … on target …"* line. It **does not**:
  - call Graph,
  - perform **server-side validation**, or
  - produce a **property-level diff** of what would change.
- The community has explicitly asked Microsoft to make `-WhatIf` meaningful
  ("**Extend `-WhatIf` parameter**", issue #877) — i.e. it is acknowledged as
  minimal today [14].

> **Design consequence:** our dry-run and drift engine **must not rely on
> `-WhatIf`.** It must be built as **`Get-<current>` → normalize → structural diff
> against the desired profile**, and render that diff ourselves. This is also what
> gives us the "readable, reviewable diff" the tenets demand (NFR-9). `-WhatIf` can
> still be passed through on the *apply* path as a cheap secondary guard, but it is
> not the source of truth for the preview.

---

## 7. Idempotency & drift-comparison gotchas

Concrete rules the profile/diff/remediation engines must implement:

1. **`New-` (POST) is not idempotent for collections.** Re-applying creates
   duplicates (notably CA policies and named locations share no natural unique key
   but `displayName`). **Match existing objects by `displayName`** (or a stored
   `Id` map) and route to `Update-` vs `New-`.
2. **Singletons are safe** (authorization policy, security defaults,
   admin-consent-request, auth-methods policy) — always PATCH; inherently
   idempotent.
3. **`Update-` is a `PATCH` (merge), not a replace.** Fields we omit are left
   untouched. Good for surgical changes; **bad if a profile means "these are the
   *only* values"** — for full-replacement semantics on nested collections we must
   read, merge deliberately, and write the whole sub-object.
4. **`null` vs `@()` vs missing** behave inconsistently on PATCH — e.g. clearing
   `includeServicePrincipals` via `$null`/`''`/`@()` has produced no-ops or schema
   errors [10a][10b]. Decide and test an explicit convention per field.
5. **Strip read-only/server-populated properties before diffing:** `id`,
   `createdDateTime`, `modifiedDateTime`, `templateId`, `policyVersion`,
   `lastModifiedDateTime`, and the fixed `displayName`/`description` on singletons
   [3][5][6b]. Diffing these creates false drift.
6. **Projection matters on read.** `Get-` may not return every property by default;
   request fields explicitly (`-Property`/`$select`, and `-ExpandProperty` for
   auto-expanded children) so the "current" side of the diff is complete.
7. **Normalize before comparing:** array **ordering is not guaranteed**
   (`includeApplications`, `builtInControls`, targets…), enum **casing** varies,
   and objects are polymorphic. Sort arrays, canonicalize case, and compare by
   `@odata.type` + shape.
8. **Polymorphism needs discriminators on write.** Named locations and IP ranges
   require the correct `@odata.type` in the body [4]; a diff/serializer that drops
   `@odata.type` will fail on apply.
9. **GUID references are tenant-specific** — users, groups, roles, apps, named
   locations. These are exactly the **name-remapping (FR-7)** targets; profiles
   should store a resolvable name/well-known-id and resolve to GUIDs at apply time.
10. **Cross-object dependencies / ordering:** security defaults must be **off**
    before CA can be enabled; CA policies reference named-location `Id`s that must
    exist first; app-consent references a permission-grant policy id. The apply
    plan needs a **dependency-ordered sequence**, and the dry-run should surface
    these prerequisites.
11. **Secure Score is not a drift target** — it changes daily by design; use it for
    reporting only ([§4.7](#47-secure-score-read-only)).

---

## 8. Key takeaways / recommendations

- **We do not need the meta-module.** Install/import a **small pinned set** —
  `Microsoft.Graph.Authentication` + `Microsoft.Graph.Identity.SignIns` +
  `Microsoft.Graph.Security` (+ `.DirectoryManagement`) — which covers the **entire**
  baseline surface while honoring minimal-deps, small-container, and fast-import
  goals [1][8a][8b].
- **`Microsoft.Graph.Identity.SignIns` is the workhorse** — CA, named locations,
  auth-methods, authorization policy, security defaults, consent policies, and
  risky-user reads all live there. **`Microsoft.Graph.Security`** adds Secure Score.
- **Build our own dry-run/diff; do not trust `-WhatIf`.** `-WhatIf` is local-only
  and does no server validation [14]. The engine is `Get → normalize → diff →
  render`, with `Update-`(PATCH) for singletons and match-by-`displayName` +
  `New`/`Update` for collections.
- **Two-tier scopes:** request only `*.Read.All` for scan/dry-run; escalate to the
  specific `*.ReadWrite.*` scopes only on apply. Discover the exact scopes at
  runtime with `Find-MgGraphCommand` instead of hard-coding [2][7].
- **Model risk-based access as Conditional Access**, not the retiring standalone
  Identity-Protection policies (read-only now; enforcement ends 1 Oct 2026)
  [11a][11b].
- **Encode dependencies in the apply plan:** security-defaults-off → named-locations
  → CA policies; authorization-policy user-consent ↔ permission-grant policies. The
  dry-run must flag unmet prerequisites (NFR-6).
- **Secure Score = verification/reporting**, captured to the audit log around an
  apply — never a config target or drift source.
- **Store profiles by stable name, resolve GUIDs at apply time** to make
  name-remapping (FR-7) work and keep JSON diffs meaningful (NFR-9).

## 9. Open questions / risks

- **Exact write-vs-read scope pairs need runtime confirmation.** Several read paths
  accept multiple scopes (e.g. auth-methods read via `Policy.Read.All` *or*
  `Policy.ReadWrite.AuthenticationMethod`). We should generate the definitive map
  with `Find-MgGraphCommand` in a bootstrap step and snapshot it per pinned SDK
  version. The Identity-Protection scopes in §4.4 were stated from the documented
  permission set but **not each re-verified against a cmdlet reference page** in
  this pass.
- **`Set-` vs `Update-` naming** varies by area (e.g. `Set-MgPolicyAdminConsentRequestPolicy`
  vs `Update-MgPolicy…`). Confirm the exact verb per cmdlet against the pinned
  version at build time.
- **P2 licensing:** risk-based CA conditions require **Entra ID P2**; auth-strength
  and some controls have licensing prerequisites. Applying a profile to an
  under-licensed tenant will fail — dry-run should detect/flag licensing gaps.
- **PATCH null-clearing semantics** ([§7.4](#7-idempotency--drift-comparison-gotchas))
  need empirical testing per field before we trust "remove this value" in a profile.
- **Beta-only capabilities:** a few newer controls (some auth-strength combos,
  registration-campaign options) are richer on beta. Our v1.0-only stance may defer
  them — track which baseline items are v1.0-complete.
- **`New-` duplicate risk** is a genuine footgun; the match-by-`displayName`
  strategy must be robust to renames (consider persisting an `Id` map in the run
  log rather than the profile, which must stay credential-free/config-only).
- **Throttling / partial application:** bulk applies can hit Graph 429s; the apply
  engine needs idempotent retry so a mid-run failure leaves a clear, resumable
  state (NFR-6).

## 10. Sources

All Microsoft Learn pages accessed via the Microsoft Learn MCP; community pages via web search. Accessed 2026-07-22.

1. Install the Microsoft Graph PowerShell SDK (roll-up vs sub-modules, "over 47 sub modules", v1.0 recommended, PS7) — https://learn.microsoft.com/powershell/microsoftgraph/installation?view=graph-powershell-1.0
2. Get started with the Microsoft Graph PowerShell SDK (delegated auth, `Connect-MgGraph -Scopes`, `Find-MgGraphCommand`) — https://learn.microsoft.com/powershell/microsoftgraph/get-started?view=graph-powershell-1.0
   - 2b. Use `Find-MgGraphPermission` — https://learn.microsoft.com/powershell/microsoftgraph/find-mg-graph-permission?view=graph-powershell-1.0
3. `New-MgIdentityConditionalAccessPolicy` (CA policy body model, conditions/grantControls/sessionControls, read-only fields, scope `Policy.ReadWrite.ConditionalAccess`) — https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/new-mgidentityconditionalaccesspolicy?view=graph-powershell-1.0
   - 3b. `Update-MgIdentityConditionalAccessPolicy` (`-ConditionalAccessPolicyId`, PATCH) — https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/update-mgidentityconditionalaccesspolicy?view=graph-powershell-1.0
   - 3c. `Get-MgIdentityConditionalAccessPolicy` (`Policy.Read.All`) — https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/get-mgidentityconditionalaccesspolicy?view=graph-powershell-1.0
4. `New-MgIdentityConditionalAccessNamedLocation` (polymorphic `@odata.type`, IP vs country, `-WhatIf`/`-Confirm`, scopes) — https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/new-mgidentityconditionalaccessnamedlocation?view=graph-powershell-1.0
5. `Update-MgPolicyAuthenticationMethodPolicy` (singleton, `Policy.ReadWrite.AuthenticationMethod`, read-only displayName/description/policyVersion) — https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/update-mgpolicyauthenticationmethodpolicy?view=graph-powershell-1.0
   - 5b. `Update-MgPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration` (`-AuthenticationMethodConfigurationId`, per-method) — https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/update-mgpolicyauthenticationmethodpolicyauthenticationmethodconfiguration?view=graph-powershell-1.0
6. `Update-MgPolicyAuthorizationPolicy` (defaultUserRolePermissions, permissionGrantPoliciesAssigned, allowInvitesFrom, `Policy.ReadWrite.Authorization`) — https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/update-mgpolicyauthorizationpolicy?view=graph-powershell-1.0
   - 6b. `Update-MgPolicyIdentitySecurityDefaultEnforcementPolicy` (`isEnabled`, `Policy.ReadWrite.SecurityDefaults`) — https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/update-mgpolicyidentitysecuritydefaultenforcementpolicy?view=graph-powershell-1.0
7. Use `Find-MgGraphCommand` (discover API path + required permissions per cmdlet) — https://learn.microsoft.com/powershell/microsoftgraph/find-mg-graph-command?view=graph-powershell-1.0
8. Footprint:
   - 8a. Issue #428 "reduce the size of this module bundle…" (33 modules / 4254 commands / 947 MB; container/serverless impact) — https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/428
   - 8b. "Microsoft Graph PowerShell v2… half the size…" — https://devblogs.microsoft.com/microsoft365dev/microsoft-graph-powershell-v2-is-now-in-public-preview-half-the-size-and-will-speed-up-your-automations/
   - 8c. "Upgrade to Microsoft Graph PowerShell SDK v2… up to 58% smaller (v1)" — https://devblogs.microsoft.com/microsoft365dev/upgrade-to-microsoft-graph-powershell-sdk-v2-now-generally-available/
9. Upgrade from Azure AD PowerShell to Microsoft Graph PowerShell (least-privilege, permissions not pre-authorized, `Find-MgGraph*`) — https://learn.microsoft.com/powershell/microsoftgraph/migration-steps?view=graph-powershell-1.0
10. PATCH null/empty gotchas:
    - 10a. Issue #2091 `Update-MgIdentityConditionalAccessPolicy` error 1007 — https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/2091
    - 10b. Issue #2568 `Update-MgIdentityConditionalAccessPolicy` "1054: Invalid servicePrincipal value" — https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/2568
11. Identity Protection risk policies retiring / migrate to CA:
    - 11a. Microsoft Entra ID Protection — risk-based access policies (Graph-supported CA risk policies) — https://learn.microsoft.com/entra/id-protection/concept-identity-protection-policies
    - 11b. Risk policies (configure) — https://learn.microsoft.com/entra/id-protection/howto-identity-protection-configure-risk-policies
    - 11c. Community: "Migrate Identity Protection Risk Policies to Conditional Access" — https://ourcloudnetwork.com/migrate-identity-protection-risk-policies-to-conditional-access/
12. `Get-MgPolicyAdminConsentRequestPolicy` (`Policy.Read.All` / `Policy.ReadWrite.ConsentRequest`) — https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/get-mgpolicyadminconsentrequestpolicy?view=graph-powershell-1.0
13. Secure Score:
    - 13. `Get-MgSecuritySecureScoreControlProfile` (`Microsoft.Graph.Security`, `SecurityEvents.Read.All`) — https://learn.microsoft.com/powershell/module/microsoft.graph.security/get-mgsecuritysecurescorecontrolprofile?view=graph-powershell-1.0
    - 13b. `Get-MgSecuritySecureScore` (currentScore/maxScore/controlScores/averageComparativeScores) — https://learn.microsoft.com/powershell/module/microsoft.graph.security/get-mgsecuritysecurescore?view=graph-powershell-1.0
14. Issue #877 "Extend `-WhatIf` parameter" (evidence that built-in `-WhatIf` is minimal / not a real server-side preview) — https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/877
15. Troubleshooting common errors in Microsoft Graph PowerShell (`Find-MgGraphCommand` for 403/permission diagnosis) — https://learn.microsoft.com/powershell/microsoftgraph/troubleshooting?view=graph-powershell-1.0

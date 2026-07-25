# Phase 4 execution runbook — the project map

> **For agentic workers:** this is the authoritative, ordered work queue for
> finishing Phase 4 (build). Work it **top to bottom, one story at a time**.
> Every architectural decision has already been made (see [Pre-made
> decisions](#pre-made-decisions)); if you find yourself weighing a design
> choice, the answer is in this file or in `docs/decisions/` — do not invent a
> new pattern. Steps use checkbox (`- [ ]`) syntax: tick them here as you land
> stories, so the next session resumes from the ledger.
> REQUIRED SUB-SKILL if available: `superpowers:executing-plans` (inline,
> story-by-story). Each story is one TDD cycle + one independent review.

**Goal:** finish the v1 slice — apply engine, the remaining Graph + EXO
controls, drift/remediation/remap, audit log, CLI, CI — on the patterns already
proven by MCA-17/22/37.

**Architecture:** everything is the ADR-0013 control contract (uniform
Get/Compare/Set handlers built by `New-M365Control`, resolved through
`Get-M365ControlRegistry`, driven generically by `Get-M365Plan`) plus thin
owner-facing entry points. Graph calls go through the one seam
`Invoke-M365GraphRequest` (ADR-0014); EXO calls will go through the analogous
`Invoke-M365ExoCommand` (decision D5). Tests are tenant-free: they mock the
seams module-scoped.

**Tech stack:** PowerShell **7.6** (floor = target; ADR-0015 as amended
2026-07-25 — the EXO 3.10.0 pin requires 7.6+/.NET 10), Pester (pinned
**6.0.1** via `scripts/install-dev-tools.ps1`; the tests use Pester 5+
syntax), pinned modules (Microsoft.Graph.Authentication 2.38.1,
ExchangeOnlineManagement 3.10.0, powershell-yaml 0.4.12 —
`scripts/install-modules.ps1`). No new dependencies without an ADR (NFR-3).

## Global constraints

Every story implicitly includes these. Reviewers reject violations.

- **No credentials on disk, ever** (NFR-1). No tokens/secrets in code, logs,
  profiles, or test fixtures. Projections are allowlists of config fields.
- **Loud, fast failure** (NFR-6): throw with an actionable message; never a
  silent catch; never a silent skip. Self-healing = *offer* a consented fix for
  recoverable preconditions (ADR-0011), never auto-fix.
- **Minimal dependencies** (NFR-3): the Graph dependency is
  `Microsoft.Graph.Authentication` alone (ADR-0014). Never add a typed
  `Microsoft.Graph.*` sub-module. EXO cmdlets come from the already-pinned
  `ExchangeOnlineManagement`.
- **Dry-run before apply** (FR-8/FR-9): `Get-M365Plan` never calls Set; only
  `Invoke-M365Apply`/`Invoke-M365Remediation` do, and only behind `-Approve`.
- **Readability** (NFR-9): output rendering is pure, deterministic,
  stable-ordered (see `Format-M365Plan`); string arrays in projections are
  sorted so diffs are order-insensitive.
- **Test-first** (CONTRIBUTING §1): failing Pester test before implementation.
  Full suite green before every commit: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/ -CI"`.
- **One function per file**, file named after the function; public functions
  must be declared in `M365Configurator.psd1` `FunctionsToExport` (the loader
  enforces manifest ↔ `Public/` agreement and fails import on drift).
- **Runtime floor is PowerShell 7.6** (ADR-0015 as amended). Every new file
  under `src/` or `tests/` declares `#requires -Version 7.6` —
  `tests/M365Configurator.Manifest.Tests.ps1` fails the suite if one doesn't.
  (`scripts/` bootstrap files deliberately keep a lower `#requires` so their
  friendly floor guard can speak on downlevel hosts; don't "fix" that.)
- **An agent never reviews its own code** (CONTRIBUTING §4) — see the
  [review protocol](#the-work-loop-protocol).
- Reference Jira issues in commits: `MCA-NN: subject`.

**Tenant prerequisites** (document these; don't rediscover them): consolidated
delegated Graph scopes for the v1 slice are `Policy.Read.All` +
`Policy.ReadWrite.ConditionalAccess`, `Policy.ReadWrite.AuthenticationMethod`,
`Policy.ReadWrite.Authorization`, `Policy.ReadWrite.ConsentRequest`,
`SecurityEvents.Read.All`. The **privilege floor across the slice is
Privileged Role Administrator** (required for writing the authorization
policy — S6/S8); Security Administrator or Conditional Access Administrator
covers the CA controls alone. GCC/national-cloud variants are out of v1.

## The work loop (protocol)

For **each** story, in queue order:

1. **Claim** — transition the Jira story (project `MCA`, Cloud ID
   `b738554c-85e3-4c02-8140-fef01cb5fdb9`) to *In Progress*; comment naming
   your seat and the files you will touch. Check the Confluence coordination
   block (page `1048577`) for a conflicting active lane first.
2. **Red** — write the story's test file (the spec lists every case); run it,
   confirm it fails for the right reason:
   `pwsh -NoProfile -Command "Invoke-Pester -Path tests/<File>.Tests.ps1 -Output Detailed"`.
3. **Green** — implement exactly what the spec says; run the story's tests,
   then the **full suite**: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/ -CI"`.
4. **Wire-up** — registry / manifest / reference-profile edits the spec lists
   (these are the collision hot spots; only ever do this on a claimed story).
5. **Commit** on `main` — message `MCA-NN: <imperative subject>` + body noting
   test count, ending with the `Co-Authored-By` trailer your harness specifies.
6. **Review** — dispatch a **fresh sub-agent** (it must not be the author) with
   the review prompt template below. Fix every confirmed finding with a
   regression test; commit fixes as `MCA-NN: address review findings (...)`.
7. **Close** — transition the story to *Done* in Jira with a closing comment
   (what landed, test count, review verdict). Tick the story's checkbox in the
   [queue ledger](#the-queue-ledger). Push `main`.
8. Every 3–4 stories (or at session end): update the Confluence coordination
   block (page `1048577`) and the build-status bullets on that page.

**Review prompt template** (fill the bracketed parts):

> You are an independent code reviewer for C:\Code\m365-configurator
> (PowerShell 7 module, Pester 5). Review commit [HASH] ("[SUBJECT]") on main.
> Read the full diff (`git show [HASH]`) and every touched file's final state.
> Check against: docs/RUNBOOK.md story [MCA-NN] spec, docs/REQUIREMENTS.md,
> the design tenets in README.md, and ADR-0013/0014 in docs/decisions/.
> Run `pwsh -NoProfile -Command "Invoke-Pester -Path tests/ -CI"` and report
> counts. Verify every finding against the actual code; no style nitpicks.
> Report: numbered findings (severity blocker/major/minor, file:line, evidence,
> concrete fix) or "no findings"; verdict approve / approve-with-fixes / reject.

**Hot spots** (serialize; never touch on an unclaimed story):
`Public/Get-M365ControlRegistry.ps1` (every control registers here) ·
`M365Configurator.psd1` (`FunctionsToExport`) · `Public/Get-M365Plan.ps1`
(shared dry-run/apply) · `profiles/security-baseline.yaml` (each control story
appends its block) · `docs/decisions/README.md` (ADR index).

## Architecture crib sheet

Read these five files before your first story; they are the patterns every
story copies:

| File | What it teaches |
| --- | --- |
| `src/M365Configurator/Public/New-M365Control.ps1` | the control contract: `Id`, `Provider` (`graph`\|`exo`), `Shape` (`singleton`\|`collection`\|`policy-rule`\|`preset`), `Title`, `RequiredCapabilities`, `DependsOn`, and the exact seam signatures — `Get { param($Session) }`, `Compare { param($Desired, $Current) }`, `Set { param($Session, $Desired, $Current) }` (enforced positionally at construction) |
| `src/M365Configurator/Private/New-M365SecurityDefaultsControl.ps1` | the reference control: inline endpoint (no closures — seams run outside the definition scope), allowlist projection, `Get-M365MapValue` for map/object-agnostic reads |
| `src/M365Configurator/Public/Get-M365Plan.ps1` | the engine: Kahn dependency order, capability gate (`Session.Capabilities`), custom-`Compare` contract (`@{ Action; Changes }`, `Action` ∈ NoChange/Create/Update/Blocked/Unsupported), default map-diff via `Get-M365ControlChange` (desired-declared keys only, canonical-JSON equality) |
| `tests/Get-M365ControlRegistry.Tests.ps1` | control test conventions: import module from manifest, `Mock Invoke-M365GraphRequest -ModuleName M365Configurator`, invoke seams positionally (`& $control.Get $null`), `Should -Invoke ... -ParameterFilter` on Method/Uri/Body |
| `src/M365Configurator/Public/Invoke-M365DryRun.ps1` + `Private/Format-M365Plan.ps1` | entry-point pattern: injected `Importer`/`Registry` seams, pure line-renderer, returns the structured object |

Facts you will otherwise rediscover slowly:

- `Get-M365MapValue $map 'key'` / `Test-M365MapHasKey` read dictionaries AND
  pscustomobjects (profiles arrive as either). Both live in
  `Private/Get-M365MapValue.ps1`.
- `ConvertTo-M365CanonicalJson` is the equality oracle for diffs (ADR-0008).
- `Get-M365ControlChange -Desired -Current` emits `{ Path; From; To }` records
  for desired-declared keys whose canonical JSON differs. Extra keys in
  `Current` (e.g. a stashed `id`) are ignored — this is load-bearing for D2.
- Profile schema v1 (`Test-M365Profile`): top level `schemaVersion: "1.0"`,
  `name`, `framework`, `frameworkVersion`, `controls[]`; each control `id`,
  `framework`, `frameworkVersion`, `provider` (`graph`|`exo`), `settings`
  (free-form map; nested maps fine), optional `name`. The secret-scanner
  (`Find-M365SecretKey`) rejects credential-shaped keys anywhere.
- Connect state objects (from `Connect-M365Graph` / `Connect-M365ExchangeOnline`)
  are secret-free projections; neither carries `Capabilities` yet — MCA-21
  introduces the session object (D8).
- The Pester suite stands at **154 green** as of the MCA-29 follow-ups
  (2026-07-25). Every story adds tests and never breaks existing ones.

## Pre-made decisions

These were the "requires deeper consideration" items. They are **decided**;
implement as written.

- **D1 — Apply semantics (MCA-18).** `Invoke-M365Apply` recomputes the plan,
  renders it, and refuses to touch the tenant unless `-Approve` was passed
  (FR-9's explicit go-ahead) **and** the plan contains no `Blocked`/
  `Unsupported` items (NFR-6: no partial application). Items apply **in plan
  order** (already dependency-sorted). Per-item: `NoChange` → `Skipped`;
  `Create`/`Update` → invoke `Set`, catch per-item → `Applied`/`Failed`.
  **Fail-fast:** the first `Failed` stops the run; remaining items are
  `NotAttempted`; overall `Outcome = 'Failed'`. The per-item loop lives in
  **private `Invoke-M365PlanApplication`** so remediation (D7) reuses it.
- **D2 — CA collection controls (MCA-23/24).** Each control manages exactly
  **one named CA policy**, matched by `displayName` (the FR-7 name-scoped
  hook). `Get` lists all policies (`GET v1.0/identity/conditionalAccess/policies`),
  finds the one whose `displayName` equals the profile's
  `settings.displayName`, and returns `$null` if absent, else a **flat-ish
  allowlist projection plus the policy `id`** (extra `id` is invisible to the
  diff — see crib sheet). A **custom `Compare`** turns absence into
  `Action = 'Create'` (one Change per declared field, `From = $null`);
  otherwise it delegates to `Get-M365ControlChange` → `Update`/`NoChange`.
  `Set`: absent → `POST` full policy body; present → `PATCH` by the stashed
  `$Current.id`. String arrays in projections and POST/PATCH bodies are
  **sorted** so comparisons are order-insensitive. Both declare
  `DependsOn @('ID-1')`.
- **D3 — Weak-MFA control shape (MCA-25).** One `GET
  v1.0/policies/authenticationMethodsPolicy`, projected to
  `@{ sms = <state>; voice = <state>; email = <state> }`. Default map-compare.
  `Set` PATCHes **only the methods whose state differs**, one PATCH per method
  to `v1.0/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/{Sms|Voice|Email}`
  with body `@{ '@odata.type' = '#microsoft.graph.<x>AuthenticationMethodConfiguration'; state = <desired> }`.
- **D4 — Singleton policy projections are flat, control-owned vocabularies.**
  A control's `Get` maps nested Graph fields to flat keys (e.g.
  `allowedToCreateApps` ← `defaultUserRolePermissions.allowedToCreateApps`)
  and `Set` maps them back. The profile never declares raw nested Graph
  objects for these controls — this keeps the default diff meaningful and the
  profile readable.
- **D5 — EXO command seam.** New private `Invoke-M365ExoCommand -Name <cmdlet>
  -Parameters <hashtable>` mirroring the Graph seam: resolves the cmdlet at
  call time (`Get-Command -Name $Name -ErrorAction Stop`) and splats
  `-Parameters`. Tests mock `Invoke-M365ExoCommand` module-scoped and filter on
  `$Name`/`$Parameters`. A missing EXO module fails loud at call time; the
  consented fix lives in the module preflight (ADR-0011), not here.
- **D6 — Drift is the plan, re-labelled (MCA-19).** No second diff engine.
  `Get-M365Drift` wraps `Get-M365Plan` and projects each item to
  `Status ∈ InSync|Drifted|Blocked|Unsupported` (`NoChange`→InSync,
  `Create`/`Update`→Drifted). Renderer `Format-M365DriftReport` mirrors
  `Format-M365Plan`.
- **D7 — Remediation = apply the drifted subset (MCA-20).**
  `Invoke-M365Remediation` computes drift, builds a sub-plan of only the
  drifted items, renders the preview, requires `-Approve`, then calls
  `Invoke-M365PlanApplication` (D1). Deterministic because the plan order is.
- **D8 — Session & capabilities (MCA-21).** New public `New-M365Session`
  aggregates the connect-state objects into
  `@{ Graph = <state|$null>; Exo = <state|$null>; Capabilities = [string[]] }`.
  Capability vocabulary (lowercase, canonical): `graph`, `exo` (present when
  the respective connection state says Connected), `entra-id-p1`,
  `entra-id-p2`, `defender-office365` (license-derived via
  `GET v1.0/subscribedSkus`, mapping servicePlans: `AAD_PREMIUM`→p1,
  `AAD_PREMIUM_P2`→p2, any of `THREAT_INTELLIGENCE`/`ATP_ENTERPRISE`→defender;
  detection is an injected seam so it's testable). Graph controls then declare
  `RequiredCapabilities @('graph')`, EXO controls `@('exo')` (plus
  `'defender-office365'` where noted) — retrofit ID-1 and the landed controls
  in the same story.
- **D9 — Name remapping (MCA-16).** `-NameOverride <hashtable>` (control id →
  replacement name) on `Invoke-M365DryRun`, `Invoke-M365Apply`, and
  `Get-M365Drift`. A private helper rewrites the profile's name-bearing
  setting (`displayName` for CA controls, `name` for EXO policy controls)
  before planning, so previews show the remapped name. Unknown ids in the map
  → throw (NFR-6).
- **D10 — Audit log (MCA-35).** Append-only JSONL, one record per applied item
  and one per run, written by `Invoke-M365PlanApplication` through an injected
  writer seam. Default path `./logs/m365config-audit-<yyyyMMdd>.jsonl`
  (override `M365_CONFIGURATOR_LOG_DIR`). Record: `timestamp` (UTC ISO-8601),
  `actor` (session account), `runId` (GUID per run), `action`, `controlId`,
  `outcome`, `changes` (Path/From/To), `error`. Guard every record with
  `Find-M365SecretKey` before write (NFR-1 backstop) — a hit fails the write
  loudly. Public `Get-M365AuditLog` (FR-12) reads/filters by day + control id.
- **D11 — CLI (MCA-36).** `scripts/m365config.ps1` — a thin dispatcher:
  `-Command save|dryrun|apply|drift` + `-ProfilePath` + passthrough switches
  (`-Approve`, `-NameOverride`). It only maps arguments onto the module's
  public functions through an injected invoker seam (testable without a
  tenant). No business logic in the script.
- **D12 — CI (new story, MCA-40).** GitHub Actions workflow
  `.github/workflows/ci.yml`: matrix over the ADR-0015 window (7.4 floor, 7.6
  target) using pinned `mcr.microsoft.com/powershell` container images;
  steps = checkout → `Test-ModuleManifest` → install pinned Pester
  (`scripts/install-dev-tools.ps1`) → `Invoke-Pester -Path tests/ -CI`.
  Discover the exact image tags with
  `curl -s https://mcr.microsoft.com/v2/powershell/tags/list` and pin the
  newest `7.4-*` and `7.6-*` Ubuntu LTS tags (record them in the workflow
  comment with the discovery date).
- **Deliberately NOT building in v1** (do not "improve" these in):
  ID-4..ID-10 CA extras (P2/Intune gates), AM-1/3/4/5, MDO-2/3/5/6/7 custom
  Defender policies, MDO-8/9/11, SHR-2/3/4, CON-4, AUD-4/5/6, DKIM, SPF/DMARC
  (DNS), anything Security & Compliance (`Connect-IPPSSession` — not on
  Linux), per-mailbox audit actions (D-AUD2 note in S14), the web GUI
  (ADR-0012 defers it), PSScriptAnalyzer adoption, and any new module
  dependency. Also parked for MCA-9 (Phase 5): the devcontainer base image is
  `debian:bookworm` while PowerShell's supported-platform list has moved to
  Debian 13 — refresh it with the container/Dockerfile work, not before.

## The queue (ledger)

Work top to bottom. Tick when the story is **Done in Jira** (landed, reviewed,
pushed).

- [ ] **S1 · MCA-40** — CI workflow (create the Jira story first if missing)
- [ ] **S2 · MCA-18** — Apply engine
- [ ] **S3 · MCA-23** — ID-2 block legacy auth (CA)
- [ ] **S4 · MCA-24** — ID-3 require MFA for all users (CA)
- [ ] **S5 · MCA-25** — AM-2 disable weak MFA methods
- [ ] **S6 · MCA-26** — CON-1 + CON-3 consent & app-registration policy
- [ ] **S7 · MCA-27** — CON-2 admin consent workflow
- [ ] **S8 · MCA-28** — SHR-1 restrict guest inviters
- [ ] **S9 · MCA-21** — Session + capability gating
- [ ] **S10 · MCA-30** — MDO-1 Standard preset security policy (+ EXO seam)
- [ ] **S11 · MCA-31** — MDO-4 block external auto-forwarding
- [ ] **S12 · MCA-32** — MDO-10 external sender warning
- [ ] **S13 · MCA-33** — AUD-1 unified audit log
- [ ] **S14 · MCA-34** — AUD-2 mailbox auditing (org default)
- [ ] **S15 · MCA-19** — Drift detection
- [ ] **S16 · MCA-20** — Deterministic remediation
- [ ] **S17 · MCA-16** — Name remapping
- [ ] **S18 · MCA-35** — Structured audit log
- [ ] **S19 · MCA-36** — CLI dispatcher
- [ ] **S20** — Close-out: REQUIREMENTS.md status boxes, Confluence, ROADMAP

Story specs follow. Endpoint/parameter facts marked ✅ were verified against
Microsoft Learn on 2026-07-25; do not re-derive them.

---

## S1 · MCA-40 — CI workflow

**Goal:** GitHub Actions proving the ADR-0015 runtime pin (7.6, floor = target
since the 2026-07-25 amendment) on every push/PR to `main`.

**Files:** Create `.github/workflows/ci.yml`. No module/test changes — CI runs
the existing suite. (No new Pester tests for this story; verification is the
live Actions run.)

**Runtime fact (checked 2026-07-25):** MCR ships **no PowerShell 7.6 container
image yet** — `https://mcr.microsoft.com/v2/powershell/tags/list` tops out at
`7.5-*`, and 7.5 is **below the floor** (the manifest would reject import). So
CI installs the pinned 7.6.x from the official PowerShell GitHub release
tarball. When MCR publishes a `7.6-ubuntu-*` tag, simplify to a `container:`
job (leave the comment in the workflow).

**Steps:**
- [ ] Create the Jira story ("CI: Pester suite on the pinned ADR-0015
  runtime", epic MCA-9, label `v1-slice`) if it does not already exist; claim
  it, and record its real key in this file (replace MCA-40 if different).
- [ ] Confirm the newest 7.6.x patch at
  https://github.com/PowerShell/PowerShell/releases (7.6.4 was current on
  2026-07-25; use newer patch if released, and update `PWSH_VERSION` below).
- [ ] Write `.github/workflows/ci.yml` exactly:

```yaml
name: ci
on:
  push: { branches: [main] }
  pull_request: { branches: [main] }
env:
  # ADR-0015 (amended 2026-07-25): floor = target = PowerShell 7.6 LTS / .NET 10.
  # Pinned exactly; bump the patch deliberately. MCR had no 7.6 container image
  # as of 2026-07-25 — when mcr.microsoft.com/powershell grows a 7.6-ubuntu-*
  # tag, this job can become a container: job instead of the tarball install.
  PWSH_VERSION: '7.6.4'
jobs:
  pester:
    name: pester (pinned pwsh)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install pinned PowerShell from the official release tarball
        run: |
          curl -sSL --fail -o /tmp/pwsh.tar.gz "https://github.com/PowerShell/PowerShell/releases/download/v${PWSH_VERSION}/powershell-${PWSH_VERSION}-linux-x64.tar.gz"
          mkdir -p "$HOME/pwsh"
          tar -xzf /tmp/pwsh.tar.gz -C "$HOME/pwsh"
          chmod +x "$HOME/pwsh/pwsh"
          "$HOME/pwsh/pwsh" -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
      - name: Install pinned runtime modules
        run: $HOME/pwsh/pwsh -NoProfile -File scripts/install-modules.ps1
      - name: Install pinned dev tools (Pester 6.0.1)
        run: $HOME/pwsh/pwsh -NoProfile -File scripts/install-dev-tools.ps1
      - name: Run test suite
        run: $HOME/pwsh/pwsh -NoProfile -Command "Invoke-Pester -Path tests/ -CI"
```

**Correction (found while executing S1):** the `run:` lines above must NOT
wrap `$HOME/pwsh/pwsh` in double quotes — a quoted scalar followed by more
unquoted text on the same line is invalid YAML ("did not find expected key"),
and GitHub fails the run immediately (0s) before any step executes. Validate
any future workflow edits with
`pwsh -NoProfile -Command "Get-Content <file> -Raw | ConvertFrom-Yaml"`
before pushing.

  (Manifest validity is covered inside the suite by
  `tests/M365Configurator.Manifest.Tests.ps1`, so no separate
  `Test-ModuleManifest` step is needed.)
- [ ] Commit `MCA-40: CI — Pester suite on the pinned ADR-0015 runtime`,
  push, then watch the run: `gh run watch` (or `gh run list --limit 1`).
  **The story is not done until the workflow is green on GitHub.**
- [ ] Review per protocol; close.

**Why install-modules.ps1 is required in CI:** Pester's `Mock` can only mock
commands that resolve — `tests/Invoke-M365GraphRequest.Tests.ps1` mocks
`Invoke-MgGraphRequest` (needs Microsoft.Graph.Authentication present) and the
YAML round-trip tests need `powershell-yaml`. Both installs are idempotent,
CurrentUser-scope, PSGallery-only (allowed egress per NFR-2).

---

## S2 · MCA-18 — Apply engine

**Goal:** gated application of a plan with per-item success/failure (FR-9,
NFR-6), reusing the dry-run plan and never applying on a dirty signal.

**Files:**
- Create `src/M365Configurator/Private/Invoke-M365PlanApplication.ps1`
- Create `src/M365Configurator/Private/Format-M365ApplyResult.ps1`
- Create `src/M365Configurator/Public/Invoke-M365Apply.ps1`
- Modify `src/M365Configurator/M365Configurator.psd1` (add `Invoke-M365Apply`)
- Test `tests/Invoke-M365Apply.Tests.ps1`

**Interfaces:**
- Consumes: `Get-M365Plan` (unchanged), control handlers' `Set` seams.
- Produces: `Invoke-M365PlanApplication -Plan <plan> -Session <s> -Registry
  <controls>` → pscustomobject PSTypeName `M365Configurator.ApplyResult` with
  `ProfileName`, `Outcome` (`Applied`|`Failed`|`NothingToDo`), `Items[]` each
  `{ Id, Title, Action, Outcome ('Applied'|'Failed'|'Skipped'|'NotAttempted'),
  Detail, Error }`. Public `Invoke-M365Apply` mirrors `Invoke-M365DryRun`'s
  parameter sets (`-ProfilePath`/`-InputObject`, `-Session`, `-Registry`,
  `-Importer`) **plus `[switch] $Approve`**. S16 (remediation) and S18 (audit
  log) build on `Invoke-M365PlanApplication` — keep its parameters exactly as
  stated, plus an injected `[scriptblock] $AuditWriter = $null` placeholder is
  NOT added now (S18 adds it; note it so you don't pre-build).

**Behavior spec (D1):**
1. `Invoke-M365Apply` loads the profile (same importer seam as dry-run),
   computes the plan via `Get-M365Plan`, renders it with `Format-M365Plan`.
2. Without `-Approve`: print the plan, `Write-Warning` that nothing was
   applied, return the **plan** (so scripts can inspect), touch nothing.
3. With `-Approve` but plan contains `Blocked` or `Unsupported` items: `throw`
   listing the offending control ids (no partial application; NFR-6).
4. With `-Approve` and a clean plan: call `Invoke-M365PlanApplication`.
5. `Invoke-M365PlanApplication` iterates `Plan.Items` in order:
   `NoChange` → `Skipped`; `Create`/`Update` → resolve the handler from
   `$Registry` by `Id` (missing handler → throw), re-read desired from the
   plan item — **note:** the plan item does not carry `Desired`/`Current`, so
   `Get-M365Plan` must be extended to stash them per item. Add `Desired` and
   `Current` properties to plan items (a pure additive change to
   `Get-M365Plan`; existing tests keep passing — extend
   `tests/Get-M365Plan.Tests.ps1` with one case asserting they're present).
   Invoke `& $handler.Set $Session $item.Desired $item.Current` in try/catch:
   success → `Applied` with the seam's return as `Detail`; exception →
   `Failed` with the message as `Error`, **stop the loop**, mark the rest
   `NotAttempted`, overall `Outcome = 'Failed'`.
6. Overall outcome: any `Failed` → `Failed`; else any `Applied` → `Applied`;
   else `NothingToDo`.
7. `Format-M365ApplyResult` renders like `Format-M365Plan`: header
   `Apply: <profile>`, one line per item (glyphs: `✓` Applied · `-` Skipped ·
   `x` Failed · `.` NotAttempted; ASCII only: use `+`/`-`/`x`/`.`), footer
   `Result: APPLIED|FAILED|NOTHING TO DO - n applied, n skipped, n failed,
   n not-attempted`. Pure, deterministic, returns `[string[]]`.

**Tests (all with fake in-memory controls/registry, like
`tests/Get-M365Plan.Tests.ps1`):**
- [ ] without `-Approve`: renders plan, returns plan object, no `Set` invoked
- [ ] with `-Approve`, clean plan: `Set` invoked once per Create/Update item,
  in dependency order; result Items match (Applied/Skipped)
- [ ] with `-Approve`, plan has Blocked item: throws naming the control id;
  no `Set` invoked
- [ ] with `-Approve`, plan has Unsupported item: throws; no `Set` invoked
- [ ] `Set` throws on item 2 of 3: item 1 Applied, item 2 Failed (error
  captured), item 3 NotAttempted; overall Failed; the throw does NOT escape
  (per-item report instead — FR-9)
- [ ] all NoChange: Outcome NothingToDo, zero `Set` calls
- [ ] plan items carry Desired/Current (extend Get-M365Plan tests)
- [ ] `Format-M365ApplyResult` renders deterministic lines (snapshot-style
  assertion on the array)
- [ ] `Invoke-M365Apply` re-renders and re-signals via `Write-Host` lines
  (assert via `Format-M365ApplyResult` output presence in transcript or by
  returning object shape — follow `Invoke-M365DryRun.Tests.ps1`'s pattern)

**Done when:** suite green, manifest updated, reviewed, Jira Done, ledger
ticked.

---

## S3 · MCA-23 — ID-2 block legacy authentication (CA collection control)

**Goal:** the first Conditional Access collection control: a named CA policy
blocking legacy auth (SCuBA MS.AAD.1.1v1).

**Files:**
- Create `src/M365Configurator/Private/New-M365LegacyAuthBlockControl.ps1`
- Create `src/M365Configurator/Private/Get-M365CaPolicyProjection.ps1` (shared
  with S4 — build it here)
- Modify `src/M365Configurator/Public/Get-M365ControlRegistry.ps1` (add to
  `$controls`)
- Modify `profiles/security-baseline.yaml` (append control block)
- Test `tests/New-M365LegacyAuthBlockControl.Tests.ps1`

**Mechanism (✅ verified 2026-07-25, Graph v1.0 `conditionalAccessPolicy`):**
- List: `GET v1.0/identity/conditionalAccess/policies` → `@{ value = [...] }`
- Create: `POST v1.0/identity/conditionalAccess/policies` (201 + object)
- Update: `PATCH v1.0/identity/conditionalAccess/policies/{id}` (204)
- Properties: `displayName`; `state` ∈ `enabled` | `disabled` |
  `enabledForReportingButNotEnforced`; `conditions.users.includeUsers`
  (`["All"]` sentinel); `conditions.applications.includeApplications`
  (`["All"]`); `conditions.clientAppTypes` ∈ `all`, `browser`,
  `mobileAppsAndDesktopClients`, `exchangeActiveSync`, `easSupported`, `other`
  (the legacy-auth pair is `exchangeActiveSync` + `other`, per Microsoft's own
  block-legacy-auth guidance);
  `grantControls.operator` (`OR`/`AND`) + `grantControls.builtInControls`
  (needs `block` here). Write scope: `Policy.ReadWrite.ConditionalAccess`
  (+ `Policy.Read.All`). Known Graph issue (documented at
  graph/known-issues#conditional-access-policy-requires-consent-to-additional-permission):
  CA writes can demand consent beyond the documented pair — a 403 here may be
  a consent gap, not a tool bug; the error message should say so.

**Projection vocabulary** (flat where possible, D2/D4; arrays sorted):

```
displayName, state, clientAppTypes (sorted), includeUsers (sorted),
excludeUsers (sorted), includeApplications (sorted), grantOperator,
grantControls (sorted), id (stash)
```

(`excludeUsers` exists so a profile can exempt a break-glass account — the
standard guard against locking every admin out with a block/MFA policy.)

**Implementation:**

`Get-M365CaPolicyProjection` (private, shared): `param($Policy)` → hashtable
with the eight flat keys + `id` (id from `$Policy.id`; nested reads via
`Get-M365MapValue` — `excludeUsers` from `conditions.users.excludeUsers`;
each array `@(... | Sort-Object)`; absent nested parts → `$null`/`@()`).

`New-M365LegacyAuthBlockControl` (mirror the security-defaults file style):

```powershell
New-M365Control -Id 'ID-2' -Provider 'graph' -Shape 'collection' `
    -Title 'Block legacy authentication (Conditional Access)' `
    -DependsOn @('ID-1') `
    -Get {
        param($Session)
        $name = 'Block legacy authentication'   # default; profile may override via displayName
        # NOTE: the engine invokes Get before Compare with no access to Desired,
        # so match on the well-known name the profile ships. See test pinning this.
        $all = Invoke-M365GraphRequest -Method GET -Uri 'v1.0/identity/conditionalAccess/policies'
        $match = @(Get-M365MapValue $all 'value') |
            Where-Object { (Get-M365MapValue $_ 'displayName') -eq $name } |
            Select-Object -First 1
        if ($null -eq $match) { return $null }
        Get-M365CaPolicyProjection -Policy $match
    } `
    -Compare {
        param($Desired, $Current)
        if ($null -eq $Current) {
            # Shape-agnostic key walk: profiles arrive as dictionaries (YAML) or
            # pscustomobjects (code-built) — same duality Get-M365ControlChange handles.
            $keys =
                if ($Desired -is [System.Collections.IDictionary]) { @($Desired.Keys) }
                elseif ($Desired -is [System.Management.Automation.PSCustomObject]) { @($Desired.PSObject.Properties.Name) }
                else { @() }
            $changes = @()
            foreach ($key in $keys) {
                $changes += [pscustomobject]@{ Path = [string]$key; From = $null; To = (Get-M365MapValue $Desired ([string]$key)) }
            }
            return @{ Action = 'Create'; Changes = $changes }
        }
        $changes = @(Get-M365ControlChange -Desired $Desired -Current $Current)
        @{ Action = ($changes.Count -gt 0 ? 'Update' : 'NoChange'); Changes = $changes }
    } `
    -Set {
        param($Session, $Desired, $Current)
        $body = @{
            displayName = [string](Get-M365MapValue $Desired 'displayName')
            state       = [string](Get-M365MapValue $Desired 'state')
            conditions  = @{
                clientAppTypes = @(Get-M365MapValue $Desired 'clientAppTypes' | Sort-Object)
                users          = @{
                    includeUsers = @(Get-M365MapValue $Desired 'includeUsers' | Sort-Object)
                    excludeUsers = @(Get-M365MapValue $Desired 'excludeUsers' | Sort-Object)
                }
                applications   = @{ includeApplications = @(Get-M365MapValue $Desired 'includeApplications' | Sort-Object) }
            }
            grantControls = @{
                operator         = [string](Get-M365MapValue $Desired 'grantOperator')
                builtInControls  = @(Get-M365MapValue $Desired 'grantControls' | Sort-Object)
            }
        }
        if ($null -eq $Current) {
            Invoke-M365GraphRequest -Method POST -Uri 'v1.0/identity/conditionalAccess/policies' -Body $body
            @{ Id = 'ID-2'; Outcome = 'Applied'; Operation = 'Create'; displayName = $body.displayName }
        }
        else {
            $policyId = [string](Get-M365MapValue $Current 'id')
            Invoke-M365GraphRequest -Method PATCH -Uri "v1.0/identity/conditionalAccess/policies/$policyId" -Body $body
            @{ Id = 'ID-2'; Outcome = 'Applied'; Operation = 'Update'; displayName = $body.displayName }
        }
    }
```

**IMPORTANT — the Get/displayName coupling:** `Get` cannot see the profile's
desired settings (contract limitation, deliberate). v1 decision: the control
matches the **fixed well-known display name** shown above; the reference
profile ships exactly that name; per-client renames arrive with MCA-16
(S17), which rewrites `displayName` in desired **and** must then also inform
`Get` — S17's spec handles this by threading the effective name through the
handler when it lands (see S17). Do not solve it here.

**Profile block to append (`profiles/security-baseline.yaml`):**

```yaml
  # ID-2 — Block legacy authentication (SCuBA MS.AAD.1.1v1). Legacy protocols
  # cannot do MFA; blocking them is the single highest-value CA policy.
  # state is enforced ("enabled") — the dry-run preview is the safety net.
  # excludeUsers: put your break-glass account object-id here (empty = none).
  - id: ID-2
    name: Block legacy authentication
    provider: graph
    framework: CISA-SCuBA
    frameworkVersion: "1.5.0"
    settings:
      displayName: Block legacy authentication
      state: enabled
      clientAppTypes: [exchangeActiveSync, other]
      includeUsers: [All]
      excludeUsers: []
      includeApplications: [All]
      grantOperator: OR
      grantControls: [block]
```

**Tests** (mock `Invoke-M365GraphRequest` module-scoped; get the control via
the registry like `tests/Get-M365ControlRegistry.Tests.ps1`):
- [ ] registered: id ID-2, provider graph, shape collection, DependsOn ID-1
- [ ] `Get` GETs the CA policies collection once and returns `$null` when no
  policy matches the well-known name
- [ ] `Get` projects a matching policy to exactly the nine keys (eight flat
  + id), arrays sorted, via a fixture policy with unsorted arrays + extra
  fields (createdDateTime etc. must NOT appear)
- [ ] `Compare` with `$null` current → Action Create, one Change per desired
  key, From `$null`
- [ ] `Compare` with equal projection → NoChange, empty Changes
- [ ] `Compare` with differing `state` → Update with exactly that Change
- [ ] `Set` with `$null` current → POST once, body carries nested
  conditions/grantControls mapped from flat desired
- [ ] `Set` with current (id stashed) → PATCH once to `.../policies/<id>`
- [ ] end-to-end through `Get-M365Plan`: profile with ID-1 + ID-2 orders ID-1
  first (DependsOn), and an absent policy shows Action Create in the plan

**Done when:** suite green, registry + reference profile updated, reviewed,
Jira Done, ledger ticked. *(Registry and profile are hot-spot files — this
story owns them while In Progress.)*

---

## S4 · MCA-24 — ID-3 require MFA for all users (CA collection control)

**Goal:** second CA control (SCuBA MS.AAD.3.2v2): named policy `Require MFA
for all users`, grant `mfa`.

**Files:**
- Create `src/M365Configurator/Private/New-M365RequireMfaControl.ps1`
- Modify `Public/Get-M365ControlRegistry.ps1`, `profiles/security-baseline.yaml`
- Test `tests/New-M365RequireMfaControl.Tests.ps1`

**Spec:** identical structure to S3 (it reuses
`Get-M365CaPolicyProjection` and the same Compare shape — copy the S3 handler,
do NOT extract further shared helpers; two similar 60-line controls are easier
to review than a premature abstraction). Differences only:
- Id `ID-3`, Title `Require MFA for all users (Conditional Access)`,
  well-known displayName `Require MFA for all users`.
- Desired: `clientAppTypes: [all]` (SCuBA applies MFA broadly), `grantControls:
  [mfa]`, rest as S3.
- Profile block: same shape, id ID-3, comment citing SCuBA MS.AAD.3.2v2 and
  the lockout caveat (an unregistered admin can lock themselves out — dry-run
  first; this is the profile's stated posture, not the tool's problem).
- Tests: same list as S3 with names/values adjusted (yes, all of them).

---

## S5 · MCA-25 — AM-2 disable weak MFA methods

**Goal:** SMS / Voice / Email OTP disabled as auth methods (SCuBA
MS.AAD.3.5v2). Graph singleton per D3.

**Files:**
- Create `src/M365Configurator/Private/New-M365WeakMfaMethodsControl.ps1`
- Modify `Public/Get-M365ControlRegistry.ps1`, `profiles/security-baseline.yaml`
- Test `tests/New-M365WeakMfaMethodsControl.Tests.ps1`

**Mechanism (✅ verified 2026-07-25, Graph v1.0):** read
`GET v1.0/policies/authenticationMethodsPolicy` → `authenticationMethodConfigurations[]`
each `{ id, state }` with ids `Sms`, `Voice`, `Email` (among others). Write:
`PATCH v1.0/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/{segment}`
where the documented URL segment is **lowercase** — `/sms`, `/voice`,
`/email` — while the GET/body `id` is PascalCase (`Sms`): use fixed lowercase
URL constants, never interpolate the id read back. Body
`@{ '@odata.type' = <type>; state = 'disabled' }` (the `@odata.type` is
mandatory) where type is
`#microsoft.graph.smsAuthenticationMethodConfiguration` /
`#microsoft.graph.voiceAuthenticationMethodConfiguration` /
`#microsoft.graph.emailAuthenticationMethodConfiguration`. `state` ∈
`enabled`|`disabled`. Scope `Policy.ReadWrite.AuthenticationMethod`.

**Implementation:** constructor `-Id 'AM-2' -Provider 'graph' -Shape
'singleton' -Title 'Disable weak MFA methods (SMS / Voice / Email OTP)'`, no
DependsOn. `Get`: one GET, walk `authenticationMethodConfigurations` matching
ids `Sms`/`Voice`/`Email`, project
`@{ sms = <state>; voice = <state>; email = <state> }` (lowercase keys; a
missing method config → `'enabled'`? **No** — absent means the tenant doesn't
surface it; project only what exists and default absent to `$null`; the
default diff then reports `$null -> disabled`, which is honest). No custom
Compare. `Set`: method map keyed by vocabulary →
`@{ sms = @('sms', '#microsoft.graph.smsAuthenticationMethodConfiguration'); ... }`
(first element = the **lowercase URL segment**); for each desired key whose
value differs from `$Current` (use `Get-M365MapValue`), PATCH that method's
lowercase URL; return
`@{ Id = 'AM-2'; Outcome = 'Applied'; Patched = @(<method ids>) }`.

**Profile block:** settings `{ sms: disabled, voice: disabled, email: disabled }`,
framework CISA-SCuBA, comment citing MS.AAD.3.5v2.

**Tests:**
- [ ] registered: AM-2/graph/singleton, no DependsOn
- [ ] `Get` GETs the policy once; projects exactly sms/voice/email states from
  a fixture carrying extra methods (Fido2 etc. must not appear)
- [ ] `Get` projects `$null` for a method id absent from the fixture
- [ ] `Set` with all three differing → three PATCHes, each to the right
  **lowercase** URI segment with the right `@odata.type` and
  `state = 'disabled'`
- [ ] `Set` with only `sms` differing → exactly one PATCH (Voice/Email
  untouched)
- [ ] default engine diff: desired all-disabled vs current sms enabled →
  plan shows Update with the one Change

---

## S6 · MCA-26 — CON-1 + CON-3 restrict user consent & app registration

**Goal:** authorization-policy singleton (SCuBA MS.AAD.5.2v1 + 5.1v1): users
cannot consent to apps (or only low-risk verified-publisher) and cannot
register applications.

**Files:**
- Create `src/M365Configurator/Private/New-M365AppConsentControl.ps1`
- Modify registry + reference profile
- Test `tests/New-M365AppConsentControl.Tests.ps1`

**Mechanism (✅ verified 2026-07-25, Graph v1.0 `authorizationPolicy` — a
singleton at `GET/PATCH v1.0/policies/authorizationPolicy`):** BOTH fields
live under the nested `defaultUserRolePermissions` object in v1.0 —
`defaultUserRolePermissions.allowedToCreateApps` (bool) and
`defaultUserRolePermissions.permissionGrantPoliciesAssigned` (string[];
**empty list = user consent disabled**; low-risk =
`@('managePermissionGrantsForSelf.microsoft-user-default-low')`; legacy
default = `...microsoft-user-default-legacy`). ⚠️ beta calls this
`permissionGrantPolicyIdsAssignedToDefaultUserRole` at top level — do NOT use
the beta shape. Scope `Policy.ReadWrite.Authorization`.

**⚠️ Read-modify-write is MANDATORY here.** `permissionGrantPoliciesAssigned`
also carries `managePermissionGrantsForOwnedResource.*` entries (e.g.
`...DeveloperConsent`) that the docs explicitly say must be preserved — a
literal desired-state payload would silently strip developer-consent
capability. So the control's vocabulary covers ONLY the user-consent half:

**Implementation:** `-Id 'CON-1' -Provider 'graph' -Shape 'singleton' -Title
'Restrict user app consent and app registration'`. Flat projection (D4):
`Get` → `@{ allowedToCreateApps = [bool]; userConsentPolicies =
@(sorted string[]) }` where `userConsentPolicies` is
`permissionGrantPoliciesAssigned` **filtered to entries starting with**
`managePermissionGrantsForSelf.` (both read from the response's
`defaultUserRolePermissions` via `Get-M365MapValue`). `Set` must **re-GET the
live policy first** (the projection deliberately lost the foreign entries),
then PATCH `v1.0/policies/authorizationPolicy` with
`defaultUserRolePermissions` built from the declared keys only
(`Test-M365MapHasKey`): `allowedToCreateApps` verbatim;
`permissionGrantPoliciesAssigned` = (live entries NOT starting with
`managePermissionGrantsForSelf.`) + desired `userConsentPolicies`.
(Do NOT copy the Entra "configure user consent" article's PowerShell tab — it
has two documented bugs: a nonexistent beta-style property name and a doubled
prefix. The Graph REST reference is the authority.)

**Profile block:** settings
`{ allowedToCreateApps: false, userConsentPolicies: [managePermissionGrantsForSelf.microsoft-user-default-low] }`
(empty `userConsentPolicies: []` = user consent disabled entirely — the
stricter SCuBA posture; low-risk is the shipped default, comment both).

**Tests:**
- [ ] registered CON-1/graph/singleton
- [ ] `Get` projects the two flat keys from a nested fixture whose
  `permissionGrantPoliciesAssigned` mixes self + owned-resource entries —
  only the `managePermissionGrantsForSelf.*` ones appear, sorted; extra
  authorizationPolicy fields like `allowInvitesFrom` must NOT appear
- [ ] `Set` with both keys → GET then PATCH; the PATCH body's
  `permissionGrantPoliciesAssigned` PRESERVES the live
  `managePermissionGrantsForOwnedResource.DeveloperConsent` entry alongside
  the desired self entries (the load-bearing test of this story)
- [ ] `Set` with only `allowedToCreateApps` declared → the
  `defaultUserRolePermissions` body contains ONLY that key (no
  consent-policies key, and NO extra GET needed — assert none)
- [ ] engine default-diff: legacy-consent fixture vs low-risk desired → Update
  with one Change on `userConsentPolicies`

**Note:** control id is `CON-1` (covers both settings; the Jira story name
says CON-1 + CON-3 — one control, two fields; record that in the Jira closing
comment).

---

## S7 · MCA-27 — CON-2 admin consent workflow

**Goal:** admin consent request policy enabled with reviewers (SCuBA
MS.AAD.5.3v1).

**Files:**
- Create `src/M365Configurator/Private/New-M365AdminConsentWorkflowControl.ps1`
- Modify registry + reference profile
- Test `tests/New-M365AdminConsentWorkflowControl.Tests.ps1`

**Mechanism (✅ verified 2026-07-25, Graph v1.0):** `GET v1.0/policies/adminConsentRequestPolicy`
→ `{ isEnabled, notifyReviewers, remindersEnabled, requestDurationInDays,
reviewers: [ { query: '/users/<id>', queryType: 'MicrosoftGraph' } ] }`.
**Update is `PUT` (not PATCH)** to the same URL and all five properties are
required in the body (full replace). Reviewer objects carry `query` +
`queryType` only (omit `queryRoot`, per the documented example). Scope
`Policy.ReadWrite.ConsentRequest`.

**Implementation:** `-Id 'CON-2' -Provider 'graph' -Shape 'singleton' -Title
'Admin consent request workflow'`. Projection: `@{ isEnabled = [bool];
notifyReviewers = [bool]; remindersEnabled = [bool]; requestDurationInDays =
[int]; reviewerQueries = @(sorted string[] of reviewers[].query) }`. `Set`
builds the **full** PUT body from Desired — because PUT replaces, every field
must be present in the desired settings; add a guard: any of the five keys
missing from `$Desired` → throw (`"CON-2 requires the full settings map
(isEnabled, notifyReviewers, remindersEnabled, requestDurationInDays,
reviewerQueries) because the Graph update is a full-replace PUT"`).
`reviewers` body = `@(foreach q in sorted reviewerQueries: @{ query = $q;
queryType = 'MicrosoftGraph' })`.
Method support: `Invoke-M365GraphRequest` already allows PUT.

**Profile block:** enabled, notify+reminders true, 30 days, and a placeholder
reviewer — **profiles are per-tenant here**: ship
`reviewerQueries: []` in the reference baseline with a loud YAML comment that
each client must set at least one reviewer (`/users/<object-id>`), and that
the control refuses an enabled-with-no-reviewers desired state: in `Set`,
`isEnabled true` + empty `reviewerQueries` → throw (a consent workflow with no
reviewers silently blackholes requests). Add the matching test.

**Tests:**
- [ ] registered CON-2/graph/singleton
- [ ] `Get` projects the five keys (reviewers flattened to sorted queries;
  fixture has unsorted + queryType noise)
- [ ] `Set` PUTs (not PATCHes) the full body with reviewers rebuilt
- [ ] `Set` with a missing key throws the full-map message
- [ ] `Set` with enabled + zero reviewers throws
- [ ] engine default-diff detects `isEnabled false -> true`

---

## S8 · MCA-28 — SHR-1 restrict who can invite guests

**Goal:** `allowInvitesFrom = adminsAndGuestInviters` (SCuBA MS.AAD.8.2v1) —
authorization-policy singleton again.

**Files:**
- Create `src/M365Configurator/Private/New-M365GuestInviteControl.ps1`
- Modify registry + reference profile
- Test `tests/New-M365GuestInviteControl.Tests.ps1`

**Mechanism (✅ verified, Graph v1.0):** same singleton as S6.
`allowInvitesFrom` ∈ `none` | `adminsAndGuestInviters` |
`adminsGuestInvitersAndAllMembers` | `everyone`.

**Implementation:** `-Id 'SHR-1' -Provider 'graph' -Shape 'singleton' -Title
'Restrict who can invite guests'`. `Get` → `@{ allowInvitesFrom = [string] }`.
`Set` → `PATCH v1.0/policies/authorizationPolicy` body
`@{ allowInvitesFrom = <desired> }`. Simplest control in the set — mirror the
security-defaults file closely.

**Profile block:** `settings: { allowInvitesFrom: adminsAndGuestInviters }`,
SCuBA MS.AAD.8.2v1 comment.

**Tests:** registered (SHR-1/graph/singleton) · Get projects only
`allowInvitesFrom` from a noisy fixture · Set PATCHes exactly that body ·
engine diff `everyone -> adminsAndGuestInviters`.

**Coexistence note (test it):** SHR-1 and CON-1 both PATCH
`policies/authorizationPolicy` but declare disjoint keys, so their diffs never
overlap. Add one test planning a profile with both controls: two independent
plan items, no cross-talk.

---

## S9 · MCA-21 — Session object + capability gating

**Goal:** `Session.Capabilities` becomes real (D8): connection-presence and
license-derived capability strings, surfaced as `Blocked` items in dry-run
(already engine-supported), so under-licensed/-connected applies can't
half-run.

**Files:**
- Create `src/M365Configurator/Public/New-M365Session.ps1`
- Modify `M365Configurator.psd1` (export), the four Graph control files +
  registry (add `RequiredCapabilities @('graph')`), reference profile
  untouched
- Test `tests/New-M365Session.Tests.ps1` (+ extend each control test's
  "registered" case for the new RequiredCapabilities)

**Implementation:**

```powershell
function New-M365Session {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        $Graph,        # output of Connect-M365Graph (or $null)
        $Exo,          # output of Connect-M365ExchangeOnline (or $null)
        # Seam: license probe. Default hits Graph only when connected.
        [scriptblock] $LicenseReader = {
            Invoke-M365GraphRequest -Method GET -Uri 'v1.0/subscribedSkus'
        }
    )
    $caps = [System.Collections.Generic.List[string]]::new()
    if ($Graph -and (Get-M365MapValue $Graph 'Connected')) { $caps.Add('graph') }
    if ($Exo   -and (Get-M365MapValue $Exo   'Connected')) { $caps.Add('exo') }
    if ($caps.Contains('graph')) {
        $skus = & $LicenseReader
        $plans = @(
            foreach ($sku in @(Get-M365MapValue $skus 'value')) {
                foreach ($p in @(Get-M365MapValue $sku 'servicePlans')) {
                    Get-M365MapValue $p 'servicePlanName'
                }
            }
        )
        if ($plans -contains 'AAD_PREMIUM')    { $caps.Add('entra-id-p1') }
        if ($plans -contains 'AAD_PREMIUM_P2') { $caps.Add('entra-id-p2') }
        if (@('THREAT_INTELLIGENCE', 'ATP_ENTERPRISE') | Where-Object { $plans -contains $_ }) {
            $caps.Add('defender-office365')
        }
    }
    [pscustomobject]@{
        PSTypeName   = 'M365Configurator.Session'
        Graph        = $Graph
        Exo          = $Exo
        Capabilities = @($caps | Sort-Object -Unique)
    }
}
```

(✅ servicePlanName values verified against Microsoft's licensing
service-plan reference 2026-07-25: `AAD_PREMIUM` = Entra ID P1,
`AAD_PREMIUM_P2` = Entra ID P2, `ATP_ENTERPRISE` = Defender for Office 365
**Plan 1**, `THREAT_INTELLIGENCE` = **Plan 2** — Plan 2 SKUs include the
ATP_ENTERPRISE plan too, so matching either is correct. GCC tenants use
`*_GOV` variants — out of v1 scope, don't handle them.)

Retrofit in the same story: `New-M365SecurityDefaultsControl`,
`New-M365LegacyAuthBlockControl`, `New-M365RequireMfaControl`,
`New-M365WeakMfaMethodsControl`, `New-M365AppConsentControl`,
`New-M365AdminConsentWorkflowControl`, `New-M365GuestInviteControl` each gain
`-RequiredCapabilities @('graph')`.

**Tests:**
- [ ] no connections → Capabilities `@()`
- [ ] graph-only connected fixture → `@('graph')` and the license seam WAS
  invoked; exo-only → `@('exo')` and the license seam NOT invoked
- [ ] SKU fixture with AAD_PREMIUM + AAD_PREMIUM_P2 + ATP_ENTERPRISE →
  all five caps, sorted, unique
- [ ] session shape: PSTypeName + Graph/Exo passthrough
- [ ] end-to-end: plan a graph-control profile with a session lacking
  `graph` → item Blocked with gate text `requires capability: graph`
- [ ] each control's registered-case asserts its RequiredCapabilities

---

## S10 · MCA-30 — MDO-1 Standard preset security policy (+ EXO seam)

**Goal:** the flagship EXO control (SCuBA MS.DEFENDER.1.1–1.5): the Standard
preset's EOP and ATP rules are **Enabled**. Also builds the EXO command seam
(D5) every later EXO control uses.

**Files:**
- Create `src/M365Configurator/Private/Invoke-M365ExoCommand.ps1`
- Create `src/M365Configurator/Private/New-M365StandardPresetControl.ps1`
- Modify registry + reference profile
- Test `tests/Invoke-M365ExoCommand.Tests.ps1`,
  `tests/New-M365StandardPresetControl.Tests.ps1`

**Seam (D5):**

```powershell
function Invoke-M365ExoCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Name,
        [hashtable] $Parameters = @{}
    )
    # Resolved at call time: the EXO module is a runtime prerequisite handled
    # by the module preflight (ADR-0011), not a parse-time dependency.
    $command = Get-Command -Name $Name -ErrorAction Stop
    & $command @Parameters
}
```

Seam tests: invokes the named command with the splat (register a fake function
in the test scope); unknown command throws (loud).

**Mechanism (✅ verified 2026-07-25, ExchangeOnlineManagement 3.x):** preset
state lives on the rules: `Get-EOPProtectionPolicyRule -Identity 'Standard
Preset Security Policy'` / `Get-ATPProtectionPolicyRule -Identity 'Standard
Preset Security Policy'`, each with `State` `Enabled`|`Disabled`; enable via
`Enable-EOPProtectionPolicyRule` / `Enable-ATPProtectionPolicyRule`, disable
via the `Disable-` pair. **The rules do not exist until the preset has been
turned on once in the Defender portal** — Microsoft explicitly documents that
the portal is the ONLY supported way to create them (`New-*ProtectionPolicyRule`
exists but is documented as not recommended, and needs policy names embedding
an unpredictable timestamp). Treat "rule absent" as state `NotPresent` — this
control is deliberately **not self-healing** (ADR-0011's consented-fix offer
here IS the portal instruction; there is no supported programmatic fix).
ATP rule + cmdlets need Defender for Office 365 — on EOP-only tenants the
`defender-office365` capability gate blocks the whole control (EOP-only
preset coverage is out of v1; note it when closing the Jira story). "All
users" = empty rule conditions.

**Implementation:** `-Id 'MDO-1' -Provider 'exo' -Shape 'preset' -Title
'Standard preset security policy' -RequiredCapabilities @('exo',
'defender-office365')`. `Get`: two `Invoke-M365ExoCommand` calls
(`Get-EOPProtectionPolicyRule`, `Get-ATPProtectionPolicyRule`) each with
`-Parameters @{ Identity = 'Standard Preset Security Policy'; ErrorAction =
'SilentlyContinue' }`… **no silent catches (NFR-6)** — instead: pass no
ErrorAction and wrap each in try/catch that maps ONLY the known
"not found" failure to `NotPresent` and rethrows anything else. Projection:
`@{ eopRuleState = 'Enabled'|'Disabled'|'NotPresent'; atpRuleState = same }`.
Default compare. `Set`: for each declared key whose desired ≠ current:
desired `Enabled` + current `Disabled` → `Enable-*ProtectionPolicyRule`;
desired `Enabled` + current `NotPresent` → **throw** with the remediation
message ("the Standard preset has never been initialised on this tenant —
enable it once in the Defender portal (Policies & rules → Threat policies →
Preset security policies); creating it programmatically requires authoring
the full policy set, which is out of v1 scope"); desired `Disabled` →
`Disable-*ProtectionPolicyRule`. Return
`@{ Id = 'MDO-1'; Outcome = 'Applied'; Rules = @(<changed rule names>) }`.

**Profile block:** `settings: { eopRuleState: Enabled, atpRuleState: Enabled }`
with SCuBA MS.DEFENDER.1.1v1 comment.

**Tests:** registered (MDO-1/exo/preset/caps) · Get maps two rule fixtures to
the two states · Get maps rule-not-found to NotPresent (fake command throws
the EXO not-found error) but rethrows an unrelated error · Set enables only
the differing rule · Set throws the initialisation message on
Enabled-vs-NotPresent · engine plans Update when ATP disabled.

---

## S11 · MCA-31 — MDO-4 block external auto-forwarding

**Goal:** outbound spam policy `AutoForwardingMode = Off` (SCuBA MS.EXO.1.1v2).

**Files:** Create `Private/New-M365AutoForwardBlockControl.ps1`; modify
registry + profile; test `tests/New-M365AutoForwardBlockControl.Tests.ps1`.

**Mechanism (✅ verified 2026-07-25):** `Get-HostedOutboundSpamFilterPolicy`
(all policies; the default is named `Default` and cannot be disabled),
`Set-HostedOutboundSpamFilterPolicy -Identity <name> -AutoForwardingMode Off`;
`AutoForwardingMode` ∈ `Automatic` | `On` | `Off` (docs note `Automatic` now
behaves as `Off`; the profile ships an explicit `Off` for clarity, as the
docs themselves recommend). The policy+rule pairing applies only to CUSTOM
policies — modifying the Default policy needs no rule.

**Implementation:** `-Id 'MDO-4' -Provider 'exo' -Shape 'policy-rule' -Title
'Block external auto-forwarding' -RequiredCapabilities @('exo')`. Profile
settings: `{ name: Default, autoForwardingMode: 'Off' }` (name-scoped — an
FR-7 remap target). `Get`: `Invoke-M365ExoCommand -Name
'Get-HostedOutboundSpamFilterPolicy'`, find by `Name -eq` the **well-known
name `Default`** (same fixed-name convention as D2/S3 — MCA-16 threads
overrides later); absent → **throw** (`"outbound spam filter policy 'Default'
not found — every tenant ships one; this indicates a broken EXO session"`).
Project `@{ name; autoForwardingMode }` (both strings). Default compare.
`Set`: `Set-HostedOutboundSpamFilterPolicy` with `Identity = name`,
`AutoForwardingMode = desired`. v1 is **update-only** (no policy creation —
the Default policy always exists).

**Semantics note (encode in the profile YAML comment):** the tenant default
`Automatic` was silently redefined by Microsoft to BEHAVE as `Off` — so the
dry-run Change `Automatic -> Off` makes the setting explicit (the docs' own
recommendation) without altering effective behavior. Say exactly that in the
profile comment so an operator reading the plan isn't alarmed.

**Tests:** registered · Get projects name+mode from a multi-policy fixture
(picks Default) · Get throws when absent · Set calls the Set cmdlet with the
right Identity/mode · engine diff `Automatic -> Off`.

---

## S12 · MCA-32 — MDO-10 external sender warning

**Goal:** native Outlook External tag on (SCuBA MS.EXO.7.1v1).

**Files:** Create `Private/New-M365ExternalSenderTagControl.ps1`; modify
registry + profile; test `tests/New-M365ExternalSenderTagControl.Tests.ps1`.

**Mechanism (✅ verified 2026-07-25):** `Get-ExternalInOutlook` (returns
per-org config objects with `Identity`, `Enabled`, `AllowList`),
`Set-ExternalInOutlook [-Identity <org>] [-Enabled <bool>] [-AllowList
<addresses>]` (no `-Identity` needed for the tenant default; the cmdlet has
no `-WhatIf` — irrelevant here, our dry-run never calls Set).

**Implementation:** `-Id 'MDO-10' -Provider 'exo' -Shape 'singleton' -Title
'External sender warning (Outlook native tag)' -RequiredCapabilities
@('exo')`. `Get`: `Invoke-M365ExoCommand -Name 'Get-ExternalInOutlook'`, take
the **first** returned object (multi-geo tenants return several; v1 manages
the primary — record in a comment), project `@{ enabled = [bool];
allowList = @(sorted string[]) }`. `Set`: build parameters from declared
desired keys only (`Enabled` from `enabled`, `AllowList` from sorted
`allowList`), one `Set-ExternalInOutlook` call.

**Profile block:** `settings: { enabled: true, allowList: [] }`.

**Tests:** registered · Get projects enabled+sorted allowList, first object
only · Set maps keys (only-declared: enabled-only desired → no AllowList
param) · engine diff false→true.

---

## S13 · MCA-33 — AUD-1 unified audit log

**Goal:** unified audit log ingestion on (SCuBA MS.DEFENDER.6.1v1).

**Files:** Create `Private/New-M365UnifiedAuditLogControl.ps1`; modify
registry + profile; test `tests/New-M365UnifiedAuditLogControl.Tests.ps1`.

**Mechanism (✅ verified 2026-07-25):** `Get-AdminAuditLogConfig` →
`UnifiedAuditLogIngestionEnabled` (bool); `Set-AdminAuditLogConfig
-UnifiedAuditLogIngestionEnabled $true`. Caveat from the docs: the property
is only meaningful in **Exchange Online** PowerShell — in Security &
Compliance PowerShell it always reads `False`; our EXO-only session (research
02) is the right one. (Most tenants have auditing on by default since 2019 —
the control usually plans NoChange; it exists to catch the turned-it-off
case — and it is NOT on by default for Business Basic/Standard/Premium
licences, so on SMB tenants expect it to be actionable.)

**Implementation:** `-Id 'AUD-1' -Provider 'exo' -Shape 'singleton' -Title
'Unified audit log ingestion' -RequiredCapabilities @('exo')`. `Get` →
`@{ unifiedAuditLogIngestionEnabled = [bool] }`. `Set` → one
`Set-AdminAuditLogConfig` call. Simplest EXO control; mirror S12.
**Propagation note:** enabling takes up to 60 minutes to apply (hours to be
searchable) — v1's apply reports the Set outcome and does NOT immediately
re-read to verify; an instant re-read would false-fail. Don't add one.

**Profile block:** `settings: { unifiedAuditLogIngestionEnabled: true }`.

**Tests:** registered · Get projects the one bool (noisy fixture) · Set maps
it · engine diff false→true.

---

## S14 · MCA-34 — AUD-2 mailbox auditing (org default)

**Goal:** org-wide mailbox auditing on: `AuditDisabled = $false` (SCuBA
MS.EXO.13.1v1).

**Files:** Create `Private/New-M365MailboxAuditControl.ps1`; modify registry +
profile; test `tests/New-M365MailboxAuditControl.Tests.ps1`.

**Mechanism (✅ per research 02 §3.7 + SCuBA MS.EXO.13.1):**
`Get-OrganizationConfig` → `AuditDisabled` (bool; `$false` = auditing ON);
`Set-OrganizationConfig -AuditDisabled $false`.

**Implementation:** `-Id 'AUD-2' -Provider 'exo' -Shape 'singleton' -Title
'Mailbox auditing (organization default)' -RequiredCapabilities @('exo')`.
Projection uses the **positive** vocabulary: `@{ auditEnabled = [bool] }` with
`auditEnabled = -not AuditDisabled` (readable profiles — NFR-9); `Set` maps
back (`AuditDisabled = -not desired.auditEnabled`).
**Scope decision (recorded):** per-mailbox audit actions (`Set-Mailbox
-AuditOwner ...`) are OUT of v1 — org default only; note it in the Jira close.
**Do not "improve" this with per-mailbox reads:** under audit-on-by-default,
`Get-Mailbox` reports `AuditEnabled: True` for every mailbox regardless of
reality, and setting it `$false` is silently ignored — the real exclusion
mechanism is `Set-MailboxAuditBypassAssociation`, all of which is exactly why
the per-mailbox surface is deferred.

**Profile block:** `settings: { auditEnabled: true }`.

**Tests:** registered · Get inverts AuditDisabled correctly both ways · Set
inverts back · engine diff detects drift when org has auditing disabled.

---

## S15 · MCA-19 — Drift detection

**Goal:** FR-10: scan the tenant against a saved profile, report drift — D6:
the plan re-labelled, zero new diff logic.

**Files:**
- Create `src/M365Configurator/Private/Format-M365DriftReport.ps1`
- Create `src/M365Configurator/Public/Get-M365Drift.ps1`
- Modify `M365Configurator.psd1`
- Test `tests/Get-M365Drift.Tests.ps1`

**Implementation:** `Get-M365Drift` takes the same parameters as
`Invoke-M365DryRun` (`-ProfilePath`/`-InputObject`, `-Session`, `-Registry`,
`-Importer`). It calls `Get-M365Plan`, then projects: report PSTypeName
`M365Configurator.DriftReport` with `ProfileName`, `Signal` (`InSync` when
**every** item's Status is InSync; anything else — Drifted, Blocked, or
Unsupported — makes it `NeedsAttention`), `Summary` (per-Status counts), `Items[]`
each `{ Id, Title, Provider, Status, Changes, Gate }` where Status maps
NoChange→`InSync`, Create/Update→`Drifted`, Blocked→`Blocked`,
Unsupported→`Unsupported`. Renders via `Format-M365DriftReport` (glyphs `=`
InSync, `~` Drifted, `!` Blocked, `?` Unsupported; footer `Result: IN SYNC |
NEEDS ATTENTION - n drifted, n in-sync, n blocked, n unsupported`). Returns
the report object.

**Tests (fake registry):** all-NoChange plan → InSync signal, statuses mapped ·
one Update → Drifted with Changes carried through · Blocked/Unsupported map
through with Gate text · renderer is deterministic (assert exact lines) ·
plan is computed via Get-M365Plan (no Set invoked — spy control).

---

## S16 · MCA-20 — Deterministic remediation

**Goal:** FR-11: preview + consented apply of exactly the drifted subset (D7).

**Files:**
- Create `src/M365Configurator/Public/Invoke-M365Remediation.ps1`
- Modify `M365Configurator.psd1`
- Test `tests/Invoke-M365Remediation.Tests.ps1`

**Implementation:** parameters as `Invoke-M365Apply` (incl. `-Approve`).
Compute the full plan (`Get-M365Plan`); if any Blocked/Unsupported → throw
(same rule as apply). Build the remediation view: items with Action
Create/Update. Render those via `Format-M365Plan` (reuse — pass a shallow
plan copy `[pscustomobject]@{ ProfileName = "$($plan.ProfileName) (remediation)";
Signal = ...; Summary = recomputed; Items = @(drifted) }`). Without
`-Approve`: warn + return the remediation plan. With `-Approve` and zero
drifted items: return Outcome `NothingToDo` without touching the tenant. With
drifted items: `Invoke-M365PlanApplication` on the sub-plan (order is
preserved from the full plan, so dependencies still precede dependents —
**note:** a dependency that is itself `NoChange` is correctly absent from the
sub-plan; it needs no re-apply).

**Tests:** no drift → NothingToDo, no Set · drift on 1 of 3 → only that
item's Set runs (with -Approve) · without -Approve → preview only, no Set ·
Blocked item anywhere → throw · sub-plan preserves relative order of drifted
items (fixture with DependsOn chain).

---

## S17 · MCA-16 — Name remapping on apply

**Goal:** FR-7: per-client names for name-scoped controls (D9) without
touching the saved profile.

**Files:**
- Create `src/M365Configurator/Private/Set-M365ProfileNameOverride.ps1`
- Modify `Public/Invoke-M365DryRun.ps1`, `Public/Invoke-M365Apply.ps1`,
  `Public/Get-M365Drift.ps1` (add `-NameOverride [hashtable]`), and the three
  name-scoped control files (see below)
- Test `tests/Set-M365ProfileNameOverride.Tests.ps1` + extend the three entry
  points' tests

**Implementation:** `Set-M365ProfileNameOverride -InputObject <profile>
-NameOverride <hashtable>` returns a **deep-enough copy** of the profile
(copy the controls array and each overridden control's settings map — never
mutate the input; the rest may be shared) where, for each `<controlId> =
<newName>` pair: the matching control's name-bearing settings key is replaced.
Name-bearing key by control id: `ID-2`/`ID-3` → `displayName`; `MDO-4` →
`name`. Also update the control's top-level `name` field when present.
Unknown control id in the map, or a control whose id has no name-bearing key
registered → throw (NFR-6). Maintain the id→key mapping as a private constant
inside this helper (a simple `@{ 'ID-2' = 'displayName'; 'ID-3' =
'displayName'; 'MDO-4' = 'name' }`) — controls added later extend it.

**The Get coupling (deferred from S3):** the CA/EXO `Get` seams match on the
fixed well-known name, so a renamed policy needs `Get` to know the effective
name. Solve it now, minimally: the three name-scoped controls' `Get` seams
read the effective name from the session-independent module-scope variable
`$script:M365NameOverride` — **no.** Simpler and testable: those controls'
`Get` seams already receive `$Session`; thread overrides through the session:
`Set-M365ProfileNameOverride` ALSO returns the effective-name map, and the
three entry points pass `$Session` augmented with a `NameOverride` member
(`Add-Member -NotePropertyName NameOverride -NotePropertyValue $map -Force` on
a shallow copy). Each name-scoped `Get` resolves its effective name:
`$name = (Get-M365MapValue (Get-M365MapValue $Session 'NameOverride') 'ID-2') ?? 'Block legacy authentication'`.
Update S3/S4/S11 control `Get` seams accordingly (one line each) and their
tests (one new case each: override present → filter uses it).

**Tests:** override rewrites displayName for ID-2 without mutating the source
profile object (assert original untouched) · unknown id throws · MDO-4 `name`
key path · dry-run with `-NameOverride` shows the remapped name in the plan ·
CA `Get` matches the overridden name via `$Session.NameOverride`.

---

## S18 · MCA-35 — Structured audit log

**Goal:** NFR-5/FR-12: an append-only, secret-free JSONL record of every
change-applying action (D10).

**Files:**
- Create `src/M365Configurator/Private/Write-M365AuditRecord.ps1`
- Create `src/M365Configurator/Public/Get-M365AuditLog.ps1`
- Modify `Private/Invoke-M365PlanApplication.ps1` (emit records),
  `M365Configurator.psd1` (export Get-M365AuditLog)
- Test `tests/Write-M365AuditRecord.Tests.ps1`, `tests/Get-M365AuditLog.Tests.ps1`

**Implementation:**
- `Write-M365AuditRecord -Record <hashtable> -LogDirectory <string>`:
  validates the record with `Find-M365SecretKey` (any hit → throw — the
  NFR-1 backstop); ensures the directory exists; appends one line of
  `ConvertTo-Json -Compress -Depth 8` to
  `m365config-audit-<yyyyMMdd>.jsonl` (UTC date). Directory resolution:
  explicit param, else `$env:M365_CONFIGURATOR_LOG_DIR`, else `./logs`.
- `Invoke-M365PlanApplication` gains `[scriptblock] $AuditWriter = { param($Record)
  Write-M365AuditRecord -Record $Record }` and emits: one `run-started` record
  (runId GUID, profile name, actor from
  `Get-M365MapValue (Get-M365MapValue $Session 'Graph') 'Account'`, item
  count), one record per item outcome (`action = 'apply-item'`, controlId,
  outcome, changes from the plan item, error message when Failed), one
  `run-finished` record (overall outcome, counts). Timestamps:
  `[DateTime]::UtcNow.ToString('o')`.
- `Get-M365AuditLog [-Date <yyyyMMdd>] [-ControlId <string>] [-LogDirectory ...]`:
  reads the day's file (default today UTC), parses each line, optional
  control-id filter, returns objects; missing file → empty result with a verbose
  note (not an error — an un-applied day has no log).

**Tests:** record with a secret-shaped key throws and writes nothing · JSONL
append is one-line-per-record and parseable · env-var directory honored ·
apply run (fake controls) emits run-started/apply-item/run-finished with the
right outcomes (inject a capturing AuditWriter) · failed item logs the error
and run-finished Outcome Failed · Get-M365AuditLog filters by control id ·
missing file → empty, no throw.

---

## S19 · MCA-36 — CLI dispatcher

**Goal:** ADR-0012's v1 CLI: one script that runs save / dry-run / apply /
drift for a profile (D11).

**Files:**
- Create `src/M365Configurator/Private/Read-M365ControlState.ps1` (the real
  tenant reader `Save-M365Profile` was built to receive — see below)
- Create `scripts/m365config.ps1`
- Test `tests/Read-M365ControlState.Tests.ps1`, `tests/M365ConfigCli.Tests.ps1`
- Modify `README.md` (a short "CLI" usage section; also add the missing
  "License" section — Apache-2.0, see LICENSE — while the file is open:
  ADR-0010's recorded follow-up)

**Part A — `Read-M365ControlState`.** `Save-M365Profile` takes a mandatory
`-ControlReader` scriptblock returning control descriptors
(`@{ id; provider; settings; name? }`) — the real implementation was deferred
to "when the providers exist". They now exist. Build:
`Read-M365ControlState -Session <s> [-Registry <controls>]` (registry
defaults to `Get-M365ControlRegistry`): for each control, invoke
`& $control.Get $Session`; a `$null` result (e.g. an absent CA policy) →
**skip the control** with `Write-Verbose` (you cannot save what does not
exist); otherwise emit `@{ id = $control.Id; provider = $control.Provider;
settings = <projection minus the reserved stash key 'id'> }` — the CA
projection stashes the tenant policy `id` for PATCH; a tenant-specific GUID
must never be persisted into a shareable profile, so strip key `id` from a
**copy** of the settings map before emitting. Capability gates: a control
whose RequiredCapabilities aren't in `Session.Capabilities` is skipped with a
verbose note (reading it would throw against a disconnected provider).
Tests: emits descriptors for fake controls · skips null-Get controls · strips
the `id` stash without mutating the projection the Get returned · skips
capability-gated controls · defaults to the real registry (mock
`Get-M365ControlRegistry` module-scoped).

**Part B — the dispatcher.** `param([Parameter(Mandatory, Position=0)]
[ValidateSet('save','dryrun','apply','drift')][string] $Command,
[string] $ProfilePath, [string] $Name, [string] $Framework = 'CISA-SCuBA',
[string] $FrameworkVersion = '1.5.0', [string] $OutPath, [switch] $Approve,
[hashtable] $NameOverride, $Session,
[scriptblock] $Invoker = { param($FunctionName, $Splat) & (Get-Command
$FunctionName) @Splat })`. The script imports the module manifest
(`Import-Module "$PSScriptRoot/../src/M365Configurator/M365Configurator.psd1"`)
unless already loaded, builds the splat per command, and calls through
`$Invoker`:
`save` → `Save-M365Profile` with `Name`/`Framework`/`FrameworkVersion`/`Path`
(from `-OutPath`) and `ControlReader = { Read-M365ControlState -Session
$Session }` · `dryrun` → `Invoke-M365DryRun -ProfilePath ... -Session ...` ·
`apply` → `Invoke-M365Apply -ProfilePath ... -Session ... [-Approve]` ·
`drift` → `Get-M365Drift -ProfilePath ... -Session ...`. `-NameOverride`
forwards to dryrun/apply/drift when supplied. Validation (throw, NFR-6):
`dryrun|apply|drift` require `-ProfilePath`; `save` requires `-Name`.
Exit code: keep v1 plain — exit 0 unless an exception escapes (callers script
against the returned objects; CI-style signal gating is post-v1).

**Tests (dispatcher):** each command maps to the right function + splat
(capturing Invoker) · missing ProfilePath throws for dryrun/apply/drift ·
missing Name throws for save · save's splat carries a working ControlReader ·
`-Approve`/`-NameOverride` forwarded for apply · unknown command rejected by
ValidateSet (assert the error).

---

## S20 — Close-out (no Jira story; ~30 min)

- [ ] `docs/REQUIREMENTS.md`: flip status boxes — FR-1..FR-12 and NFRs that
  are now demonstrably satisfied get `[x]` (FR-4 stays `[~]` — the v1 slice
  covers a subset of the surface; NFR-4 stays `[ ]` until the container ships
  in Phase 5).
- [ ] `docs/ROADMAP.md`: mark Phase 4 complete/near-complete per reality.
- [ ] `CLAUDE.md`: update the roadmap-phase line; keep the runbook pointer.
- [ ] Confluence page `1048577`: update Status paragraph, build-status
  bullets, epics table, and the coordination block (lanes free / Phase 4
  state). Jira: every story Done; epics MCA-4/5/6 transition when their
  stories are all Done.
- [ ] Push, verify CI green on both matrix legs, and confirm
  `git status` clean + `main` synced with `origin/main`.

## When something surprises you

- A Graph/EXO response doesn't match the ✅ facts above → check
  `docs/research/01-microsoft-graph-surface.md` / `02-exchange-online-surface.md`,
  then Microsoft Learn; if the runbook fact is wrong, fix the runbook line in
  the same commit and say so in the commit body.
- A test you didn't touch goes red → stop; `git stash` your work; confirm the
  suite is green at HEAD; if it isn't, bisect before proceeding (do not layer
  work on a broken base).
- You need a decision this file doesn't make → it belongs to the owner. Post
  the question as a Jira comment on the story, mark the story blocked, move to
  the next queue item.

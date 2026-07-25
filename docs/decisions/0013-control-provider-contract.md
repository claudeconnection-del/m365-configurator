# 0013. Control-provider contract: Get / Compare / Set control handlers

- **Status:** Proposed
- **Date:** 2026-07-23
- **Deciders:** Project owner (pending ratification) — drafted autonomously during Phase 4 build
- **Requirements:** FR-4, FR-8, FR-9, FR-10, FR-11, FR-7; NFR-1, NFR-5, NFR-6, NFR-7, NFR-9
- **Related:** ADR-0002 (custom Graph/EXO engine), ADR-0008 (canonical form), ADR-0012 (CLI-first); Jira MCA-4, MCA-5, MCA-6, MCA-16; `docs/research/05-security-baselines.md` §4

## Context

ADR-0002 committed us to a **custom Graph/EXO change engine** rather than
Microsoft365DSC. The engine has to drive one profile through **save → dry-run →
apply → drift → remediate** across two very different backends, and research 05
§4 shows the v1 slice alone spans five distinct **mechanism classes**:

1. **Graph singleton PATCH** — authorization policy, security-defaults, auth-
   methods (CON-1/3, CON-2, SHR-1, ID-1, AM-2). Inherently idempotent.
2. **Graph name-scoped collection** — Conditional Access policies (ID-2, ID-3).
   Name-keyed, so an FR-7 remap target.
3. **EXO policy+rule pairing** — outbound spam filter policy + rule (MDO-4).
4. **EXO preset rule-toggle** — enable the Standard preset (MDO-1); settings are
   Microsoft-owned and *not* diffable field-by-field (research 05 R6), so the
   check is rule-state + coverage, not a settings diff.
5. **EXO singleton, no `-WhatIf`** — external-sender tag (MDO-10),
   `Set-ExternalInOutlook` has no preview flag, so the engine must compute its
   own diff.

If the engine hard-codes knowledge of each control it becomes an unmaintainable
`switch`. We need a small, uniform **contract** every control implements, so the
engine stays provider-agnostic and each control is independently testable — the
same scriptblock-seam discipline already used in the connection foundation
(`Connect-M365Graph` et al.) and the profile engine.

## Decision

A **control handler** is the unit of provider knowledge for exactly one control.
It is a plain `pscustomobject` with a fixed shape, produced by the Graph provider
(MCA-4) or the EXO provider (MCA-5) and discovered by id through a registry seam.
The contract:

```
Id            [string]  framework control id, e.g. 'MS.AAD.1.1' / local 'ID-2'
Provider      [string]  'graph' | 'exo'
Shape         [string]  'singleton' | 'collection' | 'policy-rule' | 'preset'
Title         [string]  human label for readable plan/drift output (NFR-9)
RequiredCapabilities [string[]]  license/platform gates, e.g. 'DefenderForO365',
                                 'EntraIdP2', 'Windows-SCC'  (empty = always available)
DependsOn     [string[]]  ids that must be planned/applied first (ordering)

Get      [scriptblock] { param($Session)                     -> current settings map, secret-free }
Compare  [scriptblock] { param($Desired,$Current)            -> { Action; Changes[] } }   # optional
Set      [scriptblock] { param($Session,$Desired,$Current)   -> per-item apply result }
```

The constructor (`New-M365Control`) **enforces these seam signatures at
construction**: the engine invokes seams positionally, so a handler whose
scriptblock doesn't declare the exact `param()` seam above would mis-bind
silently and only fail deep inside a plan or apply. It is rejected loudly at
build time instead (NFR-6).

- **The engine is generic.** Given a profile, a set of registered handlers, and a
  connected session it computes a **plan** (`Plan`), applies it (`Apply`), and
  scans for **drift** (`Drift`) without knowing anything control-specific:
  - **Plan (dry-run, FR-8):** for each profile control → resolve handler → evaluate
    `RequiredCapabilities` against the session → `Get` current → `Compare` to
    desired → emit a plan item `{ Id; Title; Action ∈ NoChange|Create|Update|
    Blocked|Unsupported; Changes; Gate }`. Aggregate to one **pass /
    needs-attention** signal.
  - **Apply (FR-9):** only on explicit go-ahead; walk actionable items in
    `DependsOn` order; re-check the gate; `Set`; re-`Get` and verify; record
    per-item success/failure. A failed item never silently rolls the rest back,
    and a blocked/unsupported item is never applied (NFR-6).
  - **Drift (FR-10) + remediation (FR-11):** `Drift` is `Plan` reported as
    compliant/drifted; remediation is `Apply` scoped to the drifted items, always
    previewed first — deterministic because it runs the identical plan step.
- **Comparison defaults to the canonical form.** The default `Compare` diffs
  `Desired` vs `Get` output via the profile engine's canonical JSON
  (ADR-0008 / `ConvertTo-M365SortedObject`), so "did anything change?" is
  byte-stable. Controls override `Compare` for the two cases the default can't
  express: the **preset** rule-state + coverage check, and any control whose
  desired shape isn't a straight settings map.
- **Correctness never depends on cmdlet `-WhatIf`.** Dry-run is always
  `Get` + `Compare`, computed by us. `-WhatIf` support, where it exists, is a
  belt-and-suspenders extra, not the source of truth — this absorbs the MDO-10
  no-`-WhatIf` case with no special path.
- **Gating is first-class and surfaced in dry-run (MCA-21).** A handler whose
  `RequiredCapabilities` aren't met on the tenant/platform yields a `Blocked`
  (license) or `Unsupported` (e.g. S&C-not-on-Linux) plan item with a clear
  reason — never a half-applied change.
- **Name remapping (FR-7, MCA-16)** is an engine concern for `Shape=collection`/
  `policy-rule` handlers: the profile's declared name maps to a per-tenant name
  before `Get`/`Set`, so the same profile can target differently-named objects.
- **Secret-free throughout (NFR-1).** `Get` returns config only; results flow
  through the same secret-free projection discipline as the connection layer, and
  saved profiles are still guarded by the profile secret-scanner.
- **The registry is a seam.** The engine takes its handler set as an injected
  parameter (default: the real provider registry), so it is unit-testable with
  in-memory fake controls and no tenant.

## Consequences

- **Adding a control is additive and local** — implement the contract, register
  it, test it in isolation. The engine never changes. Keeps the blast radius of
  each new control tiny and the surface reviewable (an agent-reviewable unit).
- **One diff/plan renderer** feeds dry-run, drift, and apply-preview — the single
  CLI consumer for v1 (ADR-0012), reusable by a later GUI.
- **Ordering constraints are declared, not implicit** (`DependsOn`): security
  defaults off before CA enforces, policy before rule, named locations before
  location-CA (research 05 §5). Deterministic order also keeps output diff-stable
  (NFR-9).
- **Audit logging (MCA-35) has one clean hook** — every `Set` is one plan item
  with a before/after, so the structured audit record is uniform (NFR-5).
- **Trade-off:** the contract is opinionated toward *desired-state config*.
  Read-only/monitor signals (Secure Score AUD-3, risky-user reads) are **not**
  handlers — they are separate report functions and must never enter the diff
  (research 05 R8). This is deliberate: it keeps drift meaningful.
- **Trade-off:** modelling a preset as rule-state + coverage means we assert the
  preset is *on and covers everyone*, not that its Microsoft-owned settings match
  a snapshot. Correct per research 05 R6, but it means "compliant" for MDO-1 is
  coarser than for a singleton. Documented in the handler.
- **Reversible:** this is an internal contract behind the CLI, not a user-facing
  or wire format. It can evolve as later mechanism classes (PIM, DKIM async,
  custom Defender policies) arrive without breaking profiles.
- **Isolates cmdlet-syntax churn (NFR-7):** all provider knowledge for a control
  — including the exact cmdlet/endpoint syntax it drives — lives inside that one
  handler, so a Graph/EXO module version bump that changes cmdlet syntax has a
  blast radius of one handler, not the engine.

## Deferred follow-ups (engine scope, tracked so they aren't lost)

Flagged by independent review (2026-07-24); none blocks this contract, all land
with the engine stories:

1. **`DependsOn` cycle & dangling-reference handling (MCA-17/MCA-18).** The
   engine must order plan items by a topological sort that **fails loud on a
   cycle** (NFR-6) and on a `DependsOn` id that resolves to no registered
   handler — never silently drop or reorder.
2. **Registry seam contract (MCA-4/MCA-5).** Handler discovery is deliberately
   unspecified here beyond "injected set". When the real provider registry
   lands it must define: id uniqueness (duplicate registration = loud failure)
   and deterministic discovery order.
3. **Compare/Get output validation (MCA-17).** `Action ∈ NoChange|Create|
   Update|Blocked|Unsupported` is prose, not code. The engine validates every
   plan item's `Action` against that enum and requires `Get` output to be
   canonicalizable (ADR-0008) — a custom `Compare` returning an unknown action
   is a loud plan-time failure, not an unmapped branch.

## Alternatives considered

- **Adopt DSC resource semantics (Get/Test/Set literally).** Rejected as the
  *engine* by ADR-0002; but the Get/Compare/Set *shape* here is deliberately
  DSC-like because it is the right decomposition — we take the shape, not the
  Microsoft365DSC dependency or its LCM.
- **One monolithic engine with per-control branches.** Rejected: unmaintainable,
  untestable in isolation, and violates the "reviewable, small change" tenet.
- **Rely on cmdlet `-WhatIf` for dry-run.** Rejected: inconsistent across the
  surface (MDO-10 has none; EXO/Graph coverage varies), and it would make dry-run
  correctness depend on each cmdlet rather than on our own deterministic diff.
- **Separate schemas per provider.** Rejected: research 05 §5 confirms one profile
  schema spans both engines; the provider difference lives in the handler, not the
  profile.

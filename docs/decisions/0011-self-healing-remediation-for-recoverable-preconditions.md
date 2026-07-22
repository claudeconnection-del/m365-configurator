# 0011. Self-healing: offer remediation for recoverable preconditions

- **Status:** Accepted
- **Date:** 2026-07-22
- **Deciders:** Project owner
- **Requirements:** FR-1 (module lifecycle), NFR-6 (loud, fast failure); mirrors FR-8/FR-9/FR-11 (dry-run → gated apply → remediation)
- **Related:** Jira MCA-2; [ADR-0006](0006-interface-local-web-dashboard-and-cli.md) (interfaces)

## Context

"Loud, fast failure" (NFR-6) is a core tenet, but taken naively it produces
dead-ends: *"won't work — you need Microsoft.Graph.Authentication."* For a
**recoverable, well-understood** precondition — a missing or outdated pinned
module available from a known, trusted source (the PowerShell Gallery) — the app
can do better than complain. The owner wants it to be **self-healing**: *"I'm
missing this, it can be found here — want me to get it for you?"*

## Decision

For recoverable preconditions the app **offers consented remediation** instead of
only reporting the problem. It reuses the same shape as its core engine
(dry-run → gated apply): compute a **remediation offer** — what's missing, where
it lives, and the exact, non-elevating command that fixes it — present it, and
act **only on an explicit yes**.

- The offer is **pure data** (`Get-M365ModuleRemediation`): no installs, no
  prompts, no network in the computing step — so it is unit-testable and the
  interface layer (CLI now, dashboard later, per ADR-0006) owns the actual
  prompt/consent.
- Remediation stays within the tenets: **CurrentUser scope, never elevate**;
  install the **pinned** version (ADR-0008/NFR-7); source is the PowerShell
  Gallery only (NFR-2, no surprise egress).
- This scopes NFR-6: failure is still **loud and fast** when there is *no* safe
  automatic remedy, when consent is declined, or when a remedy fails. Self-heal
  is an *offer*, never a silent auto-fix.

## Consequences

- Better UX and faster onboarding (clone-and-go) without weakening security:
  every heal is consented, scoped, pinned, and from a known source.
- Establishes a reusable pattern: any recoverable precondition (not just modules)
  should present an offer rather than a dead-end.
- Adds a small surface to keep honest — the offer command and source must always
  reflect the single source of truth (`Get-M365RequiredModule`) and never elevate.
- The consent/interaction mechanism itself is interface-specific and is decided
  in the interfaces workstream (ADR-0006 / MCA-8), not here.

## Alternatives considered

- **Report-only ("you need X")** — simplest, but a dead-end that pushes manual,
  error-prone, possibly-elevated installs onto the user. Rejected as the default.
- **Silent auto-install** — convenient but violates consent and the "reviewable,
  deterministic, dry-run-first" stance; surprising network/install side effects.
  Rejected.

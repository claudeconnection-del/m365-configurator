# 0002. Microsoft365DSC as the primary configuration engine — reject-as-primary

- **Status:** Accepted (2026-07-22 — reject-as-primary; supersedes the prior *Proposed* stance)
- **Date:** 2026-07-22
- **Deciders:** Project owner + team
- **Requirements:** FR-4, FR-5, FR-8, FR-10, FR-11, NFR-1, NFR-3, NFR-4, NFR-7
- **Related:** OPEN-QUESTIONS Q7; `docs/research/03-microsoft365dsc.md`; ADR-0001

## Context

Microsoft365DSC (M365DSC) natively models much of M365 with **export** (→ profiles),
**drift detection**, and **remediation** built in — potentially delivering several
core features with far less custom code. The owner previously wanted it evaluated
seriously (having struggled to run it via a Parallels VM on macOS), so this ADR was
opened as *Proposed* pending the Track 03 spike and a possible container proof.

The Track 03 spike (`docs/research/03-microsoft365dsc.md`) is now complete. Its
verdict is decisive and does not depend on the container proof: M365DSC's coverage
is excellent, but coverage is not the binding constraint — **three tenet-level
conflicts are**.

## Decision

**Reject Microsoft365DSC as the primary engine.** Build a **custom Graph/Exchange
Online engine** implementing the proven `export → normalize → diff → ordered
idempotent apply` loop (research 06 §7) on our own pinned cmdlets and diff renderer.
**Selectively reuse** M365DSC's cross-platform pieces — the ReverseDSC **export**
and the **offline delta-report** tooling — where they add value, but **not** its
apply/monitor (LCM) path.

The owner ratified this at the Phase 2 checkpoint **without requiring the container
proof** — the evidence is strong enough that the build direction (custom engine) is
unchanged either way; the proof would only affect *how much* export tooling we borrow.

Why reject-as-primary (from Track 03):

- **Runtime (NFR-4).** The apply/monitor loop depends on the DSC **Local
  Configuration Manager**, which is **Windows-only** — removed from DSC 2.0 /
  PowerShell 7 and abandoned in DSC v3. Our target is Linux + pwsh 7.
- **Auth (ADR-0001).** No device-code / interactive-delegated **apply** path; it is
  app/certificate-centric — the tension already flagged in ADR-0001.
- **Secrets (NFR-1).** Credentials are stored **plaintext-by-default in the compiled
  MOF** — a direct no-credentials-on-disk violation.

## Consequences

- Unblocks the build on a **portable Linux + pwsh 7 custom engine** aligned with
  ADR-0001 and NFR-1/NFR-4; resolves the ADR-0001 reconciliation risk.
- **More custom code** and slower breadth expansion than adopting DSC wholesale —
  mitigated by reusing M365DSC's export tooling and the already-mapped Graph/EXO
  surface (research 01/02) and the ~11-control MVP slice (research 05, ADR-0003).
- The architecture stays **engine-agnostic at the seam** (research 06 §7.3): if
  Microsoft ever ships a cross-platform DSC apply path, revisiting is cheap.
- We inherit DSC's **idempotency discipline** (Test-before-Set) as the model for our
  own deterministic remediation (FR-11), without inheriting its runtime.

## Alternatives considered

- **Adopt M365DSC as primary** — rejected: Windows-only apply (NFR-4), incompatible
  auth (ADR-0001), plaintext MOF credentials (NFR-1).
- **Windows-based container to host DSC** — rejected for MVP: breaks the Linux/pwsh-7
  portability tenet and the memory-only-credential posture; heavy.
- **Vendor everything (Monkey365-style, no official modules)** — rejected: more code
  and less stability than pinned official Graph/EXO modules (NFR-7).

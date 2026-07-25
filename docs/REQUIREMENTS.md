# Requirements

Requirements are written to be **testable**. Each has a stable ID so tests, ADRs,
and Jira issues (project `MCA`) can reference it. Status legend: `[ ]` not started,
`[~]` in progress, `[x]` satisfied.

## Functional requirements (FR)

- [ ] **FR-1 — Module lifecycle.** Detect, install (CurrentUser scope), import, and
  report versions of required PowerShell modules. Idempotent; safe to re-run.
- [ ] **FR-2 — Connect/disconnect at runtime.** Establish and tear down M365
  connections (Graph, Exchange Online) on demand within a running session.
- [ ] **FR-3 — Full credential cleanup.** On disconnect/session end, purge tokens
  and in-memory secrets so no residue survives between sessions.
- [ ] **FR-4 — Configuration surface.** Expose configurable settings from the
  underlying modules (Graph + Exchange Online at minimum) in a usable interface.
- [ ] **FR-5 — Save profiles.** Persist a configuration as a named, versioned,
  human-readable profile containing **configuration only — never credentials**.
- [ ] **FR-6 — Load profiles.** Select a saved profile from a list, or import an
  exported profile file (for collaboration).
- [ ] **FR-7 — Name remapping.** When applying a profile, allow updating the names
  of name-scoped configurations (names are unique per configuration/tenant).
- [ ] **FR-8 — Dry run.** Preview the exact set of changes a profile would make
  against a connected tenant, with a clear pass/needs-attention signal, before
  applying anything.
- [ ] **FR-9 — Apply.** Apply a profile only after an explicit go-ahead; report
  per-item success/failure.
- [ ] **FR-10 — Drift detection.** Scan a connected tenant against a saved profile
  and report differences.
- [ ] **FR-11 — Deterministic remediation.** For detected drift, offer remediation
  that is deterministic and previewable (dry-run applies here too).
- [ ] **FR-12 — Log access.** Provide easy, in-tool access to the verbose logs.

## Non-functional requirements (NFR)

- [ ] **NFR-1 — No credential persistence.** Credentials/tokens are never written
  to disk, logs, profiles, or telemetry. Verified by test + review.
- [ ] **NFR-2 — No unexpected egress.** The app contacts only endpoints it is
  explicitly configured to contact (M365/Graph/EXO and the PowerShell Gallery for
  module install). No analytics, no phone-home. Verifiable/auditable.
- [ ] **NFR-3 — Minimal dependencies.** Dependency count is kept as low as
  possible; each addition is justified in review.
- [ ] **NFR-4 — Containerized & portable.** Ships as a container; behaves the same
  across host OSes.
- [ ] **NFR-5 — Audit-grade logging.** Structured, verbose, timestamped, and
  retrievable; records who/what/when for every change-applying action, without
  logging secrets.
- [ ] **NFR-6 — Loud, fast failure.** Errors surface immediately with actionable
  messages; no silent catches; no partial application without a clear error state.
- [ ] **NFR-7 — Syntax-stability.** The tool remains correct as long as the
  underlying PowerShell module cmdlet syntax is unchanged. Module versions are
  pinned; upgrades are deliberate. The **runtime** is pinned too — a supported
  floor in the module manifest, and an exact PowerShell/.NET pair for the container
  and CI — so the .NET type surface the code relies on cannot drift underneath it
  (ADR-0015).
- [ ] **NFR-8 — Reproducible dev/build.** A fresh clone reaches a working dev
  environment via the documented bootstrap with no hidden steps.
- [ ] **NFR-9 — Readability & visual inspection.** All human-facing output — code,
  profiles, logs, diffs, and dry-run previews — is formatted for fast, unambiguous
  visual inspection: consistent structure, aligned columns where it helps, clear
  grouping, and stable ordering so diffs stay meaningful. Enforced by formatters/
  linters where practical and checked in review.

## Traceability

Every FR/NFR maps to: at least one ADR (design) — or a design tenet where no
hard-to-reverse decision was needed (see ¹) — at least one Jira issue (`MCA`),
and — from Phase 4 on — at least one test. The Jira mapping below was
established in **Phase 3 planning** (2026-07-22); test coverage is tracked in
[`tests/`](../tests) and reported per slice as it is built.

The MCA backlog is organised into eight capability/workstream **epics**:
MCA-1 Connection & credential foundation · MCA-3 Profile engine ·
MCA-4 Microsoft Graph provider · MCA-5 Exchange Online provider ·
MCA-6 Change engine (dry-run/apply/drift/remediate) · MCA-7 Audit logging &
observability · MCA-8 Interfaces (web dashboard + CLI) · MCA-9 Packaging &
release (later-phase stub). The `v1-slice`-labelled stories are the ~11-control
vertical slice from [research 05 §4](research/05-security-baselines.md).

| Req | ADR(s) | Jira (`MCA`) |
| --- | --- | --- |
| FR-1 | ADR-0005 | MCA-2 |
| FR-2 | ADR-0001 | MCA-10, MCA-11 |
| FR-3 | ADR-0001 | MCA-12 |
| FR-4 | ADR-0002, ADR-0003, ADR-0013 | epics MCA-4 / MCA-5; controls MCA-22…MCA-34; surfaced via MCA-36 |
| FR-5 | ADR-0008, ADR-0009 | MCA-13, MCA-14 |
| FR-6 | ADR-0009 | MCA-15 |
| FR-7 | ADR-0013 | MCA-16 (applies to MCA-23/24/31) |
| FR-8 | ADR-0013 | MCA-17, MCA-21 |
| FR-9 | ADR-0013 | MCA-18 |
| FR-10 | ADR-0013 | MCA-19 |
| FR-11 | ADR-0013 | MCA-20 |
| FR-12 | ADR-0006 | MCA-35, MCA-36 |
| NFR-1 | ADR-0001 | MCA-10, MCA-12 (validated by MCA-9) |
| NFR-2 | —¹ | MCA-7 |
| NFR-3 | —¹ | MCA-2, MCA-9 |
| NFR-4 | ADR-0007, ADR-0015 | MCA-9, MCA-39 |
| NFR-5 | ADR-0013 | MCA-35 |
| NFR-6 | ADR-0011, ADR-0013 | MCA-18, MCA-21 |
| NFR-7 | ADR-0015 | MCA-2, MCA-13, MCA-39 |
| NFR-8 | ADR-0015 | MCA-2, MCA-9, MCA-39 |
| NFR-9 | ADR-0006, ADR-0013 | MCA-13, MCA-17, MCA-36 |

¹ Anchored by a design tenet + pinned tooling rather than a dedicated ADR
(no-egress, minimal-deps). An ADR is written only if one of these becomes a
contested, hard-to-reverse decision — as version-pinning and reproducible-dev did,
now recorded in ADR-0015 (runtime version pin).

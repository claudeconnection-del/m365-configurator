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
  pinned; upgrades are deliberate.
- [ ] **NFR-8 — Reproducible dev/build.** A fresh clone reaches a working dev
  environment via the documented bootstrap with no hidden steps.
- [ ] **NFR-9 — Readability & visual inspection.** All human-facing output — code,
  profiles, logs, diffs, and dry-run previews — is formatted for fast, unambiguous
  visual inspection: consistent structure, aligned columns where it helps, clear
  grouping, and stable ordering so diffs stay meaningful. Enforced by formatters/
  linters where practical and checked in review.

## Traceability

Every FR/NFR should map to: at least one ADR (design), at least one Jira issue
(`MCA`), and at least one test. This mapping is filled in as the project moves
from design into build.

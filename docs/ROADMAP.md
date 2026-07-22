# Roadmap

Phased plan. The vision is fixed; details firm up as we move through the phases.
Progress and detailed tasks are tracked in Jira (project key **`MCA`**) and
mirrored in Confluence.

## Phase 0 — Repository bootstrap  ✅ (this commit)

- Reproducible dev environment (dev container + `scripts/bootstrap.*`).
- Captured vision, requirements, and open questions.
- Security-first git hygiene.
- **Outcome:** `git clone` → working dev environment on any machine.

## Phase 1 — Research & documentation

- Survey the configuration surface of `Microsoft.Graph` and
  `ExchangeOnlineManagement`, and evaluate adjacent options (notably
  **Microsoft365DSC** / DSC) for fit against the tenets.
- Authentication options and their credential-cleanup implications (delegated /
  device-code / app-only + certificate / managed identity).
- Prior art for profiles, dry-run, and drift detection.
- Deliverables: research corpus in `docs/` and Confluence.

## Phase 2 — Design & architecture (collaborative)

- Decide core language/runtime, interface (CLI/TUI/local web), and how the app
  drives PowerShell.
- Profile schema (config-only), name-remapping model, logging/audit format,
  dry-run and drift/remediation engines.
- Recorded as ADRs in [`decisions/`](decisions/). **Reviewed with the project
  owner before build.**

## Phase 3 — Project planning

- Break the design into epics/stories in Jira (`MCA`), mapped to FR/NFR IDs.
- Define the parallelizable workstreams and the author/reviewer agent split.

## Phase 4 — Build

- Implement in vertical slices, each with dry-run and tests.
- **An agent never reviews its own code** — separate author and reviewer.
- Parallelize independent workstreams.

## Phase 5 — Harden & ship

- Security review (no egress, no credential persistence), audit-log validation,
  container image, and reproducible release.

> Sequence intentionally front-loads research and design so the build doesn't
> drift from the vision. Design revisions are welcome, especially after Phase 1.

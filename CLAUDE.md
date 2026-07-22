# CLAUDE.md — m365-configurator

Context for any Claude session working in this repo. Read this first; it tells
you what the project is, where the live state lives, and how to **resume**.

---

## What this project is

A portable, containerized tool for configuring Microsoft 365 tenants (Microsoft
Graph + Exchange Online) from reusable, reviewable configuration profiles — with
verbose audit logging, dry-run previews, drift detection, and deterministic
remediation. Full intent in [`docs/VISION.md`](docs/VISION.md); testable
requirements in [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md).

The **repo `docs/` tree is the source of truth.** Confluence is the curated,
collaborative mirror (see [ADR-0004](docs/decisions/0004-documentation-location.md)).

## The "resume" workflow (read this)

The project owner tracks work across three places: **this repo**, **Jira**, and
**Confluence**. They are not always in sync. When the owner says **"resume"** (or
runs the **`/resume`** slash command), your job is to reconcile all three and
report where things stand — do **not** guess from this file alone, which may be
stale. The procedure is encoded in [`.claude/commands/resume.md`](.claude/commands/resume.md);
the short version:

1. **Repo** — run [`scripts/repo-status.sh`](scripts/repo-status.sh): current
   branch, uncommitted work, and any branch not yet merged into the default
   branch.
2. **Jira** — project **`MCA`** ("M365 Configuration Application"): open and
   recently-updated issues.
3. **Confluence** — space **`SD`** ("Software Development"): recently-modified
   pages.
4. **Reconcile & report** — a tight summary of the current phase, what changed
   since last time, any drift between the three sources, blockers/decisions that
   need the owner, and a recommended next action.

## Atlassian coordinates (for the MCP tools)

| Thing | Value |
| --- | --- |
| Cloud ID | `b738554c-85e3-4c02-8140-fef01cb5fdb9` |
| Site | `https://chomey.atlassian.net` |
| Jira project key | `MCA` — M365 Configuration Application |
| Confluence space key | `SD` — Software Development |
| Confluence: project home | page `1048577` — "M365 Configurator" |
| Confluence: research index | page `917517` — "M365 Configurator — Research" |

Atlassian tools are the `mcp__Atlassian_Rovo__*` set (load via ToolSearch if not
already available). Always pass the Cloud ID above.

## Branches

| Branch | Role |
| --- | --- |
| `claude/m365-exchange-config-app-1hko7b` | **Default / main working branch.** All feature work lands here (see [CONTRIBUTING.md](CONTRIBUTING.md)). |

The Phase 1 research corpus and the resume-workflow tooling were built on
short-lived branches (`claude/mca-sub-agent-research-p1g24u`,
`claude/repo-status-workflow-6uxdf1`) and **merged into the default branch**. Both
are fully merged (0 commits ahead) and safe to delete. New work branches off the
default branch per [CONTRIBUTING.md](CONTRIBUTING.md).

Never push to a branch other than your designated one without explicit
permission. Reference Jira issues in commits where applicable (e.g. `MCA-12: …`).

## Roadmap phase (where we are)

`Phase 0 bootstrap ✅ → Phase 1 research ✅ → Phase 2 design checkpoint ✅ (decisions
ratified as ADR-0002 + ADR-0005…0010) → Phase 3 Jira planning ✅ (MCA backlog:
8 workstream epics + 28 stories; v1 slice fully decomposed, 2026-07-22) →
**Phase 4 build** → Phase 5 harden & ship.`

Full plan in [`docs/ROADMAP.md`](docs/ROADMAP.md); open decisions in
[`docs/OPEN-QUESTIONS.md`](docs/OPEN-QUESTIONS.md). **The `/resume` command
refreshes this live** — treat the line above as a hint, not gospel.

## Non-negotiable design tenets

Security is paramount (no credentials on disk, ever; nothing phones home) ·
minimal dependencies · containerized & portable · audit-grade logging · loud,
fast failure · stability via pinned module versions · dry-run before apply ·
readability for visual inspection. The testable list is
[`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md); every change is measured against
it, and **an agent never reviews its own code** (see
[CONTRIBUTING.md](CONTRIBUTING.md)).

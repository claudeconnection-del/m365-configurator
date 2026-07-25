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
| `main` | **Default / main working branch.** All feature work lands here (see [CONTRIBUTING.md](CONTRIBUTING.md)). |

The Phase 1 research corpus and the resume-workflow tooling were built on
short-lived branches (`claude/mca-sub-agent-research-p1g24u`,
`claude/repo-status-workflow-6uxdf1`), **merged into the default branch**, and
have since been **deleted** (2026-07-22). All work lands directly on the default
branch per [CONTRIBUTING.md](CONTRIBUTING.md) §2.

One unmerged spike survives as a **tag, not a branch**: the never-run
Microsoft365DSC container-proof harness (built to prove ADR-0002 pre-ratification;
ADR-0002 was ratified without it) is archived at tag
`archive/m365dsc-container-proof` (owner decision, 2026-07-24). Recover it from
the tag if the planned M365DSC export-tooling reuse ever wants its probes.

S18–S20 (audit log, CLI dispatcher, close-out) were built on a dedicated branch,
`claude/runbook-build-s18-s20-3boy73` — an explicit harness override for that
session, not a change to the standing convention above. Fast-forward merged into
`main` at `6d6ebda` (2026-07-25; CI green, 307 Pester tests) and deleted.

Never push to a branch other than your designated one without explicit
permission. Reference Jira issues in commits where applicable (e.g. `MCA-12: …`).

## Working alongside other agents/seats

More than one agent may be working this project concurrently, and **all work lands
on `main`** — so an unclaimed overlap becomes a merge conflict or a silent
overwrite. Every agent authenticates to Jira/Confluence as *Moose*, so the account
name does **not** identify you.

Before starting a story:

1. **Read the coordination block** — the "⚠️ Parallel work — seat coordination"
   section on Confluence page `1048577`. It lists each active lane, who holds it,
   and the files it touches.
2. **Claim your story in Jira** — transition it to *In Progress* and comment naming
   your seat/agent and the files you will touch.
3. **Check the collision hot spots** before editing them. The known ones:
   - `src/M365Configurator/Public/Get-M365ControlRegistry.ps1` — **every** new
     control registers here, so two agents adding controls in parallel always
     conflict in this one file. Land control stories one at a time.
   - `src/M365Configurator/M365Configurator.psd1` — `FunctionsToExport` grows with
     every new public function.
   - `src/M365Configurator/Public/Get-M365Plan.ps1` — shared by the dry-run and
     apply engines.
   - `docs/decisions/README.md` — the ADR index; every new ADR appends a row.

Update the coordination block when you take or finish a lane. Per
[CONTRIBUTING.md](CONTRIBUTING.md), **an agent never reviews its own code** — hand
review to a different agent.

## Roadmap phase (where we are)

`Phase 0 bootstrap ✅ → Phase 1 research ✅ → Phase 2 design checkpoint ✅ (decisions
ratified as ADRs 0001–0015) → Phase 3 Jira planning ✅ (MCA backlog:
8 workstream epics + 29 stories; v1 slice fully decomposed, 2026-07-22) →
**Phase 4 build ✅** (docs/RUNBOOK.md queue S1–S20 all landed, 2026-07-25;
307 Pester tests) → **Phase 5 harden & ship**.`

**`docs/RUNBOOK.md`'s queue is empty** — Phase 4 is done. It remains the
historical record of every story's spec, pre-made decisions, and work-loop
protocol; Phase 5 (security review, container, reproducible release) doesn't
yet have its own runbook — open [`docs/ROADMAP.md`](docs/ROADMAP.md) and
[`docs/OPEN-QUESTIONS.md`](docs/OPEN-QUESTIONS.md) first if you're starting it.

Full plan in [`docs/ROADMAP.md`](docs/ROADMAP.md); open decisions in
[`docs/OPEN-QUESTIONS.md`](docs/OPEN-QUESTIONS.md). **The `/resume` command
refreshes this live** — treat the line above as a hint, not gospel.

## Non-negotiable design tenets

Security is paramount (no credentials on disk, ever; nothing phones home) ·
minimal dependencies · containerized & portable · audit-grade logging · loud,
fast failure — but **self-healing** for recoverable preconditions (offer a
consented fix, don't dead-end; [ADR-0011](docs/decisions/0011-self-healing-remediation-for-recoverable-preconditions.md)) ·
stability via pinned module versions · dry-run before apply · readability for
visual inspection. The **canonical summary** is in the
[README](README.md#design-tenets); the full testable list is
[`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md). Every change is measured against
them, and **an agent never reviews its own code** (see
[CONTRIBUTING.md](CONTRIBUTING.md)).

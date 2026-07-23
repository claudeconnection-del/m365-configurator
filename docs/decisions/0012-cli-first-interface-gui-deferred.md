# 0012. CLI-first interface; GUI deferred until proven in the CLI

- **Status:** Accepted
- **Date:** 2026-07-23
- **Deciders:** Project owner
- **Requirements:** FR-4, FR-8, FR-12, NFR-1, NFR-2, NFR-3, NFR-9
- **Amends:** [ADR-0006](0006-interface-local-web-dashboard-and-cli.md) (local ephemeral web dashboard + first-class CLI)
- **Related:** ADR-0005 (PowerShell 7), ADR-0007 (container runtime), `docs/research/06-prior-art-and-architecture.md` §6.2

## Context

ADR-0006 made a local, ephemeral, localhost **web dashboard** the *primary*
interface and a first-class **CLI** the secondary surface, accepting a real
NFR-3 dependency/attack-surface cost for ease-of-use. Building into Phase 4, the
owner reprioritised: **the CLI is the backbone.** It is what makes the tool
useful for automation, CI, and scripting — the reasons the project exists — and
a polished, fully-tested CLI is the cleaner foundation to build a GUI *on top
of* later. Research 06 §6.2 had recommended exactly this shape (CLI-first) on
cost/tenet grounds; ADR-0006 had overridden it for the dashboard experience.
This ADR restores the CLI-first ordering and defers the GUI.

## Decision

**The CLI is the primary and only interface for v1.** All functionality —
connect/disconnect, profile save/load, dry-run, apply, drift, remediation, log
access — is delivered and proven through the CLI first.

The **web dashboard / GUI is deferred**: it becomes a candidate only **after**
the functional surface is complete and **tested and proven in the CLI**. When
built, it is a **thin front-end over the same tested commands**, not a parallel
implementation — the CLI is the contract.

This *narrows* ADR-0006 rather than reversing its safety analysis: if and when a
GUI is built, it remains bound by ADR-0006's hard requirements (localhost-only,
ephemeral, memory-only tokens, no phone-home, never render a secret).

## Consequences

- **Removes the NFR-3 hit for v1.** No web server, no bundled front-end assets,
  no localhost bind, no content-security policy to audit — a smaller dependency
  and attack surface, closer to the "minimal dependencies" tenet.
- **CLI quality is now a first-order requirement**, not a "fine secondary
  experience": readable, discoverable (comment-based help, consistent verbs and
  parameters), script-friendly (objects out, stable exit codes), and quiet by
  default / verbose on demand for audit (NFR-5, NFR-9).
- **One diff renderer** still feeds dry-run and drift; it now targets the CLI as
  the sole consumer for v1 (a later GUI reuses it).
- **Backlog impact:** the interface epic (Jira **MCA-8**) becomes CLI-first; the
  GUI/dashboard is split out as a later, explicitly post-v1 item gated on
  "functionality proven in CLI." ADR-0006's dashboard requirements are retained
  as the spec for that future work, not deleted.
- **Phase 5 security review** loses the web-surface items for v1 (they return
  with the GUI).

## Alternatives considered

- **Keep the web dashboard as primary (ADR-0006 as-is)** — rejected now: front-
  loads the largest dependency/attack-surface before the core is proven, and
  builds UI against commands that are still changing.
- **Build CLI and GUI in parallel** — rejected: doubles the surface under active
  change and risks the GUI diverging from the command contract. Sequencing GUI
  after a proven CLI makes it a thin, low-risk layer.

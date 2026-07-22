# 0007. Container runtime model: one-shot, ephemeral, serves the local UI

- **Status:** Accepted
- **Date:** 2026-07-22
- **Deciders:** Project owner + team
- **Requirements:** FR-3, NFR-1, NFR-4
- **Related:** OPEN-QUESTIONS Q3; ADR-0001, ADR-0006; `docs/research/03-microsoft365dsc.md` §9

## Context

Q3 asked whether the tool ships as a **one-shot CLI container** or a **long-running
service** container, and where it is expected to run. With the interface decided as a
local web dashboard (ADR-0006), the container must serve a `localhost` port **while it
runs**. The expected setting is a **consultant/operator laptop, per engagement** —
not a shared, always-on server.

## Decision

Ship a **single, one-shot, ephemeral container** (PowerShell 7 on Linux). During a
session it **serves the dashboard on a `localhost`-mapped port** and exposes the CLI;
when the session ends, the container is **discarded**. It is **not** an always-on or
shared multi-tenant service.

## Consequences

- **Ephemerality is the last line of defense** for memory-only tokens (ADR-0001,
  NFR-1) — discarding the container wipes any in-memory residue; explicit cleanup
  (FR-3) is the first line, container discard the backstop.
- **Per-engagement isolation** — no shared state across tenants or clients (the
  opposite of the CIPP model).
- Port binding is **`localhost`-only**; nothing is exposed beyond the host.
- **Trade-off:** no persistent scheduled-drift daemon in the MVP. If scheduled
  monitoring is later wanted, wrap the CLI in **external** scheduling (CI / cron /
  Azure Automation, the Maester pattern) rather than making the container
  long-running — keeping the always-on surface out of the tool itself.

## Alternatives considered

- **Long-running service container** — rejected for MVP: a persistent surface that
  tempts credential caching and contradicts the ephemeral, memory-only posture.
- **Shared server deployment** — rejected: multi-tenant state, against per-engagement
  isolation and the no-persistence tenets.

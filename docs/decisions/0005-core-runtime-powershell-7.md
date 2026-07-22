# 0005. Core runtime: pure PowerShell 7

- **Status:** Accepted
- **Date:** 2026-07-22
- **Deciders:** Project owner + team
- **Requirements:** FR-1, NFR-3, NFR-4, NFR-7
- **Related:** OPEN-QUESTIONS Q1; `docs/research/06-prior-art-and-architecture.md` §6.1; ADR-0006

## Context

The tool fundamentally drives PowerShell modules (Microsoft Graph SDK, Exchange
Online Management, and the M365DSC export tooling per ADR-0002). The open choice
(Q1) was: build as a **pure PowerShell 7** module/app, or wrap it in a
second-language front-end (Python/Go/Node) that shells out to `pwsh`.

Research 06 found the entire prior-art field is PowerShell — ScubaGear, Maester,
Monkey365 and M365DSC are PowerShell, and even CIPP's backend is PowerShell; the
cross-platform tools (Maester, Monkey365) are **pure** PowerShell on Linux.

## Decision

Build the tool as a **pure PowerShell 7 module/app**. No second-language wrapper.
The local web server behind the dashboard (ADR-0006) is **also implemented in
PowerShell** (e.g. Pode), so the container carries a **single runtime**.

## Consequences

- **One runtime** in the container (NFR-4) and **minimal dependencies** (NFR-3); no
  cross-process serialization boundary to `pwsh` that would break when cmdlet output
  shape drifts (NFR-7).
- First-class testing via **Pester** (as Maester demonstrates).
- **Trade-off:** PowerShell's interactive-UI story is thinner than Node/Go. This is
  acceptable because ADR-0006 renders the dashboard from PowerShell and ships
  self-contained front-end assets rather than a second-language UI stack. A richer
  layer, if ever needed, is added as a *single scoped module*, not a new language
  runtime (justified per NFR-3).

## Alternatives considered

- **Second-language front-end (Python/Go/Node) over `pwsh`** — rejected: adds a
  runtime to install/trust/pin and a fragile serialization boundary, buying only UI
  ergonomics that ADR-0006 delivers another way.
- **Vendor-everything self-contained collectors (Monkey365-style)** — rejected:
  reimplements Graph/EXO calls, more code and less stability than pinned modules.

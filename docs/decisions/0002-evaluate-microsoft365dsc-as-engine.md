# 0002. Evaluate Microsoft365DSC as the primary configuration engine

- **Status:** Proposed (pending research spike + hands-on container validation)
- **Date:** 2026-07-22
- **Deciders:** Project owner + team
- **Requirements:** FR-4, FR-5, FR-8, FR-10, FR-11, NFR-3, NFR-4, NFR-7
- **Related:** OPEN-QUESTIONS Q7; `docs/research/03-microsoft365dsc.md`

## Context

Microsoft365DSC natively models much of M365 with **export** (→ profiles),
**drift detection**, and **remediation** built in — potentially delivering several
core features with far less custom code and strong stability. The owner previously
struggled to run it (mostly via a Parallels VM on macOS); a clean, purpose-built
container may resolve that.

Open risks driving this to "Proposed" rather than "Accepted":

- Does it run on **PowerShell 7 / Linux**, or require **Windows PowerShell**?
- Is its **auth model** compatible with our interactive/device-code decision (0001)?
- Its **large dependency footprint** vs the minimal-deps tenet.
- **MOF / credential handling** vs the no-persisted-secrets tenet.

## Decision (proposed)

Adopt Microsoft365DSC as the primary engine for profiles/drift/remediation **iff**
the research spike and a hands-on container proof confirm it can run reliably
(Linux + pwsh preferred; an isolated, portable Windows-based container is an
acceptable fallback) with an auth model compatible with our security tenets.
Otherwise, **fall back** to a custom Graph/EXO engine that reuses DSC concepts
(export → diff → ordered idempotent apply).

## Consequences

- If viable: accelerates the MVP and future breadth substantially.
- Pulls many dependent modules — mitigate via strict version pinning and a minimal
  enabled-resource set.
- Constrains container strategy; must guarantee no plaintext credentials in MOF/exports.

## Alternatives considered

- **Custom engine from day one** — full control, more code, slower breadth.
- **Skip DSC** — rejected; the owner wants it evaluated and it offers large leverage.
